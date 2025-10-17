const std = @import("std");
const xr_gen = @import("openxr");
const xr = xr_gen.c;
const xr_util = @import("xr_util.zig");
const c = xr_util.c;
const geometry = @import("geometry.zig");
const xr_linear = @import("xr_linear.zig");

const VertexShaderGlsl =
    \\#version 410
    \\
    \\in vec3 VertexPos;
    \\in vec3 VertexColor;
    \\
    \\out vec3 PSVertexColor;
    \\
    \\uniform mat4 ModelViewProjection;
    \\
    \\void main() {
    \\   gl_Position = ModelViewProjection * vec4(VertexPos, 1.0);
    \\   PSVertexColor = VertexColor;
    \\}
;

const FragmentShaderGlsl =
    \\#version 410
    \\
    \\in vec3 PSVertexColor;
    \\out vec4 FragColor;
    \\
    \\void main() {
    \\   FragColor = vec4(PSVertexColor, 1);
    \\}
;

swapchainFramebuffer: c.GLuint = 0,
program: c.GLuint = 0,
modelViewProjectionUniformLocation: c.GLint = 0,
vertexAttribCoords: c.GLuint = 0,
vertexAttribColor: c.GLuint = 0,
vao: c.GLuint = 0,
cubeVertexBuffer: c.GLuint = 0,
cubeIndexBuffer: c.GLuint = 0,

colorToDepthMap: std.AutoHashMap(u32, u32),

pub fn init(allocator: std.mem.Allocator) @This() {
    var self = @This(){
        .colorToDepthMap = .init(allocator),
    };

    c.glGenFramebuffers(1, &self.swapchainFramebuffer);

    const vertexShader = c.glCreateShader(c.GL_VERTEX_SHADER);

    c.glShaderSource(vertexShader, 1, &&VertexShaderGlsl[0], null);
    c.glCompileShader(vertexShader);
    checkShader(vertexShader);

    const fragmentShader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    c.glShaderSource(fragmentShader, 1, &&FragmentShaderGlsl[0], null);
    c.glCompileShader(fragmentShader);
    checkShader(fragmentShader);

    self.program = c.glCreateProgram();
    c.glAttachShader(self.program, vertexShader);
    c.glAttachShader(self.program, fragmentShader);
    c.glLinkProgram(self.program);
    checkProgram(self.program);

    c.glDeleteShader(vertexShader);
    c.glDeleteShader(fragmentShader);

    self.modelViewProjectionUniformLocation = @intCast(c.glGetUniformLocation(self.program, "ModelViewProjection"));

    self.vertexAttribCoords = @intCast(c.glGetAttribLocation(self.program, "VertexPos"));
    self.vertexAttribColor = @intCast(c.glGetAttribLocation(self.program, "VertexColor"));

    c.glGenBuffers(1, &self.cubeVertexBuffer);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, self.cubeVertexBuffer);
    c.glBufferData(
        c.GL_ARRAY_BUFFER,
        @sizeOf(@TypeOf(geometry.c_cubeVertices)),
        &geometry.c_cubeVertices[0],
        c.GL_STATIC_DRAW,
    );

    c.glGenBuffers(1, &self.cubeIndexBuffer);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.cubeIndexBuffer);
    c.glBufferData(
        c.GL_ELEMENT_ARRAY_BUFFER,
        @sizeOf(@TypeOf(geometry.c_cubeIndices)),
        &geometry.c_cubeIndices[0],
        c.GL_STATIC_DRAW,
    );

    c.glGenVertexArrays(1, &self.vao);
    c.glBindVertexArray(self.vao);
    c.glEnableVertexAttribArray(self.vertexAttribCoords);
    c.glEnableVertexAttribArray(self.vertexAttribColor);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, self.cubeVertexBuffer);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.cubeIndexBuffer);
    c.glVertexAttribPointer(
        self.vertexAttribCoords,
        3,
        c.GL_FLOAT,
        c.GL_FALSE,
        @sizeOf(geometry.Vertex),
        null,
    );
    c.glVertexAttribPointer(
        self.vertexAttribColor,
        3,
        c.GL_FLOAT,
        c.GL_FALSE,
        @sizeOf(geometry.Vertex),
        @ptrFromInt(@sizeOf(xr.XrVector3f)),
    );

    return self;
}

fn checkShader(shader: c.GLuint) void {
    var r: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &r);
    if (r == c.GL_FALSE) {
        var msg: [4096]u8 = undefined;
        var length: c.GLsizei = undefined;
        c.glGetShaderInfoLog(shader, msg.len, &length, &msg[0]);
        std.log.err("Compile shader failed: {s}", .{std.mem.sliceTo(&msg, 0)});
    }
}

