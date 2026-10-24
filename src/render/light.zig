//! light that moves: the key light's (sun or moon) shadows and the points
//! of light the garden makes (blooms, motes, a halo's flash).
//!
//! Shadows are a cascaded shadow map: the view is cut by distance into
//! `CASCADES` slices, each wrapped in a sphere seen straight down the key
//! light by an orthographic projection into one layer of a depth array.
//! Every caster pass draws once into all the layers (multiview: each view
//! one cascade, `gl_ViewIndex` picking its matrix), so shadows add one draw
//! per mesh, not one per cascade. A slice's sphere depends only on the
//! camera's shape, never where it is, and its centre is snapped to whole
//! texels, so shadow edges hold still as the view pans. The world shaders
//! read it with hardware depth compares (common.glsl `keyShadow`).
//!
//! Points of light are sent each frame in the same record as the cascades
//! (`Lighting`, reached by its address like the bones), and every lit
//! surface sums them on the GPU (common.glsl `pointLight`).
const std = @import("std");
const vk = @import("vulkan");
const m = @import("../core/math.zig");
const ctx = @import("../gfx/ctx.zig");
const Ctx = ctx.Ctx;
const sw = @import("../gfx/swapchain.zig");
const vertex = @import("../gfx/vertex.zig");
const meshgen = @import("../gfx/meshgen.zig");

/// slices of the view, each its own layer (common.glsl CASCADES)
pub const CASCADES = 3;
/// texels along each side of a cascade's layer
pub const RES = 1536;
/// points of light a frame can hold (common.glsl MAX_LIGHTS)
pub const MAX_LIGHTS = 32;
/// the views the casters draw: one per cascade
pub const VIEWS:u32 = (1 << CASCADES) - 1;
/// casters pushed away from the light by a constant and with their slope
pub const BIAS = [2]f32{1.25, 1.75};
pub const FORMAT = sw.depth_format;

/// the mesh a caster drawn from `slot` (a plant's or a part's) casts with:
/// the same mesh at its coarsest level of detail (a slot table lays each
/// mesh's levels side by side). A shadow needs no fine detail, and every
/// caster is drawn into every cascade.
pub fn caster(slot:usize) usize { return slot - slot % meshgen.LODS + meshgen.LODS - 1; }

/// how far toward the light beyond a slice's sphere casters are caught
/// (taller than anything the garden grows or floats)
const CASTER_REACH:f32 = 48;
/// cascade splits: this share logarithmic, the rest even
const SPLIT_LOG:f32 = 0.6;
/// the first split's base: this share of the eye's distance to its target
const SPLIT_BASE:f32 = 0.5;
const SPLIT_MIN:f32 = 2;
/// shadows reach the drawn world's edge from the eye, at most this far
const REACH_MAX:f32 = 260;
/// a slice's sphere grows in steps of this share (so a zoom moves it only
/// now and then, and panning never does)
const RADIUS_STEP:f32 = 1.0 / 32.0;
/// and never in steps finer than this (world units)
const STEP_MIN:f32 = 0.25;

/// what the world shaders read about light each frame (common.glsl
/// `Lighting`)
pub const Lighting = extern struct {
  /// world to each cascade's clip space
  cascades:[CASCADES]m.M4,
  /// per cascade, the world size of one of its texels (one vec4's worth)
  texel:[4]f32,
  /// x points of light, y how far from the eye shadows reach, zw unused
  info:[4]f32,
  lights:[MAX_LIGHTS]vertex.Light,
};
comptime {
  // std430 as common.glsl reads it: the texel sizes pack into one vec4
  if (CASCADES > 4 or @offsetOf(Lighting, "info") != CASCADES * 64 + 16 or @offsetOf(Lighting, "lights") != CASCADES * 64 + 32)
    @compileError("Lighting must match common.glsl's layout");
}

/// the cascades for a view: each world to its clip space, the world size
/// of its texels, and how far from the eye they reach in all
pub const Fit = struct { mats:[CASCADES]m.M4, texel:[CASCADES]f32, reach:f32 };

