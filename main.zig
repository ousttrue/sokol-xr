// Copyright (c) 2017-2025 The Khronos Group Inc.
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const Options = @import("Options.zig");
const PlatformPlugin = @import("PlatformPluginWin32.zig");
const GraphicsPluginOpengl = @import("GraphicsPluginOpengl.zig");
const GraphicsPluginD3D11 = @import("GraphicsPluginD3D11.zig");
const OpenXrProgram = @import("OpenXrProgram.zig");
const xr_util = @import("xr_util.zig");
const xr_result = @import("xr_result.zig");

pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .debug,
};

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = if (scope == .default) "" else "(" ++ @tagName(scope) ++ "): ";

    var buf = std.io.FixedBufferStream([4 * 1024]u8){
        .buffer = undefined,
        .pos = 0,
    };
    var writer = buf.writer();
    writer.print(prefix ++ format, args) catch {};

    if (buf.pos >= buf.buffer.len) {
        buf.pos = buf.buffer.len - 1;
    }
    buf.buffer[buf.pos] = 0;

    const CSI = "\x1B[";
    const begin = switch (message_level) {
        .debug => CSI ++ "37m",
        .info => CSI ++ "33m",
        .warn => CSI ++ "35m",
        .err => CSI ++ "31m",
    };

    std.debug.print("{s}{s}{s}0m\n", .{ begin, &buf.buffer, CSI });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    // Parse command-line arguments into Options.
    var options = try Options.init(std.os.argv.len, std.os.argv.ptr);

    // Spawn a thread to wait for a keypress
    const KeyPolling = struct {
        quitKeyPressed: bool = false,
        exitPollingThread: std.Thread = undefined,

        fn spawn(self: *@This()) !void {
            self.exitPollingThread = try std.Thread.spawn(.{}, launch, .{self});
            std.Thread.detach(self.exitPollingThread);
        }

        fn launch(self: *@This()) void {
            std.log.info("Press any key to shutdown...", .{});
            var buf: [128]u8 = undefined;
            var r = std.fs.File.stdin().reader(&buf);
            var tmp: [1]u8 = undefined;
            _ = r.read(&tmp) catch 0;
            self.quitKeyPressed = true;
        }
    };
    var key_polling = KeyPolling{};
    try key_polling.spawn();

    var requestRestart = true;
    while (!key_polling.quitKeyPressed and requestRestart) {
        requestRestart = false;

        // Create platform-specific implementation.
        var platformPlugin = PlatformPlugin.init(options);

        // Create graphics API implementation.
        var graphicsPlugin = switch (options.GraphicsPlugin) {
            .D3D11 => try GraphicsPluginD3D11.init(allocator),
            .OpenGL => try GraphicsPluginOpengl.init(allocator),
            else => @panic("not impl"),
        };
        defer graphicsPlugin.deinit();

        // Initialize the OpenXR program.
        var program = OpenXrProgram.init(allocator, options, graphicsPlugin);
        defer program.deinit();

        try program.createInstance(
            platformPlugin.getInstanceExtensions(),
            platformPlugin.getInstanceCreateExtension(),
        );

        program.initializeSystem() catch |e| {
            switch (e) {
                xr_result.Error.XR_ERROR_FORM_FACTOR_UNAVAILABLE => {
                    std.log.warn("{s}: VR DEVICE not ready", .{@errorName(e)});
                    return;
                },
                else => {
                    return e;
                },
            }
        };

        try options.setEnvironmentBlendMode(try program.getPreferredBlendMode());

        platformPlugin.updateOptions(&options);

        try program.initializeDevice();
        try program.initializeSession();
        try program.createSwapchains();

        while (!key_polling.quitKeyPressed) {
            var exitRenderLoop = false;
            try program.pollEvents(&exitRenderLoop, &requestRestart);
            if (exitRenderLoop) {
                break;
            }

            if (program.sessionRunning) {
                // program.pollActions();
                try program.renderFrame();
            } else {
                // Throttle loop since xrWaitFrame won't be called.
                std.Thread.sleep(std.time.ns_per_ms * 250);
            }
        }
    }
}
