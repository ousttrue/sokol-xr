const std = @import("std");
const xr_util = @import("xr_util.zig");
const c = @import("c");

const ksGpuSurfaceColorFormat = enum {
    KS_GPU_SURFACE_COLOR_FORMAT_R5G6B5,
    KS_GPU_SURFACE_COLOR_FORMAT_B5G6R5,
    KS_GPU_SURFACE_COLOR_FORMAT_R8G8B8A8,
    KS_GPU_SURFACE_COLOR_FORMAT_B8G8R8A8,
    KS_GPU_SURFACE_COLOR_FORMAT_MAX,
};

const ksGpuSurfaceDepthFormat = enum {
    KS_GPU_SURFACE_DEPTH_FORMAT_NONE,
    KS_GPU_SURFACE_DEPTH_FORMAT_D16,
    KS_GPU_SURFACE_DEPTH_FORMAT_D24,
    KS_GPU_SURFACE_DEPTH_FORMAT_MAX,
};

const ksGpuSampleCount = enum(i32) {
    KS_GPU_SAMPLE_COUNT_1 = 1,
    KS_GPU_SAMPLE_COUNT_2 = 2,
    KS_GPU_SAMPLE_COUNT_4 = 4,
    KS_GPU_SAMPLE_COUNT_8 = 8,
    KS_GPU_SAMPLE_COUNT_16 = 16,
    KS_GPU_SAMPLE_COUNT_32 = 32,
    KS_GPU_SAMPLE_COUNT_64 = 64,
};

const ksGpuLimits = struct {
    maxPushConstantsSize: usize,
    maxSamples: i32,
};

const ksGpuContext = struct {
    //     EGLDisplay display;
    //     EGLConfig config;
    //     EGLSurface tinySurface;
    //     EGLSurface mainSurface;
    //     EGLContext context;
};

const ksGpuSurfaceBits = struct {
    redBits: u8 = 0,
    greenBits: u8 = 0,
    blueBits: u8 = 0,
    alphaBits: u8 = 0,
    colorBits: u8 = 0,
    depthBits: u8 = 0,

    fn bitsForSurfaceFormat(
        colorFormat: ksGpuSurfaceColorFormat,
        depthFormat: ksGpuSurfaceDepthFormat,
    ) @This() {
        var bits = ksGpuSurfaceBits{};
        bits.redBits = (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_R8G8B8A8)
            8
        else
            (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_B8G8R8A8)
                8
            else
                (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_R5G6B5)
                    5
                else
                    (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_B5G6R5) 5 else 8))));
        bits.greenBits = (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_R8G8B8A8)
            8
        else
            (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_B8G8R8A8)
                8
            else
                (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_R5G6B5)
                    6
                else
                    (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_B5G6R5) 6 else 8))));
        bits.blueBits = (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_R8G8B8A8)
            8
        else
            (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_B8G8R8A8)
                8
            else
                (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_R5G6B5)
                    5
                else
                    (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_B5G6R5) 5 else 8))));
        bits.alphaBits = (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_R8G8B8A8)
            8
        else
            (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_B8G8R8A8)
                8
            else
                (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_R5G6B5)
                    0
                else
                    (if (colorFormat == .KS_GPU_SURFACE_COLOR_FORMAT_B5G6R5) 0 else 8))));
        bits.colorBits = bits.redBits + bits.greenBits + bits.blueBits + bits.alphaBits;
        bits.depthBits =
            (if (depthFormat == .KS_GPU_SURFACE_DEPTH_FORMAT_D16)
                16
            else
                (if (depthFormat == .KS_GPU_SURFACE_DEPTH_FORMAT_D24)
                    24
                else
                    0));
        return bits;
    }
};

display: c.EGLDisplay,
//     EGLConfig config;
//     EGLSurface tinySurface;
//     EGLSurface mainSurface;
context: c.EGLContext,

// #if defined(OS_ANDROID) || defined(OS_LINUX_WAYLAND)
//
// #define EGL(func)                                                      \
//     do {                                                               \
//         if (func == EGL_FALSE) {                                       \
//             Error(#func " failed: %s", EglErrorString(eglGetError())); \
//         }                                                              \
//     } while (0)