/// the cascades covering what a camera sees: `vp` its view-projection,
/// `eye` where it is and `target` what it looks at, `reach` how far from it
/// shadows are drawn, `toward` the direction toward the key light (unit)
pub fn fit(vp:m.M4, eye:m.V3, target:m.V3, reach:f32, toward:m.V3) Fit {
  // the view's corner rays, scaled to reach one unit along its gaze
  const inv = m.inverse(vp);
  var near_c:[4]m.V3 = undefined;
  var far_mid = m.v3(0, 0, 0);
  var near_mid = m.v3(0, 0, 0);
  for (0..4) |i| {
    const x:f32 = if (i & 1 == 0) -1 else 1;
    const y:f32 = if (i & 2 == 0) -1 else 1;
    near_c[i] = unproject(inv, x, y, 0);
    near_mid += near_c[i] * m.splat3(0.25);
    far_mid += unproject(inv, x, y, 1) * m.splat3(0.25);
  }
  const gaze = m.norm(far_mid - near_mid);
  const near_d = m.dot(near_mid - eye, gaze);
  var rays:[4]m.V3 = undefined;
  for (&rays, near_c) |*r, c| r.* = (c - eye) * m.splat3(1 / near_d);
  const far_d = m.dot(far_mid - eye, gaze);
  const far = @min(@min(reach, far_d), REACH_MAX);

  // splits: mostly logarithmic from a base near what the camera looks at
  const base = @min(@max(m.len(target - eye) * SPLIT_BASE, SPLIT_MIN), far * 0.5);
  var cut:[CASCADES + 1]f32 = undefined;
  cut[0] = near_d;
  for (1..CASCADES + 1) |i| {
    const k = m.f(i) / CASCADES;
    const lg = base * m.pow(f32, far / base, k);
    const even = base + (far - base) * k;
    cut[i] = m.lerp(even, lg, SPLIT_LOG);
  }
  cut[CASCADES] = far;

  // the light's own frame, from the world origin: x, y across its rays, -z along them
  const up = if (@abs(toward[1]) < m.NEAR_PARALLEL) m.v3(0, 1, 0) else m.v3(1, 0, 0);
  const view = m.lookAt(m.v3(0, 0, 0), -toward, up);
  var out:Fit = undefined;
  out.reach = far;
  for (0..CASCADES) |i| {
    // the slice's eight corners and a sphere round them
    var pts:[8]m.V3 = undefined;
    var mid = m.v3(0, 0, 0);
    for (0..4) |c| {
      pts[c] = eye + rays[c] * m.splat3(cut[i]);
      pts[c + 4] = eye + rays[c] * m.splat3(cut[i + 1]);
      mid += (pts[c] + pts[c + 4]) * m.splat3(1.0 / 8.0);
    }
    var r:f32 = 0;
    for (pts) |p| r = @max(r, m.len(p - mid));
    const step = @max(r * RADIUS_STEP, STEP_MIN);
    r = @ceil(r / step) * step;
    const texel = 2 * r / RES;
    // its centre seen from the light, snapped to whole texels
    const c4 = m.mulV(view, .{mid[0], mid[1], mid[2], 1});
    const cx = @floor(c4[0] / texel) * texel;
    const cy = @floor(c4[1] / texel) * texel;
    const proj = m.ortho(cx - r, cx + r, cy - r, cy + r, -c4[2] - r - CASTER_REACH, -c4[2] + r);
    out.mats[i] = m.mul(proj, view);
    out.texel[i] = texel;
  }
  return out;
}

fn unproject(inv:m.M4, x:f32, y:f32, z:f32) m.V3 {
  const p = m.mulV(inv, .{x, y, z, 1});
  return m.v3(p[0], p[1], p[2]) * m.splat3(1 / p[3]);
}

