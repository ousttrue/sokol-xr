const std = @import("std");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr_util = @import("xr_util.zig");
// const c = xr_util.c;
const c = @import("c");
const xr_result = @import("xr_result.zig");
const xr_linear = @import("xr_linear.zig");

const INSTANCE_EXTENSIONS = [_][]const u8{"XR_KHR_opengl_es_enable"};

pub fn getInstanceExtensions() []const []const u8 {
    return &INSTANCE_EXTENSIONS;
}

pub fn selectColorSwapchainFormat(runtimeFormats: []i64) ?i64 {
    const supportedColorSwapchainFormats = [_]i64{ c.GL_RGBA8, c.GL_RGBA8_SNORM, c.GL_SRGB8_ALPHA8 };
    for (runtimeFormats) |runtime| {
        for (supportedColorSwapchainFormats) |supported| {
            if (runtime == supported) {
                return runtime;
            }
        }
    }
    return null;
}

pub fn getSupportedSwapchainSampleCount(_: c.XrViewConfigurationView) u32 {
    return 1;
}

pub fn calcViewProjectionMatrix(fov: c.XrFovf, view_pose: c.XrPosef) xr_linear.Matrix4x4f {
    const proj = xr_linear.Matrix4x4f.createProjectionFov(.OPENGL_ES, fov, 0.05, 100.0);
    const toView = xr_linear.Matrix4x4f.createFromRigidTransform(view_pose);
    const view = toView.invertRigidBody();
    const vp = proj.multiply(view);
    return vp;
}

const vtable = GraphicsPlugin.VTable{
    .getInstanceExtensions = &getInstanceExtensions,
    .selectColorSwapchainFormat = &selectColorSwapchainFormat,
    .getSupportedSwapchainSampleCount = &getSupportedSwapchainSampleCount,
    .calcViewProjectionMatrix = &calcViewProjectionMatrix,
    //
    .deinit = &destroy,
    .initializeDevice = &initializeDevice,
    .getGraphicsBinding = &getGraphicsBinding,
    .allocateSwapchainImageStructs = &allocateSwapchainImageStructs,
    .getSwapchainImage = &getSwapchainImage,
};

allocator: std.mem.Allocator,
swapchainBufferMap: std.AutoHashMap(c.XrSwapchain, []c.XrSwapchainImageOpenGLESKHR),
graphicsBinding: c.XrGraphicsBindingOpenGLESAndroidKHR = .{},

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
    clear_color: [4]f32 = .{ 0, 0, 0, 0 },
    display: c.EGLDisplay,
    context: c.EGLContext,
};

pub fn create(opts: InitOptions) !*@This() {
    const self = try opts.allocator.create(@This());
    self.* = .{
        .allocator = opts.allocator,
        .swapchainBufferMap = .init(opts.allocator),
        .graphicsBinding = .{
            .type = c.XR_TYPE_GRAPHICS_BINDING_OPENGL_ES_ANDROID_KHR,
            .next = null,
            .display = opts.display,
            .config = null,
            .context = opts.context,
        },
    };
    return self;
}

pub fn init(opts: InitOptions) !GraphicsPlugin {
    return .{
        .ptr = try create(opts),
        .vtable = &vtable,
    };
}

pub fn destroy(_self: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(_self));
    var it = self.swapchainBufferMap.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.value_ptr.*);
    }
    self.swapchainBufferMap.deinit();
    self.allocator.destroy(self);
}

