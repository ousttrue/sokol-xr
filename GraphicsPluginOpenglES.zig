const std = @import("std");
const Options = @import("Options.zig");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr = @import("openxr");
const xr_util = @import("xr_util.zig");
const c = xr_util.c;
const CHECK_XRCMD = xr_util.CHECK_XRCMD;
const geometry = @import("geometry.zig");
const xr_linear = @import("xr_linear.zig");

const INSTANCE_EXTENSIONS = [_][]const u8{"XR_KHR_opengl_es_enable"};

// The version statement has come on first line.
const VertexShaderGlsl =
    \\#version 320 es
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

// The version statement has come on first line.
const FragmentShaderGlsl =
    \\#version 320 es
    \\
    \\in lowp vec3 PSVertexColor;
    \\out lowp vec4 FragColor;
    \\
    \\void main() {
    \\   FragColor = vec4(PSVertexColor, 1);
    \\}
;

const SwapchainImageBufferNode = struct {
    node: std.SinglyLinkedList.Node = .{},
    imageBuffer: []xr.XrSwapchainImageOpenGLESKHR = &.{},
};

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
graphicsBinding: xr.XrGraphicsBindingOpenGLESAndroidKHR = .{},
clearColor: [4]f32 = .{ 0, 0, 0, 0 },
colorToDepthMap: std.AutoHashMap(u32, u32),

swapchainImageBufferList: std.SinglyLinkedList = .{},

swapchainFramebuffer: c.GLuint = 0,
program: c.GLuint = 0,
modelViewProjectionUniformLocation: c.GLint = 0,
vertexAttribCoords: c.GLuint = 0,
vertexAttribColor: c.GLuint = 0,
vao: c.GLuint = 0,
cubeVertexBuffer: c.GLuint = 0,
cubeIndexBuffer: c.GLuint = 0,

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
    clear_color: [4]f32 = .{ 0, 0, 0, 0 },
    display: c.EGLDisplay,
    context: c.EGLContext,
};

pub fn create(opts: InitOptions) !*@This() {
    const self = try opts.allocator.create(@This());
    self.* = .{
        .allocator = opts.allocator,
        .graphicsBinding = .{
            .type = xr.XR_TYPE_GRAPHICS_BINDING_OPENGL_ES_ANDROID_KHR,
            .next = null,
            .display = opts.display,
            .config = null,
            .context = opts.context,
        },
        .colorToDepthMap = std.AutoHashMap(u32, u32).init(opts.allocator),
        .clearColor = opts.clear_color,
    };
    return self;
}

pub fn init(opts: InitOptions) !GraphicsPlugin {
    return .{
        .ptr = try create(opts),
        .vtable = &vtable,
    };
}

pub fn destroy(_self: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(_self));
    var current = self.swapchainImageBufferList.first;
    while (current) |p| {
        std.log.debug("destroy list node", .{});
        current = p.next;
        const node: *SwapchainImageBufferNode = @fieldParentPtr("node", p);
        self.allocator.free(node.imageBuffer);
        self.allocator.destroy(node);
    }
    self.colorToDepthMap.deinit();
    self.allocator.destroy(self);
}

pub fn getInstanceExtensions(_: *anyopaque) []const []const u8 {
    return &INSTANCE_EXTENSIONS;
}

