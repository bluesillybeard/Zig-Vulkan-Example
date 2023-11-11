const builtin = @import("builtin");
const std = @import("std");

// I am extremely annoyed with the build.zig.zon system because if a dependency has a problem there isn't an easy way to see which dependency it comes from.
// And, I can't just modify the code of that dependency to fix it, which is even more excruciatingly annoying.
// Just use blooming git submodules! They exist for a freaking reason!!
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ZigVulkanExample",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // Add cglm headers. cglm supports compiling to a static or shared library,
    // But thankfully all of its headers contain implementations so no extra compile steps are required.
    // The cglm headers are imported into a single zig file so the implementation isn't inlined and copied everywhere
    exe.installHeadersDirectory("cglm/include/cglm", "cglm");

    const zglfw = b.addModule("zglfw", .{ .source_file = .{ .path = "zglfw/src/main.zig" } });
    exe.addModule("zglfw", zglfw);

    linkGLFW(b, exe, target, optimize);
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

pub fn linkGLFW(b: *std.Build, exe: *std.Build.CompileStep, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) void {
    _ = optimize;
    exe.linkLibC();
    // Don't you just love linking precompiled binaries?
    // I had to do this since Mach's version of GLFW only compiles with zig 0.12,
    // but since I'm using 0.11 I can't do that, and in fact cross compilation to macos in 0.11 is completely unusable.
    // Once 0.12 becomes stable, I'll probably refactor glfw to be a submodule and ditch the precompiled binaries.
    var glfwLibPath = std.ArrayList(u8).initCapacity(b.allocator, 100) catch unreachable;
    glfwLibPath.appendSlice("lib/glfw/") catch unreachable;
    switch (target.getCpuArch()) {
        .x86_64 => {
            glfwLibPath.appendSlice("x86_64") catch unreachable;
        },
        .x86 => {
            glfwLibPath.appendSlice("x86") catch unreachable;
        },
        .aarch64 => {
            glfwLibPath.appendSlice("aarch64") catch unreachable;
        },
        .riscv64 => {
            glfwLibPath.appendSlice("riscv64") catch unreachable;
        },
        else => @panic("Unsupported architecture"),
    }
    glfwLibPath.append('-') catch unreachable;
    switch (target.getOsTag()) {
        .linux => {
            glfwLibPath.appendSlice("linux/lib/libglfw.a") catch unreachable;
        },
        .windows => {
            glfwLibPath.appendSlice("windows/lib/glfw.lib") catch unreachable;
        },
        .macos => {
            glfwLibPath.appendSlice("macos/lib/libglfw.a") catch unreachable;
        },
        else => @panic("Unsupported OS"),
    }
    const glfwLibPathStr = glfwLibPath.toOwnedSlice() catch unreachable;
    exe.addObjectFile(.{.path=glfwLibPathStr});
    
    // https://github.com/hexops/glfw/blob/master/build.zig made this part a lot easier
    switch(target.getOsTag()) {
        .linux => {
            // Apparently GLFW doesn't need to link with any libraries AT ALL!
            // ...I guess X11, wayland, Vulkan, etc are linked through some other fashon,
        },
        .windows => {
            exe.linkSystemLibrary2("gdi32", .{ .use_pkg_config = .no });
            exe.linkSystemLibrary2("user32", .{ .use_pkg_config = .no });
            exe.linkSystemLibrary2("shell32", .{ .use_pkg_config = .no });
            //exe.linkSystemLibrary2("opengl32", .{ .use_pkg_config = .no });
        },
        .macos => {
            //TODO: when 0.12 becomes stable, update and test cross-compilation, and fix these to make sure they work.
            // Transitive dependencies, explicit linkage of these works around
            // ziglang/zig#17130
            exe.linkFramework("CFNetwork");
            exe.linkFramework("ApplicationServices");
            exe.linkFramework("ColorSync");
            exe.linkFramework("CoreText");
            exe.linkFramework("ImageIO");
            // Direct dependencies
            exe.linkSystemLibrary2("objc", .{ .use_pkg_config = .no });
            exe.linkFramework("IOKit");
            exe.linkFramework("CoreFoundation");
            exe.linkFramework("AppKit");
            exe.linkFramework("CoreServices");
            exe.linkFramework("CoreGraphics");
            exe.linkFramework("Foundation");
            //exe.linkFramework("Metal");
            //exe.linkFramework("OpenGL");
        },
        else => @panic("Unsupported OS"),
    }
}