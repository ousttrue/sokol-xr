const std = @import("std");
const zcc = @import("compile_commands");

const zbk = @import("zbk");
// const zbk = @import("zbk_dev"); // from "../zbk"
const ndk = zbk.android.ndk;

const sokol = @import("sokol");

const BUILD_NAME = "hello_xr";
const PKG_NAME = "com.zig." ++ BUILD_NAME;
const API_LEVEL = 35;

pub fn build(b: *std.Build) !void {
    // compile_commands.json
    var targets = std.ArrayListUnmanaged(*std.Build.Step.Compile){};

    const target = b.standardTargetOptions(.{});
    std.debug.print("[build target] {s} ...\n", .{target.result.linuxTriple(b.allocator) catch @panic("OOM")});

    // x64_86-windows-gnu
    // aarch64-linux-android
    const optimize = b.standardOptimizeOption(.{});

    const compiled = if (target.result.abi.isAndroid())
        try build_android_so(b, target, optimize)
    else
        try build_exe(b, target, optimize);

    // xr_result
    const xr_result = b.addModule("xr_result", .{
        .root_source_file = b.path("xr_result.zig"),
    });
    compiled.root_module.addImport("xr_result", xr_result);

    // compile_commands.json
    targets.append(b.allocator, compiled) catch @panic("OOM");
    const step = zcc.createStep(b, "cdb", targets.toOwnedSlice(b.allocator) catch @panic("OOM"));
    step.dependOn(&compiled.step);
}

fn build_exe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = BUILD_NAME,
        .root_module = b.addModule(BUILD_NAME, .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("main.zig"),
            .link_libc = true,
        }),
    });
    b.installArtifact(exe);
    exe.addIncludePath(b.path(""));

    // openxr_loader
    const openxr_dep = b.dependency("openxr", .{});
    const vcenv = try zbk.windows.VcEnv.init(b.allocator);
    const openxr_loader = try zbk.cpp.cmake.build(b, .{
        .source = openxr_dep.path(""),
        .build_dir_name = "build-win32",
        .envmap = vcenv.envmap,
        .args = &.{"-DDYNAMIC_LOADER=ON"},
    });
    exe.addLibraryPath(openxr_loader.prefix.getDirectory().path(b, "lib"));
    exe.linkSystemLibrary("openxr_loader");
    // copy dll
    const dll = b.addInstallBinFile(
        openxr_loader.prefix.getDirectory().path(b, "bin/openxr_loader.dll"),
        "openxr_loader.dll",
    );
    b.getInstallStep().dependOn(&dll.step);

    // translate-c
    const t = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("xr_win32.h"),
    });
    t.addIncludePath(openxr_dep.path("include"));
    const openxr_mod = t.createModule();
    exe.root_module.addImport("openxr", openxr_mod);
    exe.addIncludePath(openxr_dep.path("include"));

    // glad
    exe.addIncludePath(b.path("external/glad2/include"));
    exe.addCSourceFiles(.{
        .files = &.{
            "external/glad2/src/gl.c",
            "external/glad2/src/wgl.c",
            "common/gfxwrapper_opengl.c",
            "graphicsplugin_d3d11.cpp",
            "d3d_common.cpp",
        },
        .flags = &.{
            "-D_WIN32",
            "-DXR_USE_PLATFORM_WIN32",
            "-DXR_USE_GRAPHICS_API_OPENGL",
            "-DXR_USE_GRAPHICS_API_D3D11",
        },
    });
    exe.linkLibCpp();

    // windows
    exe.linkSystemLibrary("ole32");
    exe.linkSystemLibrary("opengl32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("d3d11");
    exe.linkSystemLibrary("dxgi");

    // d3d msvc
    exe.addLibraryPath(.{
        .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Lib/10.0.26100.0/um/x64",
    });
    exe.linkSystemLibrary("d3dcompiler");

    // d3d graphicsplugin_d3d11.cpp dependency
    const directxmath_dep = b.dependency("DirectXMath", .{});
    exe.addIncludePath(directxmath_dep.path("Inc"));

    // sokol
    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .gl = true,
    });
    const sokol_mod = sokol_dep.module("sokol");
    exe.root_module.addImport("sokol", sokol_mod);
    const shdc_dep = sokol_dep.builder.dependency("shdc", .{});
    const shd_mod = try sokol.shdc.createModule(b, "shader", sokol_mod, .{
        .shdc_dep = shdc_dep,
        .input = "cube.glsl",
        .output = "shader.zig",
        .slang = .{
            .glsl430 = true,
        },
    });
    exe.root_module.addImport("shd", shd_mod);

    return exe;
}

