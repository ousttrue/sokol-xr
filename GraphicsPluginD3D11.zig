const std = @import("std");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr_util = @import("xr_util.zig");
const xr_result = @import("xr_result.zig");
const xr_linear = @import("xr_linear.zig");
const xr = @import("openxr");
const geometry = @import("geometry.zig");
const c = @cImport({
    @cInclude("graphicsplugin_d3d11.h");
    @cInclude("dxgi.h");
});

const INSTANCE_EXTENSIONS = [_][]const u8{xr.XR_KHR_D3D11_ENABLE_EXTENSION_NAME};

pub fn getInstanceExtensions() []const []const u8 {
    return &INSTANCE_EXTENSIONS;
}

pub fn selectColorSwapchainFormat(runtimeFormats: []i64) ?i64 {
    // List of supported color swapchain formats.
    const SupportedColorSwapchainFormats = [_]i64{
        c.DXGI_FORMAT_R8G8B8A8_UNORM,
        c.DXGI_FORMAT_B8G8R8A8_UNORM,
        c.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
        c.DXGI_FORMAT_B8G8R8A8_UNORM_SRGB,
    };

    for (runtimeFormats) |runtime| {
        for (SupportedColorSwapchainFormats) |supported| {
            if (runtime == supported) {
                return runtime;
            }
        }
    }

    xr_util.my_panic("No runtime swapchain format supported for color swapchain", .{});
}

pub fn getSupportedSwapchainSampleCount(_: xr.XrViewConfigurationView) u32 {
    return 1;
}

pub fn getSwapchainTextureValue(p: *const xr.XrSwapchainImageBaseHeader) usize {
    const image: *const xr.XrSwapchainImageD3D11KHR = @ptrCast(p);
    return @intFromPtr(image.texture);
}

pub fn calcViewProjectionMatrix(fov: xr.XrFovf, view_pose: xr.XrPosef) xr_linear.Matrix4x4f {
    const proj = xr_linear.Matrix4x4f.createProjectionFov(.D3D, fov, 0.05, 100.0);
    const toView = xr_linear.Matrix4x4f.createFromRigidTransform(view_pose);
    const view = toView.invertRigidBody();
    const vp = proj.multiply(view);
    return vp;
}

const vtable = GraphicsPlugin.VTable{
    .getInstanceExtensions = &getInstanceExtensions,
    .selectColorSwapchainFormat = &selectColorSwapchainFormat,
    .getSupportedSwapchainSampleCount = &getSupportedSwapchainSampleCount,
    .getSwapchainTextureValue = &getSwapchainTextureValue,
    .calcViewProjectionMatrix = &calcViewProjectionMatrix,
    //
    .deinit = &destroy,
    .initializeDevice = &initializeDevice,
    .getGraphicsBinding = &getGraphicsBinding,
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

pub fn initializeDevice(
    _self: *anyopaque,
    instance: xr.XrInstance,
    systemId: xr.XrSystemId,
) xr_result.Error!void {
    const self: *@This() = @ptrCast(@alignCast(_self));
    try xr_result.check(c.initializeDevice(self.impl, instance, systemId));
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
    image: usize,
    format: i64,
    extent: xr.XrExtent2Di,
    vp: xr_linear.Matrix4x4f,
    cubes: []geometry.Cube,
) bool {
    const self: *@This() = @ptrCast(@alignCast(_self));
    c.renderView(
        self.impl,
        image,
        format,
        extent.width,
        extent.height,
        &vp.m[0],
        &cubes[0],
        cubes.len,
    );
    return true;
}
