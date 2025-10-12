const std = @import("std");
const Options = @import("Options.zig");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr_util = @import("xr_util.zig");
const xr_result = @import("xr_result.zig");
const geometry = @import("geometry.zig");
const c = xr_util.c;
const xr = @import("openxr");
const InputState = @import("InputState.zig");

const Swapchain = struct {
    handle: xr.XrSwapchain,
    width: u32,
    height: u32,
};

allocator: std.mem.Allocator,
options: Options,
graphics: GraphicsPlugin,
instance: xr.XrInstance = null,
systemId: xr.XrSystemId = xr.XR_NULL_SYSTEM_ID,
session: xr.XrSession = null,
appSpace: xr.XrSpace = null,

configViews: std.array_list.Managed(xr.XrViewConfigurationView),
views: std.array_list.Managed(xr.XrView),
swapchains: std.array_list.Managed(Swapchain),
colorSwapchainFormat: i64 = -1,

// Application's current lifecycle state according to the runtime
sessionState: xr.XrSessionState = xr.XR_SESSION_STATE_UNKNOWN,
sessionRunning: bool = false,

eventDataBuffer: xr.XrEventDataBuffer = .{},
input: InputState = .{},

const ACCEPTABLE_BLENDMODES = [_]xr.XrEnvironmentBlendMode{
    xr.XR_ENVIRONMENT_BLEND_MODE_OPAQUE,
    xr.XR_ENVIRONMENT_BLEND_MODE_ADDITIVE,
    xr.XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND,
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
        .configViews = std.array_list.Managed(xr.XrViewConfigurationView).init(allocator),
        .views = std.array_list.Managed(xr.XrView).init(allocator),
        .swapchains = std.array_list.Managed(Swapchain).init(allocator),
    };
}

pub fn deinit(self: *@This()) void {
    std.log.debug("#### OpenXrProgram.deinit ####", .{});
    self.swapchains.deinit();
    self.views.deinit();
    self.configViews.deinit();
}

pub fn createInstance(
    self: *@This(),
    platform_extensions: []const []const u8,
    instance_create_extension: ?*anyopaque,
) !void {
    try self.logLayersAndExtensions();
    try self.createInstanceInternal(platform_extensions, instance_create_extension);
    try self.logInstanceInfo();
}

fn logLayersAndExtensions(self: *@This()) !void {
    // Write out extension properties for a given layer.

    // Log non-layer extensions (layerName==nullptr).
    // try self.logExtensions("", "");

    // Log layers and any of their extensions.
    {
        var layerCount: u32 = undefined;
        _ = try xr_result.check(xr.xrEnumerateApiLayerProperties(0, &layerCount, null));
        std.log.info("Available Layers: ({})", .{layerCount});
        if (layerCount > 0) {
            var layers = try self.allocator.alloc(xr.XrApiLayerProperties, layerCount);
            // std::vector<XrApiLayerProperties> layers(layerCount, {XR_TYPE_API_LAYER_PROPERTIES});
            _ = try xr_result.check(xr.xrEnumerateApiLayerProperties(@intCast(layers.len), &layerCount, &layers[0]));

            for (layers) |layer| {
                std.log.debug("  Name={s} SpecVersion={}.{}.{} LayerVersion={} Description={s}", .{
                    layer.layerName,
                    // GetXrVersionString(layer.specVersion).c_str(),
                    xr.XR_VERSION_MAJOR(layer.specVersion),
                    xr.XR_VERSION_MINOR(layer.specVersion),
                    xr.XR_VERSION_PATCH(layer.specVersion),
                    layer.layerVersion,
                    layer.description,
                });
                try self.logExtensions(@ptrCast(&layer.layerName), "    ");
            }
        }
    }
}

