const Options = @import("Options.zig");
const xr = @import("openxr");

create_info: xr.XrInstanceCreateInfoAndroidKHR = .{},

pub fn init(_: Options, app: *xr.android_app) @This() {
    return .{
        .create_info = .{
            .type = xr.XR_TYPE_INSTANCE_CREATE_INFO_ANDROID_KHR,
            .next = null,
            .applicationVM = @ptrCast(app.activity.*.vm),
            .applicationActivity = @ptrCast(app.activity.*.clazz),
        },
    };
}

const INSTANCE_EXTENSIONS = [_][]const u8{
    xr.XR_KHR_ANDROID_CREATE_INSTANCE_EXTENSION_NAME,
};

pub fn getInstanceExtensions(_: @This()) []const []const u8 {
    return &INSTANCE_EXTENSIONS;
}

pub fn getInstanceCreateExtension(self: *@This()) ?*anyopaque {
    return &self.create_info;
}

pub fn updateOptions(_: @This(), _: *Options) void {}
