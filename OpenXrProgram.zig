const std = @import("std");
const Options = @import("Options.zig");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr_util = @import("xr_util.zig");
const xr_result = @import("xr_result.zig");
const geometry = @import("geometry.zig");
const c = xr_util.c;
const xr = @import("openxr");

const Side = struct {
    const LEFT = 0;
    const RIGHT = 1;
    const COUNT = 2;
};

const InputState = struct {
    actionSet: xr.XrActionSet = null,
    // XrAction grabAction{XR_NULL_HANDLE};
    // XrAction poseAction{XR_NULL_HANDLE};
    // XrAction vibrateAction{XR_NULL_HANDLE};
    // XrAction quitAction{XR_NULL_HANDLE};
    // std::array<XrPath, Side::COUNT> handSubactionPath;
    handSpace: [2]xr.XrSpace = .{ null, null },
    handScale: [2]f32 = .{ 1.0, 1.0 },
    handActive: [2]xr.XrBool32 = .{ xr.XR_FALSE, xr.XR_FALSE },
};

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
swapchainImageMap: std.AutoHashMap(xr.XrSwapchain, []*xr.XrSwapchainImageBaseHeader),
colorSwapchainFormat: i64 = -1,

visualizedSpaces: std.array_list.Managed(xr.XrSpace),

// Application's current lifecycle state according to the runtime
sessionState: xr.XrSessionState = xr.XR_SESSION_STATE_UNKNOWN,
sessionRunning: bool = false,

eventDataBuffer: xr.XrEventDataBuffer = .{},
input: InputState = .{},

layers: std.array_list.Managed(*xr.XrCompositionLayerBaseHeader),
layer: xr.XrCompositionLayerProjection = .{
    .type = xr.XR_TYPE_COMPOSITION_LAYER_PROJECTION,
},
projectionLayerViews: std.array_list.Managed(xr.XrCompositionLayerProjectionView),

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
        .visualizedSpaces = std.array_list.Managed(xr.XrSpace).init(allocator),
        .configViews = std.array_list.Managed(xr.XrViewConfigurationView).init(allocator),
        .views = std.array_list.Managed(xr.XrView).init(allocator),
        .swapchains = std.array_list.Managed(Swapchain).init(allocator),
        .swapchainImageMap = std.AutoHashMap(xr.XrSwapchain, []*xr.XrSwapchainImageBaseHeader).init(allocator),

        .layers = .init(allocator),
        .projectionLayerViews = .init(allocator),
    };
}

