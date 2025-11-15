const std = @import("std");
// const c = @import("xr_util.zig").c;
const Options = @import("Options.zig");
const GraphicsPlugin = @import("GraphicsPluginOpenglES.zig");
const OpenXrProgram = @import("OpenXrProgram.zig");
const xr = @import("openxr").c;
const xr_util = @import("xr_util.zig");
const xr_result = @import("xr_result.zig");
const Egl = @import("Egl.zig");
const Scene = @import("Scene.zig");
const RendererGLES = @import("GraphicsRendererAndroidGLES.zig");
const RendererSokol = @import("GraphicsRendererSokol.zig");
const c = @import("c");

// https://ziggit.dev/t/set-debug-level-at-runtime/6196/3
pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .debug,
};

// https://github.com/vamolessa/zig-sdl-android-template/blob/master/src/android_main.zig
// make the std.log.<logger> functions write to the android log
pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const priority = switch (message_level) {
        .err => c.ANDROID_LOG_ERROR,
        .warn => c.ANDROID_LOG_WARN,
        .info => c.ANDROID_LOG_INFO,
        .debug => c.ANDROID_LOG_DEBUG,
    };
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

    _ = c.__android_log_write(priority, "ZIG", &buf.buffer);
}

fn updateOptionsFromSystemProperties(allocator: std.mem.Allocator) !Options {
    var options = Options{
        .GraphicsPlugin = .OpenGLES,
    };

    var value: [c.PROP_VALUE_MAX]c_char = undefined;
    if (c.__system_property_get("debug.xr.graphics_plugin", &value[0]) != 0) {
        // options.GraphicsPlugin = try allocator.dupe(u8, std.mem.sliceTo(&value, 0));
        if (Options.GraphicsPluginType.fromStr(&value)) |graphics_type| {
            options.GraphicsPlugin = graphics_type;
        }
    }

    if (c.__system_property_get("debug.xr.formFactor", &value[0]) != 0) {
        options.FormFactor = try allocator.dupe(u8, std.mem.sliceTo(&value, 0));
    }

    if (c.__system_property_get("debug.xr.viewConfiguration", &value[0]) != 0) {
        options.ViewConfiguration = try allocator.dupe(u8, std.mem.sliceTo(&value, 0));
    }

    if (c.__system_property_get("debug.xr.blendMode", &value[0]) != 0) {
        options.EnvironmentBlendMode = try allocator.dupe(u8, std.mem.sliceTo(&value, 0));
    }

    try options.parseStrings();

    return options;
}

const AndroidAppState = struct {
    NativeWindow: ?*c.ANativeWindow = null,
    Resumed: bool = false,
};

// Process the next main command.
export fn app_handle_cmd(app: [*c]c.android_app, cmd: i32) void {
    const appState: *AndroidAppState = @ptrCast(@alignCast(app.*.userData));
    switch (cmd) {
        // There is no APP_CMD_CREATE. The ANativeActivity creates the
        // application thread from onCreate(). The application thread
        // then calls android_main().
        c.APP_CMD_START => {
            std.log.info("    APP_CMD_START", .{});
            std.log.info("onStart()", .{});
        },
        c.APP_CMD_RESUME => {
            std.log.info("onResume()", .{});
            std.log.info("    APP_CMD_RESUME", .{});
            appState.Resumed = true;
        },
        c.APP_CMD_PAUSE => {
            std.log.info("onPause()", .{});
            std.log.info("    APP_CMD_PAUSE", .{});
            appState.Resumed = false;
        },
        c.APP_CMD_STOP => {
            std.log.info("onStop()", .{});
            std.log.info("    APP_CMD_STOP", .{});
        },
        c.APP_CMD_DESTROY => {
            std.log.info("onDestroy()", .{});
            std.log.info("    APP_CMD_DESTROY", .{});
            appState.NativeWindow = null;
        },
        c.APP_CMD_INIT_WINDOW => {
            std.log.info("surfaceCreated()", .{});
            std.log.info("    APP_CMD_INIT_WINDOW", .{});
            appState.NativeWindow = app.*.window;
        },
        c.APP_CMD_TERM_WINDOW => {
            std.log.info("surfaceDestroyed()", .{});
            std.log.info("    APP_CMD_TERM_WINDOW", .{});
            appState.NativeWindow = null;
        },
        else => {},
    }
}

