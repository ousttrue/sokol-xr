const std = @import("std");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr_util = @import("xr_util.zig");
const xr_result = @import("xr_result.zig");
const xr = @import("openxr");
const geometry = @import("geometry.zig");
const c = @cImport({
    @cInclude("graphicsplugin_d3d11.h");
});

const INSTANCE_EXTENSIONS = [_][]const u8{xr.XR_KHR_D3D11_ENABLE_EXTENSION_NAME};

const vtable = GraphicsPlugin.VTable{
    .deinit = &destroy,
    .getInstanceExtensions = &getInstanceExtensions,
    .initializeDevice = &initializeDevice,
    .getGraphicsBinding = &getGraphicsBinding,
    .selectColorSwapchainFormat = &selectColorSwapchainFormat,
    .getSupportedSwapchainSampleCount = &getSupportedSwapchainSampleCount,
    .allocateSwapchainImageStructs = &allocateSwapchainImageStructs,
    .renderView = &renderView,
};

allocator: std.mem.Allocator,

impl: *anyopaque,

pub fn create(allocator: std.mem.Allocator) !*@This() {
    const self = try allocator.create(@This());
    self.* = .{
        .allocator = allocator,
        .impl = c.create().?,
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
    c.destroy(self.impl);
    self.allocator.destroy(self);
}

pub fn getInstanceExtensions(_: *anyopaque) []const []const u8 {
    return &INSTANCE_EXTENSIONS;
}

pub fn initializeDevice(
    _self: *anyopaque,
    instance: xr.XrInstance,
    systemId: xr.XrSystemId,
) xr_result.Error!void {
    const self: *@This() = @ptrCast(@alignCast(_self));
    try xr_result.check(c.initializeDevice(self.impl, instance, systemId));
}

pub fn selectColorSwapchainFormat(_self: *anyopaque, runtimeFormats: []i64) ?i64 {
    const self: *@This() = @ptrCast(@alignCast(_self));
    return c.selectColorSwapchainFormat(self.impl, &runtimeFormats[0], runtimeFormats.len);
}

pub fn getGraphicsBinding(_self: *anyopaque) *const xr.XrBaseInStructure {
    const self: *@This() = @ptrCast(@alignCast(_self));
    return @ptrCast(@alignCast(c.getGraphicsBinding(self.impl)));
}

pub fn allocateSwapchainImageStructs(
    _self: *anyopaque,
    _: xr.XrSwapchainCreateInfo,
    swapchainImageBase: []*xr.XrSwapchainImageBaseHeader,
) bool {
    const self: *@This() = @ptrCast(@alignCast(_self));
    c.allocateSwapchainImageStructs(self.impl, @ptrCast(&swapchainImageBase[0]), swapchainImageBase.len);
    return true;
}

pub fn renderView(
    _self: *anyopaque,
    layerView: *const xr.XrCompositionLayerProjectionView,
    swapchainImage: *const xr.XrSwapchainImageBaseHeader,
    swapchainFormat: i64,
    cubes: []geometry.Cube,
) bool {
    const self: *@This() = @ptrCast(@alignCast(_self));
    c.renderView(self.impl, @ptrCast(layerView), swapchainImage, swapchainFormat, &cubes[0], cubes.len);
    return true;
}

pub fn getSupportedSwapchainSampleCount(_: *anyopaque, _: xr.XrViewConfigurationView) u32 {
    return 1;
}
