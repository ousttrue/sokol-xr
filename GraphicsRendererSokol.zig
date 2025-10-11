const std = @import("std");
const geometry = @import("geometry.zig");
const xr_linear = @import("xr_linear.zig");

const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const shd = @import("shd");

const State = struct {
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
};

allocator: std.mem.Allocator,
imageMap: std.AutoHashMap(u32, sg.Attachments),

state: State = .{},

pub fn init(allocator: std.mem.Allocator) @This() {
    var self = @This(){
        .allocator = allocator,
        .imageMap = .init(allocator),
    };

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

    return self;
}

pub fn deinit(self: *@This()) void {
    self.imageMap.deinit();
    sg.shutdown();
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

pub fn render(
    self: *@This(),
    color_texture: u32,
    viewport_width: i32,
    viewport_height: i32,
    vp: xr_linear.Matrix4x4f,
    cubes: []geometry.Cube,
) void {
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
            color_texture,
            viewport_width,
            viewport_height,
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
}