fn EglErrorString(err: c.EGLint) []const u8 {
    return switch (err) {
        c.EGL_SUCCESS => "EGL_SUCCESS",
        c.EGL_NOT_INITIALIZED => "EGL_NOT_INITIALIZED",
        c.EGL_BAD_ACCESS => "EGL_BAD_ACCESS",
        c.EGL_BAD_ALLOC => "EGL_BAD_ALLOC",
        c.EGL_BAD_ATTRIBUTE => "EGL_BAD_ATTRIBUTE",
        c.EGL_BAD_CONTEXT => "EGL_BAD_CONTEXT",
        c.EGL_BAD_CONFIG => "EGL_BAD_CONFIG",
        c.EGL_BAD_CURRENT_SURFACE => "EGL_BAD_CURRENT_SURFACE",
        c.EGL_BAD_DISPLAY => "EGL_BAD_DISPLAY",
        c.EGL_BAD_SURFACE => "EGL_BAD_SURFACE",
        c.EGL_BAD_MATCH => "EGL_BAD_MATCH",
        c.EGL_BAD_PARAMETER => "EGL_BAD_PARAMETER",
        c.EGL_BAD_NATIVE_PIXMAP => "EGL_BAD_NATIVE_PIXMAP",
        c.EGL_BAD_NATIVE_WINDOW => "EGL_BAD_NATIVE_WINDOW",
        c.EGL_CONTEXT_LOST => "EGL_CONTEXT_LOST",
        else => "unknown",
    };
}

fn ksGpuContext_CreateForSurface(
    display: c.EGLDisplay,
    colorFormat: ksGpuSurfaceColorFormat,
    depthFormat: ksGpuSurfaceDepthFormat,
    sampleCount: ksGpuSampleCount,
) ?c.EGLContext {

    // Do NOT use eglChooseConfig, because the Android EGL code pushes in multisample
    // flags in eglChooseConfig when the user has selected the "force 4x MSAA" option in
    // settings, and that is completely wasted on the time warped frontbuffer.
    const MAX_CONFIGS = 1024;
    var configs: [MAX_CONFIGS]c.EGLConfig = undefined;
    var numConfigs: c.EGLint = 0;
    if (c.eglGetConfigs(display, &configs[0], MAX_CONFIGS, &numConfigs) != c.EGL_TRUE) {
        return null;
    }

    const bits = ksGpuSurfaceBits.bitsForSurfaceFormat(colorFormat, depthFormat);

    const configAttribs = [_]c.EGLint{
        c.EGL_RED_SIZE,       bits.redBits,
        c.EGL_GREEN_SIZE,     bits.greenBits,
        c.EGL_BLUE_SIZE,      bits.blueBits,
        c.EGL_ALPHA_SIZE,     bits.alphaBits,
        c.EGL_DEPTH_SIZE,     bits.depthBits,
        // EGL_STENCIL_SIZE, 0,
        c.EGL_SAMPLE_BUFFERS,
        if (@intFromEnum(sampleCount) > @intFromEnum(ksGpuSampleCount.KS_GPU_SAMPLE_COUNT_1))
            1
        else
            0,
        c.EGL_SAMPLES,
        if (@intFromEnum(sampleCount) > @intFromEnum(ksGpuSampleCount.KS_GPU_SAMPLE_COUNT_1))
            @intFromEnum(sampleCount)
        else
            0,
        c.EGL_NONE,
    };

    var config: c.EGLConfig = null;
    for (0..@as(usize, @intCast(numConfigs))) |i| {
        var value: c.EGLint = undefined;
        _ = c.eglGetConfigAttrib(display, configs[i], c.EGL_RENDERABLE_TYPE, &value);
        if ((value & c.EGL_OPENGL_ES3_BIT) != c.EGL_OPENGL_ES3_BIT) {
            continue;
        }

        // Without EGL_KHR_surfaceless_context, the config needs to support both pbuffers and window surfaces.
        _ = c.eglGetConfigAttrib(display, configs[i], c.EGL_SURFACE_TYPE, &value);
        if ((value & (c.EGL_WINDOW_BIT | c.EGL_PBUFFER_BIT)) != (c.EGL_WINDOW_BIT | c.EGL_PBUFFER_BIT)) {
            continue;
        }

        var j: usize = 0;
        while (configAttribs[j] != c.EGL_NONE) {
            _ = c.eglGetConfigAttrib(display, configs[i], configAttribs[j], &value);
            if (value != configAttribs[j + 1]) {
                break;
            }
            j += 2;
        }
        if (configAttribs[j] == c.EGL_NONE) {
            config = configs[i];
            break;
        }
    }
    if (config == null) {
        std.log.err("Failed to find EGLConfig", .{});
        return null;
    }

    const contextAttribs = [_]c.EGLint{
        c.EGL_CONTEXT_CLIENT_VERSION,
        3, //c.OPENGL_VERSION_MAJOR,
        c.EGL_NONE,
        c.EGL_NONE,
        c.EGL_NONE,
    };
    // Use the default priority if KS_GPU_QUEUE_PRIORITY_MEDIUM is selected.
    // const ksGpuQueuePriority priority = device->queueInfo.queuePriorities[queueIndex];
    // if (priority != KS_GPU_QUEUE_PRIORITY_MEDIUM) {
    //     contextAttribs[2] = EGL_CONTEXT_PRIORITY_LEVEL_IMG;
    //     contextAttribs[3] = (priority == KS_GPU_QUEUE_PRIORITY_LOW) ? EGL_CONTEXT_PRIORITY_LOW_IMG : EGL_CONTEXT_PRIORITY_HIGH_IMG;
    // }
    const context = c.eglCreateContext(display, config, c.EGL_NO_CONTEXT, &contextAttribs[0]);
    if (context == c.EGL_NO_CONTEXT) {
        std.log.err("eglCreateContext() failed: {s}", .{EglErrorString(c.eglGetError())});
        return null;
    }

    const surfaceAttribs = [_]c.EGLint{
        c.EGL_WIDTH,
        16,
        c.EGL_HEIGHT,
        16,
        c.EGL_NONE,
    };
    const tinySurface = c.eglCreatePbufferSurface(display, config, &surfaceAttribs[0]);
    if (tinySurface == c.EGL_NO_SURFACE) {
        std.log.err("eglCreatePbufferSurface() failed: {s}", .{EglErrorString(c.eglGetError())});
        _ = c.eglDestroyContext(display, context);
        // context = c.EGL_NO_CONTEXT;
        return null;
    }
    // context->mainSurface = context->tinySurface;

    return context;
}

