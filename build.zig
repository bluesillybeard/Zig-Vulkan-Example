const builtin = @import("builtin");
const std = @import("std");
const glfwBuild = @import("glfw/build.zig");


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