/// the shadow map: a depth layer per cascade, drawn into by the caster
/// passes and read by the world shaders through one descriptor set
pub const Shadow = struct {
  image:vk.Image = .null_handle,
  mem:vk.DeviceMemory = .null_handle,
  /// every layer, as one array (drawn into and read)
  view:vk.ImageView = .null_handle,
  sampler:vk.Sampler = .null_handle,
  set_layout:vk.DescriptorSetLayout = .null_handle,
  pool:vk.DescriptorPool = .null_handle,
  set:vk.DescriptorSet = undefined,

  pub fn init(c:*const Ctx) ctx.Error!Shadow {
    var s:Shadow = .{};
    s.create(c) catch |e| {
      s.deinit(c);
      return ctx.fold(e);
    };
    return s;
  }

  fn create(s:*Shadow, c:*const Ctx) !void {
    s.image = try c.device.createImage(&.{
      .image_type = .@"2d",
      .format = FORMAT,
      .extent = .{.width = RES, .height = RES, .depth = 1},
      .mip_levels = 1,
      .array_layers = CASCADES,
      .samples = .{.@"1" = true},
      .tiling = .optimal,
      .usage = .{.depth_stencil_attachment = true, .sampled = true},
      .sharing_mode = .exclusive,
      .initial_layout = .undefined,
    }, null);
    const req = c.device.getImageMemoryRequirements(s.image);
    s.mem = try c.device.allocateMemory(&.{
      .allocation_size = req.size,
      .memory_type_index = try c.memType(req.memory_type_bits, .{.device_local = true}),
    }, null);
    try c.device.bindImageMemory(s.image, s.mem, 0);
    s.view = try c.device.createImageView(&.{
      .image = s.image,
      .view_type = .@"2d_array",
      .format = FORMAT,
      .components = .{.r = .identity, .g = .identity, .b = .identity, .a = .identity},
      .subresource_range = layers(),
    }, null);
    // a compare sampler: each tap answers how much of its 2x2 texels are lit;
    // outside the map everything is
    s.sampler = try c.device.createSampler(&.{
      .mag_filter = .linear, .min_filter = .linear, .mipmap_mode = .nearest,
      .address_mode_u = .clamp_to_border, .address_mode_v = .clamp_to_border, .address_mode_w = .clamp_to_edge,
      .mip_lod_bias = 0, .anisotropy_enable = .false, .max_anisotropy = 1,
      .compare_enable = .true, .compare_op = .less_or_equal, .min_lod = 0, .max_lod = 0,
      .border_color = .float_opaque_white, .unnormalized_coordinates = .false,
    }, null);
    const bindings = [_]vk.DescriptorSetLayoutBinding{
      .{.binding = 0, .descriptor_type = .combined_image_sampler, .descriptor_count = 1, .stage_flags = .{.vertex = true, .fragment = true}},
    };
    s.set_layout = try c.device.createDescriptorSetLayout(&.{.binding_count = bindings.len, .p_bindings = &bindings}, null);
    const sizes = [_]vk.DescriptorPoolSize{.{.type = .combined_image_sampler, .descriptor_count = 1}};
    s.pool = try c.device.createDescriptorPool(&.{.max_sets = 1, .pool_size_count = sizes.len, .p_pool_sizes = &sizes}, null);
    try c.device.allocateDescriptorSets(&.{.descriptor_pool = s.pool, .descriptor_set_count = 1, .p_set_layouts = @ptrCast(&s.set_layout)}, @ptrCast(&s.set));
    const info = [_]vk.DescriptorImageInfo{.{.sampler = s.sampler, .image_view = s.view, .image_layout = .shader_read_only_optimal}};
    const writes = [_]vk.WriteDescriptorSet{
      .{.dst_set = s.set, .dst_binding = 0, .dst_array_element = 0, .descriptor_count = 1, .descriptor_type = .combined_image_sampler, .p_image_info = &info, .p_buffer_info = undefined, .p_texel_buffer_view = undefined},
    };
    c.device.updateDescriptorSets(&writes, null);
  }

  pub fn deinit(s:*Shadow, c:*const Ctx) void {
    c.device.destroyDescriptorPool(s.pool, null);
    c.device.destroyDescriptorSetLayout(s.set_layout, null);
    c.device.destroySampler(s.sampler, null);
    c.device.destroyImageView(s.view, null);
    c.device.destroyImage(s.image, null);
    c.device.freeMemory(s.mem, null);
    s.* = .{};
  }

  /// open the casters' scope: every layer cleared, one view per cascade.
  /// (What earlier frames read of it is done first: a barrier waits on
  /// every command before it in the queue.)
  pub fn begin(s:*const Shadow, cmd:vk.CommandBufferProxy) void {
    barrier(cmd, s.image, .undefined, .depth_attachment_optimal,
      .{.fragment_shader = true}, .{},
      .{.early_fragment_tests = true, .late_fragment_tests = true}, .{.depth_stencil_attachment_write = true, .depth_stencil_attachment_read = true});
    const depth:vk.RenderingAttachmentInfo = .{
      .image_view = s.view,
      .image_layout = .depth_attachment_optimal,
      .resolve_mode = .{},
      .resolve_image_layout = .undefined,
      .load_op = .clear,
      .store_op = .store,
      .clear_value = .{.depth_stencil = .{.depth = 1, .stencil = 0}},
    };
    const area:vk.Rect2D = .{.offset = .{.x = 0, .y = 0}, .extent = .{.width = RES, .height = RES}};
    cmd.beginRendering(&.{
      .render_area = area,
      .layer_count = 1,
      .view_mask = VIEWS,
      .color_attachment_count = 0,
      .p_color_attachments = null,
      .p_depth_attachment = &depth,
    });
    cmd.setViewport(0, &.{.{.x = 0, .y = 0, .width = RES, .height = RES, .min_depth = 0, .max_depth = 1}});
    cmd.setScissor(0, &.{area});
  }

  /// close it and hand the map to the world's fragment shaders
  pub fn end(s:*const Shadow, cmd:vk.CommandBufferProxy) void {
    cmd.endRendering();
    barrier(cmd, s.image, .depth_attachment_optimal, .shader_read_only_optimal,
      .{.late_fragment_tests = true}, .{.depth_stencil_attachment_write = true},
      .{.fragment_shader = true}, .{.shader_sampled_read = true});
  }
};