// void ksGpuContext_Destroy(ksGpuContext *context) {

// #if defined(OS_ANDROID)
//     if (context->mainSurface != context->tinySurface) {
//         EGL(eglDestroySurface(context->display, context->mainSurface));
//     }
//     if (context->tinySurface != EGL_NO_SURFACE) {
//         EGL(eglDestroySurface(context->display, context->tinySurface));
//     }
//     context->tinySurface = EGL_NO_SURFACE;
// }

// void ksGpuContext_UnsetCurrent(ksGpuContext *context) {
//     EGL(eglMakeCurrent(context->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT));
// }

// bool ksGpuContext_CheckCurrent(ksGpuContext *context) {
//     return (eglGetCurrentContext() == context->context);
// }

// void ksGpuWindow_Destroy(ksGpuWindow *window) {
//     ksGpuContext_Destroy(&window->context);
//     ksGpuDevice_Destroy(&window->device);
//
//     if (window->display != 0) {
//         EGL(eglTerminate(window->display));
//         window->display = 0;
//     }
// }

pub fn init(
    colorFormat: ksGpuSurfaceColorFormat,
    depthFormat: ksGpuSurfaceDepthFormat,
    sampleCount: ksGpuSampleCount,
) ?@This() {
    const display = c.eglGetDisplay(c.EGL_DEFAULT_DISPLAY);
    var majorVersion: c_int = undefined;
    var minorVersion: c_int = undefined;
    if (c.eglInitialize(display, &majorVersion, &minorVersion) != c.EGL_TRUE) {
        return null;
    }
    std.log.info("EGL {}.{}", .{ majorVersion, minorVersion });

    const context = ksGpuContext_CreateForSurface(
        @ptrCast(display),
        colorFormat,
        depthFormat,
        sampleCount,
    ) orelse {
        return null;
    };

    if (c.eglMakeCurrent(display, null, null, context) != c.EGL_TRUE) {
        std.log.err("eglMakeCurrent", .{});
        return null;
    }

    return @This(){
        .display = display,
        .context = context,
    };
}
