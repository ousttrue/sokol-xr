const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");

pub const REQUIRED_EXTENSIONS = [_][]const u8{
    // passthrough
    c.XR_FB_PASSTHROUGH_EXTENSION_NAME,
    c.XR_FB_TRIANGLE_MESH_EXTENSION_NAME,
    // handtracking
    c.XR_EXT_HAND_TRACKING_EXTENSION_NAME,
    // c.XR_FB_HAND_TRACKING_MESH_EXTENSION_NAME,
    // c.XR_FB_HAND_TRACKING_AIM_EXTENSION_NAME,
    // c.XR_FB_HAND_TRACKING_CAPSULES_EXTENSION_NAME,
};

pub const REQUIRED_EXTENSIONS_ANDROID = [_][]const u8{
    c.XR_EXT_PERFORMANCE_SETTINGS_EXTENSION_NAME,
    c.XR_KHR_ANDROID_THREAD_SETTINGS_EXTENSION_NAME,
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

    pub fn fromXrVersion(xr_version: c.XrVersion) @This() {
        return .{
            .value = xr_version,
        };
    }
};