fn checkProgram(prog: c.GLuint) void {
    var r: c.GLint = 0;
    c.glGetProgramiv(prog, c.GL_LINK_STATUS, &r);
    if (r == c.GL_FALSE) {
        var msg: [4096]u8 = undefined;
        var length: c.GLsizei = undefined;
        c.glGetProgramInfoLog(prog, msg.len, &length, &msg[0]);
        std.log.err("Link program failed: {s}", .{std.mem.sliceTo(&msg, 0)});
    }
}

pub fn deinit(self: *@This()) void {
    self.colorToDepthMap.deinit();
    //         if (m_swapchainFramebuffer != 0) {
    //             glDeleteFramebuffers(1, &m_swapchainFramebuffer);
    //         }
    //         if (m_program != 0) {
    //             glDeleteProgram(m_program);
    //         }
    //         if (m_vao != 0) {
    //             glDeleteVertexArrays(1, &m_vao);
    //         }
    //         if (m_cubeVertexBuffer != 0) {
    //             glDeleteBuffers(1, &m_cubeVertexBuffer);
    //         }
    //         if (m_cubeIndexBuffer != 0) {
    //             glDeleteBuffers(1, &m_cubeIndexBuffer);
    //         }
    //         for (auto& colorToDepth : m_colorToDepthMap) {
    //             if (colorToDepth.second != 0) {
    //                 glDeleteTextures(1, &colorToDepth.second);
    //             }
    //         }
    //
    //     }
}

pub fn render(
    self: *@This(),
    color_texture: u32,
    viewport_width: i32,
    viewport_height: i32,
    clear_color: [4]f32,
    vp: xr_linear.Matrix4x4f,
    cubes: []geometry.Cube,
) void {
    c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.swapchainFramebuffer);

    c.glViewport(
        0,
        0,
        viewport_width,
        viewport_height,
    );

    c.glFrontFace(c.GL_CW);
    c.glCullFace(c.GL_BACK);
    c.glEnable(c.GL_CULL_FACE);
    c.glEnable(c.GL_DEPTH_TEST);

    const depth_texture = self.getDepthTexture(color_texture) catch {
        return;
    };

    c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, color_texture, 0);
    c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, depth_texture, 0);

    // Clear swapchain and depth buffer.
    c.glClearColor(clear_color[0], clear_color[1], clear_color[2], clear_color[3]);
    c.glClearDepth(1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT);

    // Set shaders and uniform variables.
    c.glUseProgram(self.program);

    // Set cube primitive data.
    c.glBindVertexArray(self.vao);

    // Render each cube
    for (cubes) |cube| {
        // Compute the model-view-projection transform and set it..
        const model = xr_linear.Matrix4x4f.createTranslationRotationScale(
            cube.Pose.position,
            cube.Pose.orientation,
            cube.Scale,
        );
        const mvp = vp.multiply(model);
        c.glUniformMatrix4fv(self.modelViewProjectionUniformLocation, 1, c.GL_FALSE, &mvp.m[0]);

        // Draw the cube.
        c.glDrawElements(c.GL_TRIANGLES, geometry.c_cubeIndices.len, c.GL_UNSIGNED_SHORT, null);
    }

    c.glBindVertexArray(0);
    c.glUseProgram(0);
    c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
}

fn getDepthTexture(self: *@This(), colorTexture: u32) !u32 {
    // If a depth-stencil view has already been created for this back-buffer, use it.
    if (self.colorToDepthMap.get(colorTexture)) |depthBuffer| {
        return depthBuffer;
    }

    {
        // This back-buffer has no corresponding depth-stencil texture, so create one with matching dimensions.
        c.glBindTexture(c.GL_TEXTURE_2D, colorTexture);

        var width: c.GLint = undefined;
        c.glGetTexLevelParameteriv(c.GL_TEXTURE_2D, 0, c.GL_TEXTURE_WIDTH, &width);
        var height: c.GLint = undefined;
        c.glGetTexLevelParameteriv(c.GL_TEXTURE_2D, 0, c.GL_TEXTURE_HEIGHT, &height);

        var depthTexture: u32 = undefined;
        c.glGenTextures(1, &depthTexture);
        c.glBindTexture(c.GL_TEXTURE_2D, depthTexture);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_DEPTH_COMPONENT32,
            width,
            height,
            0,
            c.GL_DEPTH_COMPONENT,
            c.GL_FLOAT,
            null,
        );

        try self.colorToDepthMap.put(colorTexture, depthTexture);

        return depthTexture;
    }
}
