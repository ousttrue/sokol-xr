const builtin = @import("builtin");
const geometry = @import("geometry.zig");
const xr_result = @import("xr_result.zig");
const xr_linear = @import("xr_linear.zig");
const c = @import("c");

pub const SwapchainImage = if (builtin.abi.isAndroid())
    union(enum) {
        OpenGLES: c.XrSwapchainImageOpenGLESKHR,
    }
else
    union(enum) {
        OpenGL: c.XrSwapchainImageOpenGLKHR,
        D3D11: c.XrSwapchainImageD3D11KHR,
    };

pub const VTable = struct {
    getInstanceExtensions: *const fn () []const []const u8,
    selectColorSwapchainFormat: *const fn (runtime_formats: []i64) ?i64,
    getSupportedSwapchainSampleCount: *const fn (config: c.XrViewConfigurationView) u32,
    calcViewProjectionMatrix: *const fn (fov: c.XrFovf, view_pose: c.XrPosef) xr_linear.Matrix4x4f,
    //
    deinit: *const fn (ptr: *anyopaque) void,
    initializeDevice: *const fn (
        ptr: *anyopaque,
        instance: c.XrInstance,
        systemId: c.XrSystemId,
    ) xr_result.Error!void,
    getGraphicsBinding: *const fn (ptr: *anyopaque) ?*const c.XrBaseInStructure,
    allocateSwapchainImageStructs: *const fn (
        ptr: *anyopaque,
        swapchain: c.XrSwapchain,
        image_count: u32,
    ) *c.XrSwapchainImageBaseHeader,
    getSwapchainImage: *const fn (ptr: *anyopaque, swapchain: c.XrSwapchain, image_index: u32) SwapchainImage,
};

ptr: *anyopaque,
vtable: *const VTable,

// static

pub fn getInstanceExtensions(self: @This()) []const []const u8 {
    return self.vtable.getInstanceExtensions();
}

pub fn selectColorSwapchainFormat(self: @This(), runtimeFormats: []i64) ?i64 {
    return self.vtable.selectColorSwapchainFormat(runtimeFormats);
}

pub fn getSupportedSwapchainSampleCount(self: @This(), config: c.XrViewConfigurationView) u32 {
    return self.vtable.getSupportedSwapchainSampleCount(config);
}

pub fn calcViewProjectionMatrix(self: @This(), fov: c.XrFovf, view_pose: c.XrPosef) xr_linear.Matrix4x4f {
    return self.vtable.calcViewProjectionMatrix(fov, view_pose);
}

// instance

pub fn deinit(self: @This()) void {
    self.vtable.deinit(self.ptr);
}

pub fn initializeDevice(
    self: @This(),
    instance: c.XrInstance,
    systemId: c.XrSystemId,
) xr_result.Error!void {
    try self.vtable.initializeDevice(self.ptr, instance, systemId);
}

pub fn getGraphicsBinding(self: @This()) ?*const c.XrBaseInStructure {
    return self.vtable.getGraphicsBinding(self.ptr);
}

pub fn allocateSwapchainImageStructs(
    self: *@This(),
    swapchain: c.XrSwapchain,
    image_count: u32,
) *c.XrSwapchainImageBaseHeader {
    return self.vtable.allocateSwapchainImageStructs(self.ptr, swapchain, image_count);
}

pub fn getSwapchainImage(self: @This(), swapchain: c.XrSwapchain, image_index: u32) SwapchainImage {
    return self.vtable.getSwapchainImage(self.ptr, swapchain, image_index);
}
