const std = @import("std");
const Options = @import("Options.zig");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr_util = @import("xr_util.zig");
const xr_result = @import("xr_result.zig");
const geometry = @import("geometry.zig");
// const c = xr_util.c;
const InputState = @import("InputState.zig");
const get_proc = @import("get_proc.zig");

const c = @import("c");

const Swapchain = struct {
    handle: c.XrSwapchain,
    width: u32,
    height: u32,
};

allocator: std.mem.Allocator,
options: Options,
graphics: GraphicsPlugin,
instance: c.XrInstance = null,
systemId: c.XrSystemId = c.XR_NULL_SYSTEM_ID,
session: c.XrSession = null,

configViews: std.array_list.Managed(c.XrViewConfigurationView),
views: std.array_list.Managed(c.XrView),
swapchains: std.array_list.Managed(Swapchain),
colorSwapchainFormat: i64 = -1,

// Application's current lifecycle state according to the runtime
sessionState: c.XrSessionState = c.XR_SESSION_STATE_UNKNOWN,
sessionRunning: bool = false,

eventDataBuffer: c.XrEventDataBuffer = .{},
input: InputState = .{},

const ACCEPTABLE_BLENDMODES = [_]c.XrEnvironmentBlendMode{
    c.XR_ENVIRONMENT_BLEND_MODE_OPAQUE,
    c.XR_ENVIRONMENT_BLEND_MODE_ADDITIVE,
    c.XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND,
};

pub fn init(
    allocator: std.mem.Allocator,
    options: Options,
    graphics: GraphicsPlugin,
) @This() {
    return .{
        .allocator = allocator,
        .options = options,
        .graphics = graphics,
        .configViews = .init(allocator),
        .views = .init(allocator),
        .swapchains = .init(allocator),
    };
}

pub fn deinit(this: *@This()) void {
    std.log.debug("#### OpenXrProgram.deinit ####", .{});
    this.swapchains.deinit();
    this.views.deinit();
    this.configViews.deinit();
}

pub fn createInstance(
    this: *@This(),
    platform_extensions: []const []const u8,
    instance_create_extension: ?*anyopaque,
) !void {
    try this.logLayersAndExtensions();
    try this.createInstanceInternal(platform_extensions, instance_create_extension);
    try this.logInstanceInfo();
}

fn logLayersAndExtensions(this: *@This()) !void {
    // Write out extension properties for a given layer.

    // Log non-layer extensions (layerName==nullptr).
    // try this.logExtensions("", "");

    // Log layers and any of their extensions.
    {
        var layerCount: u32 = undefined;
        _ = try xr_result.check(c.xrEnumerateApiLayerProperties(0, &layerCount, null));
        std.log.info("Available Layers: ({})", .{layerCount});
        if (layerCount > 0) {
            var layers = try this.allocator.alloc(c.XrApiLayerProperties, layerCount);
            // std::vector<XrApiLayerProperties> layers(layerCount, {XR_TYPE_API_LAYER_PROPERTIES});
            _ = try xr_result.check(c.xrEnumerateApiLayerProperties(@intCast(layers.len), &layerCount, &layers[0]));

            for (layers) |layer| {
                std.log.debug("  Name={s} SpecVersion={}.{}.{} LayerVersion={} Description={s}", .{
                    layer.layerName,
                    // GetXrVersionString(layer.specVersion).c_str(),
                    c.XR_VERSION_MAJOR(layer.specVersion),
                    c.XR_VERSION_MINOR(layer.specVersion),
                    c.XR_VERSION_PATCH(layer.specVersion),
                    layer.layerVersion,
                    layer.description,
                });
                try this.logExtensions(@ptrCast(&layer.layerName), "    ");
            }
        }
    }
}

