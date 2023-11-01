// This is a set of helper functions and stuff for interfacing with Vulkan.
const builtin = @import("builtin");
const glfw = @import("zglfw");
const vk = @import("vk.zig");
const std = @import("std");
// TODO: apparently some of these functions are optional for drivers to implement? look into it.
// TODO: There's also apparently a bunch of functions that were added in more recent versions that were previously only available through extensions.
// As such, those methods have two names: the legacy name for the extension, and the one for the addition into Vulkan itself.
// Instead of forcing Vulkan 1.3, check the extensions and load that instead if the base version is not available
// TODO: apparently there's no reason to bother using the old fallbacks though, so unless it shows up in a bug report or something it's probably fine.

// A list of all official Vulkan extensions can be found at https://registry.khronos.org/vulkan/
pub const possibleRequiredExtensions = Extensions.initPossibleRequired();

// use that list to build the wrappers

// BaseWrapper doesn't actually use any extensions
const BaseWrapper = vk.BaseWrapper(.{
    .createInstance = true,
    .enumerateInstanceExtensionProperties = true,
    .enumerateInstanceLayerProperties = true,
    .enumerateInstanceVersion = true,
    .getInstanceProcAddr = true,
});

const InstanceWrapperFuncs = createInstanceWrapperFlags(possibleRequiredExtensions);
const InstanceWrapper = vk.InstanceWrapper(InstanceWrapperFuncs);

const DeviceWrapperFuncs = createDeviceWrapperFlags(possibleRequiredExtensions);
const DeviceWrapper = vk.DeviceWrapper(DeviceWrapperFuncs);