pub fn initializeDevice(_self: *anyopaque, instance: xr.XrInstance, systemId: xr.XrSystemId) bool {
    std.log.debug("initializeDevice", .{});
    const self: *@This() = @ptrCast(@alignCast(_self));
    // Extension function must be loaded by name
    var pfnGetOpenGLESGraphicsRequirementsKHR: xr.PFN_xrGetOpenGLESGraphicsRequirementsKHR = undefined;
    CHECK_XRCMD(xr.xrGetInstanceProcAddr(
        instance,
        "xrGetOpenGLESGraphicsRequirementsKHR",
        &pfnGetOpenGLESGraphicsRequirementsKHR,
    )) catch {
        return false;
    };

    var graphicsRequirements = xr.XrGraphicsRequirementsOpenGLESKHR{
        .type = xr.XR_TYPE_GRAPHICS_REQUIREMENTS_OPENGL_ES_KHR,
        .next = null,
    };
    CHECK_XRCMD((pfnGetOpenGLESGraphicsRequirementsKHR.?)(instance, systemId, &graphicsRequirements)) catch {
        std.log.debug("{}", .{graphicsRequirements});
        return false;
    };
    std.log.debug("minApiVersionSupported: {}", .{
        xr_util.ExtractVersion.fromXrVersion(graphicsRequirements.minApiVersionSupported),
    });

    // Initialize the gl extensions. Note we have to open a window.
    // var driverInstance = c.ksDriverInstance{};
    // const queueInfo = c.ksGpuQueueInfo{};
    // const colorFormat = c.KS_GPU_SURFACE_COLOR_FORMAT_B8G8R8A8;
    // const depthFormat = c.KS_GPU_SURFACE_DEPTH_FORMAT_D24;
    // const sampleCount = c.KS_GPU_SAMPLE_COUNT_1;
    // if (!c.ksGpuWindow_Create(
    //     &self.window,
    //     &driverInstance,
    //     &queueInfo,
    //     0,
    //     colorFormat,
    //     depthFormat,
    //     sampleCount,
    //     640,
    //     480,
    //     false,
    // )) {
    //     std.log.err("Unable to create GL context", .{});
    //     return false;
    // }

    var major: c.GLint = 0;
    var minor: c.GLint = 0;
    c.glGetIntegerv(c.GL_MAJOR_VERSION, &major);
    c.glGetIntegerv(c.GL_MINOR_VERSION, &minor);
    const desiredApiVersion: xr.XrVersion = xr.XR_MAKE_VERSION(
        @as(u64, @intCast(major)),
        @as(u64, @intCast(minor)),
        0,
    );
    std.log.debug("desiredApiVersion: {}", .{
        xr_util.ExtractVersion.fromXrVersion(desiredApiVersion),
    });

    // if (graphicsRequirements.minApiVersionSupported > desiredApiVersion) {
    //     std.log.err("graphicsRequirements.minApiVersionSupported > desiredApiVersion: {} > {}", .{
    //         graphicsRequirements.minApiVersionSupported,
    //         desiredApiVersion,
    //     });
    //     return false;
    // }

    //         glEnable(GL_DEBUG_OUTPUT);
    //         glDebugMessageCallback(
    //             [](GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length, const GLchar* message,
    //                const void* userParam) {
    //                 ((OpenGLESGraphicsPlugin*)userParam)->DebugMessageCallback(source, type, id, severity, length, message);
    //             },
    //             this);

    return self.initializeResources();
}

fn initializeResources(self: *@This()) bool {
    std.log.debug("initializeResources", .{});

    c.glGenFramebuffers(1, &self.swapchainFramebuffer);

    const vertexShader = c.glCreateShader(c.GL_VERTEX_SHADER);
    c.glShaderSource(vertexShader, 1, &&VertexShaderGlsl[0], null);
    c.glCompileShader(vertexShader);
    if (!CheckShader(vertexShader)) {
        return false;
    }

    const fragmentShader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    c.glShaderSource(fragmentShader, 1, &&FragmentShaderGlsl[0], null);
    c.glCompileShader(fragmentShader);
    if (!CheckShader(fragmentShader)) {
        return false;
    }

    self.program = c.glCreateProgram();
    c.glAttachShader(self.program, vertexShader);
    c.glAttachShader(self.program, fragmentShader);
    c.glLinkProgram(self.program);
    if (!CheckProgram(self.program)) {
        return false;
    }

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
    c.glVertexAttribPointer(self.vertexAttribCoords, 3, c.GL_FLOAT, c.GL_FALSE, @sizeOf(geometry.Vertex), null);
    c.glVertexAttribPointer(
        self.vertexAttribColor,
        3,
        c.GL_FLOAT,
        c.GL_FALSE,
        @sizeOf(geometry.Vertex),
        @ptrFromInt(@sizeOf(xr.XrVector3f)),
    );

    return true;
}

fn CheckProgram(prog: c.GLuint) bool {
    var r: c.GLint = 0;
    c.glGetProgramiv(prog, c.GL_LINK_STATUS, &r);
    if (r == c.GL_FALSE) {
        var msg: [4096]u8 = undefined;
        var length: c.GLsizei = undefined;
        c.glGetProgramInfoLog(prog, @sizeOf(@TypeOf(msg)), &length, &msg[0]);
        std.log.err("Link program failed: {s}", .{msg});
        return false;
    }
    return true;
}

fn CheckShader(shader: c.GLuint) bool {
    var r: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &r);
    if (r == c.GL_FALSE) {
        var msg: [4096]u8 = undefined;
        var length: c.GLsizei = undefined;
        c.glGetShaderInfoLog(shader, @sizeOf(@TypeOf(msg)), &length, &msg[0]);
        std.log.err("Compile shader failed: {s}", .{msg});
        return false;
    }
    return true;
}

pub fn selectColorSwapchainFormat(_: *anyopaque, runtimeFormats: []i64) ?i64 {
    const supportedColorSwapchainFormats = [_]i64{ c.GL_RGBA8, c.GL_RGBA8_SNORM, c.GL_SRGB8_ALPHA8 };
    for (runtimeFormats) |runtime| {
        for (supportedColorSwapchainFormats) |supported| {
            if (runtime == supported) {
                return runtime;
            }
        }
    }
    return null;
}

