//! post-processing: light that bleeds, and smooth edges. The world is drawn
//! into an HDR image (`hdrFormat`) instead of straight to the screen. What
//! is brighter than white there (the celestial blooms and their beams, the
//! motes, glowing sap, ley crystals, highlights) is pulled out and blurred
//! through a chain of ever smaller images (each half the size of the last, a
//! 13-tap filter going down, a tent filter adding back up), then the
//! composite lays that glow over the scene and gently tone-maps it onto the
//! swapchain image, under the UI.
//!
//! Anti-aliasing (`Antialias`): with MSAA the world draws into multisampled
//! colour and depth images that resolve into the HDR image as the world's
//! scope ends; with FXAA the composite goes into an image of the screen's
//! format first and the FXAA pass filters it onto the screen. Everything
//! here runs on the GPU; the CPU only records it.
/// the standard library
const std=@import("std");
/// the allocator type (nothing here uses it yet)
const Allocator=std.mem.Allocator;
/// the Vulkan bindings: images, samplers, descriptors, pipelines
const vk=@import("vulkan");
/// the engine's maths, for turning sizes into texel steps
const m=@import("../core/math.zig");
/// the Vulkan context and its error fold
const ctx=@import("../gfx/ctx.zig");
/// the device context everything here is made on
const Ctx=ctx.Ctx;
/// pipeline construction, for the full-screen passes
const pipeline=@import("../gfx/pipeline.zig");
/// the swapchain module: the depth format, depth ranges and image barriers
const sw=@import("../gfx/swapchain.zig");
/// the world's HDR image format: 16-bit float rgba, room above white
pub const hdrFormat:vk.Format=.r16g16b16a16_sfloat;
/// levels in the blur chain, the first at half the screen's size
const levels=5;
/// how edges are smoothed: not at all, by FXAA on the finished image, or by
/// rendering the world with 2, 4 or 8 samples per pixel
pub const Antialias=enum{
  /// hard edges, nothing smoothed
  off,
  /// FXAA over the finished image, the world drawn once a pixel
  fxaa,
  /// the world drawn with 2 samples a pixel
  msaa2,
  /// the world drawn with 4 samples a pixel
  msaa4,
  /// the world drawn with 8 samples a pixel
  msaa8,
  /// how many samples per pixel the world draws with (1 without MSAA)
  pub fn samples(a:Antialias)u32{
    return switch(a){.off,.fxaa=>1,.msaa2=>2,.msaa4=>4,.msaa8=>8};
  }
  /// whether the FXAA pass runs
  pub fn filtered(a:Antialias)bool{return a==.fxaa;}
};
/// the sample-count flag for `n` samples (1, 2, 4 or 8)
pub fn sampleFlags(n:u32)vk.SampleCountFlags{
  return switch(n){
    1=>.{.@"1"=true},
    2=>.{.@"2"=true},
    4=>.{.@"4"=true},
    8=>.{.@"8"=true},
    else=>@panic("unsupported sample count"),
  };
}
/// how the glow is pulled out and laid back: brightness where it starts
/// (with a soft knee below it) and how strongly it is added
pub const Push=extern struct{
  /// one texel of the image being read
  texel:[2]f32,
  /// the brightness the glow starts at (0 on all but the first step down)
  threshold:f32=1.0,
  /// how strongly the glow is laid back over the scene
  intensity:f32=0.7,
};
/// what kind of image to make: format, mip levels, samples, depth or colour
pub const Spec=struct{
  /// its pixel format
  format:vk.Format=hdrFormat,
  /// how many mip levels (the blur chain's levels)
  levels:u32=1,
  /// samples per pixel
  samples:u32=1,
  /// a depth image instead of colour
  depth:bool=false,
  /// only ever drawn into within one scope (multisampled targets)
  transient:bool=false,
};
/// one image of the post chain, with a view per level and its size
pub const Image=struct{
  /// the Vulkan image
  image:vk.Image=.null_handle,
  /// the memory under it
  mem:vk.DeviceMemory=.null_handle,
  /// one view per level
  views:[levels]vk.ImageView=@splat(.null_handle),
  /// its full size, in pixels
  extent:vk.Extent2D=.{.width=0,.height=0},
  /// how many levels it has
  levels:u32=1,
  /// an image of `w`×`h` as `sp` describes, with its memory and views;
  /// freed again on failure
  pub fn init(c:*const Ctx,w:u32,h:u32,sp:Spec)!Image{
    // the image being made
    var im:Image=.{.extent=.{.width=w,.height=h},.levels=sp.levels};
    errdefer im.deinit(c);
    im.image=try c.device.createImage(&.{
      .image_type=.@"2d",
      .format=sp.format,
      .extent=.{.width=w,.height=h,.depth=1},
      .mip_levels=sp.levels,
      .array_layers=1,
      .samples=sampleFlags(sp.samples),
      .tiling=.optimal,
      .usage=.{
        .color_attachment=!sp.depth,.depth_stencil_attachment=sp.depth,
        .sampled=!sp.transient,.transient_attachment=sp.transient,
      },
      .sharing_mode=.exclusive,
      .initial_layout=.undefined,
    },null);
    im.mem=try c.imageMemory(im.image);
    for(0..sp.levels)|l|{
      im.views[l]=try c.device.createImageView(&.{
        .image=im.image,
        .view_type=.@"2d",
        .format=sp.format,
        .components=.{.r=.identity,.g=.identity,.b=.identity,.a=.identity},
        .subresource_range=if(sp.depth)sw.depthRange()else range(@intCast(l)),
      },null);
    }
    return im;
  }
  /// free its views, image and memory and leave it empty (safe when empty)
  pub fn deinit(im:*Image,c:*const Ctx)void{
    for(im.views)|v|c.device.destroyImageView(v,null);
    c.device.destroyImage(im.image,null);
    c.device.freeMemory(im.mem,null);
    im.*=.{};
  }
  /// the size of level `level`: halved per level, never under one pixel
  fn size(im:*const Image,level:u32)vk.Extent2D{
    return.{.width=@max(im.extent.width>>@intCast(level),1),.height=@max(im.extent.height>>@intCast(level),1)};
  }
};
/// one colour level of an image
pub fn range(level:u32)vk.ImageSubresourceRange{
  return.{.aspect_mask=.{.color=true},.base_mip_level=level,.level_count=1,.base_array_layer=0,.layer_count=1};
}
/// the post chain: the world's HDR image, MSAA and FXAA images, the blur
/// chain, and the full-screen passes that glow, tone-map and smooth it
pub const Post=struct{
  /// how edges are smoothed now
  aa:Antialias=.off,
  /// the swapchain's format (the composite's and FXAA's output)
  screen:vk.Format=.undefined,
  /// the world, drawn (or with MSAA resolved) at full size
  hdr:Image=.{},
  /// MSAA: the world's multisampled colour and depth, resolved into `hdr`
  ms:Image=.{},
  /// (the multisampled depth beside it)
  msDepth:Image=.{},
  /// FXAA: the composite, tone-mapped, which FXAA reads
  ldr:Image=.{},
  /// the blur chain
  bloom:Image=.{},
  /// the linear, edge-clamped sampler every pass reads through
  sampler:vk.Sampler=.null_handle,
  /// every set's layout: two images, read by the fragment shader
  setLayout:vk.DescriptorSetLayout=.null_handle,
  /// the pool every set comes from
  pool:vk.DescriptorPool=.null_handle,
  /// down[l] reads the level above (the HDR image for l = 0); up[l] reads
  /// level l + 1; composite reads the HDR image and the first level; fxaa
  /// reads the composite
  down:[levels]vk.DescriptorSet=undefined,
  /// (the up sets)
  up:[levels-1]vk.DescriptorSet=undefined,
  /// (the composite's set)
  composite:vk.DescriptorSet=undefined,
  /// (FXAA's set)
  fxaa:vk.DescriptorSet=undefined,
  /// the layout every post pipeline shares: one set and `Push`
  layout:vk.PipelineLayout=.null_handle,
  /// the step down the chain (13-tap filter, the first keeping only the bright)
  pipeDown:vk.Pipeline=.null_handle,
  /// the step back up (tent filter, added onto the level)
  pipeUp:vk.Pipeline=.null_handle,
  /// the composite: the glow laid over the scene, tone-mapped
  pipeComposite:vk.Pipeline=.null_handle,
  /// FXAA: the composite's edges smoothed onto the screen
  pipeFxaa:vk.Pipeline=.null_handle,
  /// make the post chain for a `screen`-format swapchain of `w`×`h`, smoothed
  /// by `aa`; anything half made is freed again on failure
  pub fn init(c:*const Ctx,screen:vk.Format,w:u32,h:u32,aa:Antialias)ctx.Error!Post{
    // the post chain being made
    var p:Post=.{.aa=aa,.screen=screen};
    p.create(c,w,h)catch|e|{
      p.deinit(c);
      return ctx.fold(e);
    };
    return p;
  }
  /// the steps of `init`: sampler, set layout, sets, pipelines, then the images
  fn create(p:*Post,c:*const Ctx,w:u32,h:u32)!void{
    p.sampler=try c.device.createSampler(&.{
      .mag_filter=.linear,.min_filter=.linear,.mipmap_mode=.nearest,
      .address_mode_u=.clamp_to_edge,.address_mode_v=.clamp_to_edge,.address_mode_w=.clamp_to_edge,
      .mip_lod_bias=0,.anisotropy_enable=.false,.max_anisotropy=1,
      .compare_enable=.false,.compare_op=.always,.min_lod=0,.max_lod=0,
      .border_color=.float_transparent_black,.unnormalized_coordinates=.false,
    },null);
    // the two images every pass may read
    const bindings=[_]vk.DescriptorSetLayoutBinding{
      .{.binding=0,.descriptor_type=.combined_image_sampler,.descriptor_count=1,.stage_flags=.{.fragment=true}},
      .{.binding=1,.descriptor_type=.combined_image_sampler,.descriptor_count=1,.stage_flags=.{.fragment=true}},
    };
    p.setLayout=try c.device.createDescriptorSetLayout(&.{.binding_count=bindings.len,.p_bindings=&bindings},null);
    // how many sets: one per step down, one per step up, composite and FXAA
    const sets=levels+(levels-1)+2;
    // room for two images per set
    const sizes=[_]vk.DescriptorPoolSize{.{.type=.combined_image_sampler,.descriptor_count=sets*2}};
    p.pool=try c.device.createDescriptorPool(&.{.max_sets=sets,.pool_size_count=sizes.len,.p_pool_sizes=&sizes},null);
    // every set's layout (all the same), and the sets made from them
    var layouts:[sets]vk.DescriptorSetLayout=@splat(p.setLayout);
    var all:[sets]vk.DescriptorSet=undefined;
    try c.device.allocateDescriptorSets(&.{.descriptor_pool=p.pool,.descriptor_set_count=sets,.p_set_layouts=&layouts},&all);
    p.down=all[0..levels].*;
    p.up=all[levels..2*levels-1].*;
    p.composite=all[sets-2];
    p.fxaa=all[sets-1];
    // the one push constant range, seen by both stages
    const push=[_]vk.PushConstantRange{.{.stage_flags=.{.vertex=true,.fragment=true},.offset=0,.size=@sizeOf(Push)}};
    p.layout=try c.device.createPipelineLayout(&.{
      .set_layout_count=1,.p_set_layouts=@ptrCast(&p.setLayout),
      .push_constant_range_count=push.len,.p_push_constant_ranges=&push,
    },null);
    p.pipeDown=try p.pipe(c,@embedFile("bloom_down.frag"),hdrFormat,false);
    p.pipeUp=try p.pipe(c,@embedFile("bloom_up.frag"),hdrFormat,true);
    p.pipeComposite=try p.pipe(c,@embedFile("composite.frag"),p.screen,false);
    p.pipeFxaa=try p.pipe(c,@embedFile("fxaa.frag"),p.screen,false);
    try p.images(c,w,h);
  }
  /// a full-screen pipeline: the shared vertex shader with fragment shader
  /// `frag`, drawing into `fmt`, added onto what is there if `additive`
  fn pipe(p:*const Post,c:*const Ctx,comptime frag:[]const u8,fmt:vk.Format,additive:bool)!vk.Pipeline{
    // the shared full-screen vertex shader
    const vs=try c.shader(@embedFile("post.vert"));
    defer c.device.destroyShaderModule(vs,null);
    // the pass's own fragment shader
    const fs=try c.shader(frag);
    defer c.device.destroyShaderModule(fs,null);
    return pipeline.create(c,.{
      .vert=vs,.frag=fs,.bindings=&.{},.attrs=&.{},
      .layout=p.layout,.colorFormat=fmt,
      .depth=false,.depthAttachment=false,.blend=additive,.additive=additive,.cull=false,
    });
  }
  /// (re)make the images for a screen `w` x `h` and point the sets at them.
  /// The device must be idle.
  pub fn resize(p:*Post,c:*const Ctx,w:u32,h:u32)ctx.Error!void{
    p.images(c,w,h)catch|e|return ctx.fold(e);
  }
  /// free the old images, make new ones for `w`×`h` and the antialiasing
  /// mode, and point every set at them
  fn images(p:*Post,c:*const Ctx,w:u32,h:u32)!void{
    p.hdr.deinit(c);
    p.ms.deinit(c);
    p.msDepth.deinit(c);
    p.ldr.deinit(c);
    p.bloom.deinit(c);
    p.hdr=try Image.init(c,w,h,.{});
    // the world's samples per pixel
    const n=p.aa.samples();
    if(n>1){
      p.ms=try Image.init(c,w,h,.{.samples=n,.transient=true});
      p.msDepth=try Image.init(c,w,h,.{.format=sw.depthFormat,.samples=n,.depth=true,.transient=true});
    }
    if(p.aa.filtered())p.ldr=try Image.init(c,w,h,.{.format=p.screen});
    p.bloom=try Image.init(c,@max(w/2,1),@max(h/2,1),.{.levels=levels});
    for(0..levels)|l|{
      // what this step down reads: the HDR image, or the level above
      const src=if(l==0)p.hdr.views[0]else p.bloom.views[l-1];
      p.point(c,p.down[l],src,src);
    }
    for(0..levels-1)|l|p.point(c,p.up[l],p.bloom.views[l+1],p.bloom.views[l+1]);
    p.point(c,p.composite,p.hdr.views[0],p.bloom.views[0]);
    if(p.aa.filtered())p.point(c,p.fxaa,p.ldr.views[0],p.ldr.views[0]);
  }
  /// smooth edges another way: remakes the images (the device must be idle;
  /// pipelines drawing into the world must be remade for its sample count)
  pub fn antialias(p:*Post,c:*const Ctx,aa:Antialias)ctx.Error!void{
    p.aa=aa;
    try p.resize(c,p.hdr.extent.width,p.hdr.extent.height);
  }
  /// point `set`'s two bindings at images `a` and `b`
  fn point(p:*const Post,c:*const Ctx,set:vk.DescriptorSet,a:vk.ImageView,b:vk.ImageView)void{
    // the two images, read through the shared sampler
    const infos=[_]vk.DescriptorImageInfo{
      .{.sampler=p.sampler,.image_view=a,.image_layout=.shader_read_only_optimal},
      .{.sampler=p.sampler,.image_view=b,.image_layout=.shader_read_only_optimal},
    };
    // the writes that point the bindings there
    const writes=[_]vk.WriteDescriptorSet{
      .{.dst_set=set,.dst_binding=0,.dst_array_element=0,.descriptor_count=1,.descriptor_type=.combined_image_sampler,.p_image_info=@ptrCast(&infos[0]),.p_buffer_info=undefined,.p_texel_buffer_view=undefined},
      .{.dst_set=set,.dst_binding=1,.dst_array_element=0,.descriptor_count=1,.descriptor_type=.combined_image_sampler,.p_image_info=@ptrCast(&infos[1]),.p_buffer_info=undefined,.p_texel_buffer_view=undefined},
    };
    c.device.updateDescriptorSets(&writes,null);
  }
  /// free the images, pipelines, layouts, pool and sampler and leave it empty
  pub fn deinit(p:*Post,c:*const Ctx)void{
    p.hdr.deinit(c);
    p.ms.deinit(c);
    p.msDepth.deinit(c);
    p.ldr.deinit(c);
    p.bloom.deinit(c);
    c.device.destroyPipeline(p.pipeDown,null);
    c.device.destroyPipeline(p.pipeUp,null);
    c.device.destroyPipeline(p.pipeComposite,null);
    c.device.destroyPipeline(p.pipeFxaa,null);
    c.device.destroyPipelineLayout(p.layout,null);
    c.device.destroyDescriptorPool(p.pool,null);
    c.device.destroyDescriptorSetLayout(p.setLayout,null);
    c.device.destroySampler(p.sampler,null);
    p.*=.{};
  }
  /// whether the world draws multisampled (into `ms`, resolved into `hdr`)
  pub fn multisampled(p:*const Post)bool{return p.aa.samples()>1;}
  /// the world's images, ready to be drawn into (their old contents dropped)
  pub fn beginWorld(p:*const Post,cmd:vk.CommandBufferProxy)void{
    sw.barrier(cmd,p.hdr.image,range(0),.undefined,.color_attachment_optimal,.{.fragment_shader=true},.{.shader_sampled_read=true},.{.color_attachment_output=true},.{.color_attachment_write=true});
    if(!p.multisampled())return;
    sw.barrier(cmd,p.ms.image,range(0),.undefined,.color_attachment_optimal,.{.color_attachment_output=true},.{.color_attachment_write=true},.{.color_attachment_output=true},.{.color_attachment_write=true,.color_attachment_read=true});
  }
  /// the world scope's colour attachment: the HDR image, or with MSAA the
  /// multisampled one, averaged into the HDR image as the scope ends
  pub fn worldColor(p:*const Post,clear:[3]f32)vk.RenderingAttachmentInfo{
    // the clear colour, opaque
    const cv:vk.ClearValue=.{.color=.{.float_32=.{clear[0],clear[1],clear[2],1}}};
    if(p.multisampled())return.{
      .image_view=p.ms.views[0],
      .image_layout=.color_attachment_optimal,
      .resolve_mode=.{.average=true},
      .resolve_image_view=p.hdr.views[0],
      .resolve_image_layout=.color_attachment_optimal,
      .load_op=.clear,
      .store_op=.dont_care,
      .clear_value=cv,
    };
    return.{
      .image_view=p.hdr.views[0],
      .image_layout=.color_attachment_optimal,
      .resolve_mode=.{},
      .resolve_image_layout=.undefined,
      .load_op=.clear,
      .store_op=.store,
      .clear_value=cv,
    };
  }
  /// after the world is drawn: pull the glow out of it and blur it down the
  /// chain and back up again.
  pub fn glow(p:*const Post,cmd:vk.CommandBufferProxy)void{
    sw.barrier(cmd,p.hdr.image,range(0),.color_attachment_optimal,.shader_read_only_optimal,.{.color_attachment_output=true},.{.color_attachment_write=true},.{.fragment_shader=true},.{.shader_sampled_read=true});
    // down: each level filters the one above it (the first also keeps only
    // what is brighter than the threshold)
    for(0..levels)|l|{
      // this level, as the barrier and size calls want it
      const lv:u32=@intCast(l);
      sw.barrier(cmd,p.bloom.image,range(lv),.undefined,.color_attachment_optimal,.{.fragment_shader=true},.{.shader_sampled_read=true},.{.color_attachment_output=true},.{.color_attachment_write=true});
      // the size of what this level reads
      const src=if(l==0)p.hdr.extent else p.bloom.size(lv-1);
      p.pass(cmd,p.pipeDown,p.down[l],p.bloom.views[l],p.bloom.size(lv),src,.dont_care,if(l==0)1 else 0);
      sw.barrier(cmd,p.bloom.image,range(lv),.color_attachment_optimal,.shader_read_only_optimal,.{.color_attachment_output=true},.{.color_attachment_write=true},.{.fragment_shader=true},.{.shader_sampled_read=true});
    }
    // up: each level adds the blurred level below it onto itself
    // the level being added onto, counting up from the second smallest
    var l:usize=levels-1;
    while(l>0){
      l-=1;
      // that level, as the barrier and size calls want it
      const lv:u32=@intCast(l);
      sw.barrier(cmd,p.bloom.image,range(lv),.shader_read_only_optimal,.color_attachment_optimal,.{.fragment_shader=true},.{.shader_sampled_read=true},.{.color_attachment_output=true},.{.color_attachment_write=true,.color_attachment_read=true});
      p.pass(cmd,p.pipeUp,p.up[l],p.bloom.views[l],p.bloom.size(lv),p.bloom.size(lv+1),.load,0);
      sw.barrier(cmd,p.bloom.image,range(lv),.color_attachment_optimal,.shader_read_only_optimal,.{.color_attachment_output=true},.{.color_attachment_write=true},.{.fragment_shader=true},.{.shader_sampled_read=true});
    }
    // FXAA: the composite goes into its own image first, for FXAA to read
    if(p.aa.filtered()){
      sw.barrier(cmd,p.ldr.image,range(0),.undefined,.color_attachment_optimal,.{.fragment_shader=true},.{.shader_sampled_read=true},.{.color_attachment_output=true},.{.color_attachment_write=true});
      p.pass(cmd,p.pipeComposite,p.composite,p.ldr.views[0],p.ldr.extent,p.hdr.extent,.dont_care,0);
      sw.barrier(cmd,p.ldr.image,range(0),.color_attachment_optimal,.shader_read_only_optimal,.{.color_attachment_output=true},.{.color_attachment_write=true},.{.fragment_shader=true},.{.shader_sampled_read=true});
    }
  }
  /// inside the screen's rendering scope: the world and its glow,
  /// tone-mapped (or, with FXAA, that filtered)
  pub fn compose(p:*const Post,cmd:vk.CommandBufferProxy,screen:vk.Extent2D)void{
    // whether FXAA does the last step
    const filtered=p.aa.filtered();
    cmd.bindPipeline(.graphics,if(filtered)p.pipeFxaa else p.pipeComposite);
    cmd.bindDescriptorSets(.graphics,p.layout,0,&.{if(filtered)p.fxaa else p.composite},null);
    // one screen texel
    const push:Push=.{.texel=.{1/m.f(screen.width),1/m.f(screen.height)}};
    cmd.pushConstants(p.layout,.{.vertex=true,.fragment=true},0,@sizeOf(Push),&push);
    cmd.draw(3,1,0,0);
  }
  /// one full-screen draw into `dst` (of `size`) reading `srcSize` texels
  fn pass(p:*const Post,cmd:vk.CommandBufferProxy,pip:vk.Pipeline,set:vk.DescriptorSet,dst:vk.ImageView,size:vk.Extent2D,srcSize:vk.Extent2D,load:vk.AttachmentLoadOp,first:f32)void{
    // the attachment drawn into
    const color=[_]vk.RenderingAttachmentInfo{.{
      .image_view=dst,
      .image_layout=.color_attachment_optimal,
      .resolve_mode=.{},
      .resolve_image_layout=.undefined,
      .load_op=load,
      .store_op=.store,
      .clear_value=.{.color=.{.float_32=.{0,0,0,0}}},
    }};
    // the whole of the target
    const area:vk.Rect2D=.{.offset=.{.x=0,.y=0},.extent=size};
    cmd.beginRendering(&.{.render_area=area,.layer_count=1,.view_mask=0,.color_attachment_count=color.len,.p_color_attachments=&color});
    cmd.setViewport(0,&.{.{.x=0,.y=0,.width=m.f(size.width),.height=m.f(size.height),.min_depth=0,.max_depth=1}});
    cmd.setScissor(0,&.{area});
    cmd.bindPipeline(.graphics,pip);
    cmd.bindDescriptorSets(.graphics,p.layout,0,&.{set},null);
    // threshold > 0 only on the first step down; the rest pass everything
    // the texel step of what is read, and the threshold
    const push:Push=.{.texel=.{1/m.f(srcSize.width),1/m.f(srcSize.height)},.threshold=if(first>0)1.0 else 0};
    cmd.pushConstants(p.layout,.{.vertex=true,.fragment=true},0,@sizeOf(Push),&push);
    cmd.draw(3,1,0,0);
    cmd.endRendering();
  }
};