pub fn initializeDevice(_self: *anyopaque, instance: c.XrInstance, systemId: c.XrSystemId) xr_result.Error!void {
    std.log.debug("initializeDevice", .{});
    _ = _self;
    // const self: *@This() = @ptrCast(@alignCast(_self));
    // Extension function must be loaded by name
    var pfnGetOpenGLESGraphicsRequirementsKHR: c.PFN_xrGetOpenGLESGraphicsRequirementsKHR = undefined;
    try xr_result.check(c.xrGetInstanceProcAddr(
        @ptrCast(instance),
        "xrGetOpenGLESGraphicsRequirementsKHR",
        &pfnGetOpenGLESGraphicsRequirementsKHR,
    ));

    var graphicsRequirements = c.XrGraphicsRequirementsOpenGLESKHR{
        .type = c.XR_TYPE_GRAPHICS_REQUIREMENTS_OPENGL_ES_KHR,
        .next = null,
    };
    try xr_result.check((pfnGetOpenGLESGraphicsRequirementsKHR.?)(@ptrCast(instance), systemId, &graphicsRequirements));
    std.log.debug("minApiVersionSupported: {}", .{
        xr_util.ExtractVersion.fromXrVersion(graphicsRequirements.minApiVersionSupported),
    });

    // Initialize the gl extensions. Note we have to open a window.
    // var driverInstance = c.ksDriverInstance{};
    // const queueInfo = c.ksGpuQueueInfo{};
    // const colorFormat = c.KS_GPU_SURFACE_COLOR_FORMAT_B8G8R8A8;
    // const depthFormat = c.KS_GPU_SURFACE_DEPTH_FORMAT_D24;
    // const sampleCount = c.KS_GPU_SAMPLE_COUNT_1;
    // if (!c.ksGpuWindow_Create(
    //     &self.window,
    //     &driverInstance,
    //     &queueInfo,
    //     0,
    //     colorFormat,
    //     depthFormat,
    //     sampleCount,
    //     640,
    //     480,
    //     false,
    // )) {
    //     std.log.err("Unable to create GL context", .{});
    //     return false;
    // }

    var major: c.GLint = 0;
    var minor: c.GLint = 0;
    c.glGetIntegerv(c.GL_MAJOR_VERSION, &major);
    c.glGetIntegerv(c.GL_MINOR_VERSION, &minor);
    const desiredApiVersion: c.XrVersion = c.XR_MAKE_VERSION(
        @as(u64, @intCast(major)),
        @as(u64, @intCast(minor)),
        0,
    );
    std.log.debug("desiredApiVersion: {}", .{
        xr_util.ExtractVersion.fromXrVersion(desiredApiVersion),
    });

    // if (graphicsRequirements.minApiVersionSupported > desiredApiVersion) {
    //     std.log.err("graphicsRequirements.minApiVersionSupported > desiredApiVersion: {} > {}", .{
    //         graphicsRequirements.minApiVersionSupported,
    //         desiredApiVersion,
    //     });
    //     return false;
    // }

    //         glEnable(GL_DEBUG_OUTPUT);
    //         glDebugMessageCallback(
    //             [](GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length, const GLchar* message,
    //                const void* userParam) {
    //                 ((OpenGLESGraphicsPlugin*)userParam)->DebugMessageCallback(source, type, id, severity, length, message);
    //             },
    //             this);
}

pub fn getGraphicsBinding(_self: *anyopaque) ?*const c.XrBaseInStructure {
    const self: *@This() = @ptrCast(@alignCast(_self));
    return @ptrCast(&self.graphicsBinding);
}

pub fn allocateSwapchainImageStructs(
    _self: *anyopaque,
    swapchain: c.XrSwapchain,
    image_count: u32,
) *c.XrSwapchainImageBaseHeader {
    const self: *@This() = @ptrCast(@alignCast(_self));
    // Allocate and initialize the buffer of image structs
    // (must be sequential in memory for xrEnumerateSwapchainImages).
    // Return back an array of pointers to each swapchain image struct so the consumer doesn't need to know the type/size.
    const images = self.allocator.alloc(c.XrSwapchainImageOpenGLESKHR, image_count) catch @panic("OOM");
    for (images) |*image| {
        image.* = .{
            .type = c.XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_ES_KHR,
        };
    }
    self.swapchainBufferMap.put(swapchain, images) catch @panic("OOM");
    return @ptrCast(&images[0]);
}

pub fn getSwapchainImage(
    _self: *anyopaque,
    swapchain: c.XrSwapchain,
    image_index: u32,
) GraphicsPlugin.SwapchainImage {
    const self: *@This() = @ptrCast(@alignCast(_self));
    const textures = self.swapchainBufferMap.get(swapchain).?;
    return .{ .OpenGLES = textures[image_index] };
}