fn build_android_so(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Step.Compile {
    const android_home = zbk.getEnvPath(b.allocator, "ANDROID_HOME") orelse {
        return error.no_android_home;
    };
    const ndk_path = try ndk.getPath(b, .{ .android_home = android_home });

    const lib = b.addLibrary(.{
        .name = BUILD_NAME,
        .root_module = b.addModule(BUILD_NAME, .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("android_main.zig"),
        }),
        .linkage = .dynamic,
    });
    b.installArtifact(lib);
    lib.addIncludePath(b.path(""));

    // openxr_loader
    const openxr_dep = b.dependency("openxr", .{});
    const openxr_loader = try zbk.cpp.cmake.build(b, .{
        .source = openxr_dep.path(""),
        .build_dir_name = "build-android",
        .ndk_path = ndk_path,
        .args = &.{"-DDYNAMIC_LOADER=ON"},
    });
    lib.addLibraryPath(openxr_loader.prefix.getDirectory().path(b, "lib"));
    lib.linkSystemLibrary("openxr_loader");

    // translate-c
    const t = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("xr_android.h"),
    });
    t.addIncludePath(openxr_dep.path("include"));
    const openxr_mod = t.createModule();
    lib.root_module.addImport("openxr", openxr_mod);
    lib.addIncludePath(openxr_dep.path("include"));

    // sokol
    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        // same as building sokol-zig with -Dgl=true
        .gles3 = true,
    });
    const sokol_mod = sokol_dep.module("sokol");
    lib.root_module.addImport("sokol", sokol_mod);

    const shdc_dep = sokol_dep.builder.dependency("shdc", .{});
    // call shdc.createModule() helper function, this returns a `!*Build.Module`:
    const shd_mod = try sokol.shdc.createModule(b, "shader", sokol_mod, .{
        .shdc_dep = shdc_dep,
        .input = "cube.glsl",
        .output = "shader.zig",
        .slang = .{
            .glsl310es = true,
        },
    });
    lib.root_module.addImport("shd", shd_mod);

    const libc_file = try ndk.LibCFile.make(b, ndk_path, target, API_LEVEL);
    // for compile
    lib.addSystemIncludePath(.{ .cwd_relative = libc_file.include_dir });
    lib.addSystemIncludePath(.{ .cwd_relative = libc_file.sys_include_dir });
    // for link
    lib.setLibCFile(libc_file.path);
    lib.addLibraryPath(.{ .cwd_relative = libc_file.crt_dir });

    t.addSystemIncludePath(.{ .cwd_relative = libc_file.include_dir });
    t.addSystemIncludePath(.{ .cwd_relative = libc_file.sys_include_dir });

    lib.linkSystemLibrary("android");
    lib.linkSystemLibrary("log");

    lib.linkSystemLibrary("EGL");
    lib.linkSystemLibrary("GLESv1_CM");
    lib.linkSystemLibrary("GLESv2");
    lib.linkSystemLibrary("GLESv3");

    // sokol use ndk
    const sokol_clib = sokol_dep.artifact("sokol_clib");
    sokol_clib.addSystemIncludePath(.{ .cwd_relative = libc_file.include_dir });
    sokol_clib.addSystemIncludePath(.{ .cwd_relative = libc_file.sys_include_dir });
    sokol_clib.setLibCFile(libc_file.path);
    sokol_clib.addLibraryPath(.{ .cwd_relative = libc_file.crt_dir });

    // native_app_glue (android_main dependency)
    t.addIncludePath(.{ .cwd_relative = b.fmt("{s}/sources/android/native_app_glue", .{ndk_path}) });
    openxr_mod.addIncludePath(.{ .cwd_relative = b.fmt("{s}/sources/android/native_app_glue", .{ndk_path}) });
    lib.addCSourceFile(.{ .file = .{ .cwd_relative = b.fmt(
        "{s}/sources/android/native_app_glue/android_native_app_glue.c",
        .{ndk_path},
    ) } });
    lib.addCSourceFile(.{ .file = b.path("cpp_helper.cpp") });
    lib.addIncludePath(.{ .cwd_relative = b.fmt("{s}/sources/android/native_app_glue", .{ndk_path}) });

    // android sdk
    const java_home = zbk.getEnvPath(b.allocator, "JAVA_HOME") orelse {
        return error.no_java_home;
    };
    const apk_builder = try zbk.android.ApkBuilder.init(b, .{
        .android_home = android_home,
        .java_home = java_home,
        .api_level = API_LEVEL,
    });

    const keystore_password = "example_password";
    const keystore = apk_builder.jdk.makeKeystore(b, keystore_password);

    // make apk from
    const apk = apk_builder.makeApk(b, .{
        .android_manifest = b.path("AndroidManifest.xml"),
        .keystore_password = keystore_password,
        .keystore_file = keystore.output,
        .resource_dir = b.path("android_resources"),
        .copy_list = &.{
            .{
                .src = lib.getEmittedBin(),
                .dst = "lib/arm64-v8a/libmain.so",
            },
            .{
                .src = openxr_loader.prefix.getDirectory().path(b, "lib/libopenxr_loader.so"),
                .dst = "lib/arm64-v8a/libopenxr_loader.so",
            },
        },
    });
    const install = b.addInstallFile(apk, "bin/hello_xr.apk");
    b.getInstallStep().dependOn(&install.step);

    const run_step = b.step("run", "Install and run the application on an Android device");
    const adb_install = apk_builder.platform_tools.adb_install(b, install.source);
    const adb_start = apk_builder.platform_tools.adb_start(b, .{ .package_name = PKG_NAME });
    adb_start.step.dependOn(&adb_install.step);
    run_step.dependOn(&adb_start.step);

    return lib;
}
