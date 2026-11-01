//! graphics pipeline construction for dynamic rendering. Vertex layouts are
//! derived at comptime from plain extern structs, so a vertex type is the
//! single source of truth for its GPU layout.
/// the standard library
const std=@import("std");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=@import("../core/math.zig");
/// an all-zero value, for the stencil states nobody uses
const zeroes=std.mem.zeroes;
/// the Vulkan bindings: pipeline records, formats and flags
const vk=@import("vulkan");
/// the Vulkan context and its error fold
const ctx=@import("ctx.zig");
/// colour types, so an eight-bit rgba field gets its format
const color=@import("../core/color.zig");
/// the device context pipelines are made with
const Ctx=ctx.Ctx;
/// the swapchain, for the one depth format every pass shares
const swapchain=@import("swapchain.zig");
/// the Vulkan format a vertex field of type `T` is read as; a type with
/// none is a compile error
fn formatOf(comptime T:type)vk.Format{
  return switch(T){
    f32=>.r32_sfloat,
    m.Vice(f32,2)=>.r32g32_sfloat,
    m.Vice(f32,3)=>.r32g32b32_sfloat,
    m.Vice(f32,4)=>.r32g32b32a32_sfloat,
    u32=>.r32_uint,
    m.Vice(u32,2)=>.r32g32_uint,
    m.Vice(u8,4),color.Rgba8=>.r8g8b8a8_unorm,
    else=>@compileError("no vertex format for "++@typeName(T)),
  };
}
/// one attribute per field of `T`, read from binding `bind`, locations
/// counting up from `first` in field order (the shader's `location`s)
pub fn attrs(comptime T:type,comptime bind:u32,comptime first:u32)[@typeInfo(T).@"struct".fields.len]vk.VertexInputAttributeDescription{
  // the vertex struct's fields, in order
  const fields=@typeInfo(T).@"struct".fields;
  // one attribute description per field
  var out:[fields.len]vk.VertexInputAttributeDescription=undefined;
  inline for(fields,0..)|f,i|out[i]=.{
    .location=first+i,
    .binding=bind,
    .format=formatOf(f.type),
    .offset=@offsetOf(T,f.name),
  };
  return out;
}
/// how one vertex buffer binding of `T` steps: binding `b`, a `T` per
/// vertex or per instance (`rate`)
pub fn binding(comptime T:type,comptime b:u32,rate:vk.VertexInputRate)vk.VertexInputBindingDescription{
  return.{.binding=b,.stride=@sizeOf(T),.input_rate=rate};
}
/// what a pipeline is made of: its two shaders, vertex layout, push layout
/// and the depth, blend, cull and sample choices it draws with
pub const Desc=struct{
  /// the vertex shader
  vert:vk.ShaderModule,
  /// the fragment shader
  frag:vk.ShaderModule,
  /// the vertex buffers it reads and how each steps
  bindings:[]const vk.VertexInputBindingDescription,
  /// the fields it reads from them, by location
  attrs:[]const vk.VertexInputAttributeDescription,
  /// the push constant and descriptor layout it is drawn with
  layout:vk.PipelineLayout,
  /// `.undefined`: no colour attachment (depth only, a shadow map)
  colorFormat:vk.Format,
  /// whether it tests depth at all
  depth:bool=true,
  /// with `depth`: whether it writes depth too (see-through surfaces only test it)
  depthWrite:bool=true,
  /// with `depth`: what passes it (`.less`: only what lies nearer than
  /// anything drawn there yet)
  depthCompare:vk.CompareOp=.less_or_equal,
  /// whether the rendering scope it draws in has a depth attachment
  depthAttachment:bool=true,
  /// whether it blends over what is there by its alpha (see-through things)
  blend:bool=false,
  /// with `blend`: add onto what is there instead of blending over it
  additive:bool=false,
  /// with `blend`: what it draws is already weighted by its alpha (colour
  /// added on, what is there kept by one minus its alpha: a veil over it)
  premultiplied:bool=false,
  /// whether back faces are culled
  cull:bool=true,
  /// samples per pixel of the attachments it draws into (MSAA)
  samples:vk.SampleCountFlags=.{.@"1"=true},
  /// with several samples: run the fragment shader for each one (where a
  /// shader, not the geometry, decides what a fragment draws), if the GPU can
  perSample:bool=false,
  /// with several views (multiview), one bit each: one draw renders into
  /// every layer they name
  viewMask:u32=0,
  /// pushes depth away by a constant and with the slope (shadow casters)
  depthBias:?m.Vice(f32,2)=null,
};
/// `sets`: descriptor set layouts the pipelines also bind (0..)
/// a pipeline layout with one push constant range of `pushSize` bytes, seen
/// by both stages; `NoSuitableGpu` when the GPU cannot push that much
pub fn layout(c:*const Ctx,pushSize:u32,sets:[]const vk.DescriptorSetLayout)ctx.Error!vk.PipelineLayout{
  // 128 bytes is all Vulkan guarantees; desktop GPUs offer 256
  if(pushSize>c.props.limits.max_push_constants_size)return error.NoSuitableGpu;
  // the one push constant range, shared by vertex and fragment
  const range=[_]vk.PushConstantRange{.{
    .stage_flags=.{.vertex=true,.fragment=true},
    .offset=0,
    .size=pushSize,
  }};
  return c.device.createPipelineLayout(&.{
    .set_layout_count=@intCast(sets.len),.p_set_layouts=sets.ptr,
    .push_constant_range_count=1,.p_push_constant_ranges=&range,
  },null)catch|e|ctx.fold(e);
}
/// a graphics pipeline for dynamic rendering from `d`: triangle lists,
/// viewport and scissor set at draw time
pub fn create(c:*const Ctx,d:Desc)ctx.Error!vk.Pipeline{
  // the two shader stages, both entered at `main`
  const stages=[_]vk.PipelineShaderStageCreateInfo{
    .{.stage=.{.vertex=true},.module=d.vert,.p_name="main"},
    .{.stage=.{.fragment=true},.module=d.frag,.p_name="main"},
  };
  // the vertex layout: bindings and attributes (none for a full-screen pass)
  const vin:vk.PipelineVertexInputStateCreateInfo=.{
    .vertex_binding_description_count=@intCast(d.bindings.len),
    .p_vertex_binding_descriptions=if(d.bindings.len>0)d.bindings.ptr else null,
    .vertex_attribute_description_count=@intCast(d.attrs.len),
    .p_vertex_attribute_descriptions=if(d.attrs.len>0)d.attrs.ptr else null,
  };
  // plain triangle lists
  const ia:vk.PipelineInputAssemblyStateCreateInfo=.{.topology=.triangle_list,.primitive_restart_enable=.false};
  // one viewport and scissor, both set while drawing
  const vp:vk.PipelineViewportStateCreateInfo=.{.viewport_count=1,.scissor_count=1};
  // filled, counter-clockwise front faces, back faces culled if asked, depth bias for casters
  const rs:vk.PipelineRasterizationStateCreateInfo=.{
    .depth_clamp_enable=.false,
    .rasterizer_discard_enable=.false,
    .polygon_mode=.fill,
    .cull_mode=if(d.cull).{.back=true}else.{},
    .front_face=.counter_clockwise,
    .depth_bias_enable=if(d.depthBias!=null).true else.false,
    .depth_bias_constant_factor=if(d.depthBias)|b|b[0]else 0,
    .depth_bias_clamp=0,
    .depth_bias_slope_factor=if(d.depthBias)|b|b[1]else 0,
    .line_width=1,
  };
  // the samples per pixel, and whether each one is shaded
  const ms:vk.PipelineMultisampleStateCreateInfo=.{
    .rasterization_samples=d.samples,
    .sample_shading_enable=if(d.perSample and c.sampleShading and !d.samples.@"1").true else.false,
    .min_sample_shading=1,
    .alpha_to_coverage_enable=.false,
    .alpha_to_one_enable=.false,
  };
  // the depth test and write; no stencil
  const ds:vk.PipelineDepthStencilStateCreateInfo=.{
    .depth_test_enable=if(d.depth).true else.false,
    .depth_write_enable=if(d.depth and d.depthWrite).true else.false,
    .depth_compare_op=d.depthCompare,
    .depth_bounds_test_enable=.false,
    .stencil_test_enable=.false,
    .front=zeroes(vk.StencilOpState),
    .back=zeroes(vk.StencilOpState),
    .min_depth_bounds=0,
    .max_depth_bounds=1,
  };
  // how the one colour attachment blends: alpha over, or added on
  const att=[_]vk.PipelineColorBlendAttachmentState{.{
    .blend_enable=if(d.blend).true else.false,
    .src_color_blend_factor=if(d.additive or d.premultiplied).one else.src_alpha,
    .dst_color_blend_factor=if(d.additive).one else.one_minus_src_alpha,
    .color_blend_op=.add,
    .src_alpha_blend_factor=.one,
    .dst_alpha_blend_factor=.one_minus_src_alpha,
    .alpha_blend_op=.add,
    .color_write_mask=.{.r=true,.g=true,.b=true,.a=true},
  }};
  // whether it draws colour at all (a depth-only pass does not)
  const colour=d.colorFormat!=.undefined;
  // the blend state over that attachment
  const cb:vk.PipelineColorBlendStateCreateInfo=.{
    .logic_op_enable=.false,
    .logic_op=.copy,
    .attachment_count=if(colour)1 else 0,
    .p_attachments=&att,
    .blend_constants=.{0,0,0,0},
  };
  // the states set while drawing: viewport and scissor
  const dyn=[_]vk.DynamicState{.viewport,.scissor};
  // that list, as the pipeline record wants it
  const dy:vk.PipelineDynamicStateCreateInfo=.{.dynamic_state_count=dyn.len,.p_dynamic_states=&dyn};
  // the colour attachment's format
  const fmts=[_]vk.Format{d.colorFormat};
  // what it renders into: views, colour format, the shared depth format
  const rendering:vk.PipelineRenderingCreateInfo=.{
    .view_mask=d.viewMask,
    .color_attachment_count=if(colour)1 else 0,
    .p_color_attachment_formats=&fmts,
    .depth_attachment_format=if(d.depthAttachment)swapchain.depthFormat else.undefined,
    .stencil_attachment_format=.undefined,
  };
  // the made pipeline
  var p:vk.Pipeline=undefined;
  _=c.device.createGraphicsPipelines(.null_handle,&.{.{
    .p_next=&rendering,
    .stage_count=stages.len,
    .p_stages=&stages,
    .p_vertex_input_state=&vin,
    .p_input_assembly_state=&ia,
    .p_viewport_state=&vp,
    .p_rasterization_state=&rs,
    .p_multisample_state=&ms,
    .p_depth_stencil_state=&ds,
    .p_color_blend_state=&cb,
    .p_dynamic_state=&dy,
    .layout=d.layout,
    .subpass=0,
    .base_pipeline_index=-1,
  }},null,@ptrCast(&p))catch|e|return ctx.fold(e);
  return p;
}
