const glfw = @import("zglfw");
const std = @import("std");
const cglm = @import("cglm.zig").cglm;
const vulkan = @import("vulkan.zig");
const vk = @import("vk.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var allocatorObj = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 10 }){};
    defer _ = allocatorObj.deinit();
    var allocator = allocatorObj.allocator();

    try glfw.init();
    defer glfw.terminate();

    // Unlike with C++, I need to load the proc addresses myself for some reason.
    vulkan.loadBaseProcs();

    printVulkanDebugInformation(stdout, allocator);

    var window: *glfw.Window = try glfw.createWindow(800, 640, "Hello World", null, null);

    while (!glfw.windowShouldClose(window)) {
        if (glfw.getKey(window, glfw.KeyEscape) == glfw.Press) {
            glfw.setWindowShouldClose(window, true);
        }

        glfw.pollEvents();
    }
}

/// Prints a bunch of debug information (Mostly versions) about GLFW and Vulkan, to made debugging in release easier. (for excample, a player's PC doesn't support a required extension)
fn printVulkanDebugInformation(stdout: anytype, allocator: std.mem.Allocator) void {
    {
        var glfwVersionMajor: i32 = 0;
        var glfwVersionMinor: i32 = 0;
        var glfwVersionRev: i32 = 0;
        glfw.getVersion(&glfwVersionMajor, &glfwVersionMinor, &glfwVersionRev);
        std.debug.print("\nGLFW {}.{}.{}\n", .{ glfwVersionMajor, glfwVersionMinor, glfwVersionRev });
    }
    {
        const vkVersion = vulkan.Base.enumerateInstanceVersion() catch @panic("Couldn't get Vulkan version!");
        const vkVersionMajor = vk.apiVersionMajor(vkVersion);
        const vkVersionMinor = vk.apiVersionMinor(vkVersion);
        const vkVersionPatch = vk.apiVersionPatch(vkVersion);
        const vkVersionVariant = vk.apiVersionVariant(vkVersion);
        stdout.print("Vulkan {}.{}.{} Variant {}\n", .{ vkVersionMajor, vkVersionMinor, vkVersionPatch, vkVersionVariant }) catch @panic("Couldn't get Vulkan version");
    }
    {
        var extensionCount: u32 = undefined;
        _ = vulkan.Base.enumerateInstanceExtensionProperties(null, &extensionCount, null) catch @panic("Couldn't get Vulkan extensions!");
        var extensions = allocator.alloc(vk.ExtensionProperties, extensionCount) catch @panic("Allocation Failed");
        defer allocator.free(extensions);
        _ = vulkan.Base.enumerateInstanceExtensionProperties(null, &extensionCount, extensions.ptr) catch unreachable;
        stdout.print("Enabled Vulkan extensions:\n", .{}) catch unreachable;
        for (extensions) |extension| {
            stdout.print("\t{s}: {}\n", .{ extension.extension_name, extension.spec_version }) catch unreachable;
        }
    }
    {
        var glfwRequiredExtensionsCount: u32 = undefined;
        var glfwRequiredExtensions: []const [*:0]const u8 = undefined;
        glfwRequiredExtensions.ptr = glfw.getRequiredInstanceExtensions(&glfwRequiredExtensionsCount).?;
        glfwRequiredExtensions.len = glfwRequiredExtensionsCount;
        stdout.print("GLFW required Vulkan extensions:\n", .{}) catch unreachable;
        for (glfwRequiredExtensions) |extension| {
            stdout.print("\t{s}\n", .{extension}) catch unreachable;
        }
    }
    {
        var extensionCount: usize = 0;
        vulkan.Extensions.enumerateExtensions(vulkan.possibleRequiredExtensions, null, &extensionCount);
        var extensions = allocator.alloc([]const u8, extensionCount) catch unreachable;
        defer allocator.free(extensions);
        vulkan.Extensions.enumerateExtensions(vulkan.possibleRequiredExtensions, extensions.ptr, &extensionCount);
        stdout.print("Vulkan extensions that might be required by the application:\n", .{}) catch unreachable;
        for(extensions) |extension| {
            stdout.print("\t{s}\n", .{extension}) catch unreachable;
        }
    }
}