pub fn deinit(self: *@This()) void {
    std.log.debug("#### OpenXrProgram.deinit ####", .{});
    self.projectionLayerViews.deinit();
    self.layers.deinit();
    {
        var iterator = self.swapchainImageMap.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
    }
    self.swapchainImageMap.deinit();

    self.swapchains.deinit();
    self.views.deinit();
    self.configViews.deinit();
    self.visualizedSpaces.deinit();
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

// inline std::string GetXrVersionString(XrVersion ver) {
//     return Fmt("%d.%d.%d", XR_VERSION_MAJOR(ver), XR_VERSION_MINOR(ver), XR_VERSION_PATCH(ver));
// }

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
    try self.createVisualizedSpaces();

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

fn createVisualizedSpaces(self: *@This()) !void {
    try xr_util.assert(self.session != null);

    const visualizedSpaces = [_][]const u8{
        "ViewFront",
        "Local",
        "Stage",
        "StageLeft",
        "StageRight",
        "StageLeftRotated",
        "StageRightRotated",
    };

    for (visualizedSpaces) |visualizedSpace| {
        const referenceSpaceCreateInfo = try xr_util.getXrReferenceSpaceCreateInfo(visualizedSpace);
        var space: xr.XrSpace = undefined;
        const res = xr.xrCreateReferenceSpace(self.session, &referenceSpaceCreateInfo, &space);
        if (res == 0) {
            try self.visualizedSpaces.append(space);
        } else {
            std.log.warn("Failed to create reference space {s} with error {}", .{
                visualizedSpace,
                res,
            });
        }
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

            var imageCount: u32 = undefined;
            try xr_result.check(xr.xrEnumerateSwapchainImages(swapchain.handle, 0, &imageCount, null));
            // XXX This should really just return XrSwapchainImageBaseHeader*

            const swapchainBuffer = try self.allocator.alloc(*xr.XrSwapchainImageBaseHeader, imageCount);
            if (!self.graphics.allocateSwapchainImageStructs(swapchainCreateInfo, swapchainBuffer)) {
                return error.allocateSwapchainImageStructs;
            }
            try xr_result.check(xr.xrEnumerateSwapchainImages(
                swapchain.handle,
                imageCount,
                &imageCount,
                swapchainBuffer[0],
            ));

            try self.swapchainImageMap.put(swapchain.handle, swapchainBuffer);
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
    try self.layers.resize(0);

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

pub fn renderFrame(self: *@This(), predictedDisplayTime: i64) !void {
    try self.projectionLayerViews.resize(self.views.items.len);

    // For each locatable space that we want to visualize, render a 25cm cube.
    var cubes = std.array_list.Managed(geometry.Cube).init(self.allocator);
    defer cubes.deinit();

    for (self.visualizedSpaces.items) |visualizedSpace| {
        var spaceLocation = xr.XrSpaceLocation{
            .type = xr.XR_TYPE_SPACE_LOCATION,
        };
        const res = xr.xrLocateSpace(
            visualizedSpace,
            self.appSpace,
            predictedDisplayTime,
            &spaceLocation,
        );
        try xr_util.assert(res == 0); //, "xrLocateSpace");
        if (xr.XR_UNQUALIFIED_SUCCESS(res)) {
            if ((spaceLocation.locationFlags & xr.XR_SPACE_LOCATION_POSITION_VALID_BIT) != 0 and
                (spaceLocation.locationFlags & xr.XR_SPACE_LOCATION_ORIENTATION_VALID_BIT) != 0)
            {
                try cubes.append(.{
                    .Pose = spaceLocation.pose,
                    .Scale = .{ .x = 0.25, .y = 0.25, .z = 0.25 },
                });
            }
        } else {
            std.log.debug("Unable to locate a visualized reference space in app space: {}", .{res});
        }
    }

    // Render a 10cm cube scaled by grabAction for each hand. Note renderHand will only be
    // true when the application has focus.

    const hands = [2]u32{ Side.LEFT, Side.RIGHT };
    for (hands) |hand| {
        var spaceLocation = xr.XrSpaceLocation{
            .type = xr.XR_TYPE_SPACE_LOCATION,
        };
        const res = xr.xrLocateSpace(
            self.input.handSpace[hand],
            self.appSpace,
            predictedDisplayTime,
            &spaceLocation,
        );
        // std.debug.assert(res == 0); //, "xrLocateSpace");
        if (xr.XR_UNQUALIFIED_SUCCESS(res)) {
            if ((spaceLocation.locationFlags & xr.XR_SPACE_LOCATION_POSITION_VALID_BIT) != 0 and
                (spaceLocation.locationFlags & xr.XR_SPACE_LOCATION_ORIENTATION_VALID_BIT) != 0)
            {
                const scale = 0.1 * self.input.handScale[hand];
                try cubes.append(.{ .Pose = spaceLocation.pose, .Scale = .{ .x = scale, .y = scale, .z = scale } });
            }
        } else {
            // Tracking loss is expected when the hand is not active so only log a message
            // if the hand is active.
            if (self.input.handActive[hand] == xr.XR_TRUE) {
                const handName = [_][]const u8{ "left", "right" };
                std.log.debug("Unable to locate {s} hand action space in app space: {}", .{
                    handName[hand],
                    res,
                });
            }
        }
    }

    // Render view to the appropriate part of the swapchain image.
    for (0..self.swapchains.items.len) |i| {
        // Each view has a separate swapchain which is acquired, rendered to, and released.
        const viewSwapchain = self.swapchains.items[i];

        var acquireInfo = xr.XrSwapchainImageAcquireInfo{
            .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO,
        };

        var swapchainImageIndex: u32 = undefined;
        try xr_result.check(xr.xrAcquireSwapchainImage(viewSwapchain.handle, &acquireInfo, &swapchainImageIndex));

        var waitInfo = xr.XrSwapchainImageWaitInfo{
            .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO,
            .timeout = xr.XR_INFINITE_DURATION,
        };
        try xr_result.check(xr.xrWaitSwapchainImage(viewSwapchain.handle, &waitInfo));

        self.projectionLayerViews.items[i] = .{
            .type = xr.XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW,
            .pose = self.views.items[i].pose,
            .fov = self.views.items[i].fov,
            .subImage = .{
                .swapchain = viewSwapchain.handle,
                .imageRect = .{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = .{
                        .width = @intCast(viewSwapchain.width),
                        .height = @intCast(viewSwapchain.height),
                    },
                },
            },
        };

        if (self.swapchainImageMap.get(viewSwapchain.handle)) |imageBuffers| {
            const swapchainImage: *const xr.XrSwapchainImageBaseHeader = imageBuffers[swapchainImageIndex];
            if (!self.graphics.renderView(
                &self.projectionLayerViews.items[i],
                swapchainImage,
                self.colorSwapchainFormat,
                cubes.items,
            )) {
                xr_util.my_panic("OOM", .{});
            }

            const releaseInfo = xr.XrSwapchainImageReleaseInfo{
                .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO,
            };
            try xr_result.check(xr.xrReleaseSwapchainImage(viewSwapchain.handle, &releaseInfo));
        }
    }

    self.layer.space = self.appSpace;
    self.layer.layerFlags = if (self.options.Parsed.EnvironmentBlendMode == xr.XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND)
        xr.XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT | xr.XR_COMPOSITION_LAYER_UNPREMULTIPLIED_ALPHA_BIT
    else
        0;
    self.layer.viewCount = @intCast(self.projectionLayerViews.items.len);
    self.layer.views = &self.projectionLayerViews.items[0];

    try self.layers.append(@ptrCast(&self.layer));
}

pub fn endFrame(self: @This(), predictedDisplayTime: i64) !void {
    const frameEndInfo = xr.XrFrameEndInfo{
        .type = xr.XR_TYPE_FRAME_END_INFO,
        .displayTime = predictedDisplayTime,
        .environmentBlendMode = self.options.Parsed.EnvironmentBlendMode,
        .layerCount = @intCast(self.layers.items.len),
        .layers = if (self.layers.items.len > 0) &self.layers.items[0] else null,
    };
    try xr_result.check(xr.xrEndFrame(self.session, &frameEndInfo));
}

fn initializeActions(self: *@This()) !void {
    // Create an action set.
    {
        var actionSetInfo = xr.XrActionSetCreateInfo{
            .type = xr.XR_TYPE_ACTION_SET_CREATE_INFO,
            .priority = 0,
        };
        //     strcpy_s(actionSetInfo.actionSetName, "gameplay");
        //     strcpy_s(actionSetInfo.localizedActionSetName, "Gameplay");
        try xr_result.check(xr.xrCreateActionSet(self.instance, &actionSetInfo, &self.input.actionSet));
    }

    // // Get the XrPath for the left and right hands - we will use them as subaction paths.
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left", &m_input.handSubactionPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right", &m_input.handSubactionPath[Side::RIGHT]));
    //
    // // Create actions.
    // {
    //     // Create an input action for grabbing objects with the left and right hands.
    //     XrActionCreateInfo actionInfo{XR_TYPE_ACTION_CREATE_INFO};
    //     actionInfo.actionType = XR_ACTION_TYPE_FLOAT_INPUT;
    //     strcpy_s(actionInfo.actionName, "grab_object");
    //     strcpy_s(actionInfo.localizedActionName, "Grab Object");
    //     actionInfo.countSubactionPaths = uint32_t(m_input.handSubactionPath.size());
    //     actionInfo.subactionPaths = m_input.handSubactionPath.data();
    //     xr_result.check(xrCreateAction(m_input.actionSet, &actionInfo, &m_input.grabAction));
    //
    //     // Create an input action getting the left and right hand poses.
    //     actionInfo.actionType = XR_ACTION_TYPE_POSE_INPUT;
    //     strcpy_s(actionInfo.actionName, "hand_pose");
    //     strcpy_s(actionInfo.localizedActionName, "Hand Pose");
    //     actionInfo.countSubactionPaths = uint32_t(m_input.handSubactionPath.size());
    //     actionInfo.subactionPaths = m_input.handSubactionPath.data();
    //     xr_result.check(xrCreateAction(m_input.actionSet, &actionInfo, &m_input.poseAction));
    //
    //     // Create output actions for vibrating the left and right controller.
    //     actionInfo.actionType = XR_ACTION_TYPE_VIBRATION_OUTPUT;
    //     strcpy_s(actionInfo.actionName, "vibrate_hand");
    //     strcpy_s(actionInfo.localizedActionName, "Vibrate Hand");
    //     actionInfo.countSubactionPaths = uint32_t(m_input.handSubactionPath.size());
    //     actionInfo.subactionPaths = m_input.handSubactionPath.data();
    //     xr_result.check(xrCreateAction(m_input.actionSet, &actionInfo, &m_input.vibrateAction));
    //
    //     // Create input actions for quitting the session using the left and right controller.
    //     // Since it doesn't matter which hand did this, we do not specify subaction paths for it.
    //     // We will just suggest bindings for both hands, where possible.
    //     actionInfo.actionType = XR_ACTION_TYPE_BOOLEAN_INPUT;
    //     strcpy_s(actionInfo.actionName, "quit_session");
    //     strcpy_s(actionInfo.localizedActionName, "Quit Session");
    //     actionInfo.countSubactionPaths = 0;
    //     actionInfo.subactionPaths = nullptr;
    //     xr_result.check(xrCreateAction(m_input.actionSet, &actionInfo, &m_input.quitAction));
    // }
    //
    // std::array<XrPath, Side::COUNT> selectPath;
    // std::array<XrPath, Side::COUNT> squeezeValuePath;
    // std::array<XrPath, Side::COUNT> squeezeForcePath;
    // std::array<XrPath, Side::COUNT> squeezeClickPath;
    // std::array<XrPath, Side::COUNT> posePath;
    // std::array<XrPath, Side::COUNT> hapticPath;
    // std::array<XrPath, Side::COUNT> menuClickPath;
    // std::array<XrPath, Side::COUNT> bClickPath;
    // std::array<XrPath, Side::COUNT> triggerValuePath;
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/select/click", &selectPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/select/click", &selectPath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/squeeze/value", &squeezeValuePath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/squeeze/value", &squeezeValuePath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/squeeze/force", &squeezeForcePath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/squeeze/force", &squeezeForcePath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/squeeze/click", &squeezeClickPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/squeeze/click", &squeezeClickPath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/grip/pose", &posePath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/grip/pose", &posePath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/output/haptic", &hapticPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/output/haptic", &hapticPath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/menu/click", &menuClickPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/menu/click", &menuClickPath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/b/click", &bClickPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/b/click", &bClickPath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/trigger/value", &triggerValuePath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/trigger/value", &triggerValuePath[Side::RIGHT]));
    // // Suggest bindings for KHR Simple.
    // {
    //     XrPath khrSimpleInteractionProfilePath;
    //     xr_result.check(xrStringToPath(m_instance, "/interaction_profiles/khr/simple_controller", &khrSimpleInteractionProfilePath));
    //     std::vector<XrActionSuggestedBinding> bindings{{// Fall back to a click input for the grab action.
    //                                                     {m_input.grabAction, selectPath[Side::LEFT]},
    //                                                     {m_input.grabAction, selectPath[Side::RIGHT]},
    //                                                     {m_input.poseAction, posePath[Side::LEFT]},
    //                                                     {m_input.poseAction, posePath[Side::RIGHT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::LEFT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::RIGHT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::RIGHT]}}};
    //     XrInteractionProfileSuggestedBinding suggestedBindings{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    //     suggestedBindings.interactionProfile = khrSimpleInteractionProfilePath;
    //     suggestedBindings.suggestedBindings = bindings.data();
    //     suggestedBindings.countSuggestedBindings = (uint32_t)bindings.size();
    //     xr_result.check(xrSuggestInteractionProfileBindings(m_instance, &suggestedBindings));
    // }
    // // Suggest bindings for the Oculus Touch.
    // {
    //     XrPath oculusTouchInteractionProfilePath;
    //     xr_result.check(
    //         xrStringToPath(m_instance, "/interaction_profiles/oculus/touch_controller", &oculusTouchInteractionProfilePath));
    //     std::vector<XrActionSuggestedBinding> bindings{{{m_input.grabAction, squeezeValuePath[Side::LEFT]},
    //                                                     {m_input.grabAction, squeezeValuePath[Side::RIGHT]},
    //                                                     {m_input.poseAction, posePath[Side::LEFT]},
    //                                                     {m_input.poseAction, posePath[Side::RIGHT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::RIGHT]}}};
    //     XrInteractionProfileSuggestedBinding suggestedBindings{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    //     suggestedBindings.interactionProfile = oculusTouchInteractionProfilePath;
    //     suggestedBindings.suggestedBindings = bindings.data();
    //     suggestedBindings.countSuggestedBindings = (uint32_t)bindings.size();
    //     xr_result.check(xrSuggestInteractionProfileBindings(m_instance, &suggestedBindings));
    // }
    // // Suggest bindings for the Vive Controller.
    // {
    //     XrPath viveControllerInteractionProfilePath;
    //     xr_result.check(xrStringToPath(m_instance, "/interaction_profiles/htc/vive_controller", &viveControllerInteractionProfilePath));
    //     std::vector<XrActionSuggestedBinding> bindings{{{m_input.grabAction, triggerValuePath[Side::LEFT]},
    //                                                     {m_input.grabAction, triggerValuePath[Side::RIGHT]},
    //                                                     {m_input.poseAction, posePath[Side::LEFT]},
    //                                                     {m_input.poseAction, posePath[Side::RIGHT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::LEFT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::RIGHT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::RIGHT]}}};
    //     XrInteractionProfileSuggestedBinding suggestedBindings{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    //     suggestedBindings.interactionProfile = viveControllerInteractionProfilePath;
    //     suggestedBindings.suggestedBindings = bindings.data();
    //     suggestedBindings.countSuggestedBindings = (uint32_t)bindings.size();
    //     xr_result.check(xrSuggestInteractionProfileBindings(m_instance, &suggestedBindings));
    // }
    //
    // // Suggest bindings for the Valve Index Controller.
    // {
    //     XrPath indexControllerInteractionProfilePath;
    //     xr_result.check(
    //         xrStringToPath(m_instance, "/interaction_profiles/valve/index_controller", &indexControllerInteractionProfilePath));
    //     std::vector<XrActionSuggestedBinding> bindings{{{m_input.grabAction, squeezeForcePath[Side::LEFT]},
    //                                                     {m_input.grabAction, squeezeForcePath[Side::RIGHT]},
    //                                                     {m_input.poseAction, posePath[Side::LEFT]},
    //                                                     {m_input.poseAction, posePath[Side::RIGHT]},
    //                                                     {m_input.quitAction, bClickPath[Side::LEFT]},
    //                                                     {m_input.quitAction, bClickPath[Side::RIGHT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::RIGHT]}}};
    //     XrInteractionProfileSuggestedBinding suggestedBindings{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    //     suggestedBindings.interactionProfile = indexControllerInteractionProfilePath;
    //     suggestedBindings.suggestedBindings = bindings.data();
    //     suggestedBindings.countSuggestedBindings = (uint32_t)bindings.size();
    //     xr_result.check(xrSuggestInteractionProfileBindings(m_instance, &suggestedBindings));
    // }
    //
    // // Suggest bindings for the Microsoft Mixed Reality Motion Controller.
    // {
    //     XrPath microsoftMixedRealityInteractionProfilePath;
    //     xr_result.check(xrStringToPath(m_instance, "/interaction_profiles/microsoft/motion_controller",
    //                                &microsoftMixedRealityInteractionProfilePath));
    //     std::vector<XrActionSuggestedBinding> bindings{{{m_input.grabAction, squeezeClickPath[Side::LEFT]},
    //                                                     {m_input.grabAction, squeezeClickPath[Side::RIGHT]},
    //                                                     {m_input.poseAction, posePath[Side::LEFT]},
    //                                                     {m_input.poseAction, posePath[Side::RIGHT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::LEFT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::RIGHT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::RIGHT]}}};
    //     XrInteractionProfileSuggestedBinding suggestedBindings{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    //     suggestedBindings.interactionProfile = microsoftMixedRealityInteractionProfilePath;
    //     suggestedBindings.suggestedBindings = bindings.data();
    //     suggestedBindings.countSuggestedBindings = (uint32_t)bindings.size();
    //     xr_result.check(xrSuggestInteractionProfileBindings(m_instance, &suggestedBindings));
    // }
    // XrActionSpaceCreateInfo actionSpaceInfo{XR_TYPE_ACTION_SPACE_CREATE_INFO};
    // actionSpaceInfo.action = m_input.poseAction;
    // actionSpaceInfo.poseInActionSpace.orientation.w = 1.f;
    // actionSpaceInfo.subactionPath = m_input.handSubactionPath[Side::LEFT];
    // xr_result.check(xrCreateActionSpace(m_session, &actionSpaceInfo, &m_input.handSpace[Side::LEFT]));
    // actionSpaceInfo.subactionPath = m_input.handSubactionPath[Side::RIGHT];
    // xr_result.check(xrCreateActionSpace(m_session, &actionSpaceInfo, &m_input.handSpace[Side::RIGHT]));
    //
    // XrSessionActionSetsAttachInfo attachInfo{XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO};
    // attachInfo.countActionSets = 1;
    // attachInfo.actionSets = &m_input.actionSet;
    // xr_result.check(xrAttachSessionActionSets(m_session, &attachInfo));
}
