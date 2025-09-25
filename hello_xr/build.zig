const std = @import("std");

const BUILD_NAME = "hello_xr";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable(.{
        .name = BUILD_NAME,
        .root_module = b.addModule(BUILD_NAME, .{
            .target = target,
        }),
    });
    b.installArtifact(exe);
    exe.addCSourceFiles(.{
        .files = &.{
            "d3d_common.cpp",
            "graphicsplugin_d3d11.cpp",
            "graphicsplugin_d3d12.cpp",
            "graphicsplugin_factory.cpp",
            "graphicsplugin_opengl.cpp",
            "graphicsplugin_opengles.cpp",
            "graphicsplugin_vulkan.cpp",
            "graphicsplugin_metal.cpp",
            "logger.cpp",
            "main.cpp",
            "openxr_program.cpp",
            "pch.cpp",
            "platformplugin_android.cpp",
            "platformplugin_factory.cpp",
            "platformplugin_posix.cpp",
            "platformplugin_win32.cpp",
            // XR_USE_GRAPHICS_API_OPENGL
            "external/glad2/src/gl.c",
            "external/glad2/src/wgl.c",
            // common
            "common/gfxwrapper_opengl.c",
        },
        .flags = &.{
            "-D_WIN32",
            "-DXR_USE_PLATFORM_WIN32",
            "-DXR_USE_GRAPHICS_API_OPENGL",
        },
    });
    exe.linkLibCpp();
    exe.addIncludePath(b.path(""));
    exe.addIncludePath(b.path("external/glad2/include"));

    const openxr_dep = b.dependency("openxr", .{});
    const openxr_prefix = openxr_dep.namedWriteFiles("prefix").getDirectory();
    exe.addIncludePath(openxr_prefix.path(b, "include"));

    exe.addLibraryPath(openxr_prefix.path(b, "lib"));
    exe.linkSystemLibrary("openxr_loader");
    exe.linkSystemLibrary("ole32");
    exe.linkSystemLibrary("opengl32");
    exe.linkSystemLibrary("gdi32");
}
