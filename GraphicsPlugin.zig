const xr = @import("openxr");
const geometry = @import("geometry.zig");
const xr_result = @import("xr_result.zig");

pub const VTable = struct {
    deinit: *const fn (ptr: *anyopaque) void,
    getInstanceExtensions: *const fn (ptr: *anyopaque) []const []const u8,
    initializeDevice: *const fn (
        ptr: *anyopaque,
        instance: xr.XrInstance,
        systemId: xr.XrSystemId,
    ) xr_result.Error!void,
    getGraphicsBinding: *const fn (ptr: *anyopaque) ?*const xr.XrBaseInStructure,
    selectColorSwapchainFormat: *const fn (ptr: *anyopaque, runtime_formats: []i64) ?i64,
    getSupportedSwapchainSampleCount: *const fn (ptr: *anyopaque, config: xr.XrViewConfigurationView) u32,
    allocateSwapchainImageStructs: *const fn (
        ptr: *anyopaque,
        info: xr.XrSwapchainCreateInfo,
        swapchainImageBase: []*xr.XrSwapchainImageBaseHeader,
    ) bool,
    renderView: *const fn (
        ptr: *anyopaque,
        layerView: *const xr.XrCompositionLayerProjectionView,
        swapchainImage: *const xr.XrSwapchainImageBaseHeader,
        swapchainFormat: i64,
        cubes: []geometry.Cube,
    ) bool,
};

ptr: *anyopaque,
vtable: *const VTable,

pub fn deinit(self: @This()) void {
    self.vtable.deinit(self.ptr);
}

pub fn getInstanceExtensions(self: @This()) []const []const u8 {
    return self.vtable.getInstanceExtensions(self.ptr);
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

pub fn selectColorSwapchainFormat(self: @This(), runtimeFormats: []i64) ?i64 {
    return self.vtable.selectColorSwapchainFormat(self.ptr, runtimeFormats);
}

pub fn getSupportedSwapchainSampleCount(self: @This(), config: xr.XrViewConfigurationView) u32 {
    return self.vtable.getSupportedSwapchainSampleCount(self.ptr, config);
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
    layerView: *const xr.XrCompositionLayerProjectionView,
    swapchainImage: *const xr.XrSwapchainImageBaseHeader,
    swapchainFormat: i64,
    cubes: []geometry.Cube,
) bool {
    return self.vtable.renderView(self.ptr, layerView, swapchainImage, swapchainFormat, cubes);
}
