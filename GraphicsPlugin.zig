const xr = @import("openxr");
const geometry = @import("geometry.zig");
const xr_result = @import("xr_result.zig");

pub const VTable = struct {
    getInstanceExtensions: *const fn () []const []const u8,
    selectColorSwapchainFormat: *const fn (runtime_formats: []i64) ?i64,
    getSupportedSwapchainSampleCount: *const fn (config: xr.XrViewConfigurationView) u32,
    getSwapchainTextureValue: *const fn (base: *const xr.XrSwapchainImageBaseHeader) usize,
    //
    deinit: *const fn (ptr: *anyopaque) void,
    initializeDevice: *const fn (
        ptr: *anyopaque,
        instance: xr.XrInstance,
        systemId: xr.XrSystemId,
    ) xr_result.Error!void,
    getGraphicsBinding: *const fn (ptr: *anyopaque) ?*const xr.XrBaseInStructure,
    allocateSwapchainImageStructs: *const fn (
        ptr: *anyopaque,
        info: xr.XrSwapchainCreateInfo,
        swapchainImageBase: []*xr.XrSwapchainImageBaseHeader,
    ) bool,
    renderView: *const fn (
        ptr: *anyopaque,
        swapchain_texture: usize,
        swapchain_format: i64,
        extent: xr.XrExtent2Di,
        fov: xr.XrFovf,
        view_pose: xr.XrPosef,
        cubes: []geometry.Cube,
    ) bool,
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

pub fn getSupportedSwapchainSampleCount(self: @This(), config: xr.XrViewConfigurationView) u32 {
    return self.vtable.getSupportedSwapchainSampleCount(config);
}

pub fn getSwapchainTextureValue(self: @This(), base: *const xr.XrSwapchainImageBaseHeader) usize {
    return self.vtable.getSwapchainTextureValue(base);
}

// instance

pub fn deinit(self: @This()) void {
    self.vtable.deinit(self.ptr);
}

pub fn initializeDevice(
    self: @This(),
    instance: xr.XrInstance,
    systemId: xr.XrSystemId,
) xr_result.Error!void {
    try self.vtable.initializeDevice(self.ptr, instance, systemId);
}

pub fn getGraphicsBinding(self: @This()) ?*const xr.XrBaseInStructure {
    return self.vtable.getGraphicsBinding(self.ptr);
}

pub fn allocateSwapchainImageStructs(
    self: *@This(),
    info: xr.XrSwapchainCreateInfo,
    swapchainImageBase: []*xr.XrSwapchainImageBaseHeader,
) bool {
    return self.vtable.allocateSwapchainImageStructs(self.ptr, info, swapchainImageBase);
}

pub fn renderView(
    self: @This(),
    texture: usize,
    format: i64,
    extent: xr.XrExtent2Di,
    fov: xr.XrFovf,
    view_pose: xr.XrPosef,
    cubes: []geometry.Cube,
) bool {
    return self.vtable.renderView(self.ptr, texture, format, extent, fov, view_pose, cubes);
}
