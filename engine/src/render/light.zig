//! light that moves: the key light's (sun or moon) shadows and the points
//! of light the garden makes (blooms, motes, a halo's flash).
//!
//! Shadows are a cascaded shadow map: the view is cut by distance into
//! `cascades` slices, each wrapped in a sphere seen straight down the key
//! light by an orthographic projection into one layer of a depth array.
//! Every caster pass draws once into all the layers (multiview: each view
//! one cascade, `gl_ViewIndex` picking its matrix), so shadows add one draw
//! per mesh, not one per cascade. A slice's sphere depends only on the
//! camera's shape, never where it is, and its centre is snapped to whole
//! texels, so shadow edges hold still as the view pans. The world shaders
//! read it with hardware depth compares (light.glsl `keyShadow`).
//!
//! Points of light are sent each frame in the same record as the cascades
//! (`Lighting`, reached by its address like the bones), and every lit
//! surface sums them on the GPU (light.glsl `pointLight`).
/// the standard library
const std=@import("std");
/// the Vulkan bindings: images, samplers, descriptors, rendering scopes
const vk=@import("vulkan");
/// all the maths: vectors, matrices, projections
const m=@import("../core/math.zig");
/// the Vulkan context and its error fold
const ctx=@import("../gfx/ctx.zig");
/// the device context the shadow map is made on
const Ctx=ctx.Ctx;
/// the swapchain module: the shared depth format and image barriers
const sw=@import("../gfx/swapchain.zig");
/// the GPU layouts: a point of light as the shaders read it
const vertex=@import("../gfx/vertex.zig");
/// slices of the view, each its own layer (light.glsl CASCADES)
pub const cascades=3;
/// texels along each side of a cascade's layer
pub const res=2048;
/// points of light a frame can hold (light.glsl MAX_LIGHTS)
pub const maxLights=32;
/// the views the casters draw: one per cascade
pub const views:u32=(1<<cascades)-1;
/// casters pushed away from the light by a constant and with their slope
pub const bias=m.Vice(f32,2){1.25,1.75};
/// the shadow map's depth format, the same as every pass's
pub const format=sw.depthFormat;
/// how far toward the light beyond a slice's sphere casters are caught
/// (taller than anything the garden grows or floats)
const casterReach:f32=48;
/// cascade splits: this share logarithmic, the rest even
const splitLog:f32=0.6;
/// the first split's base: this share of the eye's distance to its target
const splitBase:f32=0.5;
/// (and never nearer than this, in world units)
const splitMin:f32=2;
/// shadows reach the drawn world's edge from the eye, at most this far
const reachMax:f32=260;
/// a slice's sphere grows in steps of this share (so a zoom moves it only
/// now and then, and panning never does)
const radiusStep:f32=1.0/32.0;
/// and never in steps finer than this (world units)
const stepMin:f32=0.25;
/// what the world shaders read about light each frame (light.glsl
/// `Lighting`)
pub const Lighting=extern struct{
  /// world to each cascade's clip space
  cascades:[cascades]m.M4,
  /// per cascade, the world size of one of its texels (one vec4's worth)
  texel:m.Vice(f32,4),
  /// x points of light, y how far from the eye shadows reach, zw unused
  info:m.Vice(f32,4),
  /// the frame's points of light, the first `info[0]` of them lit
  lights:[maxLights]vertex.Light,
};
comptime{
  // std430 as light.glsl reads it: the texel sizes pack into one vec4
  if(cascades>4 or @offsetOf(Lighting,"info")!=cascades*64+16 or @offsetOf(Lighting,"lights")!=cascades*64+32)
    @compileError("Lighting must match light.glsl's layout");
}
/// the cascades for a view: each world to its clip space, the world size
/// of its texels, and how far from the eye they reach in all
pub const Fit=struct{mats:[cascades]m.M4,texel:[cascades]f32,reach:f32};
/// the cascades covering what a camera sees: `vp` its view-projection,
/// `eye` where it is and `target` what it looks at, `reach` how far from it
/// shadows are drawn, `toward` the direction toward the key light (unit)
pub fn fit(vp:m.M4,eye:m.V3,target:m.V3,reach:f32,toward:m.V3)Fit{
  // the view's corner rays, scaled to reach one unit along its gaze
  // back from the view's clip space to the world
  const inv=m.inverse(vp);
  // the near plane's four corners, and the far and near planes' middles
  var nearC:[4]m.V3=undefined;
  var farMid=m.v3(0,0,0);
  var nearMid=m.v3(0,0,0);
  for(0..4)|i|{
    // which corner: left or right, bottom or top, in clip space
    const x:f32=if(i&1==0)-1 else 1;
    const y:f32=if(i&2==0)-1 else 1;
    nearC[i]=unproject(inv,x,y,0);
    nearMid+=nearC[i]*m.splat3(0.25);
    farMid+=unproject(inv,x,y,1)*m.splat3(0.25);
  }
  // which way the view looks, and how far along it the near plane lies
  const gaze=m.norm(farMid-nearMid);
  const nearD=m.dot(nearMid-eye,gaze);
  // each corner's ray, one unit along the gaze per unit
  var rays:[4]m.V3=undefined;
  for(&rays,nearC)|*r,c|r.*=(c-eye)*m.splat3(1/nearD);
  // how far the far plane lies along the gaze, and how far shadows reach
  const farD=m.dot(farMid-eye,gaze);
  const far=@min(@min(reach,farD),reachMax);
  // splits: mostly logarithmic from a base near what the camera looks at
  const base=@min(@max(m.len(target-eye)*splitBase,splitMin),far*0.5);
  // where each slice begins and ends, along the gaze
  var cut:[cascades+1]f32=undefined;
  cut[0]=nearD;
  for(1..cascades+1)|i|{
    // how far through the splits this one is (0..1)
    const k=m.f(i)/cascades;
    // the logarithmic split there, and the even one
    const lg=base*m.pow(f32,far/base,k);
    const even=base+(far-base)*k;
    cut[i]=m.lerp(even,lg,splitLog);
  }
  cut[cascades]=far;
  // the light's own frame, from the world origin: x, y across its rays, -z along them
  // a direction not along the light's rays, to build its frame from
  const up=if(@abs(toward[1])<m.nearParallel)m.v3(0,1,0)else m.v3(1,0,0);
  // the light's view, from the origin looking along its rays
  const view=m.lookAt(m.v3(0,0,0),-toward,up);
  // the cascades being fitted
  var out:Fit=undefined;
  out.reach=far;
  for(0..cascades)|i|{
    // the slice's eight corners and a sphere round them
    var pts:[8]m.V3=undefined;
    // the slice's centre
    var mid=m.v3(0,0,0);
    for(0..4)|c|{
      pts[c]=eye+rays[c]*m.splat3(cut[i]);
      pts[c+4]=eye+rays[c]*m.splat3(cut[i+1]);
      mid+=(pts[c]+pts[c+4])*m.splat3(1.0/8.0);
    }
    // the sphere's radius: the farthest corner from the centre
    var r:f32=0;
    for(pts)|p|r=@max(r,m.len(p-mid));
    // the step the radius grows in
    const step=@max(r*radiusStep,stepMin);
    r=@ceil(r/step)*step;
    // the world size of one texel of this cascade
    const texel=2*r/res;
    // its centre seen from the light, snapped to whole texels
    // the centre in the light's view
    const c4=m.mulV(view,.{mid[0],mid[1],mid[2],1});
    // that centre's x and y, snapped to whole texels
    const cx=@floor(c4[0]/texel)*texel;
    const cy=@floor(c4[1]/texel)*texel;
    // the cascade's projection: the snapped sphere, and casters beyond it toward the light
    const proj=m.ortho(cx-r,cx+r,cy-r,cy+r,-c4[2]-r-casterReach,-c4[2]+r);
    out.mats[i]=m.mul(proj,view);
    out.texel[i]=texel;
  }
  return out;
}
/// the world point a clip-space point (`x`, `y`, depth `z`) comes from,
/// through the inverse view-projection `inv`
fn unproject(inv:m.M4,x:f32,y:f32,z:f32)m.V3{
  // the point before the divide
  const p=m.mulV(inv,.{x,y,z,1});
  return m.v3(p[0],p[1],p[2])*m.splat3(1/p[3]);
}
/// the shadow map: a depth layer per cascade, drawn into by the caster
/// passes and read by the world shaders through one descriptor set
pub const Shadow=struct{
  /// the depth array image, one layer per cascade
  image:vk.Image=.null_handle,
  /// the memory under it
  mem:vk.DeviceMemory=.null_handle,
  /// every layer, as one array (drawn into and read)
  view:vk.ImageView=.null_handle,
  /// the compare sampler the world shaders read it through
  sampler:vk.Sampler=.null_handle,
  /// a plain sampler reading its raw depths (for how far a shadow falls
  /// from what casts it)
  depthSampler:vk.Sampler=.null_handle,
  /// the descriptor set's layout: one image-and-sampler binding
  setLayout:vk.DescriptorSetLayout=.null_handle,
  /// the pool its one set comes from
  pool:vk.DescriptorPool=.null_handle,
  /// the set binding the map for the world shaders
  set:vk.DescriptorSet=undefined,
  /// make the shadow map: its image, view, compare sampler and descriptor
  /// set; anything half made is freed again on failure
  pub fn init(c:*const Ctx)ctx.Error!Shadow{
    // the shadow map being made
    var s:Shadow=.{};
    s.create(c)catch|e|{
      s.deinit(c);
      return ctx.fold(e);
    };
    return s;
  }
  /// the steps of `init`: image, view, sampler, then the set pointing at them
  fn create(s:*Shadow,c:*const Ctx)!void{
    s.image=try c.device.createImage(&.{
      .image_type=.@"2d",
      .format=format,
      .extent=.{.width=res,.height=res,.depth=1},
      .mip_levels=1,
      .array_layers=cascades,
      .samples=.{.@"1"=true},
      .tiling=.optimal,
      .usage=.{.depth_stencil_attachment=true,.sampled=true},
      .sharing_mode=.exclusive,
      .initial_layout=.undefined,
    },null);
    s.mem=try c.imageMemory(s.image);
    s.view=try c.device.createImageView(&.{
      .image=s.image,
      .view_type=.@"2d_array",
      .format=format,
      .components=.{.r=.identity,.g=.identity,.b=.identity,.a=.identity},
      .subresource_range=layers(),
    },null);
    // a compare sampler: each tap answers how much of its 2x2 texels are lit;
    // outside the map everything is
    s.sampler=try c.device.createSampler(&.{
      .mag_filter=.linear,.min_filter=.linear,.mipmap_mode=.nearest,
      .address_mode_u=.clamp_to_border,.address_mode_v=.clamp_to_border,.address_mode_w=.clamp_to_edge,
      .mip_lod_bias=0,.anisotropy_enable=.false,.max_anisotropy=1,
      .compare_enable=.true,.compare_op=.less_or_equal,.min_lod=0,.max_lod=0,
      .border_color=.float_opaque_white,.unnormalized_coordinates=.false,
    },null);
    // a plain sampler on the same map: the depths themselves, unfiltered
    s.depthSampler=try c.device.createSampler(&.{
      .mag_filter=.nearest,.min_filter=.nearest,.mipmap_mode=.nearest,
      .address_mode_u=.clamp_to_edge,.address_mode_v=.clamp_to_edge,.address_mode_w=.clamp_to_edge,
      .mip_lod_bias=0,.anisotropy_enable=.false,.max_anisotropy=1,
      .compare_enable=.false,.compare_op=.always,.min_lod=0,.max_lod=0,
      .border_color=.float_opaque_white,.unnormalized_coordinates=.false,
    },null);
    // the set's two bindings: the map through each sampler, read by both stages
    const bindings=[_]vk.DescriptorSetLayoutBinding{
      .{.binding=0,.descriptor_type=.combined_image_sampler,.descriptor_count=1,.stage_flags=.{.vertex=true,.fragment=true}},
      .{.binding=1,.descriptor_type=.combined_image_sampler,.descriptor_count=1,.stage_flags=.{.vertex=true,.fragment=true}},
    };
    s.setLayout=try c.device.createDescriptorSetLayout(&.{.binding_count=bindings.len,.p_bindings=&bindings},null);
    // room for that one descriptor
    const sizes=[_]vk.DescriptorPoolSize{.{.type=.combined_image_sampler,.descriptor_count=2}};
    s.pool=try c.device.createDescriptorPool(&.{.max_sets=1,.pool_size_count=sizes.len,.p_pool_sizes=&sizes},null);
    try c.device.allocateDescriptorSets(&.{.descriptor_pool=s.pool,.descriptor_set_count=1,.p_set_layouts=@ptrCast(&s.setLayout)},@ptrCast(&s.set));
    // what the set's binding points at: the map's view, through the sampler
    const info=[_]vk.DescriptorImageInfo{.{.sampler=s.sampler,.image_view=s.view,.image_layout=.shader_read_only_optimal}};
    // ...and through the plain sampler
    const depthInfo=[_]vk.DescriptorImageInfo{.{.sampler=s.depthSampler,.image_view=s.view,.image_layout=.shader_read_only_optimal}};
    // the write that points it there
    const writes=[_]vk.WriteDescriptorSet{
      .{.dst_set=s.set,.dst_binding=0,.dst_array_element=0,.descriptor_count=1,.descriptor_type=.combined_image_sampler,.p_image_info=&info,.p_buffer_info=undefined,.p_texel_buffer_view=undefined},
      .{.dst_set=s.set,.dst_binding=1,.dst_array_element=0,.descriptor_count=1,.descriptor_type=.combined_image_sampler,.p_image_info=&depthInfo,.p_buffer_info=undefined,.p_texel_buffer_view=undefined},
    };
    c.device.updateDescriptorSets(&writes,null);
  }
  /// free everything the shadow map holds and leave it empty
  pub fn deinit(s:*Shadow,c:*const Ctx)void{
    c.device.destroyDescriptorPool(s.pool,null);
    c.device.destroyDescriptorSetLayout(s.setLayout,null);
    c.device.destroySampler(s.sampler,null);
    c.device.destroySampler(s.depthSampler,null);
    c.device.destroyImageView(s.view,null);
    c.device.destroyImage(s.image,null);
    c.device.freeMemory(s.mem,null);
    s.*=.{};
  }
  /// open the casters' scope: every layer cleared, one view per cascade.
  /// (What earlier frames read of it is done first: a barrier waits on
  /// every command before it in the queue.)
  pub fn begin(s:*const Shadow,cmd:vk.CommandBufferProxy)void{
    sw.barrier(cmd,s.image,layers(),.undefined,.depth_attachment_optimal,
      .{.fragment_shader=true},.{},
      .{.early_fragment_tests=true,.late_fragment_tests=true},.{.depth_stencil_attachment_write=true,.depth_stencil_attachment_read=true});
    // the depth attachment: every layer, cleared to the far plane
    const depth:vk.RenderingAttachmentInfo=.{
      .image_view=s.view,
      .image_layout=.depth_attachment_optimal,
      .resolve_mode=.{},
      .resolve_image_layout=.undefined,
      .load_op=.clear,
      .store_op=.store,
      .clear_value=.{.depth_stencil=.{.depth=1,.stencil=0}},
    };
    // the whole of a layer
    const area:vk.Rect2D=.{.offset=.{.x=0,.y=0},.extent=.{.width=res,.height=res}};
    cmd.beginRendering(&.{
      .render_area=area,
      .layer_count=1,
      .view_mask=views,
      .color_attachment_count=0,
      .p_color_attachments=null,
      .p_depth_attachment=&depth,
    });
    cmd.setViewport(0,&.{.{.x=0,.y=0,.width=res,.height=res,.min_depth=0,.max_depth=1}});
    cmd.setScissor(0,&.{area});
  }
  /// close it and hand the map to the world's fragment shaders
  pub fn end(s:*const Shadow,cmd:vk.CommandBufferProxy)void{
    cmd.endRendering();
    sw.barrier(cmd,s.image,layers(),.depth_attachment_optimal,.shader_read_only_optimal,
      .{.late_fragment_tests=true},.{.depth_stencil_attachment_write=true},
      .{.fragment_shader=true},.{.shader_sampled_read=true});
  }
};
/// every layer of the depth array
fn layers()vk.ImageSubresourceRange{
  return.{.aspect_mask=.{.depth=true},.base_mip_level=0,.level_count=1,.base_array_layer=0,.layer_count=cascades};
}
/// the test helpers
const testing=std.testing;
test"cascades cover what the camera sees, nearest first, and hold still as it pans"{
  // the direction toward the light
  const toward=m.norm(m.v3(0.4,0.8,0.35));
  // the point looked at, and the eye up and behind it
  const at=m.v3(10,0,4);
  const eye=at+m.v3(0,26,18);
  // the camera's view-projection
  const vp=m.mul(m.perspective(0.6,16.0/9.0,0.1,300),m.lookAt(eye,at,m.v3(0,1,0)));
  // the cascades fitted to it
  const a=fit(vp,eye,at,120,toward);
  // the point looked at lies in the first cascade or the second
  // the point looked at, in the first two cascades' clip spaces
  const q=m.mulV(a.mats[0],.{at[0],at[1],at[2],1});
  const q1=m.mulV(a.mats[1],.{at[0],at[1],at[2],1});
  try testing.expect((@abs(q[0])<1 and @abs(q[1])<1)or(@abs(q1[0])<1 and @abs(q1[1])<1));
  for(0..cascades-1)|i|try testing.expect(a.texel[i]<=a.texel[i+1]);
  // panning keeps the texel grid where it was in the world: a point lands
  // a whole number of texels from where it did
  // how far the camera pans
  const shift=m.v3(3.7,0,-1.3);
  // the cascades fitted after the pan
  const b=fit(m.mul(vp,m.translate(-shift)),eye+shift,at+shift,120,toward);
  for(0..cascades)|i|{
    try testing.expectApproxEqAbs(a.texel[i],b.texel[i],1e-5);
    // the point looked at in each fit's cascade
    const pa=m.mulV(a.mats[i],.{at[0],at[1],at[2],1});
    const pb=m.mulV(b.mats[i],.{at[0],at[1],at[2],1});
    inline for(0..2)|k|{
      // how many texels apart they land
      const texels=(pa[k]-pb[k])*res/2;
      try testing.expect(@abs(texels-@round(texels))<0.05);
    }
  }
}
