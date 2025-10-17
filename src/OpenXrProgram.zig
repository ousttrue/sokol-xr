const std = @import("std");
const Options = @import("Options.zig");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr_util = @import("xr_util.zig");
const xr_result = @import("xr_result.zig");
const geometry = @import("geometry.zig");
const c = xr_util.c;
const InputState = @import("InputState.zig");

const xr_gen = @import("openxr");
const xr = xr_gen.c;

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

configViews: std.array_list.Managed(xr.XrViewConfigurationView),
views: std.array_list.Managed(xr.XrView),
swapchains: std.array_list.Managed(Swapchain),
colorSwapchainFormat: i64 = -1,

// Application's current lifecycle state according to the runtime
sessionState: xr.XrSessionState = xr.XR_SESSION_STATE_UNKNOWN,
sessionRunning: bool = false,

eventDataBuffer: xr.XrEventDataBuffer = .{},
input: InputState = .{},

// extensions
passthrough: xr_gen.extensions.XR_FB_passthrough = .{},
passthroughFeature: xr.XrPassthroughFB = null,
passthroughLayer: xr.XrPassthroughLayerFB = null,

pub extern fn xrGetInstanceProcAddr(
    instance: *anyopaque,
    procname: [*:0]const u8,
    function: *anyopaque,
) i64;

pub fn getProcs(
    loader: anytype,
    instance: *anyopaque,
    table: anytype,
) void {
    inline for (std.meta.fields(@typeInfo(@TypeOf(table)).pointer.child)) |field| {
        const name: [*:0]const u8 = @ptrCast(field.name ++ "\x00");
        var cmd_ptr: xr.PFN_xrVoidFunction = undefined;
        const result = loader(instance, name, @ptrCast(&cmd_ptr));
        if (result != 0) @panic("loader");
        @field(table, field.name) = @ptrCast(cmd_ptr);
    }
}

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
        _ = try xr_result.check(xr.xrEnumerateApiLayerProperties(0, &layerCount, null));
        std.log.info("Available Layers: ({})", .{layerCount});
        if (layerCount > 0) {
            var layers = try this.allocator.alloc(xr.XrApiLayerProperties, layerCount);
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
                try this.logExtensions(@ptrCast(&layer.layerName), "    ");
            }
        }
    }
}

