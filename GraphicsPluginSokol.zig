const std = @import("std");
const builtin = @import("builtin");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr_util = @import("xr_util.zig");
const c = xr_util.c;
const xr_result = @import("xr_result.zig");
const xr = @import("openxr");
const geometry = @import("geometry.zig");
const xr_gl = @import("xr_gl.zig");

const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;

// OpenGL backend
const INSTANCE_EXTENSIONS = [_][]const u8{xr.XR_KHR_OPENGL_ENABLE_EXTENSION_NAME};

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

const SwapchainImageBufferNode = struct {
    node: std.SinglyLinkedList.Node = .{},
    imageBuffer: []xr.XrSwapchainImageOpenGLKHR = &.{},
};

allocator: std.mem.Allocator,
window: c.ksGpuWindow = .{},
graphicsBinding: xr_util.GetGraphicsBindingType(builtin.target) = .{},
swapchainImageBufferList: std.SinglyLinkedList = .{},
swapchainFramebuffer: c.GLuint = 0,
imageMap: std.AutoHashMap(u32, sg.Attachments),

// default pass action, clear to red
pass_action: sg.PassAction = undefined,

pub fn create(allocator: std.mem.Allocator) !*@This() {
    const self = try allocator.create(@This());
    self.* = .{
        .allocator = allocator,
        .imageMap = std.AutoHashMap(u32, sg.Attachments).init(allocator),
    };
    self.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
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
    {
        var current = self.swapchainImageBufferList.first;
        while (current) |p| {
            std.log.debug("destroy list node", .{});
            current = p.next;
            const node: *SwapchainImageBufferNode = @fieldParentPtr("node", p);
            self.allocator.free(node.imageBuffer);
            self.allocator.destroy(node);
        }
    }
    sg.shutdown();
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

    sg.setup(.{
        .logger = .{ .func = slog.func },
    });
    std.debug.assert(sg.isvalid());

    // TODO: sokol
    c.glGenFramebuffers(1, &self.swapchainFramebuffer);
}

pub fn selectColorSwapchainFormat(_self: *anyopaque, runtimeFormats: []i64) ?i64 {
    const self: *@This() = @ptrCast(@alignCast(_self));
    _ = self;
    return xr_gl.selectColorSwapchainFormat(runtimeFormats);
}

pub fn getGraphicsBinding(_self: *anyopaque) *const xr.XrBaseInStructure {
    const self: *@This() = @ptrCast(@alignCast(_self));
    return @ptrCast(&self.graphicsBinding);
}

pub fn allocateSwapchainImageStructs(
    _self: *anyopaque,
    info: xr.XrSwapchainCreateInfo,
    swapchainImageBase: []*xr.XrSwapchainImageBaseHeader,
) bool {
    const self: *@This() = @ptrCast(@alignCast(_self));
    _ = info;
    // Allocate and initialize the buffer of image structs
    // (must be sequential in memory for xrEnumerateSwapchainImages).
    // Return back an array of pointers to each swapchain image struct so the consumer doesn't need to know the type/size.
    var item = self.allocator.create(SwapchainImageBufferNode) catch {
        return false;
    };
    // Keep the buffer alive by moving it into the list of buffers.
    self.swapchainImageBufferList.prepend(&item.node);

    item.imageBuffer = self.allocator.alloc(xr.XrSwapchainImageOpenGLKHR, swapchainImageBase.len) catch {
        return false;
    };
    for (item.imageBuffer, 0..) |*buffer, i| {
        buffer.* = .{
            .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_KHR,
        };
        swapchainImageBase[i] = @ptrCast(buffer);
    }

    return true;
}

pub fn getSupportedSwapchainSampleCount(_: *anyopaque, _: xr.XrViewConfigurationView) u32 {
    return 1;
}

pub fn renderView(
    _self: *anyopaque,
    layerView: *const xr.XrCompositionLayerProjectionView,
    swapchainImage: *const xr.XrSwapchainImageBaseHeader,
    swapchainFormat: i64,
    cubes: []geometry.Cube,
) bool {
    const self: *@This() = @ptrCast(@alignCast(_self));
    _ = swapchainFormat;
    _ = cubes;

    const image = @as(*const xr.XrSwapchainImageOpenGLKHR, @ptrCast(swapchainImage)).image;
    sg.beginPass(.{
        .action = self.pass_action,
        .attachments = self.getAttachment(
            image,
            layerView.subImage.imageRect.extent.width,
            layerView.subImage.imageRect.extent.height,
        ),
    });
    sg.endPass();
    sg.commit();

    return true;
}

fn getAttachment(self: *@This(), colorTexture: u32, width: i32, height: i32) sg.Attachments {
    const attachments = self.imageMap.get(colorTexture) orelse blk: {
        const color_img = sg.makeImage(.{
            .usage = .{ .color_attachment = true },
            .width = width,
            .height = height,
            .sample_count = 1,
            .pixel_format = .RGBA8,
            .gl_textures = .{ colorTexture, 0 },
        });

        const depth_img = sg.makeImage(.{
            .usage = .{ .depth_stencil_attachment = true },
            .width = width,
            .height = height,
            .sample_count = 1,
            .pixel_format = .DEPTH,
        });

        const new_attachments = sg.Attachments{
            .colors = .{
                sg.makeView(.{ .color_attachment = .{ .image = color_img } }),
                .{},
                .{},
                .{},
            },
            .depth_stencil = sg.makeView(.{ .depth_stencil_attachment = .{ .image = depth_img } }),
        };

        self.imageMap.put(colorTexture, new_attachments) catch @panic("OOM");

        break :blk new_attachments;
    };
    return attachments;
}