// This is the main entry point of a native application that is using
// android_native_app_glue.  It runs in its own thread, with its own
// event loop for receiving input events and doing other things.
export fn android_main(app: *c.android_app) void {
    std.log.info("#### android_main ####", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    // JNIEnv* Env;
    // app.activity.vm.AttachCurrentThread(&Env, nullptr);

    var appState = AndroidAppState{};

    app.userData = &appState;
    app.onAppCmd = &app_handle_cmd;

    var options = updateOptionsFromSystemProperties(allocator) catch |e|
        {
            xr_util.my_panic("{s}", .{@errorName(e)});
        };

    const egl = Egl.init(
        .KS_GPU_SURFACE_COLOR_FORMAT_B8G8R8A8,
        .KS_GPU_SURFACE_DEPTH_FORMAT_D24,
        .KS_GPU_SAMPLE_COUNT_1,
    ) orelse {
        xr_util.my_panic("Egl.init", .{});
    };
    std.log.debug("Egl.init", .{});

    // Create graphics API implementation.
    const graphics_plugin = GraphicsPlugin.init(.{
        .allocator = allocator,
        .clear_color = options.getBackgroundClearColor(),
        .display = egl.display,
        .context = egl.context,
    }) catch {
        xr_util.my_panic("GraphicsPlugin", .{});
    };

    // Initialize the OpenXR program.
    var program = OpenXrProgram.init(allocator, options, graphics_plugin);
    defer program.deinit();

    // Initialize the loader for this platform
    var initializeLoader: c.PFN_xrInitializeLoaderKHR = null;
    const res = c.xrGetInstanceProcAddr(null, "xrInitializeLoaderKHR", &initializeLoader);
    if (res == c.XR_SUCCESS) {
        var loaderInitInfoAndroid = c.XrLoaderInitInfoAndroidKHR{
            .type = c.XR_TYPE_LOADER_INIT_INFO_ANDROID_KHR,
            .applicationVM = @ptrCast(app.*.activity.*.vm),
            .applicationContext = @ptrCast(app.*.activity.*.clazz),
        };
        _ = (initializeLoader.?)(@ptrCast(&loaderInitInfoAndroid));
    } else {
        xr_util.my_panic("xrInitializeLoaderKHR: {}", .{res});
    }
    std.log.debug("xrInitializeLoaderKHR", .{});

    const INSTANCE_EXTENSIONS = [_][]const u8{
        c.XR_KHR_ANDROID_CREATE_INSTANCE_EXTENSION_NAME,
    };
    var create_info: c.XrInstanceCreateInfoAndroidKHR = .{
        .type = c.XR_TYPE_INSTANCE_CREATE_INFO_ANDROID_KHR,
        .next = null,
        .applicationVM = @ptrCast(app.activity.*.vm),
        .applicationActivity = @ptrCast(app.activity.*.clazz),
    };
    program.createInstance(
        &(INSTANCE_EXTENSIONS ++ xr_util.REQUIRED_EXTENSIONS),
        @ptrCast(&create_info),
    ) catch {
        xr_util.my_panic("program.createInstance", .{});
    };
    program.initializeSystem() catch {
        xr_util.my_panic("initializeSystem", .{});
    };
    std.log.debug("program.initializeSystem", .{});

    if (program.getPreferredBlendMode()) |mode| {
        options.setEnvironmentBlendMode(mode) catch {
            xr_util.my_panic("setEnvironmentBlendMode", .{});
        };
    } else |_| {
        xr_util.my_panic("getPreferredBlendMode", .{});
    }
    std.log.debug("getPreferredBlendMode", .{});

    program.initializeDevice() catch {
        xr_util.my_panic("initializeDevice", .{});
    };
    program.initializeSession() catch {
        xr_util.my_panic("initializeSession", .{});
    };
    program.createSwapchains() catch {
        xr_util.my_panic("createSwapchains", .{});
    };

    var scene = Scene.init(allocator, program.instance, program.session) catch {
        xr_util.my_panic("Scene.init", .{});
    };
    defer scene.deinit();

    const referenceSpaceCreateInfo = Scene.getXrReferenceSpaceCreateInfo(options.AppSpace) catch {
        xr_util.my_panic("Scene.getXrReferenceSpaceCreateInfo", .{});
    };
    var space: xr.XrSpace = null;
    xr_result.check(xr.xrCreateReferenceSpace(program.session, &referenceSpaceCreateInfo, &space)) catch {
        xr_util.my_panic("xrCreateReferenceSpace", .{});
    };

    var renderer = RendererSokol.init(allocator) catch {
        xr_util.my_panic("Renderer.init", .{});
    };
    defer renderer.deinit();

    var projectionLayerViews = std.array_list.Managed(xr.XrCompositionLayerProjectionView).init(allocator);
    defer projectionLayerViews.deinit();

    std.log.debug("loop start...", .{});
    var requestRestart = false;
    var exitRenderLoop = false;
    while (app.destroyRequested == 0) {
        // Read all pending events.
        while (true) {
            var events: c_int = undefined;
            var _source: ?*anyopaque = null;
            // If the timeout is zero, returns immediately without blocking.
            // If the timeout is negative, waits indefinitely until an event appears.
            const timeoutMilliseconds: c_int =
                if (!appState.Resumed and !program.sessionRunning and app.destroyRequested == 0)
                    -1
                else
                    0;
            if (c.ALooper_pollAll(timeoutMilliseconds, null, &events, &_source) < 0) {
                break;
            }

            // Process this event.
            c.call_source_process(app, @ptrCast(@alignCast(_source)));
        }

        program.pollEvents(&exitRenderLoop, &requestRestart) catch {
            xr_util.my_panic("pollEvents", .{});
        };
        if (exitRenderLoop) {
            c.ANativeActivity_finish(app.activity);
            continue;
        }

        if (!program.sessionRunning) {
            // Throttle loop since xrWaitFrame won't be called.
            std.Thread.sleep(std.time.ns_per_ms * 250);
            continue;
        }

        // program.pollActions();
        // program.renderFrame() catch {
        //     xr_util.my_panic("renderFrame", .{});
        // };
        const frame_state = program.beginFrame() catch {
            xr_util.my_panic("program.beginFrame", .{});
        };
        projectionLayerViews.resize(0) catch @panic("OOM");
        if (frame_state.shouldRender == xr.XR_TRUE) {
            //
            const view_state = program.locateView(space, frame_state.predictedDisplayTime) catch {
                xr_util.my_panic("program.locateView", .{});
            };
            if ((view_state.viewStateFlags & xr.XR_VIEW_STATE_POSITION_VALID_BIT) != 0 and
                (view_state.viewStateFlags & xr.XR_VIEW_STATE_ORIENTATION_VALID_BIT) != 0)
            {
                // render
                // try xr_util.assert(viewCountOutput == self.views.items.len);
                // try xr_util.assert(viewCountOutput == self.configViews.items.len);
                // try xr_util.assert(viewCountOutput == self.swapchains.items.len);
                const cubes = scene.update(
                    space,
                    &program.input,
                    frame_state.predictedDisplayTime,
                ) catch @panic("OOM");

                projectionLayerViews.resize(2) catch @panic("OOM");

                // Render view to the appropriate part of the swapchain image.
                for (program.views.items, program.swapchains.items, 0..) |view, viewSwapchain, i| {
                    // Each view has a separate swapchain which is acquired, rendered to, and released.
                    var acquireInfo = xr.XrSwapchainImageAcquireInfo{
                        .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO,
                    };
                    var swapchainImageIndex: u32 = undefined;
                    if (xr_result.check(xr.xrAcquireSwapchainImage(
                        viewSwapchain.handle,
                        &acquireInfo,
                        &swapchainImageIndex,
                    ))) {
                        var waitInfo = xr.XrSwapchainImageWaitInfo{
                            .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO,
                            .timeout = xr.XR_INFINITE_DURATION,
                        };
                        if (xr_result.check(xr.xrWaitSwapchainImage(viewSwapchain.handle, &waitInfo))) {
                            // composition
                            projectionLayerViews.items[i] = .{
                                .type = xr.XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW,
                                .pose = view.pose,
                                .fov = view.fov,
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

                            // render
                            switch (program.graphics.getSwapchainImage(
                                viewSwapchain.handle,
                                swapchainImageIndex,
                            )) {
                                .OpenGLES => |image| renderer.render(
                                    image.image,
                                    @intCast(viewSwapchain.width),
                                    @intCast(viewSwapchain.height),
                                    .{ 0, 0, 0, 0 },
                                    program.graphics.calcViewProjectionMatrix(view.fov, view.pose),
                                    cubes,
                                ),
                            }

                            // commit
                            const releaseInfo = xr.XrSwapchainImageReleaseInfo{
                                .type = xr.XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO,
                            };
                            xr_result.check(xr.xrReleaseSwapchainImage(
                                viewSwapchain.handle,
                                &releaseInfo,
                            )) catch |e| {
                                std.log.err("xr.xrReleaseSwapchainImage: {s}", .{@errorName(e)});
                            };
                        } else |_| {}
                    } else |_| {}
                }
            }
        }
        program.endFrame(space, frame_state.predictedDisplayTime, projectionLayerViews.items, null) catch |e| {
            std.log.err("program.endFrame: {s}", .{@errorName(e)});
        };
    }

    // app.activity.vm.DetachCurrentThread();
}
