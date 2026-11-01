//! the air between the eye and what it sees: volumes a game raymarches on
//! the GPU from the world's depth (mist, haze, light falling through them).
//!
//! Two images of its own: the overhead map, which the game's `.overhead`
//! passes draw from straight above before the world, and the volume, which
//! its `.volume` passes draw at half the screen's size after the world, one
//! texel for every 2x2 pixels, reading the world's depth (the depth of the
//! texel's top-left pixel) and the overhead map through set 1 of the world
//! layout. A volume texel holds the light the air sends toward the eye (rgb)
//! and how much of what lies behind it still shows through (a). The
//! composite then lays it over the HDR image, each pixel taking the four
//! volume texels round it weighted by how near their depth is to its own,
//! so the half-size volume keeps the world's edges. Everything here runs on
//! the GPU; the CPU only records it.
//!
//! The overhead map is fixed to the world and wraps: one texel a world
//! unit, `overheadSize` units across, world (x, z) at uv (x, -z) /
//! `overheadSize` (read through a repeating sampler; volume.glsl
//! `overheadUv`). It is kept from frame to frame, so the game redraws a few
//! of its pieces each frame (each chunk of ground in its turn) instead of
//! all of it, and never because the view moved; what is drawn into one
//! place stays until something else lands there, `overheadSize` away.
/// the standard library, for its test helpers
const std=@import("std");
/// the Vulkan bindings: images, samplers, descriptors, pipelines
const vk=@import("vulkan");
/// the engine's maths, for sizes
const m=@import("../core/math.zig");
/// the Vulkan context and its error fold
const ctx=@import("../gfx/ctx.zig");
/// the device context everything here is made on
const Ctx=ctx.Ctx;
/// pipeline construction, for the composite
const pipeline=@import("../gfx/pipeline.zig");
/// the swapchain module: depth ranges and image barriers
const sw=@import("../gfx/swapchain.zig");
/// the post chain: its image type and colour ranges
const post=@import("post.zig");
/// one image with its memory and views
const Image=post.Image;
/// what the volume and the overhead map are drawn in: 16-bit float rgba
pub const format=post.hdrFormat;
/// texels along each side of the overhead map, one a world unit
pub const overheadRes=512;
/// how far across the overhead map reaches before it wraps (world units;
/// volume.glsl OVERHEAD_SIZE)
pub const overheadSize:f32=overheadRes;
/// how high above and how far below the ground's zero the overhead map sees
const overheadTop:f32=64;
/// (how far below)
const overheadBottom:f32=-16;
/// world to the overhead map's clip space for what lies in the square from
/// `at` (x, z) `overheadSize` along each way (its corner a whole number of
/// `overheadSize`s from the world's origin, so every square lands on the
/// whole map): a draw of anything within one, pushed as its `vp`
pub fn overheadOf(at:m.Vice(f32,2))m.M4{
  // the square's corner: `at` floored to whole squares
  const cx=@floor(at[0]/overheadSize)*overheadSize;
  const cz=@floor(at[1]/overheadSize)*overheadSize;
  // its half width and centre
  const h=overheadSize/2;
  const mid=m.v3(cx+h,0,cz+h);
  // looking straight down from over the centre
  const view=m.lookAt(mid+m.v3(0,overheadTop,0),mid,m.v3(0,0,-1));
  return m.mul(m.ortho(-h,h,-h,h,0,overheadTop-overheadBottom),view);
}
/// the air's images, their sets and the composite that lays the volume over
/// the world
pub const Volume=struct{
  /// the volume at half the screen's size: rgb the light the air sends to
  /// the eye, a how much of what lies behind shows through
  fog:Image=.{},
  /// the overhead map: what the game's overhead passes draw, seen from above
  overhead:Image=.{},
  /// reads the depth texel by texel
  nearest:vk.Sampler=.null_handle,
  /// reads the overhead map smoothly, wrapping round
  linear:vk.Sampler=.null_handle,
  /// whether the overhead map holds anything yet (its first scope clears it)
  drawn:bool=false,
  /// set 1 of the world layout: the world's depth and the overhead map
  setLayout:vk.DescriptorSetLayout=.null_handle,
  /// the composite's set layout: the volume and the world's depth
  composeLayout:vk.DescriptorSetLayout=.null_handle,
  /// the pool both sets come from
  pool:vk.DescriptorPool=.null_handle,
  /// (the volume passes' set)
  set:vk.DescriptorSet=undefined,
  /// (the composite's set)
  composeSet:vk.DescriptorSet=undefined,
  /// the composite's pipeline layout: its one set, no push constants
  layout:vk.PipelineLayout=.null_handle,
  /// the composite: the volume laid over the HDR image
  pipe:vk.Pipeline=.null_handle,
  /// make the air's images, sets and composite for a `w`×`h` screen whose
  /// depth `depth` the volume reads; anything half made is freed on failure
  pub fn init(c:*const Ctx,w:u32,h:u32,depth:vk.ImageView)ctx.Error!Volume{
    // the air being made
    var v:Volume=.{};
    v.create(c,w,h,depth)catch|e|{
      v.deinit(c);
      return ctx.fold(e);
    };
    return v;
  }
  /// the steps of `init`: samplers, set layouts, sets, the composite, images
  fn create(v:*Volume,c:*const Ctx,w:u32,h:u32,depth:vk.ImageView)!void{
    v.nearest=try c.device.createSampler(&sampler(.nearest,.clamp_to_edge),null);
    v.linear=try c.device.createSampler(&sampler(.linear,.repeat),null);
    // two images, read by the fragment shader (the overhead map by the vertex too)
    const bindings=[_]vk.DescriptorSetLayoutBinding{
      .{.binding=0,.descriptor_type=.combined_image_sampler,.descriptor_count=1,.stage_flags=.{.vertex=true,.fragment=true}},
      .{.binding=1,.descriptor_type=.combined_image_sampler,.descriptor_count=1,.stage_flags=.{.vertex=true,.fragment=true}},
    };
    v.setLayout=try c.device.createDescriptorSetLayout(&.{.binding_count=bindings.len,.p_bindings=&bindings},null);
    v.composeLayout=try c.device.createDescriptorSetLayout(&.{.binding_count=bindings.len,.p_bindings=&bindings},null);
    // room for both sets' two images
    const sizes=[_]vk.DescriptorPoolSize{.{.type=.combined_image_sampler,.descriptor_count=4}};
    v.pool=try c.device.createDescriptorPool(&.{.max_sets=2,.pool_size_count=sizes.len,.p_pool_sizes=&sizes},null);
    // the two sets' layouts, and the sets made from them
    const layouts=[_]vk.DescriptorSetLayout{v.setLayout,v.composeLayout};
    var sets:[2]vk.DescriptorSet=undefined;
    try c.device.allocateDescriptorSets(&.{.descriptor_pool=v.pool,.descriptor_set_count=sets.len,.p_set_layouts=&layouts},&sets);
    v.set=sets[0];
    v.composeSet=sets[1];
    v.layout=try c.device.createPipelineLayout(&.{.set_layout_count=1,.p_set_layouts=@ptrCast(&v.composeLayout),.push_constant_range_count=0,.p_push_constant_ranges=null},null);
    // the shared full-screen vertex shader and the composite's own
    const vs=try c.shader(@embedFile("post.vert"));
    defer c.device.destroyShaderModule(vs,null);
    const fs=try c.shader(@embedFile("volume_compose.frag"));
    defer c.device.destroyShaderModule(fs,null);
    v.pipe=try pipeline.create(c,.{
      .vert=vs,.frag=fs,.bindings=&.{},.attrs=&.{},
      .layout=v.layout,.colorFormat=post.hdrFormat,
      .depth=false,.depthAttachment=false,.blend=true,.premultiplied=true,.cull=false,
    });
    v.overhead=try Image.init(c,overheadRes,overheadRes,.{.format=format});
    try v.images(c,w,h,depth);
  }
  /// a sampler filtering `filter`, addressing past the edges by `edge`
  fn sampler(filter:vk.Filter,edge:vk.SamplerAddressMode)vk.SamplerCreateInfo{
    return.{
      .mag_filter=filter,.min_filter=filter,.mipmap_mode=.nearest,
      .address_mode_u=edge,.address_mode_v=edge,.address_mode_w=edge,
      .mip_lod_bias=0,.anisotropy_enable=.false,.max_anisotropy=1,
      .compare_enable=.false,.compare_op=.always,.min_lod=0,.max_lod=0,
      .border_color=.float_transparent_black,.unnormalized_coordinates=.false,
    };
  }
  /// (re)make the volume for a `w`×`h` screen whose depth is now `depth`,
  /// and point both sets at the images. The device must be idle.
  pub fn resize(v:*Volume,c:*const Ctx,w:u32,h:u32,depth:vk.ImageView)ctx.Error!void{
    v.images(c,w,h,depth)catch|e|return ctx.fold(e);
  }
  /// the volume's image for `w`×`h`, and both sets pointed at what they read
  fn images(v:*Volume,c:*const Ctx,w:u32,h:u32,depth:vk.ImageView)!void{
    v.fog.deinit(c);
    v.fog=try Image.init(c,half(w),half(h),.{.format=format});
    v.point(c,v.set,.{.{v.nearest,depth},.{v.linear,v.overhead.views[0]}});
    v.point(c,v.composeSet,.{.{v.nearest,v.fog.views[0]},.{v.nearest,depth}});
  }
  /// point `set`'s two bindings at the two (sampler, view) pairs `to`
  fn point(_:*const Volume,c:*const Ctx,set:vk.DescriptorSet,to:[2]struct{vk.Sampler,vk.ImageView})void{
    // the two images, each read through its sampler
    var infos:[2]vk.DescriptorImageInfo=undefined;
    for(&infos,to)|*i,t|i.*=.{.sampler=t[0],.image_view=t[1],.image_layout=.shader_read_only_optimal};
    // the writes that point the bindings there
    var writes:[2]vk.WriteDescriptorSet=undefined;
    for(&writes,0..)|*wr,b|wr.*=.{.dst_set=set,.dst_binding=@intCast(b),.dst_array_element=0,.descriptor_count=1,.descriptor_type=.combined_image_sampler,.p_image_info=@ptrCast(&infos[b]),.p_buffer_info=undefined,.p_texel_buffer_view=undefined};
    c.device.updateDescriptorSets(&writes,null);
  }
  /// free everything the air holds and leave it empty (safe when empty)
  pub fn deinit(v:*Volume,c:*const Ctx)void{
    v.fog.deinit(c);
    v.overhead.deinit(c);
    c.device.destroyPipeline(v.pipe,null);
    c.device.destroyPipelineLayout(v.layout,null);
    c.device.destroyDescriptorPool(v.pool,null);
    c.device.destroyDescriptorSetLayout(v.setLayout,null);
    c.device.destroyDescriptorSetLayout(v.composeLayout,null);
    c.device.destroySampler(v.nearest,null);
    c.device.destroySampler(v.linear,null);
    v.*=.{};
  }
  /// open the overhead passes' scope: the map as earlier frames left it
  /// (cleared to black, alpha 1, the first time). What they read of it is
  /// done first.
  pub fn beginOverhead(v:*Volume,cmd:vk.CommandBufferProxy)void{
    sw.barrier(cmd,v.overhead.image,post.range(0),if(v.drawn).shader_read_only_optimal else.undefined,.color_attachment_optimal,.{.fragment_shader=true,.vertex_shader=true},.{.shader_sampled_read=true},.{.color_attachment_output=true},.{.color_attachment_write=true,.color_attachment_read=true});
    scope(cmd,v.overhead.views[0],v.overhead.extent,if(v.drawn).load else.clear);
    v.drawn=true;
  }
  /// close it and hand the map to the shaders that read it
  pub fn endOverhead(v:*const Volume,cmd:vk.CommandBufferProxy)void{
    cmd.endRendering();
    sw.barrier(cmd,v.overhead.image,post.range(0),.color_attachment_optimal,.shader_read_only_optimal,.{.color_attachment_output=true},.{.color_attachment_write=true},.{.fragment_shader=true,.vertex_shader=true},.{.shader_sampled_read=true});
  }
  /// after the world: its depth `depth` handed to the shaders, and the
  /// volume passes' scope opened, the volume cleared to clear air (nothing
  /// sent, everything showing through)
  pub fn beginVolume(v:*const Volume,cmd:vk.CommandBufferProxy,depth:vk.Image)void{
    sw.barrier(cmd,depth,sw.depthRange(),.depth_attachment_optimal,.shader_read_only_optimal,
      .{.late_fragment_tests=true,.color_attachment_output=true},.{.depth_stencil_attachment_write=true,.color_attachment_write=true},
      .{.fragment_shader=true},.{.shader_sampled_read=true});
    sw.barrier(cmd,v.fog.image,post.range(0),.undefined,.color_attachment_optimal,.{.fragment_shader=true},.{.shader_sampled_read=true},.{.color_attachment_output=true},.{.color_attachment_write=true});
    scope(cmd,v.fog.views[0],v.fog.extent,.clear);
  }
  /// close the volume passes' scope, then lay the volume over the world's
  /// HDR image `hdr` (left as a colour attachment)
  pub fn compose(v:*const Volume,cmd:vk.CommandBufferProxy,hdr:Image)void{
    cmd.endRendering();
    sw.barrier(cmd,v.fog.image,post.range(0),.color_attachment_optimal,.shader_read_only_optimal,.{.color_attachment_output=true},.{.color_attachment_write=true},.{.fragment_shader=true},.{.shader_sampled_read=true});
    // what the world wrote (or resolved) into it is done before it is blended over
    sw.barrier(cmd,hdr.image,post.range(0),.color_attachment_optimal,.color_attachment_optimal,.{.color_attachment_output=true},.{.color_attachment_write=true},.{.color_attachment_output=true},.{.color_attachment_write=true,.color_attachment_read=true});
    scope(cmd,hdr.views[0],hdr.extent,.load);
    cmd.bindPipeline(.graphics,v.pipe);
    cmd.bindDescriptorSets(.graphics,v.layout,0,&.{v.composeSet},null);
    cmd.draw(3,1,0,0);
    cmd.endRendering();
  }
};
/// half of `n` pixels, rounded up: the volume's size along a side
fn half(n:u32)u32{return @max((n+1)/2,1);}
/// the test helpers
const testing=std.testing;
test"the overhead map lands every square of the world on all of it, a texel a unit"{
  // a point, and the map's frame for the square it lies in
  const p=m.Vice(f32,2){-37.3,1012.6};
  const a=overheadOf(p);
  const q=m.mulV(a,.{p[0],0.5,p[1],1});
  try testing.expect(@abs(q[0])<=1 and @abs(q[1])<=1 and q[2]>0 and q[2]<1);
  // where it lands on the map (uv, rows counted down): (x, -z) / size, wrapped
  const u=q[0]*0.5+0.5;
  const v=q[1]*0.5+0.5;
  try testing.expectApproxEqAbs(u,@mod(p[0]/overheadSize,1),1e-4);
  try testing.expectApproxEqAbs(v,@mod(-p[1]/overheadSize,1),1e-4);
  // a unit along x is one texel
  const r=m.mulV(a,.{p[0]+1,0.5,p[1],1});
  try testing.expectApproxEqAbs((r[0]-q[0])*overheadRes/2,1,1e-3);
}
/// begin rendering into all of `view` (`size`), its old contents kept or
/// cleared to clear air (black, alpha 1: wholly showing through); the
/// viewport and scissor set to match
fn scope(cmd:vk.CommandBufferProxy,view:vk.ImageView,size:vk.Extent2D,load:vk.AttachmentLoadOp)void{
  // the attachment drawn into
  const color=[_]vk.RenderingAttachmentInfo{.{
    .image_view=view,
    .image_layout=.color_attachment_optimal,
    .resolve_mode=.{},
    .resolve_image_layout=.undefined,
    .load_op=load,
    .store_op=.store,
    .clear_value=.{.color=.{.float_32=.{0,0,0,1}}},
  }};
  // the whole of the target
  const area:vk.Rect2D=.{.offset=.{.x=0,.y=0},.extent=size};
  cmd.beginRendering(&.{.render_area=area,.layer_count=1,.view_mask=0,.color_attachment_count=color.len,.p_color_attachments=&color});
  cmd.setViewport(0,&.{.{.x=0,.y=0,.width=m.f(size.width),.height=m.f(size.height),.min_depth=0,.max_depth=1}});
  cmd.setScissor(0,&.{area});
}
