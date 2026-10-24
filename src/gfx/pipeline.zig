//! graphics pipeline construction for dynamic rendering. Vertex layouts are
//! derived at comptime from plain extern structs, so a vertex type is the
//! single source of truth for its GPU layout.
const std = @import("std");
const zeroes = std.mem.zeroes;
const vk = @import("vulkan");
const ctx = @import("ctx.zig");
const color = @import("../core/color.zig");
const Ctx = ctx.Ctx;
const swapchain = @import("swapchain.zig");

fn formatOf(comptime T:type) vk.Format {
  return switch (T) {
    f32 => .r32_sfloat,
    [2]f32 => .r32g32_sfloat,
    [3]f32 => .r32g32b32_sfloat,
    [4]f32 => .r32g32b32a32_sfloat,
    u32 => .r32_uint,
    [2]u32 => .r32g32_uint,
    [4]u8, color.Rgba8 => .r8g8b8a8_unorm,
    else => @compileError("no vertex format for " ++ @typeName(T)),
  };
}

/// one attribute per field of `T`, locations starting at `first`.
pub fn attrs(comptime T:type, comptime bind:u32, comptime first:u32) [@typeInfo(T).@"struct".fields.len]vk.VertexInputAttributeDescription {
  const fields = @typeInfo(T).@"struct".fields;
  var out:[fields.len]vk.VertexInputAttributeDescription = undefined;
  inline for (fields, 0..) |f, i| out[i] = .{
    .location = first + i,
    .binding = bind,
    .format = formatOf(f.type),
    .offset = @offsetOf(T, f.name),
  };
  return out;
}

pub fn binding(comptime T:type, comptime b:u32, rate:vk.VertexInputRate) vk.VertexInputBindingDescription {
  return .{.binding = b, .stride = @sizeOf(T), .input_rate = rate};
}

pub const Desc = struct {
  vert:vk.ShaderModule,
  frag:vk.ShaderModule,
  bindings:[]const vk.VertexInputBindingDescription,
  attrs:[]const vk.VertexInputAttributeDescription,
  layout:vk.PipelineLayout,
  color_format:vk.Format,
  depth:bool = true,
  /// with `depth`: whether it writes depth too (see-through surfaces only test it)
  depth_write:bool = true,
  /// whether the rendering scope it draws in has a depth attachment
  depth_attachment:bool = true,
  blend:bool = false,
  /// with `blend`: add onto what is there instead of blending over it
  additive:bool = false,
  cull:bool = true,
  /// samples per pixel of the attachments it draws into (MSAA)
  samples:vk.SampleCountFlags = .{.@"1" = true},
  /// with several samples: run the fragment shader for each one (where a
  /// shader, not the geometry, decides what a fragment draws), if the GPU can
  per_sample:bool = false,
};

pub fn layout(c:*const Ctx, push_size:u32) ctx.Error!vk.PipelineLayout {
  // 128 bytes is all Vulkan guarantees; desktop GPUs offer 256
  if (push_size > c.props.limits.max_push_constants_size) return error.NoSuitableGpu;
  const range = [_]vk.PushConstantRange{.{
    .stage_flags = .{.vertex = true, .fragment = true},
    .offset = 0,
    .size = push_size,
  }};
  return c.device.createPipelineLayout(&.{.push_constant_range_count = 1, .p_push_constant_ranges = &range}, null) catch |e| ctx.fold(e);
}

