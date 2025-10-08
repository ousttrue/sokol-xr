const Options = @import("Options.zig");
const xr = @import("openxr");

pub fn init(_: Options) @This() {
    return .{};
}

pub fn getInstanceExtensions(_: @This()) []const []const u8 {
    return &.{};
}

pub fn getInstanceCreateExtension(_: @This()) ?*xr.XrBaseInStructure {
    return null;
}

pub fn updateOptions(_: @This(), _: *Options) void {}
