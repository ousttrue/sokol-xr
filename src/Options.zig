const std = @import("std");
const builtin = @import("builtin");
const c = @import("xr_util.zig").c;
const xr = @import("openxr");

pub const GraphicsPluginType = enum {
    D3D11,
    D3D12,
    OpenGLES,
    OpenGL,
    Vulkan2,
    Vulkan,
    Metal,

    pub fn fromStr(s: []const u8) ?@This() {
        inline for (@typeInfo(@This()).@"enum".fields) |f| {
            if (std.mem.eql(u8, f.name, s)) {
                return @as(@This(), @enumFromInt(f.value));
            }
        }
        return null;
    }
};

GraphicsPlugin: GraphicsPluginType = if (builtin.target.os.tag == .windows)
    .D3D11
else if (builtin.target.abi.isAndroid())
    .OpenGLES
else
    .OpenGL,
FormFactor: []const u8 = "Hmd",
ViewConfiguration: []const u8 = "Stereo",
EnvironmentBlendMode: []const u8 = "Opaque",
AppSpace: []const u8 = "Local",

Parsed: struct {
    FormFactor: xr.XrFormFactor = xr.XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY,
    ViewConfigType: xr.XrViewConfigurationType = xr.XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,
    EnvironmentBlendMode: xr.XrEnvironmentBlendMode = xr.XR_ENVIRONMENT_BLEND_MODE_OPAQUE,
} = .{},

pub fn init(argc: usize, argv: [*][*:0]u8) !@This() {
    const NextArg = struct {
        // Index 0 is the program name and is skipped.
        i: usize = 1,
        argc: usize,
        argv: [*][*:0]u8,

        fn get(self: *@This()) ![]const u8 {
            if (self.i >= self.argc) {
                return error.argument_parameter_missing;
            }
            defer self.i += 1;
            return std.mem.sliceTo(self.argv[self.i], 0);
        }
    };
    var nextArg = NextArg{
        .argc = argc,
        .argv = argv,
    };

    var options = @This(){};
    while (nextArg.i < nextArg.argc) {
        const arg = try nextArg.get();
        if (std.mem.eql(u8, arg, "--graphics") or std.mem.eql(u8, arg, "-g")) {
            if (GraphicsPluginType.fromStr(try nextArg.get())) |graphics_type| {
                options.GraphicsPlugin = graphics_type;
            }
        } else if (std.mem.eql(u8, arg, "--formfactor") or std.mem.eql(u8, arg, "-ff")) {
            options.FormFactor = try nextArg.get();
        } else if (std.mem.eql(u8, arg, "--viewconfig") or std.mem.eql(u8, arg, "-vc")) {
            options.ViewConfiguration = try nextArg.get();
        } else if (std.mem.eql(u8, arg, "--blendmode") or std.mem.eql(u8, arg, "-bm")) {
            options.EnvironmentBlendMode = try nextArg.get();
        } else if (std.mem.eql(u8, arg, "--space") or std.mem.eql(u8, arg, "-s")) {
            options.AppSpace = try nextArg.get();
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            // Log::SetLevel(Log::Level::Verbose);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            // showHelp();
            return error.help;
        } else {
            return error.unknown_argument;
        }
    }

    try options.parseStrings();

    return options;
}

pub fn parseStrings(options: *@This()) !void {
    options.Parsed.FormFactor = try getXrFormFactor(options.FormFactor);
    options.Parsed.ViewConfigType = try getXrViewConfigurationType(options.ViewConfiguration);
    options.Parsed.EnvironmentBlendMode = try getXrEnvironmentBlendMode(options.EnvironmentBlendMode);
}

fn getXrEnvironmentBlendMode(environmentBlendModeStr: []const u8) !xr.XrEnvironmentBlendMode {
    if (std.mem.eql(u8, environmentBlendModeStr, "Opaque")) {
        return xr.XR_ENVIRONMENT_BLEND_MODE_OPAQUE;
    }
    if (std.mem.eql(u8, environmentBlendModeStr, "Additive")) {
        return xr.XR_ENVIRONMENT_BLEND_MODE_ADDITIVE;
    }
    if (std.mem.eql(u8, environmentBlendModeStr, "AlphaBlend")) {
        return xr.XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND;
    }
    return error.unknown_environment_blend_mode; // '%s'", environmentBlendModeStr.c_str()));
}

fn getXrViewConfigurationType(viewConfigurationStr: []const u8) !xr.XrViewConfigurationType {
    if (std.mem.eql(u8, viewConfigurationStr, "Mono")) {
        return xr.XR_VIEW_CONFIGURATION_TYPE_PRIMARY_MONO;
    }
    if (std.mem.eql(u8, viewConfigurationStr, "Stereo")) {
        return xr.XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
    }
    return error.unknown_view_configuration; // '%s'", viewConfigurationStr.c_str()));
}

fn getXrFormFactor(formFactorStr: []const u8) !xr.XrFormFactor {
    if (std.mem.eql(u8, formFactorStr, "Hmd")) {
        return xr.XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
    }
    if (std.mem.eql(u8, formFactorStr, "Handheld")) {
        return xr.XR_FORM_FACTOR_HANDHELD_DISPLAY;
    }
    return error.unknown_form_factor; // '%s'", formFactorStr.c_str()));
}

fn showHelp() void {
    // TODO: Improve/update when things are more settled.
    std.log.info("HelloXr --graphics|-g <Graphics API> [--formfactor|-ff <Form factor>] [--viewconfig|-vc <View config>] [--blendmode|-bm <Blend mode>] [--space|-s <Space>] [--verbose|-v]", .{});
    std.log.info("Graphics APIs:            D3D11, D3D12, OpenGLES, OpenGL, Vulkan2, Vulkan, Metal", .{});
    std.log.info("Form factors:             Hmd, Handheld", .{});
    std.log.info("View configurations:      Mono, Stereo", .{});
    std.log.info("Environment blend modes:  Opaque, Additive, AlphaBlend", .{});
    std.log.info("Spaces:                   View, Local, Stage", .{});
}

fn getXrEnvironmentBlendModeStr(environmentBlendMode: xr.XrEnvironmentBlendMode) ![]const u8 {
    return switch (environmentBlendMode) {
        xr.XR_ENVIRONMENT_BLEND_MODE_OPAQUE => "Opaque",
        xr.XR_ENVIRONMENT_BLEND_MODE_ADDITIVE => "Additive",
        xr.XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND => "AlphaBlend",
        else => error.unknown_environment_blend_mode, // '%s'", to_string(environmentBlendMode)));
    };
}

pub fn setEnvironmentBlendMode(self: *@This(), environmentBlendMode: xr.XrEnvironmentBlendMode) !void {
    self.EnvironmentBlendMode = try getXrEnvironmentBlendModeStr(environmentBlendMode);
    self.Parsed.EnvironmentBlendMode = environmentBlendMode;
}

const SlateGrey: [4]f32 = .{ 0.184313729, 0.309803933, 0.309803933, 1.0 };
const TransparentBlack: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 };
const Black: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 };

pub fn getBackgroundClearColor(self: @This()) [4]f32 {
    return switch (self.Parsed.EnvironmentBlendMode) {
        xr.XR_ENVIRONMENT_BLEND_MODE_OPAQUE => SlateGrey,
        xr.XR_ENVIRONMENT_BLEND_MODE_ADDITIVE => Black,
        xr.XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND => TransparentBlack,
        else => SlateGrey,
    };
}