pub fn create(c:*const Ctx, d:Desc) ctx.Error!vk.Pipeline {
  const stages = [_]vk.PipelineShaderStageCreateInfo{
    .{.stage = .{.vertex = true}, .module = d.vert, .p_name = "main"},
    .{.stage = .{.fragment = true}, .module = d.frag, .p_name = "main"},
  };
  const vin:vk.PipelineVertexInputStateCreateInfo = .{
    .vertex_binding_description_count = @intCast(d.bindings.len),
    .p_vertex_binding_descriptions = if (d.bindings.len > 0) d.bindings.ptr else null,
    .vertex_attribute_description_count = @intCast(d.attrs.len),
    .p_vertex_attribute_descriptions = if (d.attrs.len > 0) d.attrs.ptr else null,
  };
  const ia:vk.PipelineInputAssemblyStateCreateInfo = .{.topology = .triangle_list, .primitive_restart_enable = .false};
  const vp:vk.PipelineViewportStateCreateInfo = .{.viewport_count = 1, .scissor_count = 1};
  const rs:vk.PipelineRasterizationStateCreateInfo = .{
    .depth_clamp_enable = .false,
    .rasterizer_discard_enable = .false,
    .polygon_mode = .fill,
    .cull_mode = if (d.cull) .{.back = true} else .{},
    .front_face = .counter_clockwise,
    .depth_bias_enable = .false,
    .depth_bias_constant_factor = 0,
    .depth_bias_clamp = 0,
    .depth_bias_slope_factor = 0,
    .line_width = 1,
  };
  const ms:vk.PipelineMultisampleStateCreateInfo = .{
    .rasterization_samples = d.samples,
    .sample_shading_enable = if (d.per_sample and c.sample_shading and !d.samples.@"1") .true else .false,
    .min_sample_shading = 1,
    .alpha_to_coverage_enable = .false,
    .alpha_to_one_enable = .false,
  };
  const ds:vk.PipelineDepthStencilStateCreateInfo = .{
    .depth_test_enable = if (d.depth) .true else .false,
    .depth_write_enable = if (d.depth and d.depth_write) .true else .false,
    .depth_compare_op = .less_or_equal,
    .depth_bounds_test_enable = .false,
    .stencil_test_enable = .false,
    .front = zeroes(vk.StencilOpState),
    .back = zeroes(vk.StencilOpState),
    .min_depth_bounds = 0,
    .max_depth_bounds = 1,
  };
  const att = [_]vk.PipelineColorBlendAttachmentState{.{
    .blend_enable = if (d.blend) .true else .false,
    .src_color_blend_factor = if (d.additive) .one else .src_alpha,
    .dst_color_blend_factor = if (d.additive) .one else .one_minus_src_alpha,
    .color_blend_op = .add,
    .src_alpha_blend_factor = .one,
    .dst_alpha_blend_factor = .one_minus_src_alpha,
    .alpha_blend_op = .add,
    .color_write_mask = .{.r = true, .g = true, .b = true, .a = true},
  }};
  const cb:vk.PipelineColorBlendStateCreateInfo = .{
    .logic_op_enable = .false,
    .logic_op = .copy,
    .attachment_count = 1,
    .p_attachments = &att,
    .blend_constants = .{0, 0, 0, 0},
  };
  const dyn = [_]vk.DynamicState{.viewport, .scissor};
  const dy:vk.PipelineDynamicStateCreateInfo = .{.dynamic_state_count = dyn.len, .p_dynamic_states = &dyn};
  const fmts = [_]vk.Format{d.color_format};
  const rendering:vk.PipelineRenderingCreateInfo = .{
    .view_mask = 0,
    .color_attachment_count = 1,
    .p_color_attachment_formats = &fmts,
    .depth_attachment_format = if (d.depth_attachment) swapchain.depth_format else .undefined,
    .stencil_attachment_format = .undefined,
  };
  var p:vk.Pipeline = undefined;
  _ = c.device.createGraphicsPipelines(.null_handle, &.{.{
    .p_next = &rendering,
    .stage_count = stages.len,
    .p_stages = &stages,
    .p_vertex_input_state = &vin,
    .p_input_assembly_state = &ia,
    .p_viewport_state = &vp,
    .p_rasterization_state = &rs,
    .p_multisample_state = &ms,
    .p_depth_stencil_state = &ds,
    .p_color_blend_state = &cb,
    .p_dynamic_state = &dy,
    .layout = d.layout,
    .subpass = 0,
    .base_pipeline_index = -1,
  }}, null, @ptrCast(&p)) catch |e| return ctx.fold(e);
  return p;
}
