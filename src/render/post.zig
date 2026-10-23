//! post-processing: light that bleeds. The world is drawn into an HDR image
//! (`HDR_FORMAT`) instead of straight to the screen. What is brighter than
//! white there (the celestial blooms and their beams, the motes, glowing
//! sap, ley crystals, highlights) is pulled out and blurred through a chain
//! of ever smaller images (each half the size of the last, a 13-tap filter
//! going down, a tent filter adding back up), then the composite lays that
//! glow over the scene and gently tone-maps it onto the swapchain image,
//! under the UI. Everything here runs on the GPU; the CPU only records it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const vk = @import("vulkan");
const m = @import("../core/math.zig");
const ctx = @import("../gfx/ctx.zig");
const Ctx = ctx.Ctx;
const pipeline = @import("../gfx/pipeline.zig");

pub const HDR_FORMAT:vk.Format = .r16g16b16a16_sfloat;
/// levels in the blur chain, the first at half the screen's size
const LEVELS = 5;

/// how the glow is pulled out and laid back: brightness where it starts
/// (with a soft knee below it) and how strongly it is added
pub const Push = extern struct {
  /// one texel of the image being read
  texel:[2]f32,
  threshold:f32 = 1.0,
  intensity:f32 = 0.7,
};

const Image = struct {
  image:vk.Image = .null_handle,
  mem:vk.DeviceMemory = .null_handle,
  views:[LEVELS]vk.ImageView = @splat(.null_handle),
  /// a view of the whole image (all its levels), for the world to draw into
  extent:vk.Extent2D = .{.width = 0, .height = 0},
  levels:u32 = 1,

  fn init(c:*const Ctx, w:u32, h:u32, levels:u32) !Image {
    var im:Image = .{.extent = .{.width = w, .height = h}, .levels = levels};
    im.image = try c.device.createImage(&.{
      .image_type = .@"2d",
      .format = HDR_FORMAT,
      .extent = .{.width = w, .height = h, .depth = 1},
      .mip_levels = levels,
      .array_layers = 1,
      .samples = .{.@"1" = true},
      .tiling = .optimal,
      .usage = .{.color_attachment = true, .sampled = true},
      .sharing_mode = .exclusive,
      .initial_layout = .undefined,
    }, null);
    const req = c.device.getImageMemoryRequirements(im.image);
    im.mem = try c.device.allocateMemory(&.{
      .allocation_size = req.size,
      .memory_type_index = try c.memType(req.memory_type_bits, .{.device_local = true}),
    }, null);
    try c.device.bindImageMemory(im.image, im.mem, 0);
    for (0..levels) |l| {
      im.views[l] = try c.device.createImageView(&.{
        .image = im.image,
        .view_type = .@"2d",
        .format = HDR_FORMAT,
        .components = .{.r = .identity, .g = .identity, .b = .identity, .a = .identity},
        .subresource_range = range(@intCast(l)),
      }, null);
    }
    return im;
  }

  fn deinit(im:*Image, c:*const Ctx) void {
    for (im.views) |v| c.device.destroyImageView(v, null);
    c.device.destroyImage(im.image, null);
    c.device.freeMemory(im.mem, null);
    im.* = .{};
  }

  fn size(im:*const Image, level:u32) vk.Extent2D {
    return .{.width = @max(im.extent.width >> @intCast(level), 1), .height = @max(im.extent.height >> @intCast(level), 1)};
  }
};

fn range(level:u32) vk.ImageSubresourceRange {
  return .{.aspect_mask = .{.color = true}, .base_mip_level = level, .level_count = 1, .base_array_layer = 0, .layer_count = 1};
}