fn loadInstaceProc(instance: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction {
    return glfw.getInstanceProcAddress(@as(usize, @intFromEnum(instance)), name);
}

// TODO figure out some way to remove extensions at runtime since loading functions for extensions that won't be used seems unnessesary.
pub var Base: BaseWrapper = undefined;
//Must be called before any vulkan functions
pub fn loadBaseProcs() void {
    Base = BaseWrapper.loadNoFail(loadInstaceProc);
}

pub var Instance: InstanceWrapper = undefined;
//Must be called before any vulkan instance functions
pub fn loadInstanceProcs(instance: vk.Instance) void {
    Instance = InstanceWrapper.loadNoFail(instance, loadInstaceProc);
}

pub var Device: DeviceWrapper = undefined;
//Must be called before any vulkan device functions
pub fn loadDeviceProcs(device: vk.Device) void {
    Device = DeviceWrapper.loadNoFail(device, Instance.getDeviceProcAddr);
}

/// NOTE: the name of each of this structs field is PRECISELY the same as the actual field name.
pub const Extensions = struct {
    const This = @This();
    const numTotalExtensions = @typeInfo(This).Struct.fields.len;
    
    // required for debug callbacks
    VK_EXT_debug_utils: bool = false,
    // required for hopefully obvious reasons
    VK_KHR_swapchain: bool = false,
    VK_KHR_surface: bool = false,
    // requried for Linux (to support both X11 and Wayland)
    VK_KHR_xcb_surface: bool = false,
    VK_KHR_wayland_surface: bool = false,
    // required for Windows
    VK_KHR_win32_surface: bool = false,
    // required for Macos
    VK_EXT_metal_surface: bool = false,
    VK_MVK_macos_surface: bool = false, //NOTE: this is deprecated, check GLFW for its removal. As of GLFW 3.3.8, it is still present.

    pub fn initPossibleRequired() Extensions {
        var res = Extensions{
            .VK_EXT_debug_utils = builtin.mode == std.builtin.Mode.Debug,
            .VK_KHR_surface = true,
            .VK_KHR_swapchain = true,
        };
        switch (builtin.target.os.tag) {
            .linux => {
                res.VK_KHR_xcb_surface = true;
                res.VK_KHR_wayland_surface = true;
            },
            .windows => {
                res.VK_KHR_win32_surface = true;
            },
            .macos => {
                res.VK_EXT_metal_surface = true;
                res.VK_MVK_macos_surface = true;
            },
            else => @compileError("Unsupported OS"),
        }
        if(builtin.mode == std.builtin.OptimizeMode.Debug){
            res.VK_EXT_debug_utils = true;
        }
        return res;
    }

    pub fn enumerateExtensions(self: Extensions, output: ?[*][]const u8, outputNum: *usize) void{
        outputNum.* = 0;
        inline for(@typeInfo(This).Struct.fields) |field| {
            const extensionEnabled = @field(self, field.name);
            if(field.type != bool)continue;
            if(extensionEnabled) {
                //IMPORTANT: This only works because the field name is EXACTLY identical to the extension name
                if(output != null)output.?[outputNum.*] = field.name;
                outputNum.*+=1;
            }
        }
    }
};


fn createInstanceWrapperFlags(extensions: Extensions) vk.InstanceCommandFlags {
    var flags = vk.InstanceCommandFlags {
        .destroyInstance = true,
        .enumeratePhysicalDevices = true,
        .getDeviceProcAddr = true,
        .getPhysicalDeviceProperties = true,
        .getPhysicalDeviceQueueFamilyProperties = true,
        .getPhysicalDeviceMemoryProperties = true,
        .getPhysicalDeviceFeatures = true,
        .getPhysicalDeviceFormatProperties = true,
        .getPhysicalDeviceImageFormatProperties = true,
        .createDevice = true,
        .enumerateDeviceLayerProperties = true,
        .enumerateDeviceExtensionProperties = true,
        .getPhysicalDeviceSparseImageFormatProperties = true,
        .getPhysicalDeviceFeatures2 = true,
        .getPhysicalDeviceProperties2 = true,
        .getPhysicalDeviceFormatProperties2 = true,
        .getPhysicalDeviceImageFormatProperties2 = true,
        .getPhysicalDeviceQueueFamilyProperties2 = true,
        .getPhysicalDeviceMemoryProperties2 = true,
        .getPhysicalDeviceSparseImageFormatProperties2 = true,
        .getPhysicalDeviceExternalBufferProperties = true,
        .getPhysicalDeviceExternalSemaphoreProperties = true,
        .getPhysicalDeviceExternalFenceProperties = true,
        .enumeratePhysicalDeviceGroups = true,
        .getPhysicalDeviceToolProperties = true,
    };

    if(extensions.VK_KHR_surface){
        flags.destroySurfaceKHR = true;
        // idk what these are doing in the instance flags but whatever I guess
        flags.getPhysicalDeviceSurfaceCapabilitiesKHR = true;
        flags.getPhysicalDeviceSurfaceFormatsKHR = true;
        flags.getPhysicalDeviceSurfacePresentModesKHR = true;
        flags.getPhysicalDeviceSurfaceSupportKHR = true;
    }
    
    if(extensions.VK_KHR_swapchain){
        // NOTE: This is incompatible with vulkan 1.0 (which is probably a non-issue)
        flags.getPhysicalDevicePresentRectanglesKHR = true;
    }

    if(extensions.VK_KHR_xcb_surface){
        flags.createXcbSurfaceKHR = true;
        flags.getPhysicalDeviceXcbPresentationSupportKHR = true;
    }

    if(extensions.VK_KHR_wayland_surface){
        flags.createWaylandSurfaceKHR = true;
        flags.getPhysicalDeviceWaylandPresentationSupportKHR = true;
    }

    if(extensions.VK_KHR_win32_surface){
        flags.createWin32SurfaceKHR = true;
        flags.getPhysicalDeviceWin32PresentationSupportKHR = true;
    }
    
    // TODO: Look into what this is, because creating a surface for another rendering API seems a bit odd.
    // It might be related to MoltenVK but i'm not sure
    if(extensions.VK_EXT_metal_surface){
        flags.createMetalSurfaceEXT = true;
    }

    // NOTE: this is deprecated, check on GLFW occasionally to see if they still support it
    // As of GLFW 3.3.8, it still supports this.
    if(extensions.VK_MVK_macos_surface){
        flags.createMacOsSurfaceMVK = true;
    }
    // I can't help but notice that neither of the surface extensions for macos are in the KHR namespace.
    // Makes me wonder what kind of unholy insanity went down to get macos support for Vulkan...

}

fn createDeviceWrapperFlags(extensions: Extensions) vk.DeviceCommandFlags{
    var flags = vk.DeviceCommandFlags{
        .destroyDevice = true,
        .getDeviceQueue = true,
        .queueSubmit = true,
        .queueWaitIdle = true,
        .deviceWaitIdle = true,
        .allocateMemory = true,
        .freeMemory = true,
        .mapMemory = true,
        .unmapMemory = true,
        .flushMappedMemoryRanges = true,
        .invalidateMappedMemoryRanges = true,
        .getDeviceMemoryCommitment = true,
        .getBufferMemoryRequirements = true,
        .bindBufferMemory = true,
        .getImageMemoryRequirements = true,
        .bindImageMemory = true,
        .getImageSparseMemoryRequirements = true,
        .queueBindSparse = true,
        .createFence = true,
        .destroyFence = true,
        .resetFences = true,
        .getFenceStatus = true,
        .waitForFences = true,
        .createSemaphore = true,
        .destroySemaphore = true,
        .createEvent = true,
        .destroyEvent = true,
        .getEventStatus = true,
        .setEvent = true,
        .resetEvent = true,
        .createQueryPool = true,
        .destroyQueryPool = true,
        .getQueryPoolResults = true,
        .resetQueryPool = true,
        .createBuffer = true,
        .destroyBuffer = true,
        .createBufferView = true,
        .destroyBufferView = true,
        .createImage = true,
        .destroyImage = true,
        .getImageSubresourceLayout = true,
        .createImageView = true,
        .destroyImageView = true,
        .createShaderModule = true,
        .destroyShaderModule = true,
        .createPipelineCache = true,
        .destroyPipelineCache = true,
        .getPipelineCacheData = true,
        .mergePipelineCaches = true,
        .createGraphicsPipelines = true,
        .createComputePipelines = true,
        .destroyPipeline = true,
        .createPipelineLayout = true,
        .destroyPipelineLayout = true,
        .createSampler = true,
        .destroySampler = true,
        .createDescriptorSetLayout = true,
        .destroyDescriptorSetLayout = true,
        .createDescriptorPool = true,
        .destroyDescriptorPool = true,
        .resetDescriptorPool = true,
        .allocateDescriptorSets = true,
        .freeDescriptorSets = true,
        .updateDescriptorSets = true,
        .createFramebuffer = true,
        .destroyFramebuffer = true,
        .createRenderPass = true,
        .destroyRenderPass = true,
        .getRenderAreaGranularity = true,
        .createCommandPool = true,
        .destroyCommandPool = true,
        .resetCommandPool = true,
        .allocateCommandBuffers = true,
        .freeCommandBuffers = true,
        .beginCommandBuffer = true,
        .endCommandBuffer = true,
        .resetCommandBuffer = true,
        .cmdBindPipeline = true,
        .cmdSetViewport = true,
        .cmdSetScissor = true,
        .cmdSetLineWidth = true,
        .cmdSetDepthBias = true,
        .cmdSetBlendConstants = true,
        .cmdSetDepthBounds = true,
        .cmdSetStencilCompareMask = true,
        .cmdSetStencilWriteMask = true,
        .cmdSetStencilReference = true,
        .cmdBindDescriptorSets = true,
        .cmdBindIndexBuffer = true,
        .cmdBindVertexBuffers = true,
        .cmdDraw = true,
        .cmdDrawIndexed = true,
        .cmdDrawIndirect = true,
        .cmdDrawIndexedIndirect = true,
        .cmdDispatch = true,
        .cmdDispatchIndirect = true,
        .cmdCopyBuffer = true,
        .cmdCopyImage = true,
        .cmdBlitImage = true,
        .cmdCopyBufferToImage = true,
        .cmdCopyImageToBuffer = true,
        .cmdUpdateBuffer = true,
        .cmdFillBuffer = true,
        .cmdClearColorImage = true,
        .cmdClearDepthStencilImage = true,
        .cmdClearAttachments = true,
        .cmdResolveImage = true,
        .cmdSetEvent = true,
        .cmdResetEvent = true,
        .cmdWaitEvents = true,
        .cmdPipelineBarrier = true,
        .cmdBeginQuery = true,
        .cmdEndQuery = true,
        .cmdResetQueryPool = true,
        .cmdWriteTimestamp = true,
        .cmdCopyQueryPoolResults = true,
        .cmdPushConstants = true,
        .cmdBeginRenderPass = true,
        .cmdNextSubpass = true,
        .cmdEndRenderPass = true,
        .cmdExecuteCommands = true,
        .trimCommandPool = true,
        .getDeviceGroupPeerMemoryFeatures = true,
        .bindBufferMemory2 = true,
        .bindImageMemory2 = true,
        .cmdSetDeviceMask = true,
        .cmdDispatchBase = true,
        .createDescriptorUpdateTemplate = true,
        .destroyDescriptorUpdateTemplate = true,
        .updateDescriptorSetWithTemplate = true,
        .getBufferMemoryRequirements2 = true,
        .getImageMemoryRequirements2 = true,
        .getImageSparseMemoryRequirements2 = true,
        .getDeviceBufferMemoryRequirements = true,
        .getDeviceImageMemoryRequirements = true,
        .getDeviceImageSparseMemoryRequirements = true,
        .createSamplerYcbcrConversion = true,
        .destroySamplerYcbcrConversion = true,
        .getDeviceQueue2 = true,
        .getDescriptorSetLayoutSupport = true,
        .createRenderPass2 = true,
        .cmdBeginRenderPass2 = true,
        .cmdNextSubpass2 = true,
        .cmdEndRenderPass2 = true,
        .getSemaphoreCounterValue = true,
        .waitSemaphores = true,
        .signalSemaphore = true,
        .cmdDrawIndirectCount = true,
        .cmdDrawIndexedIndirectCount = true,
        .getBufferOpaqueCaptureAddress = true,
        .getBufferDeviceAddress = true,
        .getDeviceMemoryOpaqueCaptureAddress = true,
        .getFaultData = true,
        .cmdSetCullMode = true,
        .cmdSetFrontFace = true,
        .cmdSetPrimitiveTopology = true,
        .cmdSetViewportWithCount = true,
        .cmdSetScissorWithCount = true,
        .cmdBindVertexBuffers2 = true,
        .cmdSetDepthTestEnable = true,
        .cmdSetDepthWriteEnable = true,
        .cmdSetDepthCompareOp = true,
        .cmdSetDepthBoundsTestEnable = true,
        .cmdSetStencilTestEnable = true,
        .cmdSetStencilOp = true,
        .cmdSetRasterizerDiscardEnable = true,
        .cmdSetDepthBiasEnable = true,
        .cmdSetPrimitiveRestartEnable = true,
        .createPrivateDataSlot = true,
        .destroyPrivateDataSlot = true,
        .setPrivateData = true,
        .getPrivateData = true,
        .cmdCopyBuffer2 = true,
        .cmdCopyImage2 = true,
        .cmdBlitImage2 = true,
        .cmdCopyBufferToImage2 = true,
        .cmdCopyImageToBuffer2 = true,
        .cmdResolveImage2 = true,
        .cmdSetEvent2 = true,
        .cmdResetEvent2 = true,
        .cmdWaitEvents2 = true,
        .cmdPipelineBarrier2 = true,
        .queueSubmit2 = true,
        .cmdWriteTimestamp2 = true,
        .getCommandPoolMemoryConsumption = true,
        .cmdBeginRendering = true,
        .cmdEndRendering = true,
    };

    if(extensions.VK_KHR_swapchain){
        flags.acquireNextImageKHR = true;
        flags.createSwapchainKHR = true;
        flags.destroySwapchainKHR = true;
        flags.getSwapchainImagesKHR = true;
        flags.queuePresentKHR = true;
        // If Version 1.1 is supported:
        flags.acquireNextImage2KHR = true;
        flags.getDeviceGroupPresentCapabilitiesKHR = true;
        flags.getDeviceGroupSurfacePresentModesKHR = true;
    }
}