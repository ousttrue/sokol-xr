const std = @import("std");
const builtin = @import("builtin");
const xr = @import("openxr");
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

pub fn XrPosef_Identity() xr.XrPosef {
    return .{
        .orientation = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
    };
}

pub fn XrPosef_Translation(translation: xr.XrVector3f) xr.XrPosef {
    return .{
        .orientation = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        .position = translation,
    };
}

pub fn XrPosef_RotateCCWAboutYAxis(radians: f32, translation: xr.XrVector3f) xr.XrPosef {
    return .{
        .orientation = .{
            .x = 0,
            .y = @sin(radians * 0.5),
            .z = 0,
            .w = @cos(radians * 0.5),
        },
        .position = translation,
    };
}

pub fn GetGraphicsBindingType(comptime target: std.Target) type {
    // #ifdef XR_USE_PLATFORM_WIN32
    //     XrGraphicsBindingOpenGLWin32KHR m_graphicsBinding{XR_TYPE_GRAPHICS_BINDING_OPENGL_WIN32_KHR};
    // #elif defined(XR_USE_PLATFORM_XLIB)
    //     XrGraphicsBindingOpenGLXlibKHR m_graphicsBinding{XR_TYPE_GRAPHICS_BINDING_OPENGL_XLIB_KHR};
    // #elif defined(XR_USE_PLATFORM_XCB)
    //     XrGraphicsBindingOpenGLXcbKHR m_graphicsBinding{XR_TYPE_GRAPHICS_BINDING_OPENGL_XCB_KHR};
    // #elif defined(XR_USE_PLATFORM_WAYLAND)
    //     XrGraphicsBindingOpenGLWaylandKHR m_graphicsBinding{XR_TYPE_GRAPHICS_BINDING_OPENGL_WAYLAND_KHR};
    // #elif defined(XR_USE_PLATFORM_MACOS)
    // #error OpenGL bindings for Mac have not been implemented
    // #else
    // #error Platform not supported
    // #endif

    if (target.os.tag == .windows) {
        return xr.XrGraphicsBindingOpenGLWin32KHR;
    } else {
        unreachable;
    }
}

pub fn XR_FAILED(res: xr.XrResult) bool {
    return @as(c_int, @intCast(res)) < 0;
}

pub fn my_panic(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    @panic("OOM");
}

pub fn assert(val: bool) !void {
    if (!val) {
        return error.assert;
    }
}

pub fn getXrReferenceSpaceCreateInfo(referenceSpaceTypeStr: []const u8) !xr.XrReferenceSpaceCreateInfo {
    var referenceSpaceCreateInfo = xr.XrReferenceSpaceCreateInfo{
        .type = xr.XR_TYPE_REFERENCE_SPACE_CREATE_INFO,
        .poseInReferenceSpace = XrPosef_Identity(),
    };
    if (std.mem.eql(u8, referenceSpaceTypeStr, "View")) {
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_VIEW;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "ViewFront")) {
        // Render head-locked 2m in front of device.
        referenceSpaceCreateInfo.poseInReferenceSpace = XrPosef_Translation(.{ .x = 0, .y = 0, .z = -2 });
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_VIEW;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "Local")) {
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_LOCAL;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "Stage")) {
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageLeft")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = XrPosef_RotateCCWAboutYAxis(
            0,
            .{ .x = -2, .y = 0, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageRight")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = XrPosef_RotateCCWAboutYAxis(
            0,
            .{ .x = 2, .y = 0, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageLeftRotated")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = XrPosef_RotateCCWAboutYAxis(
            3.14 / 3.0,
            .{ .x = -2, .y = 0.5, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageRightRotated")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = XrPosef_RotateCCWAboutYAxis(
            -3.14 / 3.0,
            .{ .x = 2, .y = 0.5, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else {
        std.log.err("unknown_reference_space_type: {s}", .{referenceSpaceTypeStr});
        return error.unknown_reference_space_type;
    }
    return referenceSpaceCreateInfo;
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
