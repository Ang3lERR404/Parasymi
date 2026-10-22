//! swapchain + matching depth buffer. Recreated whenever the window resizes.
const std = @import("std");
const m = @import("../core/math.zig");
const Allocator = std.mem.Allocator;
const vk = @import("vulkan");
const ctx = @import("ctx.zig");
const Ctx = ctx.Ctx;

pub const depth_format:vk.Format = .d32_sfloat;

pub const Swapchain = struct {
  handle:vk.SwapchainKHR = .null_handle,
  format:vk.SurfaceFormatKHR = undefined,
  extent:vk.Extent2D = .{.width = 0, .height = 0},
  images:[]vk.Image = &.{},
  views:[]vk.ImageView = &.{},
  /// one "render finished" semaphore per image (safe reuse with present).
  done:[]vk.Semaphore = &.{},
  depth:vk.Image = .null_handle,
  depth_mem:vk.DeviceMemory = .null_handle,
  depth_view:vk.ImageView = .null_handle,

  pub fn init(c:*const Ctx, gpa:Allocator, w:u32, h:u32, vsync:bool, old:vk.SwapchainKHR) ctx.Error!Swapchain {
    var s:Swapchain = .{};
    s.create(c, gpa, w, h, vsync, old) catch |e| {
      s.deinit(c, gpa, false);
      return ctx.fold(e);
    };
    return s;
  }

  /// on failure leaves `s` holding only what was made, for `deinit` to free.
  fn create(s:*Swapchain, c:*const Ctx, gpa:Allocator, w:u32, h:u32, vsync:bool, old:vk.SwapchainKHR) !void {
    const caps = try c.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(c.pdev, c.surface);
    s.extent = if (caps.current_extent.width != m.maxInt(u32)) caps.current_extent else .{
      .width = m.clamp(w, caps.min_image_extent.width, caps.max_image_extent.width),
      .height = m.clamp(h, caps.min_image_extent.height, caps.max_image_extent.height),
    };

    const formats = try c.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(c.pdev, c.surface, gpa);
    defer gpa.free(formats);
    s.format = formats[0];
    for (formats) |f| if (f.format == .b8g8r8a8_srgb and f.color_space == .srgb_nonlinear_khr) { s.format = f; };

    var mode:vk.PresentModeKHR = .fifo_khr;
    if (!vsync) {
      const modes = try c.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(c.pdev, c.surface, gpa);
      defer gpa.free(modes);
      for (modes) |md| if (md == .mailbox_khr or (md == .immediate_khr and mode != .mailbox_khr)) { mode = md; };
    }

    var count = caps.min_image_count + 1;
    if (caps.max_image_count > 0) count = @min(count, caps.max_image_count);
    s.handle = try c.device.createSwapchainKHR(&.{
      .surface = c.surface,
      .min_image_count = count,
      .image_format = s.format.format,
      .image_color_space = s.format.color_space,
      .image_extent = s.extent,
      .image_array_layers = 1,
      .image_usage = .{.color_attachment = true},
      .image_sharing_mode = .exclusive,
      .pre_transform = caps.current_transform,
      .composite_alpha = .{.opaque_khr = true},
      .present_mode = mode,
      .clipped = .true,
      .old_swapchain = old,
    }, null);

    s.images = try c.device.getSwapchainImagesAllocKHR(s.handle, gpa);
    s.views = try gpa.alloc(vk.ImageView, s.images.len);
    @memset(s.views, .null_handle);
    s.done = try gpa.alloc(vk.Semaphore, s.images.len);
    @memset(s.done, .null_handle);
    for (s.images, s.views, s.done) |img, *v, *d| {
      v.* = try c.device.createImageView(&.{
        .image = img,
        .view_type = .@"2d",
        .format = s.format.format,
        .components = .{.r = .identity, .g = .identity, .b = .identity, .a = .identity},
        .subresource_range = colorRange(),
      }, null);
      d.* = try c.device.createSemaphore(&.{}, null);
    }

    s.depth = try c.device.createImage(&.{
      .image_type = .@"2d",
      .format = depth_format,
      .extent = .{.width = s.extent.width, .height = s.extent.height, .depth = 1},
      .mip_levels = 1,
      .array_layers = 1,
      .samples = .{.@"1" = true},
      .tiling = .optimal,
      .usage = .{.depth_stencil_attachment = true},
      .sharing_mode = .exclusive,
      .initial_layout = .undefined,
    }, null);
    const req = c.device.getImageMemoryRequirements(s.depth);
    s.depth_mem = try c.device.allocateMemory(&.{
      .allocation_size = req.size,
      .memory_type_index = try c.memType(req.memory_type_bits, .{.device_local = true}),
    }, null);
    try c.device.bindImageMemory(s.depth, s.depth_mem, 0);
    s.depth_view = try c.device.createImageView(&.{
      .image = s.depth,
      .view_type = .@"2d",
      .format = depth_format,
      .components = .{.r = .identity, .g = .identity, .b = .identity, .a = .identity},
      .subresource_range = depthRange(),
    }, null);
  }

  pub fn deinit(s:*Swapchain, c:*const Ctx, gpa:Allocator, keep_handle:bool) void {
    c.device.destroyImageView(s.depth_view, null);
    c.device.destroyImage(s.depth, null);
    c.device.freeMemory(s.depth_mem, null);
    // null handles are no-ops, so a half-built swapchain frees cleanly too
    for (s.views) |v| c.device.destroyImageView(v, null);
    for (s.done) |d| c.device.destroySemaphore(d, null);
    gpa.free(s.views);
    gpa.free(s.done);
    gpa.free(s.images);
    if (!keep_handle) c.device.destroySwapchainKHR(s.handle, null);
  }
};

pub fn colorRange() vk.ImageSubresourceRange {
  return .{.aspect_mask = .{.color = true}, .base_mip_level = 0, .level_count = 1, .base_array_layer = 0, .layer_count = 1};
}
pub fn depthRange() vk.ImageSubresourceRange {
  return .{.aspect_mask = .{.depth = true}, .base_mip_level = 0, .level_count = 1, .base_array_layer = 0, .layer_count = 1};
}
