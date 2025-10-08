// Copyright (c) 2017-2025 The Khronos Group Inc.
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const Options = @import("Options.zig");
const PlatformPlugin = @import("PlatformPluginWin32.zig");
const GraphicsPlugin = @import("GraphicsPluginOpengl.zig");
const OpenXrProgram = @import("OpenXrProgram.zig");
const xr_util = @import("xr_util.zig");

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
        var graphicsPlugin = try GraphicsPlugin.init(allocator);
        defer graphicsPlugin.deinit();

        // Initialize the OpenXR program.
        var program = OpenXrProgram.init(allocator, options, graphicsPlugin);
        defer program.deinit();

        try program.createInstance(
            platformPlugin.getInstanceExtensions(),
            platformPlugin.getInstanceCreateExtension(),
        );
        try program.initializeSystem();

        try options.setEnvironmentBlendMode(try program.getPreferredBlendMode());

        platformPlugin.updateOptions(&options);

        if (!program.initializeDevice()) {
            xr_util.my_panic("initializeDevice", .{});
        }
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