pub const Post = struct {
  /// the world, drawn at full size
  hdr:Image = .{},
  /// the blur chain
  bloom:Image = .{},
  sampler:vk.Sampler = .null_handle,
  set_layout:vk.DescriptorSetLayout = .null_handle,
  pool:vk.DescriptorPool = .null_handle,
  /// down[l] reads the level above (the HDR image for l = 0); up[l] reads
  /// level l + 1; composite reads the HDR image and the first level
  down:[LEVELS]vk.DescriptorSet = undefined,
  up:[LEVELS - 1]vk.DescriptorSet = undefined,
  composite:vk.DescriptorSet = undefined,
  layout:vk.PipelineLayout = .null_handle,
  pipe_down:vk.Pipeline = .null_handle,
  pipe_up:vk.Pipeline = .null_handle,
  pipe_composite:vk.Pipeline = .null_handle,

  pub fn init(c:*const Ctx, screen:vk.Format, w:u32, h:u32) ctx.Error!Post {
    var p:Post = .{};
    p.create(c, screen, w, h) catch |e| {
      p.deinit(c);
      return ctx.fold(e);
    };
    return p;
  }

  fn create(p:*Post, c:*const Ctx, screen:vk.Format, w:u32, h:u32) !void {
    p.sampler = try c.device.createSampler(&.{
      .mag_filter = .linear, .min_filter = .linear, .mipmap_mode = .nearest,
      .address_mode_u = .clamp_to_edge, .address_mode_v = .clamp_to_edge, .address_mode_w = .clamp_to_edge,
      .mip_lod_bias = 0, .anisotropy_enable = .false, .max_anisotropy = 1,
      .compare_enable = .false, .compare_op = .always, .min_lod = 0, .max_lod = 0,
      .border_color = .float_transparent_black, .unnormalized_coordinates = .false,
    }, null);
    const bindings = [_]vk.DescriptorSetLayoutBinding{
      .{.binding = 0, .descriptor_type = .combined_image_sampler, .descriptor_count = 1, .stage_flags = .{.fragment = true}},
      .{.binding = 1, .descriptor_type = .combined_image_sampler, .descriptor_count = 1, .stage_flags = .{.fragment = true}},
    };
    p.set_layout = try c.device.createDescriptorSetLayout(&.{.binding_count = bindings.len, .p_bindings = &bindings}, null);
    const sets = LEVELS + (LEVELS - 1) + 1;
    const sizes = [_]vk.DescriptorPoolSize{.{.type = .combined_image_sampler, .descriptor_count = sets * 2}};
    p.pool = try c.device.createDescriptorPool(&.{.max_sets = sets, .pool_size_count = sizes.len, .p_pool_sizes = &sizes}, null);
    var layouts:[sets]vk.DescriptorSetLayout = @splat(p.set_layout);
    var all:[sets]vk.DescriptorSet = undefined;
    try c.device.allocateDescriptorSets(&.{.descriptor_pool = p.pool, .descriptor_set_count = sets, .p_set_layouts = &layouts}, &all);
    p.down = all[0..LEVELS].*;
    p.up = all[LEVELS .. 2 * LEVELS - 1].*;
    p.composite = all[sets - 1];

    const push = [_]vk.PushConstantRange{.{.stage_flags = .{.vertex = true, .fragment = true}, .offset = 0, .size = @sizeOf(Push)}};
    p.layout = try c.device.createPipelineLayout(&.{
      .set_layout_count = 1, .p_set_layouts = @ptrCast(&p.set_layout),
      .push_constant_range_count = push.len, .p_push_constant_ranges = &push,
    }, null);
    p.pipe_down = try p.pipe(c, "bloom_down.frag", HDR_FORMAT, false);
    p.pipe_up = try p.pipe(c, "bloom_up.frag", HDR_FORMAT, true);
    p.pipe_composite = try p.pipe(c, "composite.frag", screen, false);
    try p.resize(c, w, h);
  }

  fn pipe(p:*const Post, c:*const Ctx, comptime frag:[]const u8, fmt:vk.Format, additive:bool) !vk.Pipeline {
    const vs = try c.shader("post.vert");
    defer c.device.destroyShaderModule(vs, null);
    const fs = try c.shader(frag);
    defer c.device.destroyShaderModule(fs, null);
    return pipeline.create(c, .{
      .vert = vs, .frag = fs, .bindings = &.{}, .attrs = &.{},
      .layout = p.layout, .color_format = fmt,
      .depth = false, .depth_attachment = false, .blend = additive, .additive = additive, .cull = false,
    });
  }

  /// (re)make the images for a screen `w` x `h` and point the sets at them.
  /// The device must be idle.
  pub fn resize(p:*Post, c:*const Ctx, w:u32, h:u32) !void {
    p.hdr.deinit(c);
    p.bloom.deinit(c);
    p.hdr = try Image.init(c, w, h, 1);
    p.bloom = try Image.init(c, @max(w / 2, 1), @max(h / 2, 1), LEVELS);
    for (0..LEVELS) |l| {
      const src = if (l == 0) p.hdr.views[0] else p.bloom.views[l - 1];
      p.point(c, p.down[l], src, src);
    }
    for (0..LEVELS - 1) |l| p.point(c, p.up[l], p.bloom.views[l + 1], p.bloom.views[l + 1]);
    p.point(c, p.composite, p.hdr.views[0], p.bloom.views[0]);
  }

  fn point(p:*const Post, c:*const Ctx, set:vk.DescriptorSet, a:vk.ImageView, b:vk.ImageView) void {
    const infos = [_]vk.DescriptorImageInfo{
      .{.sampler = p.sampler, .image_view = a, .image_layout = .shader_read_only_optimal},
      .{.sampler = p.sampler, .image_view = b, .image_layout = .shader_read_only_optimal},
    };
    const writes = [_]vk.WriteDescriptorSet{
      .{.dst_set = set, .dst_binding = 0, .dst_array_element = 0, .descriptor_count = 1, .descriptor_type = .combined_image_sampler, .p_image_info = @ptrCast(&infos[0]), .p_buffer_info = undefined, .p_texel_buffer_view = undefined},
      .{.dst_set = set, .dst_binding = 1, .dst_array_element = 0, .descriptor_count = 1, .descriptor_type = .combined_image_sampler, .p_image_info = @ptrCast(&infos[1]), .p_buffer_info = undefined, .p_texel_buffer_view = undefined},
    };
    c.device.updateDescriptorSets(&writes, null);
  }

  pub fn deinit(p:*Post, c:*const Ctx) void {
    p.hdr.deinit(c);
    p.bloom.deinit(c);
    c.device.destroyPipeline(p.pipe_down, null);
    c.device.destroyPipeline(p.pipe_up, null);
    c.device.destroyPipeline(p.pipe_composite, null);
    c.device.destroyPipelineLayout(p.layout, null);
    c.device.destroyDescriptorPool(p.pool, null);
    c.device.destroyDescriptorSetLayout(p.set_layout, null);
    c.device.destroySampler(p.sampler, null);
    p.* = .{};
  }

  /// the world's image, ready to be drawn into (its old contents dropped)
  pub fn beginWorld(p:*const Post, cmd:vk.CommandBufferProxy) void {
    barrier(cmd, p.hdr.image, 0, .undefined, .color_attachment_optimal, .{.fragment_shader = true}, .{.shader_sampled_read = true}, .{.color_attachment_output = true}, .{.color_attachment_write = true});
  }

  /// after the world is drawn: pull the glow out of it and blur it down the
  /// chain and back up again.
  pub fn glow(p:*const Post, cmd:vk.CommandBufferProxy) void {
    barrier(cmd, p.hdr.image, 0, .color_attachment_optimal, .shader_read_only_optimal, .{.color_attachment_output = true}, .{.color_attachment_write = true}, .{.fragment_shader = true}, .{.shader_sampled_read = true});
    // down: each level filters the one above it (the first also keeps only
    // what is brighter than the threshold)
    for (0..LEVELS) |l| {
      const lv:u32 = @intCast(l);
      barrier(cmd, p.bloom.image, lv, .undefined, .color_attachment_optimal, .{.fragment_shader = true}, .{.shader_sampled_read = true}, .{.color_attachment_output = true}, .{.color_attachment_write = true});
      const src = if (l == 0) p.hdr.extent else p.bloom.size(lv - 1);
      p.pass(cmd, p.pipe_down, p.down[l], p.bloom.views[l], p.bloom.size(lv), src, .dont_care, if (l == 0) 1 else 0);
      barrier(cmd, p.bloom.image, lv, .color_attachment_optimal, .shader_read_only_optimal, .{.color_attachment_output = true}, .{.color_attachment_write = true}, .{.fragment_shader = true}, .{.shader_sampled_read = true});
    }
    // up: each level adds the blurred level below it onto itself
    var l:usize = LEVELS - 1;
    while (l > 0) {
      l -= 1;
      const lv:u32 = @intCast(l);
      barrier(cmd, p.bloom.image, lv, .shader_read_only_optimal, .color_attachment_optimal, .{.fragment_shader = true}, .{.shader_sampled_read = true}, .{.color_attachment_output = true}, .{.color_attachment_write = true, .color_attachment_read = true});
      p.pass(cmd, p.pipe_up, p.up[l], p.bloom.views[l], p.bloom.size(lv), p.bloom.size(lv + 1), .load, 0);
      barrier(cmd, p.bloom.image, lv, .color_attachment_optimal, .shader_read_only_optimal, .{.color_attachment_output = true}, .{.color_attachment_write = true}, .{.fragment_shader = true}, .{.shader_sampled_read = true});
    }
  }

  /// inside the screen's rendering scope: the world and its glow, tone-mapped
  pub fn compose(p:*const Post, cmd:vk.CommandBufferProxy, screen:vk.Extent2D) void {
    cmd.bindPipeline(.graphics, p.pipe_composite);
    cmd.bindDescriptorSets(.graphics, p.layout, 0, &.{p.composite}, null);
    const push:Push = .{.texel = .{1 / m.f(screen.width), 1 / m.f(screen.height)}};
    cmd.pushConstants(p.layout, .{.vertex = true, .fragment = true}, 0, @sizeOf(Push), &push);
    cmd.draw(3, 1, 0, 0);
  }

  /// one full-screen draw into `dst` (of `size`) reading `src_size` texels
  fn pass(p:*const Post, cmd:vk.CommandBufferProxy, pip:vk.Pipeline, set:vk.DescriptorSet, dst:vk.ImageView, size:vk.Extent2D, src_size:vk.Extent2D, load:vk.AttachmentLoadOp, first:f32) void {
    const color = [_]vk.RenderingAttachmentInfo{.{
      .image_view = dst,
      .image_layout = .color_attachment_optimal,
      .resolve_mode = .{},
      .resolve_image_layout = .undefined,
      .load_op = load,
      .store_op = .store,
      .clear_value = .{.color = .{.float_32 = .{0, 0, 0, 0}}},
    }};
    const area:vk.Rect2D = .{.offset = .{.x = 0, .y = 0}, .extent = size};
    cmd.beginRendering(&.{.render_area = area, .layer_count = 1, .view_mask = 0, .color_attachment_count = color.len, .p_color_attachments = &color});
    cmd.setViewport(0, &.{.{.x = 0, .y = 0, .width = m.f(size.width), .height = m.f(size.height), .min_depth = 0, .max_depth = 1}});
    cmd.setScissor(0, &.{area});
    cmd.bindPipeline(.graphics, pip);
    cmd.bindDescriptorSets(.graphics, p.layout, 0, &.{set}, null);
    // threshold > 0 only on the first step down; the rest pass everything
    const push:Push = .{.texel = .{1 / m.f(src_size.width), 1 / m.f(src_size.height)}, .threshold = if (first > 0) 1.0 else 0};
    cmd.pushConstants(p.layout, .{.vertex = true, .fragment = true}, 0, @sizeOf(Push), &push);
    cmd.draw(3, 1, 0, 0);
    cmd.endRendering();
  }
};

fn barrier(cmd:vk.CommandBufferProxy, image:vk.Image, level:u32, old:vk.ImageLayout, new:vk.ImageLayout, src_stage:vk.PipelineStageFlags2, src_access:vk.AccessFlags2, dst_stage:vk.PipelineStageFlags2, dst_access:vk.AccessFlags2) void {
  const b = [_]vk.ImageMemoryBarrier2{.{
    .src_stage_mask = src_stage,
    .src_access_mask = src_access,
    .dst_stage_mask = dst_stage,
    .dst_access_mask = dst_access,
    .old_layout = old,
    .new_layout = new,
    .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
    .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
    .image = image,
    .subresource_range = range(level),
  }};
  cmd.pipelineBarrier2(&.{.image_memory_barrier_count = b.len, .p_image_memory_barriers = &b});
}
