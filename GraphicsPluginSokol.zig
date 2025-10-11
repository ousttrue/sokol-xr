const std = @import("std");
const builtin = @import("builtin");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr_util = @import("xr_util.zig");
const c = xr_util.c;
const xr_result = @import("xr_result.zig");
const xr = @import("openxr");
const geometry = @import("geometry.zig");
const xr_gl = @import("xr_gl.zig");
const xr_linear = @import("xr_linear.zig");

const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const shd = @import("shd");

// OpenGL backend
const INSTANCE_EXTENSIONS = [_][]const u8{xr.XR_KHR_OPENGL_ENABLE_EXTENSION_NAME};

pub fn getInstanceExtensions() []const []const u8 {
    return &INSTANCE_EXTENSIONS;
}

pub fn selectColorSwapchainFormat(runtimeFormats: []i64) ?i64 {
    return xr_gl.selectColorSwapchainFormat(runtimeFormats);
}

pub fn getSupportedSwapchainSampleCount(_: xr.XrViewConfigurationView) u32 {
    return 1;
}

pub fn getSwapchainTextureValue(base: *const xr.XrSwapchainImageBaseHeader) usize {
    const image_gl = @as(*const xr.XrSwapchainImageOpenGLKHR, @ptrCast(base));
    return image_gl.image;
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
    .getSwapchainTextureValue = &getSwapchainTextureValue,
    .calcViewProjectionMatrix = &calcViewProjectionMatrix,
    //
    .deinit = &destroy,
    .initializeDevice = &initializeDevice,
    .getGraphicsBinding = &getGraphicsBinding,
    .allocateSwapchainImageStructs = &allocateSwapchainImageStructs,
    .renderView = &renderView,
};

const SwapchainImageBufferNode = struct {
    node: std.SinglyLinkedList.Node = .{},
    imageBuffer: []xr.XrSwapchainImageOpenGLKHR = &.{},
};

const State = struct {
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
};

allocator: std.mem.Allocator,
window: c.ksGpuWindow = .{},
graphicsBinding: xr_util.GetGraphicsBindingType(builtin.target) = .{},
swapchainImageBufferList: std.SinglyLinkedList = .{},
imageMap: std.AutoHashMap(u32, sg.Attachments),

state: State = .{},

pub fn create(allocator: std.mem.Allocator) !*@This() {
    const self = try allocator.create(@This());
    self.* = .{
        .allocator = allocator,
        .imageMap = std.AutoHashMap(u32, sg.Attachments).init(allocator),
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
    self.imageMap.deinit();
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

    // cube vertex buffer
    const s = 0.5;
    self.state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            // positions        colors
            -s, -s, -s, 1.0, 0.0, 0.0, 1.0,
            s,  -s, -s, 1.0, 0.0, 0.0, 1.0,
            s,  s,  -s, 1.0, 0.0, 0.0, 1.0,
            -s, s,  -s, 1.0, 0.0, 0.0, 1.0,

            -s, -s, s,  0.0, 1.0, 0.0, 1.0,
            s,  -s, s,  0.0, 1.0, 0.0, 1.0,
            s,  s,  s,  0.0, 1.0, 0.0, 1.0,
            -s, s,  s,  0.0, 1.0, 0.0, 1.0,

            -s, -s, -s, 0.0, 0.0, 1.0, 1.0,
            -s, s,  -s, 0.0, 0.0, 1.0, 1.0,
            -s, s,  s,  0.0, 0.0, 1.0, 1.0,
            -s, -s, s,  0.0, 0.0, 1.0, 1.0,

            s,  -s, -s, 1.0, 0.5, 0.0, 1.0,
            s,  s,  -s, 1.0, 0.5, 0.0, 1.0,
            s,  s,  s,  1.0, 0.5, 0.0, 1.0,
            s,  -s, s,  1.0, 0.5, 0.0, 1.0,

            -s, -s, -s, 0.0, 0.5, 1.0, 1.0,
            -s, -s, s,  0.0, 0.5, 1.0, 1.0,
            s,  -s, s,  0.0, 0.5, 1.0, 1.0,
            s,  -s, -s, 0.0, 0.5, 1.0, 1.0,

            -s, s,  -s, 1.0, 0.0, 0.5, 1.0,
            -s, s,  s,  1.0, 0.0, 0.5, 1.0,
            s,  s,  s,  1.0, 0.0, 0.5, 1.0,
            s,  s,  -s, 1.0, 0.0, 0.5, 1.0,
        }),
    });

    // cube index buffer
    self.state.bind.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(&[_]u16{
            0,  1,  2,  0,  2,  3,
            6,  5,  4,  7,  6,  4,
            8,  9,  10, 8,  10, 11,
            14, 13, 12, 15, 14, 12,
            16, 17, 18, 16, 18, 19,
            22, 21, 20, 23, 22, 20,
        }),
    });

    // shader and pipeline object
    self.state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.cubeShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_cube_position].format = .FLOAT3;
            l.attrs[shd.ATTR_cube_color0].format = .FLOAT4;
            break :init l;
        },
        .index_type = .UINT16,
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
            .pixel_format = .DEPTH,
        },
        .cull_mode = .BACK,
    });
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

pub fn renderView(
    _self: *anyopaque,
    image: usize,
    swapchainFormat: i64,
    extent: xr.XrExtent2Di,
    vp: xr_linear.Matrix4x4f,
    cubes: []geometry.Cube,
) bool {
    const self: *@This() = @ptrCast(@alignCast(_self));
    _ = swapchainFormat;

    sg.beginPass(.{
        .action = .{
            .colors = .{
                .{
                    .load_action = .CLEAR,
                    .clear_value = .{ .r = 0.25, .g = 0.5, .b = 0.75, .a = 1 },
                },
                .{},
                .{},
                .{},
            },
        },
        .attachments = self.getAttachment(
            @intCast(image),
            extent.width,
            extent.height,
        ),
    });

    {
        for (cubes) |cube| {
            sg.applyPipeline(self.state.pip);
            sg.applyBindings(self.state.bind);

            const model = xr_linear.Matrix4x4f.createTranslationRotationScale(
                cube.Pose.position,
                cube.Pose.orientation,
                cube.Scale,
            );
            const mvp = vp.multiply(model);

            var vs_params = shd.VsParams{
                .mvp = mvp.m,
            };

            sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
            sg.draw(0, 36, 1);
        }
    }

    sg.endPass();
    sg.commit();

    return true;
}
