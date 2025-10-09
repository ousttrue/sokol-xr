const std = @import("std");
const GraphicsPlugin = @import("GraphicsPlugin.zig");
const xr_util = @import("xr_util.zig");
const xr_result = @import("xr_result.zig");
const xr = @import("openxr");
const geometry = @import("geometry.zig");

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
// window: c.ksGpuWindow = .{},
graphicsBinding: xr.XrGraphicsBindingD3D11KHR = .{ .type = xr.XR_TYPE_GRAPHICS_BINDING_D3D11_KHR },

// swapchainImageBufferList: std.SinglyLinkedList = .{},
//
// swapchainFramebuffer: c.GLuint = 0,
// program: c.GLuint = 0,
// modelViewProjectionUniformLocation: c.GLint = 0,
// vertexAttribCoords: c.GLuint = 0,
// vertexAttribColor: c.GLuint = 0,
// vao: c.GLuint = 0,
// cubeVertexBuffer: c.GLuint = 0,
// cubeIndexBuffer: c.GLuint = 0,

// Map color buffer to associated depth buffer. This map is populated on demand.
// colorToDepthMap: std.AutoHashMap(u32, u32),
// clearColor: [4]f32 = .{ 0, 0, 0, 0 },

pub fn create(allocator: std.mem.Allocator) !*@This() {
    const self = try allocator.create(@This());
    self.* = .{
        .allocator = allocator,
        // .colorToDepthMap = std.AutoHashMap(u32, u32).init(allocator),
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
    // self.colorToDepthMap.deinit();
    // std.log.debug("#### GraphicsPluginOpengl.deinit ####", .{});
    // {
    //     var current = self.swapchainImageBufferList.first;
    //     while (current) |p| {
    //         std.log.debug("destroy list node", .{});
    //         current = p.next;
    //         const node: *SwapchainImageBufferNode = @fieldParentPtr("node", p);
    //         self.allocator.free(node.imageBuffer);
    //         self.allocator.destroy(node);
    //     }
    // }
    self.allocator.destroy(self);
}

// //     ~OpenGLGraphicsPlugin() override {
// //         if (m_swapchainFramebuffer != 0) {
// //             glDeleteFramebuffers(1, &m_swapchainFramebuffer);
// //         }
// //         if (m_program != 0) {
// //             glDeleteProgram(m_program);
// //         }
// //         if (m_vao != 0) {
// //             glDeleteVertexArrays(1, &m_vao);
// //         }
// //         if (m_cubeVertexBuffer != 0) {
// //             glDeleteBuffers(1, &m_cubeVertexBuffer);
// //         }
// //         if (m_cubeIndexBuffer != 0) {
// //             glDeleteBuffers(1, &m_cubeIndexBuffer);
// //         }
// //
// //         for (auto& colorToDepth : m_colorToDepthMap) {
// //             if (colorToDepth.second != 0) {
// //                 glDeleteTextures(1, &colorToDepth.second);
// //             }
// //         }
// //
// //         ksGpuWindow_Destroy(&window);
// //     }

pub fn getInstanceExtensions(_: *anyopaque) []const []const u8 {
    return &INSTANCE_EXTENSIONS;
}

pub fn initializeDevice(
    _self: *anyopaque,
    instance: xr.XrInstance,
    systemId: xr.XrSystemId,
) xr_result.Error!void {
    const self: *@This() = @ptrCast(@alignCast(_self));
    _ = self;
    _ = instance;
    _ = systemId;
    return xr_result.Error.XR_ERROR_RUNTIME_FAILURE;
}

// fn initializeResources(self: *@This()) void {
//     c.glGenFramebuffers(1, &self.swapchainFramebuffer);
//
//     const vertexShader = c.glCreateShader(c.GL_VERTEX_SHADER);
//
//     c.glShaderSource(vertexShader, 1, &&VertexShaderGlsl[0], null);
//     c.glCompileShader(vertexShader);
//     checkShader(vertexShader);
//
//     const fragmentShader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
//     c.glShaderSource(fragmentShader, 1, &&FragmentShaderGlsl[0], null);
//     c.glCompileShader(fragmentShader);
//     checkShader(fragmentShader);
//
//     self.program = c.glCreateProgram();
//     c.glAttachShader(self.program, vertexShader);
//     c.glAttachShader(self.program, fragmentShader);
//     c.glLinkProgram(self.program);
//     checkProgram(self.program);
//
//     c.glDeleteShader(vertexShader);
//     c.glDeleteShader(fragmentShader);
//
//     self.modelViewProjectionUniformLocation = @intCast(c.glGetUniformLocation(self.program, "ModelViewProjection"));
//
//     self.vertexAttribCoords = @intCast(c.glGetAttribLocation(self.program, "VertexPos"));
//     self.vertexAttribColor = @intCast(c.glGetAttribLocation(self.program, "VertexColor"));
//
//     c.glGenBuffers(1, &self.cubeVertexBuffer);
//     c.glBindBuffer(c.GL_ARRAY_BUFFER, self.cubeVertexBuffer);
//     c.glBufferData(
//         c.GL_ARRAY_BUFFER,
//         @sizeOf(@TypeOf(geometry.c_cubeVertices)),
//         &geometry.c_cubeVertices[0],
//         c.GL_STATIC_DRAW,
//     );
//
//     c.glGenBuffers(1, &self.cubeIndexBuffer);
//     c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.cubeIndexBuffer);
//     c.glBufferData(
//         c.GL_ELEMENT_ARRAY_BUFFER,
//         @sizeOf(@TypeOf(geometry.c_cubeIndices)),
//         &geometry.c_cubeIndices[0],
//         c.GL_STATIC_DRAW,
//     );
//
//     c.glGenVertexArrays(1, &self.vao);
//     c.glBindVertexArray(self.vao);
//     c.glEnableVertexAttribArray(self.vertexAttribCoords);
//     c.glEnableVertexAttribArray(self.vertexAttribColor);
//     c.glBindBuffer(c.GL_ARRAY_BUFFER, self.cubeVertexBuffer);
//     c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.cubeIndexBuffer);
//     c.glVertexAttribPointer(
//         self.vertexAttribCoords,
//         3,
//         c.GL_FLOAT,
//         c.GL_FALSE,
//         @sizeOf(geometry.Vertex),
//         null,
//     );
//     c.glVertexAttribPointer(
//         self.vertexAttribColor,
//         3,
//         c.GL_FLOAT,
//         c.GL_FALSE,
//         @sizeOf(geometry.Vertex),
//         @ptrFromInt(@sizeOf(xr.XrVector3f)),
//     );
// }
//
// fn checkShader(shader: c.GLuint) void {
//     var r: c.GLint = 0;
//     c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &r);
//     if (r == c.GL_FALSE) {
//         var msg: [4096]u8 = undefined;
//         var length: c.GLsizei = undefined;
//         c.glGetShaderInfoLog(shader, msg.len, &length, &msg[0]);
//         std.log.err("Compile shader failed: {s}", .{std.mem.sliceTo(&msg, 0)});
//     }
// }
//
// fn checkProgram(prog: c.GLuint) void {
//     var r: c.GLint = 0;
//     c.glGetProgramiv(prog, c.GL_LINK_STATUS, &r);
//     if (r == c.GL_FALSE) {
//         var msg: [4096]u8 = undefined;
//         var length: c.GLsizei = undefined;
//         c.glGetProgramInfoLog(prog, msg.len, &length, &msg[0]);
//         std.log.err("Link program failed: {s}", .{std.mem.sliceTo(&msg, 0)});
//     }
// }

pub fn selectColorSwapchainFormat(_: *anyopaque, runtimeFormats: []i64) ?i64 {
    _ = runtimeFormats;
    return null;
}

pub fn getGraphicsBinding(_self: *anyopaque) *const xr.XrBaseInStructure {
    const self: *@This() = @ptrCast(@alignCast(_self));
    return @ptrCast(&self.graphicsBinding);
}

pub fn allocateSwapchainImageStructs(
    _self: *anyopaque,
    _: xr.XrSwapchainCreateInfo,
    swapchainImageBase: []*xr.XrSwapchainImageBaseHeader,
) bool {
    const self: *@This() = @ptrCast(@alignCast(_self));
    _ = self;
    _ = swapchainImageBase;
    //     // Allocate and initialize the buffer of image structs
    //     // (must be sequential in memory for xrEnumerateSwapchainImages).
    //     // Return back an array of pointers to each swapchain image struct so the consumer doesn't need to know the type/size.
    //     var item = self.allocator.create(SwapchainImageBufferNode) catch {
    //         return false;
    //     };
    //     // Keep the buffer alive by moving it into the list of buffers.
    //     self.swapchainImageBufferList.prepend(&item.node);
    //
    //     item.imageBuffer = self.allocator.alloc(xr.XrSwapchainImageOpenGLKHR, swapchainImageBase.len) catch {
    //         return false;
    //     };
    //     for (item.imageBuffer, 0..) |*buffer, i| {
    //         buffer.* = .{
    //             .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_KHR,
    //         };
    //         swapchainImageBase[i] = @ptrCast(buffer);
    //     }
    //
    return false;
}

// fn getDepthTexture(self: *@This(), colorTexture: u32) !u32 {
//     // If a depth-stencil view has already been created for this back-buffer, use it.
//     if (self.colorToDepthMap.get(colorTexture)) |depthBuffer| {
//         return depthBuffer;
//     }
//
//     {
//         // This back-buffer has no corresponding depth-stencil texture, so create one with matching dimensions.
//         c.glBindTexture(c.GL_TEXTURE_2D, colorTexture);
//
//         var width: c.GLint = undefined;
//         c.glGetTexLevelParameteriv(c.GL_TEXTURE_2D, 0, c.GL_TEXTURE_WIDTH, &width);
//         var height: c.GLint = undefined;
//         c.glGetTexLevelParameteriv(c.GL_TEXTURE_2D, 0, c.GL_TEXTURE_HEIGHT, &height);
//
//         var depthTexture: u32 = undefined;
//         c.glGenTextures(1, &depthTexture);
//         c.glBindTexture(c.GL_TEXTURE_2D, depthTexture);
//         c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
//         c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
//         c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
//         c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
//         c.glTexImage2D(
//             c.GL_TEXTURE_2D,
//             0,
//             c.GL_DEPTH_COMPONENT32,
//             width,
//             height,
//             0,
//             c.GL_DEPTH_COMPONENT,
//             c.GL_FLOAT,
//             null,
//         );
//
//         try self.colorToDepthMap.put(colorTexture, depthTexture);
//
//         return depthTexture;
//     }
// }

pub fn renderView(
    _self: *anyopaque,
    layerView: *const xr.XrCompositionLayerProjectionView,
    swapchainImage: *const xr.XrSwapchainImageBaseHeader,
    swapchainFormat: i64,
    cubes: []geometry.Cube,
) bool {
    const self: *@This() = @ptrCast(@alignCast(_self));
    _ = self;
    _ = layerView;
    _ = swapchainImage;
    _ = swapchainFormat;
    _ = cubes;
    return false;
}

pub fn getSupportedSwapchainSampleCount(_: *anyopaque, _: xr.XrViewConfigurationView) u32 {
    return 1;
}