fn layers() vk.ImageSubresourceRange {
  return .{.aspect_mask = .{.depth = true}, .base_mip_level = 0, .level_count = 1, .base_array_layer = 0, .layer_count = CASCADES};
}

fn barrier(cmd:vk.CommandBufferProxy, image:vk.Image, old:vk.ImageLayout, new:vk.ImageLayout, src_stage:vk.PipelineStageFlags2, src_access:vk.AccessFlags2, dst_stage:vk.PipelineStageFlags2, dst_access:vk.AccessFlags2) void {
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
    .subresource_range = layers(),
  }};
  cmd.pipelineBarrier2(&.{.image_memory_barrier_count = b.len, .p_image_memory_barriers = &b});
}

const testing = std.testing;

test "cascades cover what the camera sees, nearest first, and hold still as it pans" {
  const toward = m.norm(m.v3(0.4, 0.8, 0.35));
  const at = m.v3(10, 0, 4);
  const eye = at + m.v3(0, 26, 18);
  const vp = m.mul(m.perspective(0.6, 16.0 / 9.0, 0.1, 300), m.lookAt(eye, at, m.v3(0, 1, 0)));
  const a = fit(vp, eye, at, 120, toward);
  // the point looked at lies in the first cascade or the second
  const q = m.mulV(a.mats[0], .{at[0], at[1], at[2], 1});
  const q1 = m.mulV(a.mats[1], .{at[0], at[1], at[2], 1});
  try testing.expect((@abs(q[0]) < 1 and @abs(q[1]) < 1) or (@abs(q1[0]) < 1 and @abs(q1[1]) < 1));
  for (0..CASCADES - 1) |i| try testing.expect(a.texel[i] <= a.texel[i + 1]);
  // panning keeps the texel grid where it was in the world: a point lands
  // a whole number of texels from where it did
  const shift = m.v3(3.7, 0, -1.3);
  const b = fit(m.mul(vp, m.translate(-shift)), eye + shift, at + shift, 120, toward);
  for (0..CASCADES) |i| {
    try testing.expectApproxEqAbs(a.texel[i], b.texel[i], 1e-5);
    const pa = m.mulV(a.mats[i], .{at[0], at[1], at[2], 1});
    const pb = m.mulV(b.mats[i], .{at[0], at[1], at[2], 1});
    inline for (0..2) |k| {
      const texels = (pa[k] - pb[k]) * RES / 2;
      try testing.expect(@abs(texels - @round(texels)) < 0.05);
    }
  }
}