fn logExtensions(self: *@This(), layerName: [*:0]const u8, indent: []const u8) !void {
    var instanceExtensionCount: u32 = undefined;
    _ = try xr_result.check(xr.xrEnumerateInstanceExtensionProperties(layerName, 0, &instanceExtensionCount, null));
    std.log.debug("{s}Available Extensions: ({})", .{ indent, instanceExtensionCount });

    if (instanceExtensionCount > 0) {
        var extensions = try self.allocator.alloc(xr.XrExtensionProperties, instanceExtensionCount);
        defer self.allocator.free(extensions);
        for (extensions) |*ex| {
            ex.* = .{
                .type = xr.XR_TYPE_EXTENSION_PROPERTIES,
            };
        }
        _ = try xr_result.check(xr.xrEnumerateInstanceExtensionProperties(
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
    self: *@This(),
    platform_extensions: []const []const u8,
    instance_create_extension: ?*anyopaque,
) !void {
    try xr_util.assert(self.instance == null);
    //
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    // Create union of extensions required by platform and graphics plugins.
    var extensions = std.array_list.Managed([*:0]const u8).init(self.allocator);
    defer extensions.deinit();

    // Transform platform and graphics extension std::strings to C strings.
    for (platform_extensions) |extension| {
        const copyz: [*:0]const u8 = try allocator.dupeZ(u8, extension);
        try extensions.append(copyz);
    }

    const graphics_extensions = self.graphics.getInstanceExtensions();
    for (graphics_extensions) |extension| {
        const copyz: [*:0]const u8 = try allocator.dupeZ(u8, extension);
        try extensions.append(copyz);
    }

    var createInfo = xr.XrInstanceCreateInfo{
        .type = xr.XR_TYPE_INSTANCE_CREATE_INFO,
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
        .apiVersion = xr.XR_API_VERSION_1_0,
        .applicationVersion = 0,
        .engineVersion = 0,
    };
    _ = try std.fmt.bufPrintZ(&createInfo.applicationInfo.applicationName, "{s}", .{"hello_xr"});
    _ = try std.fmt.bufPrintZ(&createInfo.applicationInfo.engineName, "{s}", .{"hello_xr.engine"});

    try xr_result.check(xr.xrCreateInstance(&createInfo, &self.instance));
}

fn logInstanceInfo(self: *@This()) !void {
    try xr_util.assert(self.instance != null);

    var instanceProperties = xr.XrInstanceProperties{
        .type = xr.XR_TYPE_INSTANCE_PROPERTIES,
    };
    try xr_result.check(xr.xrGetInstanceProperties(self.instance, &instanceProperties));

    std.log.info("Instance RuntimeName={s} RuntimeVersion={}", .{
        instanceProperties.runtimeName,
        xr_util.ExtractVersion.fromXrVersion(instanceProperties.runtimeVersion),
    });
}

pub fn initializeSystem(self: *@This()) !void {
    try xr_util.assert(self.instance != null);
    try xr_util.assert(self.systemId == xr.XR_NULL_SYSTEM_ID);

    var systemInfo = xr.XrSystemGetInfo{
        .type = xr.XR_TYPE_SYSTEM_GET_INFO,
        .next = null,
        .formFactor = self.options.Parsed.FormFactor,
    };
    try xr_result.check(xr.xrGetSystem(self.instance, &systemInfo, &self.systemId));

    std.log.debug("Using system {} for form factor {}", .{
        self.systemId,
        self.options.Parsed.FormFactor,
    });
    try xr_util.assert(self.instance != null);
    try xr_util.assert(self.systemId != xr.XR_NULL_SYSTEM_ID);
}

pub fn getPreferredBlendMode(self: @This()) !xr.XrEnvironmentBlendMode {
    var count: u32 = undefined;
    try xr_result.check(xr.xrEnumerateEnvironmentBlendModes(
        self.instance,
        self.systemId,
        self.options.Parsed.ViewConfigType,
        0,
        &count,
        null,
    ));
    try xr_util.assert(count > 0);

    const blendModes = try self.allocator.alloc(xr.XrEnvironmentBlendMode, count);
    defer self.allocator.free(blendModes);
    try xr_result.check(xr.xrEnumerateEnvironmentBlendModes(
        self.instance,
        self.systemId,
        self.options.Parsed.ViewConfigType,
        count,
        &count,
        &blendModes[0],
    ));

    for (blendModes) |blendMode| {
        if (std.mem.containsAtLeastScalar(
            xr.XrEnvironmentBlendMode,
            &ACCEPTABLE_BLENDMODES,
            1,
            blendMode,
        )) return blendMode;
    }

    unreachable;
}

pub fn initializeDevice(self: *@This()) !void {
    try self.logViewConfigurations();

    // The graphics API can initialize the graphics device now that the systemId and instance handle are available.
    try self.graphics.initializeDevice(@ptrCast(self.instance), self.systemId);
}

fn logViewConfigurations(self: @This()) !void {
    try xr_util.assert(self.instance != null);
    try xr_util.assert(self.systemId != xr.XR_NULL_SYSTEM_ID);

    var viewConfigTypeCount: u32 = undefined;
    try xr_result.check(xr.xrEnumerateViewConfigurations(self.instance, self.systemId, 0, &viewConfigTypeCount, null));
    const viewConfigTypes = try self.allocator.alloc(xr.XrViewConfigurationType, viewConfigTypeCount);
    defer self.allocator.free(viewConfigTypes);
    try xr_result.check(xr.xrEnumerateViewConfigurations(self.instance, self.systemId, viewConfigTypeCount, &viewConfigTypeCount, &viewConfigTypes[0]));
    try xr_util.assert(viewConfigTypes.len == viewConfigTypeCount);

    std.log.info("Available View Configuration Types: ({})", .{viewConfigTypeCount});
    for (viewConfigTypes) |viewConfigType| {
        std.log.debug("  View Configuration Type: {} {s}", .{
            viewConfigType,
            if (viewConfigType == self.options.Parsed.ViewConfigType) "(Selected)" else "",
        });

        var viewConfigProperties = xr.XrViewConfigurationProperties{
            .type = xr.XR_TYPE_VIEW_CONFIGURATION_PROPERTIES,
        };
        try xr_result.check(xr.xrGetViewConfigurationProperties(
            self.instance,
            self.systemId,
            viewConfigType,
            &viewConfigProperties,
        ));

        std.log.debug("  View configuration FovMutable={s}", .{
            if (viewConfigProperties.fovMutable == xr.XR_TRUE) "True" else "False",
        });

        var viewCount: u32 = undefined;
        try xr_result.check(xr.xrEnumerateViewConfigurationViews(
            self.instance,
            self.systemId,
            viewConfigType,
            0,
            &viewCount,
            null,
        ));
        if (viewCount > 0) {
            const views = try self.allocator.alloc(xr.XrViewConfigurationView, viewCount);
            defer self.allocator.free(views);
            for (views) |*view| {
                view.* = .{ .type = xr.XR_TYPE_VIEW_CONFIGURATION_VIEW };
            }
            try xr_result.check(xr.xrEnumerateViewConfigurationViews(
                self.instance,
                self.systemId,
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

        try self.logEnvironmentBlendMode(viewConfigType);
    }
}

fn logEnvironmentBlendMode(self: @This(), view_type: xr.XrViewConfigurationType) !void {
    try xr_util.assert(self.instance != null);
    try xr_util.assert(self.systemId != 0);

    var count: u32 = undefined;
    try xr_result.check(xr.xrEnumerateEnvironmentBlendModes(self.instance, self.systemId, view_type, 0, &count, null));
    try xr_util.assert(count > 0);

    std.log.info("Available Environment Blend Mode count : ({})", .{count});

    const blendModes = try self.allocator.alloc(xr.XrEnvironmentBlendMode, count);
    defer self.allocator.free(blendModes);
    try xr_result.check(xr.xrEnumerateEnvironmentBlendModes(
        self.instance,
        self.systemId,
        view_type,
        count,
        &count,
        &blendModes[0],
    ));

    var blendModeFound = false;
    for (blendModes) |mode| {
        const blendModeMatch = (mode == self.options.Parsed.EnvironmentBlendMode);
        std.log.info(
            "Environment Blend Mode ({}) : {s}",
            .{ mode, if (blendModeMatch) "(Selected)" else "" },
        );
        blendModeFound |= blendModeMatch;
    }
    try xr_util.assert(blendModeFound);
}

pub fn initializeSession(self: *@This()) !void {
    try xr_util.assert(self.instance != null);
    try xr_util.assert(self.session == null);

    {
        std.log.debug("Creating session...", .{});

        var createInfo = xr.XrSessionCreateInfo{
            .type = xr.XR_TYPE_SESSION_CREATE_INFO,
            .next = self.graphics.getGraphicsBinding(),
            .systemId = self.systemId,
        };
        try xr_result.check(xr.xrCreateSession(self.instance, &createInfo, &self.session));
    }

    try self.logReferenceSpaces();
    // try self.initializeActions();

    {
        const referenceSpaceCreateInfo = try xr_util.getXrReferenceSpaceCreateInfo(self.options.AppSpace);
        try xr_result.check(xr.xrCreateReferenceSpace(self.session, &referenceSpaceCreateInfo, &self.appSpace));
    }
}

fn logReferenceSpaces(self: @This()) !void {
    try xr_util.assert(self.session != null);

    var spaceCount: u32 = undefined;
    try xr_result.check(xr.xrEnumerateReferenceSpaces(self.session, 0, &spaceCount, null));
    const spaces = try self.allocator.alloc(xr.XrReferenceSpaceType, spaceCount);
    defer self.allocator.free(spaces);
    try xr_result.check(xr.xrEnumerateReferenceSpaces(self.session, spaceCount, &spaceCount, &spaces[0]));

    std.log.info("Available reference spaces: {}", .{spaceCount});
    for (spaces) |space| {
        std.log.debug("  Name: {}", .{space});
    }
}

pub fn createSwapchains(self: *@This()) !void {
    try xr_util.assert(self.session != null);
    try xr_util.assert(self.swapchains.items.len == 0);
    try xr_util.assert(self.configViews.items.len == 0);

    // Read graphics properties for preferred swapchain length and logging.
    var systemProperties = xr.XrSystemProperties{
        .type = xr.XR_TYPE_SYSTEM_PROPERTIES,
    };
    try xr_result.check(xr.xrGetSystemProperties(self.instance, self.systemId, &systemProperties));

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
        if (systemProperties.trackingProperties.orientationTracking == xr.XR_TRUE) "True" else "False",
        if (systemProperties.trackingProperties.positionTracking == xr.XR_TRUE) "True" else "False",
    });

    // Note: No other view configurations exist at the time this code was written.
    // If this condition is not met,
    // the project will need to be audited to see how support should be added.
    if (self.options.Parsed.ViewConfigType != xr.XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO) {
        xr_util.my_panic("Unsupported view configuration type", .{});
    }

    // Query and cache view configuration views.
    var viewCount: u32 = undefined;
    try xr_result.check(xr.xrEnumerateViewConfigurationViews(
        self.instance,
        self.systemId,
        self.options.Parsed.ViewConfigType,
        0,
        &viewCount,
        null,
    ));
    try self.configViews.resize(viewCount);
    for (self.configViews.items) |*configView| {
        configView.* = .{
            .type = xr.XR_TYPE_VIEW_CONFIGURATION_VIEW,
        };
    }
    try xr_result.check(xr.xrEnumerateViewConfigurationViews(
        self.instance,
        self.systemId,
        self.options.Parsed.ViewConfigType,
        viewCount,
        &viewCount,
        &self.configViews.items[0],
    ));

    // Create and cache view buffer for xrLocateViews later.
    try self.views.resize(viewCount);
    for (self.views.items) |*view| {
        view.* = .{
            .type = xr.XR_TYPE_VIEW,
        };
    }

    // Create the swapchain and get the images.
    if (viewCount > 0) {
        // Select a swapchain format.
        var swapchainFormatCount: u32 = undefined;
        try xr_result.check(xr.xrEnumerateSwapchainFormats(
            self.session,
            0,
            &swapchainFormatCount,
            null,
        ));
        const swapchainFormats = try self.allocator.alloc(i64, swapchainFormatCount);
        defer self.allocator.free(swapchainFormats);
        try xr_result.check(xr.xrEnumerateSwapchainFormats(
            self.session,
            @intCast(swapchainFormats.len),
            &swapchainFormatCount,
            &swapchainFormats[0],
        ));
        try xr_util.assert(swapchainFormatCount == swapchainFormats.len);
        self.colorSwapchainFormat = self.graphics.selectColorSwapchainFormat(swapchainFormats) orelse {
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
            const vp = self.configViews.items[i];
            std.log.info("Creating swapchain for view {} with dimensions Width={} Height={} SampleCount={}", .{
                i,
                vp.recommendedImageRectWidth,
                vp.recommendedImageRectHeight,
                vp.recommendedSwapchainSampleCount,
            });

            // Create the swapchain.
            const swapchainCreateInfo = xr.XrSwapchainCreateInfo{
                .type = xr.XR_TYPE_SWAPCHAIN_CREATE_INFO,
                .arraySize = 1,
                .format = self.colorSwapchainFormat,
                .width = vp.recommendedImageRectWidth,
                .height = vp.recommendedImageRectHeight,
                .mipCount = 1,
                .faceCount = 1,
                .sampleCount = self.graphics.getSupportedSwapchainSampleCount(vp),
                .usageFlags = xr.XR_SWAPCHAIN_USAGE_SAMPLED_BIT | xr.XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT,
            };
            var swapchain = Swapchain{
                .width = swapchainCreateInfo.width,
                .height = swapchainCreateInfo.height,
                .handle = null,
            };
            try xr_result.check(xr.xrCreateSwapchain(self.session, &swapchainCreateInfo, &swapchain.handle));
            try self.swapchains.append(swapchain);

            // const swapchainBuffer = try self.allocator.alloc(*xr.XrSwapchainImageBaseHeader, imageCount);
            // if (!self.graphics.allocateSwapchainImageStructs(swapchainCreateInfo, swapchainBuffer)) {
            //     return error.allocateSwapchainImageStructs;
            // }
            // try self.swapchainImageMap.put(swapchain.handle, swapchainBuffer);

            var imageCount: u32 = undefined;
            try xr_result.check(xr.xrEnumerateSwapchainImages(swapchain.handle, 0, &imageCount, null));
            const swapchainBuffer = self.graphics.allocateSwapchainImageStructs(swapchain.handle, imageCount);
            try xr_result.check(xr.xrEnumerateSwapchainImages(
                swapchain.handle,
                imageCount,
                &imageCount,
                swapchainBuffer,
            ));
        }
    }
}

pub fn pollEvents(
    self: *@This(),
    exitRenderLoop: *bool,
    requestRestart: *bool,
) !void {
    exitRenderLoop.* = false;
    requestRestart.* = false;

    // Process all pending messages.
    while (try self.tryReadNextEvent()) |event| {
        switch (event.type) {
            xr.XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING => {
                const instanceLossPending: *const xr.XrEventDataInstanceLossPending = @ptrCast(event);
                std.log.warn("XrEventDataInstanceLossPending by {}ns", .{
                    instanceLossPending.lossTime,
                });
                exitRenderLoop.* = true;
                requestRestart.* = true;
                break;
            },
            xr.XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED => {
                const sessionStateChangedEvent: *const xr.XrEventDataSessionStateChanged = @ptrCast(event);
                try self.handleSessionStateChangedEvent(sessionStateChangedEvent, exitRenderLoop, requestRestart);
            },
            xr.XR_TYPE_EVENT_DATA_INTERACTION_PROFILE_CHANGED => {
                //             LogActionSourceName(m_input.grabAction, "Grab");
                //             LogActionSourceName(m_input.quitAction, "Quit");
                //             LogActionSourceName(m_input.poseAction, "Pose");
                //             LogActionSourceName(m_input.vibrateAction, "Vibrate");
            },
            // xr.XR_TYPE_EVENT_DATA_REFERENCE_SPACE_CHANGE_PENDING=>:
            else => {
                std.log.debug("Ignoring event type {}", .{event.type});
            },
        }
    }
}

fn handleSessionStateChangedEvent(
    self: *@This(),
    stateChangedEvent: *const xr.XrEventDataSessionStateChanged,
    exitRenderLoop: *bool,
    requestRestart: *bool,
) !void {
    const oldState = self.sessionState;
    self.sessionState = stateChangedEvent.state;

    std.log.info("XrEventDataSessionStateChanged: state {}->{} session={any} time={}", .{
        oldState,
        self.sessionState,
        stateChangedEvent.session,
        stateChangedEvent.time,
    });

    if (stateChangedEvent.session != null and stateChangedEvent.session != self.session) {
        xr_util.my_panic("XrEventDataSessionStateChanged for unknown session", .{});
    }

    switch (self.sessionState) {
        xr.XR_SESSION_STATE_READY => {
            try xr_util.assert(self.session != null);
            const sessionBeginInfo = xr.XrSessionBeginInfo{
                .type = xr.XR_TYPE_SESSION_BEGIN_INFO,
                .primaryViewConfigurationType = self.options.Parsed.ViewConfigType,
            };
            try xr_result.check(xr.xrBeginSession(self.session, &sessionBeginInfo));
            self.sessionRunning = true;
        },
        xr.XR_SESSION_STATE_STOPPING => {
            try xr_util.assert(self.session != null);
            self.sessionRunning = false;
            try xr_result.check(xr.xrEndSession(self.session));
        },
        xr.XR_SESSION_STATE_EXITING => {
            exitRenderLoop.* = true;
            // Do not attempt to restart because user closed this session.
            requestRestart.* = false;
        },
        xr.XR_SESSION_STATE_LOSS_PENDING => {
            exitRenderLoop.* = true;
            // Poll for a new instance.
            requestRestart.* = true;
        },
        else => {},
    }
}

// Return event if one is available, otherwise return null.
fn tryReadNextEvent(self: *@This()) !?*const xr.XrEventDataBaseHeader {
    // It is sufficient to clear the just the XrEventDataBuffer header to XR_TYPE_EVENT_DATA_BUFFER
    const baseHeader: *xr.XrEventDataBaseHeader = @ptrCast(&self.eventDataBuffer);
    baseHeader.* = .{
        .type = xr.XR_TYPE_EVENT_DATA_BUFFER,
    };
    const ev = xr.xrPollEvent(self.instance, &self.eventDataBuffer);
    if (ev == 0
        // xr.XR_SUCCEEDED
    ) {
        if (baseHeader.type == xr.XR_TYPE_EVENT_DATA_EVENTS_LOST) {
            const eventsLost: *const xr.XrEventDataEventsLost = @ptrCast(baseHeader);
            std.log.warn("{} events lost", .{eventsLost.lostEventCount});
        }

        return baseHeader;
    }
    if (ev == xr.XR_EVENT_UNAVAILABLE) {
        return null;
    }
    xr_util.my_panic("xrPollEvent", .{});
}

pub fn beginFrame(self: *@This()) !xr.XrFrameState {
    try xr_util.assert(self.session != null);

    var frameWaitInfo = xr.XrFrameWaitInfo{
        .type = xr.XR_TYPE_FRAME_WAIT_INFO,
    };
    var frameState = xr.XrFrameState{
        .type = xr.XR_TYPE_FRAME_STATE,
    };
    try xr_result.check(xr.xrWaitFrame(self.session, &frameWaitInfo, &frameState));

    var frameBeginInfo = xr.XrFrameBeginInfo{
        .type = xr.XR_TYPE_FRAME_BEGIN_INFO,
    };
    try xr_result.check(xr.xrBeginFrame(self.session, &frameBeginInfo));
    // return frameState;

    return frameState;
}

pub fn locateView(self: *@This(), predictedDisplayTime: i64) !xr.XrViewState {
    var viewLocateInfo = xr.XrViewLocateInfo{
        .type = xr.XR_TYPE_VIEW_LOCATE_INFO,
        .viewConfigurationType = self.options.Parsed.ViewConfigType,
        .displayTime = predictedDisplayTime,
        .space = self.appSpace,
    };
    var viewState = xr.XrViewState{
        .type = xr.XR_TYPE_VIEW_STATE,
    };
    var viewCountOutput: u32 = undefined;
    try xr_result.check(xr.xrLocateViews(
        self.session,
        &viewLocateInfo,
        &viewState,
        @intCast(self.views.items.len),
        &viewCountOutput,
        &self.views.items[0],
    ));
    return viewState;
}

pub fn endFrame(
    self: @This(),
    predictedDisplayTime: i64,
    views: []xr.XrCompositionLayerProjectionView,
) !void {
    var frameEndInfo = xr.XrFrameEndInfo{
        .type = xr.XR_TYPE_FRAME_END_INFO,
        .displayTime = predictedDisplayTime,
        .environmentBlendMode = self.options.Parsed.EnvironmentBlendMode,
        .layerCount = 0,
        .layers = null,
    };

    var composition_layers: [1]*xr.XrCompositionLayerBaseHeader = undefined;
    var composition_layer_projection: xr.XrCompositionLayerProjection = undefined;
    if (views.len > 0) {
        composition_layer_projection = .{
            .type = xr.XR_TYPE_COMPOSITION_LAYER_PROJECTION,
            .space = self.appSpace,
            .layerFlags = if (self.options.Parsed.EnvironmentBlendMode == xr.XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND)
                xr.XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT | xr.XR_COMPOSITION_LAYER_UNPREMULTIPLIED_ALPHA_BIT
            else
                0,
            .viewCount = @intCast(views.len),
            .views = &views[0],
        };
        composition_layers[0] = @ptrCast(&composition_layer_projection);
        frameEndInfo.layerCount = 1;
        frameEndInfo.layers = &composition_layers[0];
    }

    try xr_result.check(xr.xrEndFrame(self.session, &frameEndInfo));
}