fn logExtensions(this: *@This(), layerName: [*:0]const u8, indent: []const u8) !void {
    var instanceExtensionCount: u32 = undefined;
    _ = try xr_result.check(xr.xrEnumerateInstanceExtensionProperties(layerName, 0, &instanceExtensionCount, null));
    std.log.debug("{s}Available Extensions: ({})", .{ indent, instanceExtensionCount });

    if (instanceExtensionCount > 0) {
        var extensions = try this.allocator.alloc(xr.XrExtensionProperties, instanceExtensionCount);
        defer this.allocator.free(extensions);
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

    try xr_result.check(xr.xrCreateInstance(&createInfo, &this.instance));
}

fn logInstanceInfo(this: *@This()) !void {
    try xr_util.assert(this.instance != null);

    var instanceProperties = xr.XrInstanceProperties{
        .type = xr.XR_TYPE_INSTANCE_PROPERTIES,
    };
    try xr_result.check(xr.xrGetInstanceProperties(this.instance, &instanceProperties));

    std.log.info("Instance RuntimeName={s} RuntimeVersion={}", .{
        instanceProperties.runtimeName,
        xr_util.ExtractVersion.fromXrVersion(instanceProperties.runtimeVersion),
    });
}

pub fn initializeSystem(this: *@This()) !void {
    try xr_util.assert(this.instance != null);
    try xr_util.assert(this.systemId == xr.XR_NULL_SYSTEM_ID);

    var systemInfo = xr.XrSystemGetInfo{
        .type = xr.XR_TYPE_SYSTEM_GET_INFO,
        .next = null,
        .formFactor = this.options.Parsed.FormFactor,
    };
    try xr_result.check(xr.xrGetSystem(this.instance, &systemInfo, &this.systemId));

    std.log.debug("Using system {} for form factor {}", .{
        this.systemId,
        this.options.Parsed.FormFactor,
    });
    try xr_util.assert(this.instance != null);
    try xr_util.assert(this.systemId != xr.XR_NULL_SYSTEM_ID);

    if (try systemSupportsPassthrough(this.instance, this.systemId)) {
        std.log.info("Passthrough supported", .{});
    } else {
        std.log.warn("Passthrough not supported", .{});
    }

    getProcs(xrGetInstanceProcAddr, @ptrCast(this.instance), &this.passthrough);
}

pub fn getPreferredBlendMode(this: @This()) !xr.XrEnvironmentBlendMode {
    var count: u32 = undefined;
    try xr_result.check(xr.xrEnumerateEnvironmentBlendModes(
        this.instance,
        this.systemId,
        this.options.Parsed.ViewConfigType,
        0,
        &count,
        null,
    ));
    try xr_util.assert(count > 0);

    const blendModes = try this.allocator.alloc(xr.XrEnvironmentBlendMode, count);
    defer this.allocator.free(blendModes);
    try xr_result.check(xr.xrEnumerateEnvironmentBlendModes(
        this.instance,
        this.systemId,
        this.options.Parsed.ViewConfigType,
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

pub fn initializeDevice(this: *@This()) !void {
    try this.logViewConfigurations();

    // The graphics API can initialize the graphics device now that the systemId and instance handle are available.
    try this.graphics.initializeDevice(@ptrCast(this.instance), this.systemId);
}

fn logViewConfigurations(this: @This()) !void {
    try xr_util.assert(this.instance != null);
    try xr_util.assert(this.systemId != xr.XR_NULL_SYSTEM_ID);

    var viewConfigTypeCount: u32 = undefined;
    try xr_result.check(xr.xrEnumerateViewConfigurations(this.instance, this.systemId, 0, &viewConfigTypeCount, null));
    const viewConfigTypes = try this.allocator.alloc(xr.XrViewConfigurationType, viewConfigTypeCount);
    defer this.allocator.free(viewConfigTypes);
    try xr_result.check(xr.xrEnumerateViewConfigurations(this.instance, this.systemId, viewConfigTypeCount, &viewConfigTypeCount, &viewConfigTypes[0]));
    try xr_util.assert(viewConfigTypes.len == viewConfigTypeCount);

    std.log.info("Available View Configuration Types: ({})", .{viewConfigTypeCount});
    for (viewConfigTypes) |viewConfigType| {
        std.log.debug("  View Configuration Type: {} {s}", .{
            viewConfigType,
            if (viewConfigType == this.options.Parsed.ViewConfigType) "(Selected)" else "",
        });

        var viewConfigProperties = xr.XrViewConfigurationProperties{
            .type = xr.XR_TYPE_VIEW_CONFIGURATION_PROPERTIES,
        };
        try xr_result.check(xr.xrGetViewConfigurationProperties(
            this.instance,
            this.systemId,
            viewConfigType,
            &viewConfigProperties,
        ));

        std.log.debug("  View configuration FovMutable={s}", .{
            if (viewConfigProperties.fovMutable == xr.XR_TRUE) "True" else "False",
        });

        var viewCount: u32 = undefined;
        try xr_result.check(xr.xrEnumerateViewConfigurationViews(
            this.instance,
            this.systemId,
            viewConfigType,
            0,
            &viewCount,
            null,
        ));
        if (viewCount > 0) {
            const views = try this.allocator.alloc(xr.XrViewConfigurationView, viewCount);
            defer this.allocator.free(views);
            for (views) |*view| {
                view.* = .{ .type = xr.XR_TYPE_VIEW_CONFIGURATION_VIEW };
            }
            try xr_result.check(xr.xrEnumerateViewConfigurationViews(
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

fn logEnvironmentBlendMode(this: @This(), view_type: xr.XrViewConfigurationType) !void {
    try xr_util.assert(this.instance != null);
    try xr_util.assert(this.systemId != 0);

    var count: u32 = undefined;
    try xr_result.check(xr.xrEnumerateEnvironmentBlendModes(this.instance, this.systemId, view_type, 0, &count, null));
    try xr_util.assert(count > 0);

    std.log.info("Available Environment Blend Mode count : ({})", .{count});

    const blendModes = try this.allocator.alloc(xr.XrEnvironmentBlendMode, count);
    defer this.allocator.free(blendModes);
    try xr_result.check(xr.xrEnumerateEnvironmentBlendModes(
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

        var createInfo = xr.XrSessionCreateInfo{
            .type = xr.XR_TYPE_SESSION_CREATE_INFO,
            .next = this.graphics.getGraphicsBinding(),
            .systemId = this.systemId,
        };
        try xr_result.check(xr.xrCreateSession(this.instance, &createInfo, &this.session));
    }

    try this.logReferenceSpaces();
    // try this.initializeActions();

    //
    // XR_FB_passthrough
    // https://developers.meta.com/horizon/documentation/native/android/mobile-passthrough/?locale=ja_JP
    //
    var passthroughCreateInfo = xr.XrPassthroughCreateInfoFB{
        .type = xr.XR_TYPE_PASSTHROUGH_CREATE_INFO_FB,
        .flags = xr.XR_PASSTHROUGH_IS_RUNNING_AT_CREATION_BIT_FB,
    };
    try xr_result.check(this.passthrough.xrCreatePassthroughFB.?(
        this.session,
        &passthroughCreateInfo,
        &this.passthroughFeature,
    ));

    var layerCreateInfo = xr.XrPassthroughLayerCreateInfoFB{
        .type = xr.XR_TYPE_PASSTHROUGH_LAYER_CREATE_INFO_FB,
        .passthrough = this.passthroughFeature,
        .purpose = xr.XR_PASSTHROUGH_LAYER_PURPOSE_RECONSTRUCTION_FB,
        .flags = xr.XR_PASSTHROUGH_IS_RUNNING_AT_CREATION_BIT_FB,
    };
    try xr_result.check(this.passthrough.xrCreatePassthroughLayerFB.?(
        this.session,
        &layerCreateInfo,
        &this.passthroughLayer,
    ));
}

fn logReferenceSpaces(this: @This()) !void {
    try xr_util.assert(this.session != null);

    var spaceCount: u32 = undefined;
    try xr_result.check(xr.xrEnumerateReferenceSpaces(this.session, 0, &spaceCount, null));
    const spaces = try this.allocator.alloc(xr.XrReferenceSpaceType, spaceCount);
    defer this.allocator.free(spaces);
    try xr_result.check(xr.xrEnumerateReferenceSpaces(this.session, spaceCount, &spaceCount, &spaces[0]));

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
    var systemProperties = xr.XrSystemProperties{
        .type = xr.XR_TYPE_SYSTEM_PROPERTIES,
    };
    try xr_result.check(xr.xrGetSystemProperties(this.instance, this.systemId, &systemProperties));

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
    if (this.options.Parsed.ViewConfigType != xr.XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO) {
        xr_util.my_panic("Unsupported view configuration type", .{});
    }

    // Query and cache view configuration views.
    var viewCount: u32 = undefined;
    try xr_result.check(xr.xrEnumerateViewConfigurationViews(
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
            .type = xr.XR_TYPE_VIEW_CONFIGURATION_VIEW,
        };
    }
    try xr_result.check(xr.xrEnumerateViewConfigurationViews(
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
            .type = xr.XR_TYPE_VIEW,
        };
    }

    // Create the swapchain and get the images.
    if (viewCount > 0) {
        // Select a swapchain format.
        var swapchainFormatCount: u32 = undefined;
        try xr_result.check(xr.xrEnumerateSwapchainFormats(
            this.session,
            0,
            &swapchainFormatCount,
            null,
        ));
        const swapchainFormats = try this.allocator.alloc(i64, swapchainFormatCount);
        defer this.allocator.free(swapchainFormats);
        try xr_result.check(xr.xrEnumerateSwapchainFormats(
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
            const swapchainCreateInfo = xr.XrSwapchainCreateInfo{
                .type = xr.XR_TYPE_SWAPCHAIN_CREATE_INFO,
                .arraySize = 1,
                .format = this.colorSwapchainFormat,
                .width = vp.recommendedImageRectWidth,
                .height = vp.recommendedImageRectHeight,
                .mipCount = 1,
                .faceCount = 1,
                .sampleCount = this.graphics.getSupportedSwapchainSampleCount(vp),
                .usageFlags = xr.XR_SWAPCHAIN_USAGE_SAMPLED_BIT | xr.XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT,
            };
            var swapchain = Swapchain{
                .width = swapchainCreateInfo.width,
                .height = swapchainCreateInfo.height,
                .handle = null,
            };
            try xr_result.check(xr.xrCreateSwapchain(this.session, &swapchainCreateInfo, &swapchain.handle));
            try this.swapchains.append(swapchain);

            // const swapchainBuffer = try this.allocator.alloc(*xr.XrSwapchainImageBaseHeader, imageCount);
            // if (!this.graphics.allocateSwapchainImageStructs(swapchainCreateInfo, swapchainBuffer)) {
            //     return error.allocateSwapchainImageStructs;
            // }
            // try this.swapchainImageMap.put(swapchain.handle, swapchainBuffer);

            var imageCount: u32 = undefined;
            try xr_result.check(xr.xrEnumerateSwapchainImages(swapchain.handle, 0, &imageCount, null));
            const swapchainBuffer = this.graphics.allocateSwapchainImageStructs(swapchain.handle, imageCount);
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
    this: *@This(),
    exitRenderLoop: *bool,
    requestRestart: *bool,
) !void {
    exitRenderLoop.* = false;
    requestRestart.* = false;

    // Process all pending messages.
    while (try this.tryReadNextEvent()) |event| {
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
                try this.handleSessionStateChangedEvent(sessionStateChangedEvent, exitRenderLoop, requestRestart);
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
    this: *@This(),
    stateChangedEvent: *const xr.XrEventDataSessionStateChanged,
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
        xr.XR_SESSION_STATE_READY => {
            try xr_util.assert(this.session != null);
            const sessionBeginInfo = xr.XrSessionBeginInfo{
                .type = xr.XR_TYPE_SESSION_BEGIN_INFO,
                .primaryViewConfigurationType = this.options.Parsed.ViewConfigType,
            };
            try xr_result.check(xr.xrBeginSession(this.session, &sessionBeginInfo));
            this.sessionRunning = true;
        },
        xr.XR_SESSION_STATE_STOPPING => {
            try xr_util.assert(this.session != null);
            this.sessionRunning = false;
            try xr_result.check(xr.xrEndSession(this.session));
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
fn tryReadNextEvent(this: *@This()) !?*const xr.XrEventDataBaseHeader {
    // It is sufficient to clear the just the XrEventDataBuffer header to XR_TYPE_EVENT_DATA_BUFFER
    const baseHeader: *xr.XrEventDataBaseHeader = @ptrCast(&this.eventDataBuffer);
    baseHeader.* = .{
        .type = xr.XR_TYPE_EVENT_DATA_BUFFER,
    };
    const ev = xr.xrPollEvent(this.instance, &this.eventDataBuffer);
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

pub fn beginFrame(this: *@This()) !xr.XrFrameState {
    try xr_util.assert(this.session != null);

    var frameWaitInfo = xr.XrFrameWaitInfo{
        .type = xr.XR_TYPE_FRAME_WAIT_INFO,
    };
    var frameState = xr.XrFrameState{
        .type = xr.XR_TYPE_FRAME_STATE,
    };
    try xr_result.check(xr.xrWaitFrame(this.session, &frameWaitInfo, &frameState));

    var frameBeginInfo = xr.XrFrameBeginInfo{
        .type = xr.XR_TYPE_FRAME_BEGIN_INFO,
    };
    try xr_result.check(xr.xrBeginFrame(this.session, &frameBeginInfo));
    // return frameState;

    return frameState;
}

pub fn locateView(this: *@This(), space: xr.XrSpace, predictedDisplayTime: i64) !xr.XrViewState {
    var viewLocateInfo = xr.XrViewLocateInfo{
        .type = xr.XR_TYPE_VIEW_LOCATE_INFO,
        .viewConfigurationType = this.options.Parsed.ViewConfigType,
        .displayTime = predictedDisplayTime,
        .space = space,
    };
    var viewState = xr.XrViewState{
        .type = xr.XR_TYPE_VIEW_STATE,
    };
    var viewCountOutput: u32 = undefined;
    try xr_result.check(xr.xrLocateViews(
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
    space: xr.XrSpace,
    predictedDisplayTime: i64,
    views: []xr.XrCompositionLayerProjectionView,
) !void {
    var frameEndInfo = xr.XrFrameEndInfo{
        .type = xr.XR_TYPE_FRAME_END_INFO,
        .displayTime = predictedDisplayTime,
        .environmentBlendMode = this.options.Parsed.EnvironmentBlendMode,
        .layerCount = 0,
        .layers = null,
    };

    var composition_layers: [2]*xr.XrCompositionLayerBaseHeader = undefined;
    var composition_layer_projection: xr.XrCompositionLayerProjection = undefined;
    var composition_layer_passthrough = xr.XrCompositionLayerPassthroughFB{
        .type = xr.XR_TYPE_COMPOSITION_LAYER_PASSTHROUGH_FB,
        .layerHandle = this.passthroughLayer,
        .flags = xr.XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT,
        .space = null,
    };

    if (views.len > 0) {
        composition_layer_projection = .{
            .type = xr.XR_TYPE_COMPOSITION_LAYER_PROJECTION,
            .space = space,
            .layerFlags = if (this.options.Parsed.EnvironmentBlendMode == xr.XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND)
                xr.XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT | xr.XR_COMPOSITION_LAYER_UNPREMULTIPLIED_ALPHA_BIT
            else
                0,
            .viewCount = @intCast(views.len),
            .views = &views[0],
        };
        composition_layers[frameEndInfo.layerCount] = @ptrCast(&composition_layer_projection);
        frameEndInfo.layerCount += 1;
        frameEndInfo.layers = &composition_layers[0];
    }

    {
        composition_layers[frameEndInfo.layerCount] = @ptrCast(&composition_layer_passthrough);
        frameEndInfo.layerCount += 1;
        frameEndInfo.layers = &composition_layers[0];
    }

    try xr_result.check(xr.xrEndFrame(this.session, &frameEndInfo));
}

// https://developers.meta.com/horizon/documentation/native/android/mobile-passthrough
// TODO: XR_PASSTHROUGH_CAPABILITY_COLOR_BIT_FB
fn systemSupportsPassthrough(instance: xr.XrInstance, systemId: xr.XrSystemId) !bool {
    var passthroughSystemProperties = xr.XrSystemPassthroughProperties2FB{
        .type = xr.XR_TYPE_SYSTEM_PASSTHROUGH_PROPERTIES2_FB,
    };
    var systemProperties = xr.XrSystemProperties{
        .type = xr.XR_TYPE_SYSTEM_PROPERTIES,
        .next = &passthroughSystemProperties,
    };
    try xr_result.check(xr.xrGetSystemProperties(instance, systemId, &systemProperties));
    return (passthroughSystemProperties.capabilities & xr.XR_PASSTHROUGH_CAPABILITY_BIT_FB) == xr.XR_PASSTHROUGH_CAPABILITY_BIT_FB;
}
