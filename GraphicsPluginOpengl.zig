const std = @import("std");
const builtin = @import("builtin");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr_util = @import("xr_util.zig");
const c = xr_util.c;
const xr = @import("openxr");
const xr_result = @import("xr_result.zig");
const geometry = @import("geometry.zig");
const xr_linear = @import("xr_linear.zig");
const xr_gl = @import("xr_gl.zig");

const INSTANCE_EXTENSIONS = [_][]const u8{"XR_KHR_opengl_enable"};

pub fn getInstanceExtensions() []const []const u8 {
    return &INSTANCE_EXTENSIONS;
}

pub fn selectColorSwapchainFormat(runtimeFormats: []i64) ?i64 {
    return xr_gl.selectColorSwapchainFormat(runtimeFormats);
}

pub fn getSupportedSwapchainSampleCount(_: xr.XrViewConfigurationView) u32 {
    return 1;
}

pub fn calcViewProjectionMatrix(fov: xr.XrFovf, view_pose: xr.XrPosef) xr_linear.Matrix4x4f {
    const proj = xr_linear.Matrix4x4f.createProjectionFov(.OPENGL, fov, 0.05, 100.0);
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
window: c.ksGpuWindow = .{},
graphicsBinding: xr_util.GetGraphicsBindingType(builtin.target) = .{},

swapchainBufferMap: std.AutoHashMap(xr.XrSwapchain, []xr.XrSwapchainImageOpenGLKHR),

pub fn create(allocator: std.mem.Allocator) !*@This() {
    const self = try allocator.create(@This());
    self.* = .{
        .allocator = allocator,
        .swapchainBufferMap = .init(allocator),
    };
    return self;
}

pub fn init(allocator: std.mem.Allocator) !GraphicsPlugin {
    return .{
        .ptr = try create(allocator),
        .vtable = &vtable,
    };
}

pub fn destroy(_self: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(_self));
    std.log.debug("#### GraphicsPluginOpengl.deinit ####", .{});
    {
        var it = self.swapchainBufferMap.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
    }
    self.swapchainBufferMap.deinit();
    self.allocator.destroy(self);
    // c.ksGpuWindow_Destroy(&self.window);
}

pub fn initializeDevice(
    _self: *anyopaque,
    instance: xr.XrInstance,
    systemId: xr.XrSystemId,
) xr_result.Error!void {
    const self: *@This() = @ptrCast(@alignCast(_self));

    try xr_gl.initializeDevice(instance, systemId, &self.window);
    if (builtin.target.os.tag == .windows) {
        self.graphicsBinding = .{
            .type = xr.XR_TYPE_GRAPHICS_BINDING_OPENGL_WIN32_KHR,
            .hDC = @ptrCast(self.window.context.hDC),
            .hGLRC = @ptrCast(self.window.context.hGLRC),
        };
    } else {
        xr_util.my_panic("initializeDevice: not impl");
    }
}

pub fn getGraphicsBinding(_self: *anyopaque) *const xr.XrBaseInStructure {
    const self: *@This() = @ptrCast(@alignCast(_self));
    return @ptrCast(&self.graphicsBinding);
}

pub fn allocateSwapchainImageStructs(
    _self: *anyopaque,
    swapchain: xr.XrSwapchain,
    image_count: u32,
) *xr.XrSwapchainImageBaseHeader {
    const self: *@This() = @ptrCast(@alignCast(_self));
    // Allocate and initialize the buffer of image structs
    // (must be sequential in memory for xrEnumerateSwapchainImages).
    // Return back an array of pointers to each swapchain image struct so the consumer doesn't need to know the type/size.
    const images = self.allocator.alloc(xr.XrSwapchainImageOpenGLKHR, image_count) catch @panic("OOM");
    for (images) |*image| {
        image.* = .{
            .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_KHR,
        };
    }
    self.swapchainBufferMap.put(swapchain, images) catch @panic("OOM");
    return @ptrCast(&images[0]);
}

// pub fn renderView(
//     _self: *anyopaque,
//     swapchain: xr.XrSwapchain,
//     image_index: u32,
//     format: i64,
//     extent: xr.XrExtent2Di,
//     vp: xr_linear.Matrix4x4f,
//     cubes: []geometry.Cube,
// ) void {
//     const self: *@This() = @ptrCast(@alignCast(_self));
//     _ = format;
//     const textures = self.swapchainBufferMap.get(swapchain).?;
//     const texture = textures[image_index];
//     if (self.renderer) |*r| {
//         r.render(texture.image, extent.width, extent.height, vp, cubes);
//     }
// }

pub fn getSwapchainImage(
    _self: *anyopaque,
    swapchain: xr.XrSwapchain,
    image_index: u32,
) GraphicsPlugin.SwapchainImage {
    const self: *@This() = @ptrCast(@alignCast(_self));
    const textures = self.swapchainBufferMap.get(swapchain).?;
    return .{ .OpenGL = textures[image_index] };
}
