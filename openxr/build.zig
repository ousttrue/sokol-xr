const std = @import("std");

pub fn build(b: *std.Build) void {
    const openxr_dep = b.dependency("openxr", .{});
    const zigcross_dep = b.dependency("zig-cross", .{});

    //
    // configure
    //
    const cmake_configure = b.addSystemCommand(&.{ "cmake", "-G", "Ninja", "-S",  });
    cmake_configure.addDirectoryArg(openxr_dep.path(""));

    // -B
    cmake_configure.addArg("-B");
    const build_dir = cmake_configure.addOutputDirectoryArg("build");

    // --toolchain
    cmake_configure.addArg("--toolchain");
    cmake_configure.addFileArg(zigcross_dep.path("x86_64-windows-gnu.cmake"));

    cmake_configure.addArgs(&.{
        "-DDYNAMIC_LOADER=OFF",
        "-DCMAKE_POLICY_VERSION_MINIMUM=3.10",
        "-DCMAKE_POLICY_DEFAULT_CMP0148=OLD",
        "-DCMAKE_BUILD_TYPE=Release",
    });

    //
    // build
    //
    const cmake_build = b.addSystemCommand(&.{ "cmake", "--build" });
    cmake_build.addDirectoryArg(build_dir);
    cmake_build.step.dependOn(&cmake_configure.step);

    //
    // install
    //
    const cmake_install = b.addSystemCommand(&.{ "cmake", "--install" });
    cmake_install.addDirectoryArg(build_dir);
    cmake_install.step.dependOn(&cmake_build.step);

    // --prefix
    cmake_install.addArg("--prefix");
    const prefix_dir = cmake_install.addOutputDirectoryArg("prefix");

    const wf = b.addNamedWriteFiles("prefix");
    wf.step.dependOn(&cmake_install.step);
    _ = wf.addCopyDirectory(prefix_dir, "", .{});
}
