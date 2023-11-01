const builtin = @import("builtin");
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "BlueLearnsVulkanZig",
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
    // If we are on Linux, use the system library.
    // Most (if not all) linux gamers should already have glfw,
    // and using the system library makes it more likely to use the correct underlying API
    // since glfw doesn't choose between X11 and Wayland at run time, but instead at compile time.
    // TODO: When glfw supports dynamically using X11/Wayland, change to being linked into my application
    if (target.getOs().tag == .linux) {
        exe.linkSystemLibrary("glfw");
    } else if (target.getOs().tag == .windows) {
        exe.linkSystemLibrary2("gdi32", .{});
        exe.linkSystemLibrary2("user32", .{});
        exe.linkSystemLibrary2("shell32", .{});
        exe.linkSystemLibrary2("opengl32", .{});
        //exe.linkSystemLibrary2("GLESv3", .{}); // Unfortunately, zig does not have this included in its cross-compilation toolkit. Fortunately, it appears to be unnessesary.
        if (target.cpu_arch == .x86) {
            exe.linkSystemLibrary("win32");
            exe.addObjectFile(.{ .path = "lib/windows_x86/libglfw3.a" });
        } else if (target.cpu_arch == .x86_64) {
            exe.addObjectFile(.{ .path = "lib/windows_x86_64/libglfw3.a" });
        } else {
            // TODO: support windows ARM (I would have to either cross-compile glfw or set up a virtual machine to get the binaries)
            @panic("unsuported architecture (on windows at least)");
        }
    } else if (target.getOs().tag == .macos) {
        // NOTE: Macos build does not work, probably because apple is annoying and poopoo and doesn't like cross-compilation.
        // Transitive dependencies, explicit linkage of these works around
        // ziglang/zig#17130
        exe.linkFramework("CFNetwork");
        exe.linkFramework("ApplicationServices");
        exe.linkFramework("ColorSync");
        exe.linkFramework("CoreText");
        exe.linkFramework("ImageIO");

        // Direct dependencies
        exe.linkSystemLibrary2("objc", .{});
        exe.linkFramework("IOKit");
        exe.linkFramework("CoreFoundation");
        exe.linkFramework("AppKit");
        exe.linkFramework("CoreServices");
        exe.linkFramework("CoreGraphics");
        exe.linkFramework("Foundation");
        exe.linkFramework("OpenGL");
        if (target.cpu_arch == .x86_64) {
            exe.addObjectFile(.{ .path = "lib/macos_x86_64/libglfw3.a" });
        } else if (target.cpu_arch == .aarch64) {
            exe.addObjectFile(.{ .path = "/ib/macos_arm64/libglfw3.a" });
        } else {
            // TODO: I think it would be funny to support PowerPC mac (probably would need to get OpenGL support first)
            @panic("Unsuppoted architexture (for macos at least)");
        }
    }
    // If we are on windows or macos on the other hand, the library is statically linked.
    // for one those OSs have a bit of a DLL hell problem, (Linux does too but it has tons of good solutions)
    // but more importantly they are less likely to have GLFW already installed,
    // and they each only have one API so it doesn't even matter anyway.

    exe.linkSystemLibrary("c");

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
