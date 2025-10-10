// Copyright (c) 2017-2025 The Khronos Group Inc.
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const Options = @import("Options.zig");
const PlatformPlugin = @import("PlatformPluginWin32.zig");
const GraphicsPluginOpengl = @import("GraphicsPluginOpengl.zig");
const GraphicsPluginD3D11 = @import("GraphicsPluginD3D11.zig");
const GraphicsPluginSokol = @import("GraphicsPluginSokol.zig");
const OpenXrProgram = @import("OpenXrProgram.zig");
const xr_util = @import("xr_util.zig");
const xr_result = @import("xr_result.zig");
const xr = @import("openxr");
const Scene = @import("Scene.zig");

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
            .Sokol => try GraphicsPluginSokol.init(allocator),
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

        var scene = try Scene.init(allocator, program.session);
        defer scene.deinit();

        var projectionLayerViews = std.array_list.Managed(xr.XrCompositionLayerProjectionView).init(allocator);
        defer projectionLayerViews.deinit();

        while (!key_polling.quitKeyPressed) {
            var exitRenderLoop = false;
            try program.pollEvents(&exitRenderLoop, &requestRestart);
            if (exitRenderLoop) {
                break;
            }

            if (program.sessionRunning) {
                // program.pollActions();
                const frame_state = try program.beginFrame();
                try projectionLayerViews.resize(0);
                if (frame_state.shouldRender == xr.XR_TRUE) {
                    //
                    const view_state = try program.locateView(frame_state.predictedDisplayTime);
                    if ((view_state.viewStateFlags & xr.XR_VIEW_STATE_POSITION_VALID_BIT) != 0 and
                        (view_state.viewStateFlags & xr.XR_VIEW_STATE_ORIENTATION_VALID_BIT) != 0)
                    {
                        // render
                        // try xr_util.assert(viewCountOutput == self.views.items.len);
                        // try xr_util.assert(viewCountOutput == self.configViews.items.len);
                        // try xr_util.assert(viewCountOutput == self.swapchains.items.len);
                        const cubes = try scene.update(
                            program.appSpace,
                            &program.input,
                            frame_state.predictedDisplayTime,
                        );

                        // views = try program.renderFrame(cubes);
                        try projectionLayerViews.resize(2);

                        // Render view to the appropriate part of the swapchain image.
                        for (program.swapchains.items, 0..) |viewSwapchain, i| {
                            // Each view has a separate swapchain which is acquired, rendered to, and released.
                            var acquireInfo = xr.XrSwapchainImageAcquireInfo{
                                .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO,
                            };
                            var swapchainImageIndex: u32 = undefined;
                            try xr_result.check(xr.xrAcquireSwapchainImage(
                                viewSwapchain.handle,
                                &acquireInfo,
                                &swapchainImageIndex,
                            ));
                            var waitInfo = xr.XrSwapchainImageWaitInfo{
                                .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO,
                                .timeout = xr.XR_INFINITE_DURATION,
                            };
                            try xr_result.check(xr.xrWaitSwapchainImage(viewSwapchain.handle, &waitInfo));

                            projectionLayerViews.items[i] = .{
                                .type = xr.XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW,
                                .pose = program.views.items[i].pose,
                                .fov = program.views.items[i].fov,
                                .subImage = .{
                                    .swapchain = viewSwapchain.handle,
                                    .imageRect = .{
                                        .offset = .{ .x = 0, .y = 0 },
                                        .extent = .{
                                            .width = @intCast(viewSwapchain.width),
                                            .height = @intCast(viewSwapchain.height),
                                        },
                                    },
                                },
                            };

                            if (program.swapchainImageMap.get(viewSwapchain.handle)) |imageBuffers| {
                                const swapchainImage: *const xr.XrSwapchainImageBaseHeader = imageBuffers[swapchainImageIndex];
                                _ = program.graphics.renderView(
                                    &projectionLayerViews.items[i],
                                    swapchainImage,
                                    program.colorSwapchainFormat,
                                    cubes,
                                );

                                const releaseInfo = xr.XrSwapchainImageReleaseInfo{
                                    .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO,
                                };
                                try xr_result.check(xr.xrReleaseSwapchainImage(viewSwapchain.handle, &releaseInfo));
                            }
                        }
                    }
                }
                try program.endFrame(frame_state.predictedDisplayTime, projectionLayerViews.items);
            } else {
                // Throttle loop since xrWaitFrame won't be called.
                std.Thread.sleep(std.time.ns_per_ms * 250);
            }
        }
    }
}
