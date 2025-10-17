const std = @import("std");
const builtin = @import("builtin");
const xr = @import("openxr").c;
pub const c = if (builtin.target.abi.isAndroid())
    @cImport({
        @cInclude("android/sensor.h");
        @cInclude("EGL/egl.h");
        @cInclude("GLES/gl.h");
        @cInclude("GLES3/gl3.h");
        @cInclude("GLES3/gl31.h");
    })
else
    @cImport({
        @cInclude("Windows.h");
        @cInclude("common/gfxwrapper_opengl.h");
    });

pub const REQUIRED_EXTENSIONS = [_][]const u8{
    // passthrough
    xr.XR_FB_PASSTHROUGH_EXTENSION_NAME,
    xr.XR_FB_TRIANGLE_MESH_EXTENSION_NAME,
    // handtracking
    xr.XR_EXT_HAND_TRACKING_EXTENSION_NAME,
    // xr.XR_FB_HAND_TRACKING_MESH_EXTENSION_NAME,
    // xr.XR_FB_HAND_TRACKING_AIM_EXTENSION_NAME,
    // xr.XR_FB_HAND_TRACKING_CAPSULES_EXTENSION_NAME,
};

pub const REQUIRED_EXTENSIONS_ANDROID = [_][]const u8{
    xr.XR_EXT_PERFORMANCE_SETTINGS_EXTENSION_NAME,
    xr.XR_KHR_ANDROID_THREAD_SETTINGS_EXTENSION_NAME,
};

pub fn my_panic(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    @panic("OOM");
}

pub fn assert(val: bool) !void {
    if (!val) {
        return error.assert;
    }
}

pub const ExtractVersion = extern union {
    version: extern struct {
        major: u16,
        minor: u16,
        patch: u32,
    },
    value: u64,

    pub fn fromXrVersion(xr_version: xr.XrVersion) @This() {
        return .{
            .value = xr_version,
        };
    }
};
