const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");
const xr_result = @import("xr_result.zig");
const xr_util = @import("xr_util.zig");

pub fn initializeDevice(
    instance: c.XrInstance,
    systemId: c.XrSystemId,
    window: *c.ksGpuWindow,
) !void {
    var pfnGetOpenGLGraphicsRequirementsKHR: c.PFN_xrGetOpenGLGraphicsRequirementsKHR = null;
    try xr_result.check(c.xrGetInstanceProcAddr(
        instance,
        "xrGetOpenGLGraphicsRequirementsKHR",
        &pfnGetOpenGLGraphicsRequirementsKHR,
    ));

    var graphicsRequirements = c.XrGraphicsRequirementsOpenGLKHR{
        .type = c.XR_TYPE_GRAPHICS_REQUIREMENTS_OPENGL_KHR,
    };
    try xr_result.check(pfnGetOpenGLGraphicsRequirementsKHR.?(
        instance,
        systemId,
        &graphicsRequirements,
    ));

    // Initialize the gl extensions. Note we have to open a window.
    var driverInstance = c.ksDriverInstance{};
    var queueInfo = c.ksGpuQueueInfo{};
    const colorFormat = c.KS_GPU_SURFACE_COLOR_FORMAT_B8G8R8A8;
    const depthFormat = c.KS_GPU_SURFACE_DEPTH_FORMAT_D24;
    const sampleCount = c.KS_GPU_SAMPLE_COUNT_1;
    if (!c.ksGpuWindow_Create(
        window,
        &driverInstance,
        &queueInfo,
        0,
        colorFormat,
        depthFormat,
        sampleCount,
        640,
        480,
        false,
    )) {
        xr_util.my_panic("Unable to create GL context", .{});
    }

    var major: c_int = 0;
    var minor: c_int = 0;
    c.glGetIntegerv(c.GL_MAJOR_VERSION, &major);
    c.glGetIntegerv(c.GL_MINOR_VERSION, &minor);

    const desiredApiVersion = c.XR_MAKE_VERSION(
        @as(i64, @intCast(major)),
        @as(i64, @intCast(minor)),
        0,
    );
    if (graphicsRequirements.minApiVersionSupported > desiredApiVersion) {
        xr_util.my_panic("Runtime does not support desired Graphics API and/or version", .{});
    }

    // #elif defined(XR_USE_PLATFORM_XLIB)
    //         m_graphicsBinding.xDisplay = window.context.xDisplay;
    //         m_graphicsBinding.visualid = window.context.visualid;
    //         m_graphicsBinding.glxFBConfig = window.context.glxFBConfig;
    //         m_graphicsBinding.glxDrawable = window.context.glxDrawable;
    //         m_graphicsBinding.glxContext = window.context.glxContext;
    // #elif defined(XR_USE_PLATFORM_XCB)
    //         // TODO: Still missing the platform adapter, and some items to make this usable.
    //         m_graphicsBinding.connection = window.connection;
    //         // m_graphicsBinding.screenNumber = window.context.screenNumber;
    //         // m_graphicsBinding.fbconfigid = window.context.fbconfigid;
    //         m_graphicsBinding.visualid = window.context.visualid;
    //         m_graphicsBinding.glxDrawable = window.context.glxDrawable;
    //         // m_graphicsBinding.glxContext = window.context.glxContext;
    // #elif defined(XR_USE_PLATFORM_WAYLAND)
    //         // TODO: Just need something other than NULL here for now (for validation).  Eventually need
    //         //       to correctly put in a valid pointer to an wl_display
    //         m_graphicsBinding.display = reinterpret_cast<wl_display*>(0xFFFFFFFF);
    // #elif defined(XR_USE_PLATFORM_MACOS)
    // #error OpenGL bindings for Mac have not been implemented
    // #else
    // #error Platform not supported
    // #endif

    if (builtin.target.os.tag != .macos) {
        // #if !defined(XR_USE_PLATFORM_MACOS)
        c.glEnable(c.GL_DEBUG_OUTPUT);
        //         glDebugMessageCallback(
        //             [](GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length, const GLchar* message,
        //                const void* userParam) {
        //                 ((OpenGLGraphicsPlugin*)userParam)->DebugMessageCallback(source, type, id, severity, length, message);
        //             },
        //             this);
    }
}

pub fn selectColorSwapchainFormat(runtimeFormats: []i64) ?i64 {
    // List of supported color swapchain formats.
    const SupportedColorSwapchainFormats = [_]i64{
        c.GL_RGB10_A2,
        c.GL_RGBA16F,
        // The two below should only be used as a fallback,
        // as they are linear color formats without enough bits for color
        // depth, thus leading to banding.
        c.GL_RGBA8,
        c.GL_RGBA8_SNORM,
    };

    for (runtimeFormats) |runtime| {
        for (SupportedColorSwapchainFormats) |supported| {
            if (runtime == supported) {
                return runtime;
            }
        }
    }

    return null;
}