fn logExtensions(this: *@This(), layerName: [*:0]const u8, indent: []const u8) !void {
    var instanceExtensionCount: u32 = undefined;
    _ = try xr_result.check(c.xrEnumerateInstanceExtensionProperties(layerName, 0, &instanceExtensionCount, null));
    std.log.debug("{s}Available Extensions: ({})", .{ indent, instanceExtensionCount });

    if (instanceExtensionCount > 0) {
        var extensions = try this.allocator.alloc(c.XrExtensionProperties, instanceExtensionCount);
        defer this.allocator.free(extensions);
        for (extensions) |*ex| {
            ex.* = .{
                .type = c.XR_TYPE_EXTENSION_PROPERTIES,
            };
        }
        _ = try xr_result.check(c.xrEnumerateInstanceExtensionProperties(
            layerName,
            @intCast(extensions.len),
            &instanceExtensionCount,
            &extensions[0],
        ));

        for (extensions) |extension| {
            std.log.debug("{s}  Name={s} SpecVersion={}", .{
                indent,
                extension.extensionName,
                extension.extensionVersion,
            });
        }
    }
}

fn createInstanceInternal(
    this: *@This(),
    platform_extensions: []const []const u8,
    instance_create_extension: ?*anyopaque,
) !void {
    try xr_util.assert(this.instance == null);

    //
    var arena = std.heap.ArenaAllocator.init(this.allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    // Create union of extensions required by platform and graphics plugins.
    var extensions = std.array_list.Managed([*:0]const u8).init(this.allocator);
    defer extensions.deinit();

    // Transform platform and graphics extension std::strings to C strings.
    for (platform_extensions) |extension| {
        const copyz: [*:0]const u8 = try allocator.dupeZ(u8, extension);
        try extensions.append(copyz);
    }

    const graphics_extensions = this.graphics.getInstanceExtensions();
    for (graphics_extensions) |extension| {
        const copyz: [*:0]const u8 = try allocator.dupeZ(u8, extension);
        try extensions.append(copyz);
    }

    for (extensions.items) |name| {
        std.log.info("extension: {s}", .{name});
    }
    var createInfo = c.XrInstanceCreateInfo{
        .type = c.XR_TYPE_INSTANCE_CREATE_INFO,
        .next = instance_create_extension,
        .createFlags = 0,
        .enabledApiLayerCount = 0,
        .enabledApiLayerNames = null,
        .enabledExtensionCount = @intCast(extensions.items.len),
        .enabledExtensionNames = &extensions.items[0],
    };
    _ = try std.fmt.bufPrintZ(@ptrCast(&createInfo.applicationInfo.applicationName), "HelloXR", .{});

    // Current version is 1.1.x, but hello_xr only requires 1.0.x
    createInfo.applicationInfo = .{
        .apiVersion = c.XR_API_VERSION_1_0,
        .applicationVersion = 0,
        .engineVersion = 0,
    };
    _ = try std.fmt.bufPrintZ(&createInfo.applicationInfo.applicationName, "{s}", .{"hello_xr"});
    _ = try std.fmt.bufPrintZ(&createInfo.applicationInfo.engineName, "{s}", .{"hello_xr.engine"});

    try xr_result.check(c.xrCreateInstance(&createInfo, &this.instance));
}

fn logInstanceInfo(this: *@This()) !void {
    try xr_util.assert(this.instance != null);

    var instanceProperties = c.XrInstanceProperties{
        .type = c.XR_TYPE_INSTANCE_PROPERTIES,
    };
    try xr_result.check(c.xrGetInstanceProperties(this.instance, &instanceProperties));

    std.log.info("Instance RuntimeName={s} RuntimeVersion={}", .{
        instanceProperties.runtimeName,
        xr_util.ExtractVersion.fromXrVersion(instanceProperties.runtimeVersion),
    });
}

pub fn initializeSystem(this: *@This()) !void {
    try xr_util.assert(this.instance != null);
    try xr_util.assert(this.systemId == c.XR_NULL_SYSTEM_ID);

    var systemInfo = c.XrSystemGetInfo{
        .type = c.XR_TYPE_SYSTEM_GET_INFO,
        .next = null,
        .formFactor = this.options.Parsed.FormFactor,
    };
    try xr_result.check(c.xrGetSystem(this.instance, &systemInfo, &this.systemId));

    std.log.debug("Using system {} for form factor {}", .{
        this.systemId,
        this.options.Parsed.FormFactor,
    });
    try xr_util.assert(this.instance != null);
    try xr_util.assert(this.systemId != c.XR_NULL_SYSTEM_ID);
}

pub fn getPreferredBlendMode(this: @This()) !c.XrEnvironmentBlendMode {
    var count: u32 = undefined;
    try xr_result.check(c.xrEnumerateEnvironmentBlendModes(
        this.instance,
        this.systemId,
        this.options.Parsed.ViewConfigType,
        0,
        &count,
        null,
    ));
    try xr_util.assert(count > 0);

    const blendModes = try this.allocator.alloc(c.XrEnvironmentBlendMode, count);
    defer this.allocator.free(blendModes);
    try xr_result.check(c.xrEnumerateEnvironmentBlendModes(
        this.instance,
        this.systemId,
        this.options.Parsed.ViewConfigType,
        count,
        &count,
        &blendModes[0],
    ));

    for (blendModes) |blendMode| {
        if (std.mem.containsAtLeastScalar(
            c.XrEnvironmentBlendMode,
            &ACCEPTABLE_BLENDMODES,
            1,
            blendMode,
        )) return blendMode;
    }

    unreachable;
}

pub fn initializeDevice(this: *@This()) !void {
    try this.logViewConfigurations();

    // The graphics API can initialize the graphics device now that the systemId and instance handle are available.
    try this.graphics.initializeDevice(@ptrCast(this.instance), this.systemId);
}

fn logViewConfigurations(this: @This()) !void {
    try xr_util.assert(this.instance != null);
    try xr_util.assert(this.systemId != c.XR_NULL_SYSTEM_ID);

    var viewConfigTypeCount: u32 = undefined;
    try xr_result.check(c.xrEnumerateViewConfigurations(this.instance, this.systemId, 0, &viewConfigTypeCount, null));
    const viewConfigTypes = try this.allocator.alloc(c.XrViewConfigurationType, viewConfigTypeCount);
    defer this.allocator.free(viewConfigTypes);
    try xr_result.check(c.xrEnumerateViewConfigurations(this.instance, this.systemId, viewConfigTypeCount, &viewConfigTypeCount, &viewConfigTypes[0]));
    try xr_util.assert(viewConfigTypes.len == viewConfigTypeCount);

    std.log.info("Available View Configuration Types: ({})", .{viewConfigTypeCount});
    for (viewConfigTypes) |viewConfigType| {
        std.log.debug("  View Configuration Type: {} {s}", .{
            viewConfigType,
            if (viewConfigType == this.options.Parsed.ViewConfigType) "(Selected)" else "",
        });

        var viewConfigProperties = c.XrViewConfigurationProperties{
            .type = c.XR_TYPE_VIEW_CONFIGURATION_PROPERTIES,
        };
        try xr_result.check(c.xrGetViewConfigurationProperties(
            this.instance,
            this.systemId,
            viewConfigType,
            &viewConfigProperties,
        ));

        std.log.debug("  View configuration FovMutable={s}", .{
            if (viewConfigProperties.fovMutable == c.XR_TRUE) "True" else "False",
        });

        var viewCount: u32 = undefined;
        try xr_result.check(c.xrEnumerateViewConfigurationViews(
            this.instance,
            this.systemId,
            viewConfigType,
            0,
            &viewCount,
            null,
        ));
        if (viewCount > 0) {
            const views = try this.allocator.alloc(c.XrViewConfigurationView, viewCount);
            defer this.allocator.free(views);
            for (views) |*view| {
                view.* = .{ .type = c.XR_TYPE_VIEW_CONFIGURATION_VIEW };
            }
            try xr_result.check(c.xrEnumerateViewConfigurationViews(
                this.instance,
                this.systemId,
                viewConfigType,
                viewCount,
                &viewCount,
                &views[0],
            ));

            for (views, 0..) |view, i| {
                std.log.debug("    View [{}]: Recommended Width={} Height={} SampleCount={}", .{
                    i,                               view.recommendedImageRectWidth,
                    view.recommendedImageRectHeight, view.recommendedSwapchainSampleCount,
                });
                std.log.debug("    View [{}]:     Maximum Width={} Height={} SampleCount={}", .{
                    i,
                    view.maxImageRectWidth,
                    view.maxImageRectHeight,
                    view.maxSwapchainSampleCount,
                });
            }
        } else {
            std.log.err("Empty view configuration type", .{});
        }

        try this.logEnvironmentBlendMode(viewConfigType);
    }
}

fn logEnvironmentBlendMode(this: @This(), view_type: c.XrViewConfigurationType) !void {
    try xr_util.assert(this.instance != null);
    try xr_util.assert(this.systemId != 0);

    var count: u32 = undefined;
    try xr_result.check(c.xrEnumerateEnvironmentBlendModes(this.instance, this.systemId, view_type, 0, &count, null));
    try xr_util.assert(count > 0);

    std.log.info("Available Environment Blend Mode count : ({})", .{count});

    const blendModes = try this.allocator.alloc(c.XrEnvironmentBlendMode, count);
    defer this.allocator.free(blendModes);
    try xr_result.check(c.xrEnumerateEnvironmentBlendModes(
        this.instance,
        this.systemId,
        view_type,
        count,
        &count,
        &blendModes[0],
    ));

    var blendModeFound = false;
    for (blendModes) |mode| {
        const blendModeMatch = (mode == this.options.Parsed.EnvironmentBlendMode);
        std.log.info(
            "Environment Blend Mode ({}) : {s}",
            .{ mode, if (blendModeMatch) "(Selected)" else "" },
        );
        blendModeFound |= blendModeMatch;
    }
    try xr_util.assert(blendModeFound);
}

pub fn initializeSession(this: *@This()) !void {
    try xr_util.assert(this.instance != null);
    try xr_util.assert(this.session == null);

    {
        std.log.debug("Creating session...", .{});

        var createInfo = c.XrSessionCreateInfo{
            .type = c.XR_TYPE_SESSION_CREATE_INFO,
            .next = this.graphics.getGraphicsBinding(),
            .systemId = this.systemId,
        };
        try xr_result.check(c.xrCreateSession(this.instance, &createInfo, &this.session));
    }

    try this.logReferenceSpaces();
    // try this.initializeActions();

}

fn logReferenceSpaces(this: @This()) !void {
    try xr_util.assert(this.session != null);

    var spaceCount: u32 = undefined;
    try xr_result.check(c.xrEnumerateReferenceSpaces(this.session, 0, &spaceCount, null));
    const spaces = try this.allocator.alloc(c.XrReferenceSpaceType, spaceCount);
    defer this.allocator.free(spaces);
    try xr_result.check(c.xrEnumerateReferenceSpaces(this.session, spaceCount, &spaceCount, &spaces[0]));

    std.log.info("Available reference spaces: {}", .{spaceCount});
    for (spaces) |space| {
        std.log.debug("  Name: {}", .{space});
    }
}

pub fn createSwapchains(this: *@This()) !void {
    try xr_util.assert(this.session != null);
    try xr_util.assert(this.swapchains.items.len == 0);
    try xr_util.assert(this.configViews.items.len == 0);

    // Read graphics properties for preferred swapchain length and logging.
    var systemProperties = c.XrSystemProperties{
        .type = c.XR_TYPE_SYSTEM_PROPERTIES,
    };
    try xr_result.check(c.xrGetSystemProperties(this.instance, this.systemId, &systemProperties));

    // Log system properties.
    std.log.info("System Properties: Name={s} VendorId={}", .{
        systemProperties.systemName,
        systemProperties.vendorId,
    });
    std.log.info("System Graphics Properties: MaxWidth={} MaxHeight={} MaxLayers={}", .{
        systemProperties.graphicsProperties.maxSwapchainImageWidth,
        systemProperties.graphicsProperties.maxSwapchainImageHeight,
        systemProperties.graphicsProperties.maxLayerCount,
    });
    std.log.info("System Tracking Properties: OrientationTracking={s} PositionTracking={s}", .{
        if (systemProperties.trackingProperties.orientationTracking == c.XR_TRUE) "True" else "False",
        if (systemProperties.trackingProperties.positionTracking == c.XR_TRUE) "True" else "False",
    });

    // Note: No other view configurations exist at the time this code was written.
    // If this condition is not met,
    // the project will need to be audited to see how support should be added.
    if (this.options.Parsed.ViewConfigType != c.XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO) {
        xr_util.my_panic("Unsupported view configuration type", .{});
    }

    // Query and cache view configuration views.
    var viewCount: u32 = undefined;
    try xr_result.check(c.xrEnumerateViewConfigurationViews(
        this.instance,
        this.systemId,
        this.options.Parsed.ViewConfigType,
        0,
        &viewCount,
        null,
    ));
    try this.configViews.resize(viewCount);
    for (this.configViews.items) |*configView| {
        configView.* = .{
            .type = c.XR_TYPE_VIEW_CONFIGURATION_VIEW,
        };
    }
    try xr_result.check(c.xrEnumerateViewConfigurationViews(
        this.instance,
        this.systemId,
        this.options.Parsed.ViewConfigType,
        viewCount,
        &viewCount,
        &this.configViews.items[0],
    ));

    // Create and cache view buffer for xrLocateViews later.
    try this.views.resize(viewCount);
    for (this.views.items) |*view| {
        view.* = .{
            .type = c.XR_TYPE_VIEW,
        };
    }

    // Create the swapchain and get the images.
    if (viewCount > 0) {
        // Select a swapchain format.
        var swapchainFormatCount: u32 = undefined;
        try xr_result.check(c.xrEnumerateSwapchainFormats(
            this.session,
            0,
            &swapchainFormatCount,
            null,
        ));
        const swapchainFormats = try this.allocator.alloc(i64, swapchainFormatCount);
        defer this.allocator.free(swapchainFormats);
        try xr_result.check(c.xrEnumerateSwapchainFormats(
            this.session,
            @intCast(swapchainFormats.len),
            &swapchainFormatCount,
            &swapchainFormats[0],
        ));
        try xr_util.assert(swapchainFormatCount == swapchainFormats.len);
        this.colorSwapchainFormat = this.graphics.selectColorSwapchainFormat(swapchainFormats) orelse {
            xr_util.my_panic("selectColorSwapchainFormat", .{});
        };

        // Print swapchain formats and the selected one.
        {
            //         std::string swapchainFormatsString;
            //         for (int64_t format : swapchainFormats) {
            //             const bool selected = format == m_colorSwapchainFormat;
            //             swapchainFormatsString += " ";
            //             if (selected) {
            //                 swapchainFormatsString += "[";
            //             }
            //             swapchainFormatsString += std::to_string(format);
            //             if (selected) {
            //                 swapchainFormatsString += "]";
            //             }
            //         }
            //         Log::Write(Log::Level::Verbose, Fmt("Swapchain Formats: %s", swapchainFormatsString.c_str()));
        }

        // Create a swapchain for each view.
        for (0..viewCount) |i| {
            const vp = this.configViews.items[i];
            std.log.info("Creating swapchain for view {} with dimensions Width={} Height={} SampleCount={}", .{
                i,
                vp.recommendedImageRectWidth,
                vp.recommendedImageRectHeight,
                vp.recommendedSwapchainSampleCount,
            });

            // Create the swapchain.
            const swapchainCreateInfo = c.XrSwapchainCreateInfo{
                .type = c.XR_TYPE_SWAPCHAIN_CREATE_INFO,
                .arraySize = 1,
                .format = this.colorSwapchainFormat,
                .width = vp.recommendedImageRectWidth,
                .height = vp.recommendedImageRectHeight,
                .mipCount = 1,
                .faceCount = 1,
                .sampleCount = this.graphics.getSupportedSwapchainSampleCount(vp),
                .usageFlags = c.XR_SWAPCHAIN_USAGE_SAMPLED_BIT | c.XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT,
            };
            var swapchain = Swapchain{
                .width = swapchainCreateInfo.width,
                .height = swapchainCreateInfo.height,
                .handle = null,
            };
            try xr_result.check(c.xrCreateSwapchain(this.session, &swapchainCreateInfo, &swapchain.handle));
            try this.swapchains.append(swapchain);

            // const swapchainBuffer = try this.allocator.alloc(*c.XrSwapchainImageBaseHeader, imageCount);
            // if (!this.graphics.allocateSwapchainImageStructs(swapchainCreateInfo, swapchainBuffer)) {
            //     return error.allocateSwapchainImageStructs;
            // }
            // try this.swapchainImageMap.put(swapchain.handle, swapchainBuffer);

            var imageCount: u32 = undefined;
            try xr_result.check(c.xrEnumerateSwapchainImages(swapchain.handle, 0, &imageCount, null));
            const swapchainBuffer = this.graphics.allocateSwapchainImageStructs(swapchain.handle, imageCount);
            try xr_result.check(c.xrEnumerateSwapchainImages(
                swapchain.handle,
                imageCount,
                &imageCount,
                swapchainBuffer,
            ));
        }
    }
}

pub fn pollEvents(
    this: *@This(),
    exitRenderLoop: *bool,
    requestRestart: *bool,
) !void {
    exitRenderLoop.* = false;
    requestRestart.* = false;

    // Process all pending messages.
    while (try this.tryReadNextEvent()) |event| {
        switch (event.type) {
            c.XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING => {
                const instanceLossPending: *const c.XrEventDataInstanceLossPending = @ptrCast(event);
                std.log.warn("XrEventDataInstanceLossPending by {}ns", .{
                    instanceLossPending.lossTime,
                });
                exitRenderLoop.* = true;
                requestRestart.* = true;
                break;
            },
            c.XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED => {
                const sessionStateChangedEvent: *const c.XrEventDataSessionStateChanged = @ptrCast(event);
                try this.handleSessionStateChangedEvent(sessionStateChangedEvent, exitRenderLoop, requestRestart);
            },
            c.XR_TYPE_EVENT_DATA_INTERACTION_PROFILE_CHANGED => {
                //             LogActionSourceName(m_input.grabAction, "Grab");
                //             LogActionSourceName(m_input.quitAction, "Quit");
                //             LogActionSourceName(m_input.poseAction, "Pose");
                //             LogActionSourceName(m_input.vibrateAction, "Vibrate");
            },
            // c.XR_TYPE_EVENT_DATA_REFERENCE_SPACE_CHANGE_PENDING=>:
            else => {
                std.log.debug("Ignoring event type {}", .{event.type});
            },
        }
    }
}

fn handleSessionStateChangedEvent(
    this: *@This(),
    stateChangedEvent: *const c.XrEventDataSessionStateChanged,
    exitRenderLoop: *bool,
    requestRestart: *bool,
) !void {
    const oldState = this.sessionState;
    this.sessionState = stateChangedEvent.state;

    std.log.info("XrEventDataSessionStateChanged: state {}->{} session={any} time={}", .{
        oldState,
        this.sessionState,
        stateChangedEvent.session,
        stateChangedEvent.time,
    });

    if (stateChangedEvent.session != null and stateChangedEvent.session != this.session) {
        xr_util.my_panic("XrEventDataSessionStateChanged for unknown session", .{});
    }

    switch (this.sessionState) {
        c.XR_SESSION_STATE_READY => {
            try xr_util.assert(this.session != null);
            const sessionBeginInfo = c.XrSessionBeginInfo{
                .type = c.XR_TYPE_SESSION_BEGIN_INFO,
                .primaryViewConfigurationType = this.options.Parsed.ViewConfigType,
            };
            try xr_result.check(c.xrBeginSession(this.session, &sessionBeginInfo));
            this.sessionRunning = true;
        },
        c.XR_SESSION_STATE_STOPPING => {
            try xr_util.assert(this.session != null);
            this.sessionRunning = false;
            try xr_result.check(c.xrEndSession(this.session));
        },
        c.XR_SESSION_STATE_EXITING => {
            exitRenderLoop.* = true;
            // Do not attempt to restart because user closed this session.
            requestRestart.* = false;
        },
        c.XR_SESSION_STATE_LOSS_PENDING => {
            exitRenderLoop.* = true;
            // Poll for a new instance.
            requestRestart.* = true;
        },
        else => {},
    }
}

// Return event if one is available, otherwise return null.
fn tryReadNextEvent(this: *@This()) !?*const c.XrEventDataBaseHeader {
    // It is sufficient to clear the just the XrEventDataBuffer header to XR_TYPE_EVENT_DATA_BUFFER
    const baseHeader: *c.XrEventDataBaseHeader = @ptrCast(&this.eventDataBuffer);
    baseHeader.* = .{
        .type = c.XR_TYPE_EVENT_DATA_BUFFER,
    };
    const ev = c.xrPollEvent(this.instance, &this.eventDataBuffer);
    if (ev == 0
        // c.XR_SUCCEEDED
    ) {
        if (baseHeader.type == c.XR_TYPE_EVENT_DATA_EVENTS_LOST) {
            const eventsLost: *const c.XrEventDataEventsLost = @ptrCast(baseHeader);
            std.log.warn("{} events lost", .{eventsLost.lostEventCount});
        }

        return baseHeader;
    }
    if (ev == c.XR_EVENT_UNAVAILABLE) {
        return null;
    }
    xr_util.my_panic("xrPollEvent", .{});
}

pub fn beginFrame(this: *@This()) !c.XrFrameState {
    try xr_util.assert(this.session != null);

    var frameWaitInfo = c.XrFrameWaitInfo{
        .type = c.XR_TYPE_FRAME_WAIT_INFO,
    };
    var frameState = c.XrFrameState{
        .type = c.XR_TYPE_FRAME_STATE,
    };
    try xr_result.check(c.xrWaitFrame(this.session, &frameWaitInfo, &frameState));

    var frameBeginInfo = c.XrFrameBeginInfo{
        .type = c.XR_TYPE_FRAME_BEGIN_INFO,
    };
    try xr_result.check(c.xrBeginFrame(this.session, &frameBeginInfo));
    // return frameState;

    return frameState;
}

pub fn locateView(this: *@This(), space: c.XrSpace, predictedDisplayTime: i64) !c.XrViewState {
    var viewLocateInfo = c.XrViewLocateInfo{
        .type = c.XR_TYPE_VIEW_LOCATE_INFO,
        .viewConfigurationType = this.options.Parsed.ViewConfigType,
        .displayTime = predictedDisplayTime,
        .space = space,
    };
    var viewState = c.XrViewState{
        .type = c.XR_TYPE_VIEW_STATE,
    };
    var viewCountOutput: u32 = undefined;
    try xr_result.check(c.xrLocateViews(
        this.session,
        &viewLocateInfo,
        &viewState,
        @intCast(this.views.items.len),
        &viewCountOutput,
        &this.views.items[0],
    ));
    return viewState;
}

pub fn endFrame(
    this: @This(),
    space: c.XrSpace,
    predictedDisplayTime: i64,
    views: []c.XrCompositionLayerProjectionView,
    maybe_passthrough: ?c.XrPassthroughLayerFB,
) !void {
    var frameEndInfo = c.XrFrameEndInfo{
        .type = c.XR_TYPE_FRAME_END_INFO,
        .displayTime = predictedDisplayTime,
        // .environmentBlendMode = this.options.Parsed.EnvironmentBlendMode,
        .environmentBlendMode = c.XR_ENVIRONMENT_BLEND_MODE_OPAQUE,
        .layerCount = 0,
        .layers = null,
    };

    var composition_layers: [2]*c.XrCompositionLayerBaseHeader = undefined;

    var composition_layer_passthrough: c.XrCompositionLayerPassthroughFB = undefined;
    if (maybe_passthrough) |passthrough| {
        composition_layer_passthrough = .{
            .type = c.XR_TYPE_COMPOSITION_LAYER_PASSTHROUGH_FB,
            .layerHandle = passthrough,
            .flags = c.XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT,
            .space = null,
        };
        composition_layers[frameEndInfo.layerCount] = @ptrCast(&composition_layer_passthrough);
        frameEndInfo.layerCount += 1;
        frameEndInfo.layers = &composition_layers[0];
    }

    var composition_layer_projection: c.XrCompositionLayerProjection = undefined;
    if (views.len > 0) {
        composition_layer_projection = .{
            .type = c.XR_TYPE_COMPOSITION_LAYER_PROJECTION,
            .space = space,
            .layerFlags = //if (this.options.Parsed.EnvironmentBlendMode == c.XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND)
            c.XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT | c.XR_COMPOSITION_LAYER_UNPREMULTIPLIED_ALPHA_BIT
            // else
            //     0,
            ,
            .viewCount = @intCast(views.len),
            .views = &views[0],
        };
        composition_layers[frameEndInfo.layerCount] = @ptrCast(&composition_layer_projection);
        frameEndInfo.layerCount += 1;
        frameEndInfo.layers = &composition_layers[0];
    }

    try xr_result.check(c.xrEndFrame(this.session, &frameEndInfo));
}