pub fn getGraphicsBinding(_self: *anyopaque) ?*const xr.XrBaseInStructure {
    const self: *@This() = @ptrCast(@alignCast(_self));
    return @ptrCast(&self.graphicsBinding);
}

pub fn getSupportedSwapchainSampleCount(_: *anyopaque, _: xr.XrViewConfigurationView) u32 {
    return 1;
}

pub fn allocateSwapchainImageStructs(
    _self: *anyopaque,
    _: xr.XrSwapchainCreateInfo,
    swapchainImageBase: []*xr.XrSwapchainImageBaseHeader,
) bool {
    const self: *@This() = @ptrCast(@alignCast(_self));

    // Allocate and initialize the buffer of image structs
    // (must be sequential in memory for xrEnumerateSwapchainImages).
    // Return back an array of pointers to each swapchain image struct
    // so the consumer doesn't need to know the type/size.
    var item = self.allocator.create(SwapchainImageBufferNode) catch {
        return false;
    };
    // Keep the buffer alive by moving it into the list of buffers.
    self.swapchainImageBufferList.prepend(&item.node);

    item.imageBuffer = self.allocator.alloc(xr.XrSwapchainImageOpenGLESKHR, swapchainImageBase.len) catch {
        return false;
    };
    for (item.imageBuffer, 0..) |*buf, i| {
        buf.* = .{
            .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_ES_KHR,
        };
        swapchainImageBase[i] = @ptrCast(buf);
    }
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

    if (layerView.subImage.imageArrayIndex != 0) {
        std.log.err("Texture arrays not supported.", .{});
        return false;
    }
    _ = swapchainFormat;

    c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.swapchainFramebuffer);

    const swapchain_image: *const xr.XrSwapchainImageOpenGLESKHR = @ptrCast(swapchainImage);
    const colorTexture = swapchain_image.image;

    c.glViewport(
        layerView.subImage.imageRect.offset.x,
        layerView.subImage.imageRect.offset.y,
        layerView.subImage.imageRect.extent.width,
        layerView.subImage.imageRect.extent.height,
    );

    c.glFrontFace(c.GL_CW);
    c.glCullFace(c.GL_BACK);
    c.glEnable(c.GL_CULL_FACE);
    c.glEnable(c.GL_DEPTH_TEST);

    const depthTexture = self.getDepthTexture(colorTexture);

    c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, colorTexture, 0);
    c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, depthTexture, 0);

    // Clear swapchain and depth buffer.
    c.glClearColor(self.clearColor[0], self.clearColor[1], self.clearColor[2], self.clearColor[3]);
    c.glClearDepthf(1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT);

    // Set shaders and uniform variables.
    c.glUseProgram(self.program);

    const proj = xr_linear.Matrix4x4f.createProjectionFov(.OPENGL_ES, layerView.fov, 0.05, 100.0);
    const toView = xr_linear.Matrix4x4f.createFromRigidTransform(layerView.pose);
    const view = toView.invertRigidBody();
    const vp = proj.multiply(view);

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

        c.glUniformMatrix4fv(
            self.modelViewProjectionUniformLocation,
            1,
            c.GL_FALSE,
            &mvp.m[0],
        );

        // Draw the cube.
        c.glDrawElements(
            c.GL_TRIANGLES,
            @sizeOf(@TypeOf(geometry.c_cubeIndices)),
            c.GL_UNSIGNED_SHORT,
            null,
        );
    }

    c.glBindVertexArray(0);
    c.glUseProgram(0);
    c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

    return true;
}

fn getDepthTexture(self: *@This(), colorTexture: u32) u32 {
    // If a depth-stencil view has already been created for this back-buffer, use it.
    if (self.colorToDepthMap.get(colorTexture)) |depthBuffer| {
        return depthBuffer;
    }

    // This back-buffer has no corresponding depth-stencil texture, so create one with matching dimensions.
    var width: c.GLint = undefined;
    var height: c.GLint = undefined;
    c.glBindTexture(c.GL_TEXTURE_2D, colorTexture);
    c.glGetTexLevelParameteriv(c.GL_TEXTURE_2D, 0, c.GL_TEXTURE_WIDTH, &width);
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
        c.GL_DEPTH_COMPONENT24,
        width,
        height,
        0,
        c.GL_DEPTH_COMPONENT,
        c.GL_UNSIGNED_INT,
        null,
    );

    self.colorToDepthMap.put(colorTexture, depthTexture) catch {
        @panic("OOM");
    };
    return depthTexture;
}
