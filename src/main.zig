const glfw = @import("zglfw");
const std = @import("std");
const cglm = @import("cglm.zig").cglm;
const vulkan = @import("vulkan.zig");
const vk = @import("vk.zig");
const builtin = @import("builtin");
const ArraySet = @import("arraySet.zig").ArraySet;

const width = 800;
const height = 600;

const validationLayers = []const [*:0]const u8{"VK_LAYER_KHRONOS_validation"};

// Enable validation if the validation layer extension is enabled
const enableValidationLayers = if (vulkan.possibleRequiredExtensions.VK_EXT_debug_utils) true else false;

const QueueFamilyIndices = struct {
    const This = @This();
    graphicsFamily: ?u32,
    presentFamily: ?u32,

    pub fn isComplete(this: This) bool {
        return this.graphicsFamily != null and this.presentFamily != null;
    }
};

const SwapChainSupportDetails = struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: std.ArrayList(vk.SurfaceFormatKHR),
    presentModes: std.ArrayList(vk.PresentModeKHR),
};

const HelloTriangleApplication = struct {
    const This = @This();
    pub fn run(this: *This) void {
        this.initWindow();
        this.initVulkan();
        this.mainLoop();
        this.cleanup();
    }
    window: *glfw.Window,
    instance: vk.Instance,
    debugMessenger: vk.DebugUtilsMessengerEXT,
    surface: vk.SurfaceKHR,
    physicalDevice: vk.PhysicalDevice,
    device: vk.Device,
    graphicsQueue: vk.Queue,
    presentQueue: vk.Queue,
    swapChain: vk.SwapchainKHR,
    swapChainImages: []vk.Image,
    swapChainImageFormat: vk.Format,
    swapChainExtent: vk.Extent2D,
    swapChainImageViews: []vk.ImageView,
    pipelineLayout: vk.PipelineLayout,
    renderPass: vk.RenderPass,
    graphicsPipeline: vk.Pipeline,
    swapChainFramebuffers: []vk.Framebuffer,
    commandPool: vk.CommandPool,
    commandBuffer: vk.CommandBuffer,
    imageAvailableSemaphore: vk.Semaphore,
    imageFinishedSemaphore: vk.Semaphore,
    inFlightFence: vk.Fence,
    allocator: std.mem.Allocator,
    extensions: vulkan.Extensions,
    fn initWindow(this: *This) void {
        glfw.Init();
        glfw.WindowHint(glfw.ClientAPI, glfw.NoAPI);
        glfw.WindowHint(glfw.Resizable, 0);
        this.window = glfw.createWindow(width, height, "Vulkan window", null, null);
    }

    fn initVulkan(this: *This) void {
        this.createInstance();
        this.setupDebugMessenger();
        this.createSurface();
        this.pickPhysicalDevice();
        this.createLogicalDevice();
        this.createSwapChain();
        this.createImageViews();
        this.createRenderPass();
        this.createGraphicsPipeline();
        this.createFramebuffers();
        this.createCommandPool();
        this.createCommandBuffer();
        this.createSyncObjects();
    }

    fn mainLoop(this: *This) void {
        while (!glfw.windowShouldClose(this.window)) {
            glfw.pollEvents();
            this.drawFrame();
        }
        vulkan.Device.deviceWaitIdle(this.device);
    }
    fn drawFrame(this: *This) void {
        _ = vulkan.Device.waitForFences(this.device, 1, &this.inFlightFence, vk.TRUE, std.math.maxInt(u64)) catch @panic("Vulkan error");
        _ = vulkan.Device.resetFences(this.device, 1, &this.inFlightFence) catch @panic("Vullan error");
        const imageIndex = (vulkan.Device.acquireNextImageKHR(this.device, this.swapChain, std.math.maxInt(u64), this.imageAvailableSemaphore, vk.Fence.null_handle) catch @panic("Vulkan error")).image_index;
        _ = vulkan.Device.resetCommandBuffer(this.commandBuffer) catch @panic("Vulkan error");
        this.recordCommandBuffer(this.commandBuffer, imageIndex);
        var waitStages = [_]vk.PipelineStageFlags{.{ .color_attachment_output_bit = true }};
        var signalSemaphores = [_]vk.Semaphore{this.renderFinishedSemaphore};
        var submitInfo = vk.SubmitInfo{ .s_type = .submit_info, .wait_semaphore_count = 1, .p_wait_semaphores = &this.imageAvailableSemaphore, .p_wait_dst_stage_mask = &waitStages, .command_buffer_count = 1, .p_command_buffers = &this.commandBuffer, .signal_semaphore_count = 1, .p_signal_semaphores = &signalSemaphores };

        vulkan.Device.queueSubmit(this.graphicsQueue, 1, &submitInfo, this.inFlightFence) catch @panic("failed to submit draw command buffer!");

        var presentInfo = vk.PresentInfoKHR{
            .s_type = .present_info_khr,
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &signalSemaphores,
            .swapchain_count = 1,
            .p_swapchains = &this.swapChain,
            .p_image_indices = &imageIndex,
            .p_results = null,
        };
        vulkan.Device.queuePresentKHR(this.presentQueue, &presentInfo);
    }

    fn cleanup(this: *This) void {
        vulkan.Device.destroySemaphore(this.device, this.imageAvailableSemaphore, null);
        vulkan.Device.destroySemaphore(this.device, this.renderFinishedSemaphore, null);
        vulkan.Device.destroyFence(this.device, this.inFlightFence, null);
        vulkan.Device.destroyCommandPool(this.device, this.commandPool, null);
        for (this.swapChainFramebuffers) |framebuffer| {
            vulkan.Device.destroyFramebuffer(this.device, framebuffer, null);
        }
        vulkan.Device.destroyPipeline(this.device, this.graphicsPipeline, null);
        vulkan.Device.destroyPipelineLayout(this.device, this.pipelineLayout, null);
        vulkan.Device.destroyRenderPass(this.device, this.renderPass, null);
        for (this.swapChainImageViews) |imageView| {
            vulkan.Device.destroyImageView(this.device, imageView, null);
        }
        vulkan.Device.destroySwapchainKHR(this.device, this.swapchain, null);
        vulkan.Device.destroyDevice(this.device, null);
        if (enableValidationLayers) {
            vulkan.Instance.destroyDebugUtilsMessengerEXT(this.instance, this.debugMessenger, null);
        }
        vulkan.Instance.destroySurfaceKHR(this.instance, this.surface, null);
        vulkan.Instance.destroyInstance(this.instance, null);

        glfw.destroyWindow(this.window);
        glfw.terminate();
    }

    fn recordCommandBuffer(this: *This, commandBuffer: *vk.CommandBuffer, imageIndex: u32) void {
        var beginInfo = vk.CommandBufferBeginInfo{
            .s_type = .command_buffer_begin_info,
            .flags = 0,
            .p_inheritance_info = null,
        };
        vulkan.Device.beginCommandBuffer(commandBuffer, &beginInfo) catch @panic("failed to begin recording command buffer!") catch @panic("Vulkan error");
        const clearColor = vk.ClearColorValue{ .float_32 = [4]f32{ 0.0, 0.0, 0.0, 1.0 } };
        var renderPassInfo = vk.RenderPassBeginInfo{
            .s_type = .render_pass_begin_info,
            .render_pass = this.renderPass,
            .framebuffer = this.swapChainFramebuffers[imageIndex],
            .render_area = .{ .extent = this.swapChainExtent, .offset = .{ .x = 0, .y = 0 } },
            .clear_value_count = 1,
            .p_clear_values = &clearColor,
        };
        vulkan.Device.cmdBeginRenderPass(commandBuffer, &renderPassInfo, .@"inline");
        vulkan.Device.cmdBindPipeline(commandBuffer, .graphics, this.graphicsPipeline);
        const viewport = vk.Viewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(this.swapChainExtent.width),
            .height = @floatFromInt(this.swapChainExtent.height),
            .min_depth = 0.0,
            .max_depth = 1.0,
        };
        vulkan.Device.cmdSetViewport(commandBuffer, 0, 1, &viewport);
        const scissor = vk.Rect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = this.swapChainExtent };
        vulkan.Device.cmdSetScissor(commandBuffer, 0, 1, &scissor);
        vulkan.Device.cmdDraw(commandBuffer, 3, 1, 0, 0);
        vulkan.Device.cmdEndRenderPass(commandBuffer);
        vulkan.Device.endCommandBuffer(commandBuffer) catch @panic("failed to record command buffer!");
    }

    fn createRenderPass(this: *This) void {
        const colorAttachment = vk.AttachmentDescription{
            .format = this.swapChainImageFormat,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .initial_layout = .undefined,
            .final_layout = .present_src_khr,
        };
        const colorAttachmentRef = vk.AttachmentReference{
            .attachment = 0,
            .layout = .optimal,
        };
        const subpass = vk.SubpassDescription{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = &colorAttachmentRef,
        };
        const dependency = vk.SubpassDependency{
            .src_subpass = .external,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .src_access_mask = 0,
            .dst_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_access_mask = .{ .color_attachment_write_bit = true },
        };
        const renderPassInfo = vk.RenderPassCreateInfo{
            .s_type = .render_pass_create_info,
            .attachment_count = 1,
            .p_attachments = &colorAttachment,
            .subpass_count = 1,
            .p_subpasses = &subpass,
            .dependency_count = 1,
            .p_dependencies = &dependency,
        };

        _ = vulkan.Device.createRenderPass(this.device, &renderPassInfo, null) catch @panic("failed to create render pass!");
    }

    fn createInstance(this: *This) void {
        if (enableValidationLayers and !checkValidationLayerSupport()) {
            // TODO: it's probably worth just printing an error and disabling validaiton layers
            @panic("validation layers requested, but not available!");
        }
        const appInfo = vk.ApplicationInfo{
            .s_type = .application_info,
            .p_application_name = "Hello Triangle",
            // TODO: fill this out with actually useful info
            .application_version = 0,
            .p_engine_name = null,
            .engineVersion = 0,
            .api_version = vk.API_VERSION_1_0,
        };
        this.extensions = vulkan.Extensions.initActualRequired();
        const extensionsList = this.extensions.enumerate(this.allocator);
        defer this.allocator.free(extensionsList);
        var createInfo = vk.InstanceCreateInfo{
            .s_type = .instance_create_info,
            .p_application_info = &appInfo,
            .enabled_extension_count = @intCast(extensionsList.len),
            .pp_enabled_extension_names = extensionsList.ptr,
        };
        if (enableValidationLayers and this.extensions.VK_EXT_debug_utils) {
            createInfo.enabled_layer_count = validationLayers.len;
            createInfo.pp_enabled_layer_names = validationLayers.ptr;
            var debugCreateInfo = vk.DebugUtilsMessengerCreateInfoEXT{};
            this.populateDebugMessengerCreateInfo(&debugCreateInfo);
            createInfo.p_next = &debugCreateInfo;
        } else {
            createInfo.enabled_layer_count = 0;
            createInfo.p_next = null;
        }
        this.instance = vulkan.Base.createInstance(&createInfo, null) catch @panic("failed to create Vulkan instance!");
    }

    fn populateDebugMessengerCreateInfo(createInfo: *vk.DebugUtilsMessengerCreateInfoEXT) void {
        createInfo.* = vk.DebugUtilsMessengerCreateInfoEXT{
            .s_type = .debug_utils_messenger_create_info_ext,
            .message_severity = .{ .verbose_bit_ext = true, .warning_bit_ext = true, .error_bit_ext = true },
            .message_type = .{ .general_bit_ext = true, .validation_bit_ext = true, .performance_bit_ext = true },
            .pfn_user_callback = debugCallback,
        };
    }

    fn setupDebugMessenger(this: *This) void {
        if (!this.enableValidationLayers or !vulkan.Extensions.initActualRequired().VK_EXT_debug_utils) return;
        var createInfo = vk.DebugUtilsMessengerCreateInfoEXT{};
        populateDebugMessengerCreateInfo(&createInfo);
        _ = vulkan.Instance.createDebugUtilsMessengerEXT(this.instance, &createInfo, null) catch @panic("failed to set up debug messenger!");
    }

    fn createSurface(this: *This) void {
        if (glfw.createWindowSurface(this, this.window, null, &this.surface) != .success) {
            @panic("failed to create window surface!");
        }
    }

    fn pickPhysicalDevice(this: *This) void {
        var deviceCount: u32 = undefined;
        _ = vulkan.Instance.enumeratePhysicalDevices(this.instance, &deviceCount, null) catch @panic("Vulkan error");
        if (deviceCount == 0) @panic("No Vulkan devices!");
        var devices = this.allocator.alloc(vk.PhysicalDevice, deviceCount);
        defer this.allocator.free(devices);
        _ = vulkan.Instance.enumeratePhysicalDevices(this.instance, &deviceCount, devices.ptr) catch @panic("Vulkan error");
        //sort the devices by a score
        std.mem.sort(vk.PhysicalDevice, devices, .{}, sortDevices);
        //Choose the device with the best score
        for (devices) |device| {
            std.debug.print("Device {} scored {}\n", .{ device, scoreDevice(device) });
        }

        for (devices) |device| {
            if (isDeviceSuitable(device)) {
                this.physicalDevice = device;
                break;
            }
        }

        if (this.physical_device == .null_handle) @panic("No suitable Vulkan device");
    }

    fn scoreDevice(device: vk.PhysicalDevice) i32 {
        const properties = vulkan.Instance.getPhysicalDeviceProperties(device);
        switch (properties.device_type) {
            .other => return 0,
            .cpu => return 1,
            .integrated_gpu => return 2,
            .discrete_gpu => return 3,
            .virtual_gpu => return 4,
            else => return -1,
        }
    }

    fn sortDevices(ctx: anytype, lhs: vk.PhysicalDevice, rhs: vk.PhysicalDevice) bool {
        _ = ctx;
        return scoreDevice(lhs) < scoreDevice(rhs);
    }

    fn createLogicalDevice(this: *This) void {
        const indices: QueueFamilyIndices = findQueueFamilies(this.physicalDevice);
        var queueCreateInfos = std.ArrayList(vk.DeviceQueueCreateInfo).init(this.allocator);
        var uniqueQueueFamilies = ArraySet(u32).init(this.allocator);
        uniqueQueueFamilies.add(indices.graphicsFamily.?);
        uniqueQueueFamilies.add(indices.presentFamily.?);
        const queuePriority: f32 = 1.0;
        for (uniqueQueueFamilies.items.items) |queueFamily| {
            const queueCreateInfo = vk.DeviceQueueCreateInfo{
                .s_type = .device_queue_create_info,
                .queue_family_index = queueFamily,
                .queue_count = 1,
                .p_queue_priorities = &queuePriority,
            };
            queueCreateInfos.append(queueCreateInfo);
        }
        const extensionsList = this.extensions.enumerate(this.allocator);
        defer this.allocator.free(extensionsList);
        var deviceFeatures = vk.PhysicalDeviceFeatures{};
        var createInfo = vk.DeviceCreateInfo{
            .s_type = .device_create_info,
            .queue_create_info_count = queueCreateInfos.items.len,
            .p_queue_create_infos = queueCreateInfos.items.ptr,
            .p_enabled_features = &deviceFeatures,
            .enabled_extension_count = extensionsList.len,
            .pp_enabled_extension_names = extensionsList.ptr,
        };
        if (this.enableValidationLayers) {
            createInfo.enabled_layer_count = validationLayers.len;
            createInfo.pp_enabled_layer_names = validationLayers.ptr;
        } else {
            createInfo.enabled_layer_count = 0;
        }

        this.device = vulkan.Instance.createDevice(this.physical_device, &createInfo) catch @panic("Failed to create logical device!");

        this.graphicsQueue = vulkan.Device.getDeviceQueue(this.device, 0, indices.graphicsFamily.?);
        this.presentQueue = vulkan.Device.getDeviceQueue(this.device, 0, indices.presentFamily.?);
    }

    fn createSwapChain(this: *This) void {
        _ = this;
    }
    //     void createSwapChain() {
    //         SwapChainSupportDetails swapChainSupport = querySwapChainSupport(physicalDevice);

    //         VkSurfaceFormatKHR surfaceFormat = chooseSwapSurfaceFormat(swapChainSupport.formats);
    //         VkPresentModeKHR presentMode = chooseSwapPresentMode(swapChainSupport.presentModes);
    //         VkExtent2D extent = chooseSwapExtent(swapChainSupport.capabilities);

    //         uint32_t imageCount = swapChainSupport.capabilities.minImageCount + 1;
    //         if (swapChainSupport.capabilities.maxImageCount > 0 && imageCount > swapChainSupport.capabilities.maxImageCount) {
    //             imageCount = swapChainSupport.capabilities.maxImageCount;
    //         }

    //         VkSwapchainCreateInfoKHR createInfo{};
    //         createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    //         createInfo.surface = surface;

    //         createInfo.minImageCount = imageCount;
    //         createInfo.imageFormat = surfaceFormat.format;
    //         createInfo.imageColorSpace = surfaceFormat.colorSpace;
    //         createInfo.imageExtent = extent;
    //         createInfo.imageArrayLayers = 1;
    //         createInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

    //         QueueFamilyIndices indices = findQueueFamilies(physicalDevice);
    //         uint32_t queueFamilyIndices[] = {indices.graphicsFamily.value(), indices.presentFamily.value()};

    //         if (indices.graphicsFamily != indices.presentFamily) {
    //             createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
    //             createInfo.queueFamilyIndexCount = 2;
    //             createInfo.pQueueFamilyIndices = queueFamilyIndices;
    //         } else {
    //             createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    //         }

    //         createInfo.preTransform = swapChainSupport.capabilities.currentTransform;
    //         createInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    //         createInfo.presentMode = presentMode;
    //         createInfo.clipped = VK_TRUE;

    //         createInfo.oldSwapchain = VK_NULL_HANDLE;

    //         if (vkCreateSwapchainKHR(device, &createInfo, nullptr, &swapChain) != VK_SUCCESS) {
    //             throw std::runtime_error("failed to create swap chain!");
    //         }

    //         vkGetSwapchainImagesKHR(device, swapChain, &imageCount, nullptr);
    //         swapChainImages.resize(imageCount);
    //         vkGetSwapchainImagesKHR(device, swapChain, &imageCount, swapChainImages.data());

    //         swapChainImageFormat = surfaceFormat.format;
    //         swapChainExtent = extent;
    //     }

    //     void createImageViews() {
    //         swapChainImageViews.resize(swapChainImages.size());

    //         for (size_t i = 0; i < swapChainImages.size(); i++) {
    //             VkImageViewCreateInfo createInfo{};
    //             createInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    //             createInfo.image = swapChainImages[i];
    //             createInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
    //             createInfo.format = swapChainImageFormat;
    //             createInfo.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
    //             createInfo.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
    //             createInfo.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
    //             createInfo.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
    //             createInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    //             createInfo.subresourceRange.baseMipLevel = 0;
    //             createInfo.subresourceRange.levelCount = 1;
    //             createInfo.subresourceRange.baseArrayLayer = 0;
    //             createInfo.subresourceRange.layerCount = 1;

    //             if (vkCreateImageView(device, &createInfo, nullptr, &swapChainImageViews[i]) != VK_SUCCESS) {
    //                 throw std::runtime_error("failed to create image views!");
    //             }
    //         }
    //     }

    //     void createGraphicsPipeline() {
    //         auto vertShaderCode = readFile("shaders/bin/vertex.spv");
    //         auto fragShaderCode = readFile("shaders/bin/fragment.spv");

    //         VkShaderModule vertShaderModule = createShaderModule(vertShaderCode);
    //         VkShaderModule fragShaderModule = createShaderModule(fragShaderCode);

    //         VkPipelineShaderStageCreateInfo vertShaderStageInfo{};
    //         vertShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    //         vertShaderStageInfo.stage = VK_SHADER_STAGE_VERTEX_BIT;
    //         vertShaderStageInfo.module = vertShaderModule;
    //         vertShaderStageInfo.pName = "main";

    //         VkPipelineShaderStageCreateInfo fragShaderStageInfo{};
    //         fragShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    //         fragShaderStageInfo.stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    //         fragShaderStageInfo.module = fragShaderModule;
    //         fragShaderStageInfo.pName = "main";

    //         VkPipelineShaderStageCreateInfo shaderStages[] = {vertShaderStageInfo, fragShaderStageInfo};

    //         VkPipelineVertexInputStateCreateInfo vertexInputInfo{};
    //         vertexInputInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    //         vertexInputInfo.vertexBindingDescriptionCount = 0;
    //         vertexInputInfo.vertexAttributeDescriptionCount = 0;

    //         VkPipelineInputAssemblyStateCreateInfo inputAssembly{};
    //         inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    //         inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    //         inputAssembly.primitiveRestartEnable = VK_FALSE;

    //         VkPipelineViewportStateCreateInfo viewportState{};
    //         viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    //         viewportState.viewportCount = 1;
    //         viewportState.scissorCount = 1;

    //         VkPipelineRasterizationStateCreateInfo rasterizer{};
    //         rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    //         rasterizer.depthClampEnable = VK_FALSE;
    //         rasterizer.rasterizerDiscardEnable = VK_FALSE;
    //         rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
    //         rasterizer.lineWidth = 1.0f;
    //         rasterizer.cullMode = VK_CULL_MODE_BACK_BIT;
    //         rasterizer.frontFace = VK_FRONT_FACE_CLOCKWISE;
    //         rasterizer.depthBiasEnable = VK_FALSE;

    //         VkPipelineMultisampleStateCreateInfo multisampling{};
    //         multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    //         multisampling.sampleShadingEnable = VK_FALSE;
    //         multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    //         VkPipelineColorBlendAttachmentState colorBlendAttachment{};
    //         colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    //         colorBlendAttachment.blendEnable = VK_FALSE;

    //         VkPipelineColorBlendStateCreateInfo colorBlending{};
    //         colorBlending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    //         colorBlending.logicOpEnable = VK_FALSE;
    //         colorBlending.logicOp = VK_LOGIC_OP_COPY;
    //         colorBlending.attachmentCount = 1;
    //         colorBlending.pAttachments = &colorBlendAttachment;
    //         colorBlending.blendConstants[0] = 0.0f;
    //         colorBlending.blendConstants[1] = 0.0f;
    //         colorBlending.blendConstants[2] = 0.0f;
    //         colorBlending.blendConstants[3] = 0.0f;

    //         std::vector<VkDynamicState> dynamicStates = {
    //             VK_DYNAMIC_STATE_VIEWPORT,
    //             VK_DYNAMIC_STATE_SCISSOR
    //         };
    //         VkPipelineDynamicStateCreateInfo dynamicState{};
    //         dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    //         dynamicState.dynamicStateCount = static_cast<uint32_t>(dynamicStates.size());
    //         dynamicState.pDynamicStates = dynamicStates.data();

    //         VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
    //         pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    //         pipelineLayoutInfo.setLayoutCount = 0;
    //         pipelineLayoutInfo.pushConstantRangeCount = 0;

    //         if (vkCreatePipelineLayout(device, &pipelineLayoutInfo, nullptr, &pipelineLayout) != VK_SUCCESS) {
    //             throw std::runtime_error("failed to create pipeline layout!");
    //         }

    //         VkGraphicsPipelineCreateInfo pipelineInfo{};
    //         pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    //         pipelineInfo.stageCount = 2;
    //         pipelineInfo.pStages = shaderStages;
    //         pipelineInfo.pVertexInputState = &vertexInputInfo;
    //         pipelineInfo.pInputAssemblyState = &inputAssembly;
    //         pipelineInfo.pViewportState = &viewportState;
    //         pipelineInfo.pRasterizationState = &rasterizer;
    //         pipelineInfo.pMultisampleState = &multisampling;
    //         pipelineInfo.pDepthStencilState = nullptr; // Optional
    //         pipelineInfo.pColorBlendState = &colorBlending;
    //         pipelineInfo.pDynamicState = &dynamicState;
    //         pipelineInfo.layout = pipelineLayout;
    //         pipelineInfo.renderPass = renderPass;
    //         pipelineInfo.subpass = 0;
    //         pipelineInfo.basePipelineHandle = VK_NULL_HANDLE; // Optional
    //         pipelineInfo.basePipelineIndex = -1; // Optional
    //         if (vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &graphicsPipeline) != VK_SUCCESS) {
    //             throw std::runtime_error("failed to create graphics pipeline!");
    //         }
    //         vkDestroyShaderModule(device, fragShaderModule, nullptr);
    //         vkDestroyShaderModule(device, vertShaderModule, nullptr);
    //     }

    //     void createFramebuffers() {
    //         swapChainFramebuffers.resize(swapChainImageViews.size());
    //         for (size_t i = 0; i < swapChainImageViews.size(); i++) {
    //             VkImageView attachments[] = {
    //                 swapChainImageViews[i]
    //             };

    //             VkFramebufferCreateInfo framebufferInfo{};
    //             framebufferInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
    //             framebufferInfo.renderPass = renderPass;
    //             framebufferInfo.attachmentCount = 1;
    //             framebufferInfo.pAttachments = attachments;
    //             framebufferInfo.width = swapChainExtent.width;
    //             framebufferInfo.height = swapChainExtent.height;
    //             framebufferInfo.layers = 1;

    //             if (vkCreateFramebuffer(device, &framebufferInfo, nullptr, &swapChainFramebuffers[i]) != VK_SUCCESS) {
    //                 throw std::runtime_error("failed to create framebuffer!");
    //             }
    //         }
    //     }

    //     void createCommandPool() {
    //         QueueFamilyIndices queueFamilyIndices = findQueueFamilies(physicalDevice);
    //         VkCommandPoolCreateInfo poolInfo{};
    //         poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    //         poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    //         poolInfo.queueFamilyIndex = queueFamilyIndices.graphicsFamily.value();
    //         if (vkCreateCommandPool(device, &poolInfo, nullptr, &commandPool) != VK_SUCCESS) {
    //             throw std::runtime_error("failed to create command pool!");
    //         }
    //     }

    //     void createCommandBuffer() {
    //         VkCommandBufferAllocateInfo allocInfo{};
    //         allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    //         allocInfo.commandPool = commandPool;
    //         allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    //         allocInfo.commandBufferCount = 1;

    //         if (vkAllocateCommandBuffers(device, &allocInfo, &commandBuffer) != VK_SUCCESS) {
    //             throw std::runtime_error("failed to allocate command buffers!");
    //         }
    //     }

    //     void createSyncObjects() {
    //         VkSemaphoreCreateInfo semaphoreInfo{};
    //         semaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    //         VkFenceCreateInfo fenceInfo{};
    //         fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    //         fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    //         if (vkCreateSemaphore(device, &semaphoreInfo, nullptr, &imageAvailableSemaphore) != VK_SUCCESS ||
    //             vkCreateSemaphore(device, &semaphoreInfo, nullptr, &renderFinishedSemaphore) != VK_SUCCESS ||
    //             vkCreateFence(device, &fenceInfo, nullptr, &inFlightFence) != VK_SUCCESS) {
    //             throw std::runtime_error("failed to create semaphores!");
    //         }
    //     }
    //     VkShaderModule createShaderModule(const std::vector<char>& code) {
    //         VkShaderModuleCreateInfo createInfo{};
    //         createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    //         createInfo.codeSize = code.size();
    //         createInfo.pCode = reinterpret_cast<const uint32_t*>(code.data());

    //         VkShaderModule shaderModule;
    //         if (vkCreateShaderModule(device, &createInfo, nullptr, &shaderModule) != VK_SUCCESS) {
    //             throw std::runtime_error("failed to create shader module!");
    //         }

    //         return shaderModule;
    //     }

    //     VkSurfaceFormatKHR chooseSwapSurfaceFormat(const std::vector<VkSurfaceFormatKHR>& availableFormats) {
    //         for (const auto& availableFormat : availableFormats) {
    //             if (availableFormat.format == VK_FORMAT_B8G8R8A8_SRGB && availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
    //                 return availableFormat;
    //             }
    //         }

    //         return availableFormats[0];
    //     }

    //     VkPresentModeKHR chooseSwapPresentMode(const std::vector<VkPresentModeKHR>& availablePresentModes) {
    //         for (const auto& availablePresentMode : availablePresentModes) {
    //             if (availablePresentMode == VK_PRESENT_MODE_MAILBOX_KHR) {
    //                 return availablePresentMode;
    //             }
    //         }

    //         return VK_PRESENT_MODE_FIFO_KHR;
    //     }

    //     VkExtent2D chooseSwapExtent(const VkSurfaceCapabilitiesKHR& capabilities) {
    //         if (capabilities.currentExtent.width != std::numeric_limits<uint32_t>::max()) {
    //             return capabilities.currentExtent;
    //         } else {
    //             int width, height;
    //             glfwGetFramebufferSize(window, &width, &height);

    //             VkExtent2D actualExtent = {
    //                 static_cast<uint32_t>(width),
    //                 static_cast<uint32_t>(height)
    //             };

    //             actualExtent.width = std::clamp(actualExtent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
    //             actualExtent.height = std::clamp(actualExtent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);

    //             return actualExtent;
    //         }
    //     }

    //     SwapChainSupportDetails querySwapChainSupport(VkPhysicalDevice device) {
    //         SwapChainSupportDetails details;

    //         vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities);

    //         uint32_t formatCount;
    //         vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, nullptr);

    //         if (formatCount != 0) {
    //             details.formats.resize(formatCount);
    //             vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, details.formats.data());
    //         }

    //         uint32_t presentModeCount;
    //         vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, nullptr);

    //         if (presentModeCount != 0) {
    //             details.presentModes.resize(presentModeCount);
    //             vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, details.presentModes.data());
    //         }

    //         return details;
    //     }

    //     bool isDeviceSuitable(VkPhysicalDevice device) {
    //         QueueFamilyIndices indices = findQueueFamilies(device);

    //         bool extensionsSupported = checkDeviceExtensionSupport(device);

    //         bool swapChainAdequate = false;
    //         if (extensionsSupported) {
    //             SwapChainSupportDetails swapChainSupport = querySwapChainSupport(device);
    //             swapChainAdequate = !swapChainSupport.formats.empty() && !swapChainSupport.presentModes.empty();
    //         }

    //         return indices.isComplete() && extensionsSupported && swapChainAdequate;
    //     }

    //     bool checkDeviceExtensionSupport(VkPhysicalDevice device) {
    //         uint32_t extensionCount;
    //         vkEnumerateDeviceExtensionProperties(device, nullptr, &extensionCount, nullptr);

    //         std::vector<VkExtensionProperties> availableExtensions(extensionCount);
    //         vkEnumerateDeviceExtensionProperties(device, nullptr, &extensionCount, availableExtensions.data());

    //         std::set<std::string> requiredExtensions(deviceExtensions.begin(), deviceExtensions.end());

    //         for (const auto& extension : availableExtensions) {
    //             requiredExtensions.erase(extension.extensionName);
    //         }

    //         return requiredExtensions.empty();
    //     }

    //     QueueFamilyIndices findQueueFamilies(VkPhysicalDevice device) {
    //         QueueFamilyIndices indices;

    //         uint32_t queueFamilyCount = 0;
    //         vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nullptr);

    //         std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
    //         vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.data());

    //         int i = 0;
    //         for (const auto& queueFamily : queueFamilies) {
    //             if (queueFamily.queueFlags & VK_QUEUE_GRAPHICS_BIT) {
    //                 indices.graphicsFamily = i;
    //             }

    //             VkBool32 presentSupport = false;
    //             vkGetPhysicalDeviceSurfaceSupportKHR(device, i, surface, &presentSupport);

    //             if (presentSupport) {
    //                 indices.presentFamily = i;
    //             }

    //             if (indices.isComplete()) {
    //                 break;
    //             }

    //             i++;
    //         }

    //         return indices;
    //     }

    //     std::vector<const char*> getRequiredExtensions() {
    //         uint32_t glfwExtensionCount = 0;
    //         const char** glfwExtensions;
    //         glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

    //         std::vector<const char*> extensions(glfwExtensions, glfwExtensions + glfwExtensionCount);

    //         if (enableValidationLayers) {
    //             extensions.push_back(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    //         }

    //         return extensions;
    //     }

    //     bool checkValidationLayerSupport() {
    //         uint32_t layerCount;
    //         vkEnumerateInstanceLayerProperties(&layerCount, nullptr);

    //         std::vector<VkLayerProperties> availableLayers(layerCount);
    //         vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.data());

    //         for (const char* layerName : validationLayers) {
    //             bool layerFound = false;

    //             for (const auto& layerProperties : availableLayers) {
    //                 if (strcmp(layerName, layerProperties.layerName) == 0) {
    //                     layerFound = true;
    //                     break;
    //                 }
    //             }

    //             if (!layerFound) {
    //                 return false;
    //             }
    //         }

    //         return true;
    //     }

    //     static std::vector<char> readFile(const std::string& filename) {
    //         std::ifstream file(filename, std::ios::ate | std::ios::binary);

    //         if (!file.is_open()) {
    //             throw std::runtime_error("failed to open file!");
    //         }

    //         size_t fileSize = (size_t) file.tellg();
    //         std::vector<char> buffer(fileSize);

    //         file.seekg(0);
    //         file.read(buffer.data(), fileSize);

    //         file.close();

    //         return buffer;
    //     }

    //     static VKAPI_ATTR VkBool32 VKAPI_CALL debugCallback(VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity, VkDebugUtilsMessageTypeFlagsEXT messageType, const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData, void* pUserData) {
    //         std::cerr << "validation layer: " << pCallbackData->pMessage << std::endl;

    //         return VK_FALSE;
    //     }
    // };

    // int main() {

    //     std::cout << VK_KHR_SWAPCHAIN_EXTENSION_NAME << std::endl;
    //     HelloTriangleApplication app;

    //     try {
    //         app.run();
    //     } catch (const std::exception& e) {
    //         std::cerr << e.what() << std::endl;
    //         return EXIT_FAILURE;
    //     }

    //     return EXIT_SUCCESS;
    // }
};
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

    var window: *glfw.Window = try glfw.createWindow(width, height, "Hello World", null, null);

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
        vulkan.Extensions.enumerateRaw(vulkan.possibleRequiredExtensions, null, &extensionCount);
        var extensions = allocator.alloc([]const u8, extensionCount) catch unreachable;
        defer allocator.free(extensions);
        vulkan.Extensions.enumerateRaw(vulkan.possibleRequiredExtensions, extensions.ptr, &extensionCount);
        stdout.print("Vulkan extensions that might be required by the application:\n", .{}) catch unreachable;
        for (extensions) |extension| {
            stdout.print("\t{s}\n", .{extension}) catch unreachable;
        }
    }
}
