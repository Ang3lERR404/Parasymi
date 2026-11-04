//! points of light that cast shadows: the few most telling lights near the
//! camera each get a cube of depth round them, so what stands in their
//! light blocks it and their glow fans out in rays through the air instead
//! of hanging there as a shapeless ball.
//!
//! Each cube is six square faces, each a 90° perspective view from the
//! light out along one axis, drawn as six layers of one image, a face at a
//! time, each drawing only what may stand inside it (`sees`). The faces lie
//! as Vulkan's cube maps lay them out, so the shaders read the whole cube
//! with one hardware-filtered depth compare along any direction
//! (light.glsl `cubeLit`). Which lights hold a cube is kept from frame to
//! frame (`Casters`): a light keeps its cube while it moves, and a shadow
//! eases in and out over `fade` seconds as a light gains or loses its
//! place, never popping.
/// the standard library
const std=@import("std");
/// the Vulkan bindings: images, views, samplers, rendering scopes
const vk=@import("vulkan");
/// all the maths: vectors, matrices, the view's frustum
const m=@import("../core/math.zig");
/// the Vulkan context and its error fold
const ctx=@import("../gfx/ctx.zig");
/// the device context the cubes are made on
const Ctx=ctx.Ctx;
/// the swapchain module: the shared depth format and image barriers
const sw=@import("../gfx/swapchain.zig");
/// the GPU layouts: a point of light as the shaders read it
const vertex=@import("../gfx/vertex.zig");
/// points of light given a cube at most (light.glsl MAX_CUBES)
pub const maxCubes=4;
/// faces to a cube
pub const faces=6;
/// the views a caster draws into a face: the one (light.glsl `CubeFace`)
pub const views:u32=1;
/// texels along each side of a face, unless a game asks for another size
pub const res:u32=512;
/// casters pushed away from the light by a constant and with their slope
pub const bias=m.Vice(f32,2){1.0,1.5};
/// the cubes' depth format, the same as every pass's
pub const format=sw.depthFormat;
/// seconds a shadow takes to ease in, or out
pub const fade:f32=0.6;
/// how far (world units) a light may move in a frame and still be the one
/// that held its cube the frame before
const follow:f32=1.5;
/// how much more telling a light holding a cube is counted, so two lights
/// alike never trade a cube back and forth
const keep:f32=1.5;
/// a light's near plane, as a share of its reach: what lies closer is not
/// drawn into its cube, so the shell a light glows inside never hides it
const nearShare:f32=0.06;
/// (and never nearer, or further, than these, in world units)
const nearMin:f32=0.2;
/// (the furthest)
const nearMax:f32=0.6;
/// lights dimmer than this cast no shadow worth a cube
const dimmest:f32=0.02;
/// one point of light's cube as the shaders read it (light.glsl `Cube`)
pub const Cube=extern struct{
  /// xyz the light the cube was drawn round, w how far it reaches (its far plane)
  at:m.Vice(f32,4),
  /// x which of the frame's points of light it is, y how much of its
  /// shadow shows (0 none .. 1 all of it, eased), z its near plane, w unused
  lit:m.Vice(f32,4),
  /// world to each face's clip space, in the cube map's order (+x, -x,
  /// +y, -y, +z, -z)
  faces:[faces]m.M4,
};
/// a cube no light holds: no shadow shows
pub const none:Cube=.{.at=.{0,0,0,0},.lit=.{0,0,0,0},.faces=@splat(m.identity)};
/// each face's way across (s), way down (t) and way out (its axis), as
/// Vulkan picks a cube map's face and its texel for a direction
const axes=[faces][3]m.V3{
  .{m.v3(0,0,-1),m.v3(0,-1,0),m.v3(1,0,0)},
  .{m.v3(0,0,1),m.v3(0,-1,0),m.v3(-1,0,0)},
  .{m.v3(1,0,0),m.v3(0,0,1),m.v3(0,1,0)},
  .{m.v3(1,0,0),m.v3(0,0,-1),m.v3(0,-1,0)},
  .{m.v3(1,0,0),m.v3(0,-1,0),m.v3(0,0,1)},
  .{m.v3(-1,0,0),m.v3(0,-1,0),m.v3(0,0,-1)},
};
/// world to face `f`'s clip space for a cube round `c`, seeing from `near`
/// to `far` along its axis: x and y across the face as its texels lie, the
/// depth 0 at `near` and 1 at `far` (light.glsl `cubeDepth` reads it back)
pub fn face(c:m.V3,f:usize,near:f32,far:f32)m.M4{
  // the face's three ways, and how depth runs along its axis
  const s=axes[f][0];
  const t=axes[f][1];
  const a=axes[f][2];
  const k=far/(far-near);
  const b=-far*near/(far-near);
  return.{
    .{s[0],t[0],k*a[0],a[0]},
    .{s[1],t[1],k*a[1],a[1]},
    .{s[2],t[2],k*a[2],a[2]},
    .{-m.dot(s,c),-m.dot(t,c),-k*m.dot(a,c)+b,-m.dot(a,c)},
  };
}
/// the depth a cube from `near` to `far` holds for a point `along` units out
/// along the axis of the face it lies in (light.glsl `cubeDepth`)
pub fn depth(near:f32,far:f32,along:f32)f32{return far/(far-near)-far*near/((far-near)*along);}
/// whether any of a sphere at `p` with radius `r` may lie inside face `f`
/// of a cube round `c` (the four planes through its edges, and before it)
pub fn sees(c:m.V3,f:usize,p:m.V3,r:f32)bool{
  // the sphere from the light, and how far it lies along the face's three ways
  const rel=p-c;
  const s=m.dot(rel,axes[f][0]);
  const t=m.dot(rel,axes[f][1]);
  const a=m.dot(rel,axes[f][2]);
  // (each edge's plane leans at 45°: its distance is the sum over root two)
  const lean=r*m.sqrt2;
  return a>=-r and a-s>=-lean and a+s>=-lean and a-t>=-lean and a+t>=-lean;
}
/// a light's near plane for its `reach`
pub fn nearOf(reach:f32)f32{return m.clamp(reach*nearShare,nearMin,nearMax);}
/// the cube record for light `index` at `l`, its shadow showing `shown`
pub fn record(l:vertex.Light,index:usize,shown:f32)Cube{
  // where it is, how far it reaches and its near plane
  const c=m.v3(l.pos[0],l.pos[1],l.pos[2]);
  const near=nearOf(l.pos[3]);
  // the record being filled
  var q:Cube=.{.at=l.pos,.lit=.{m.f(index),shown,near,0},.faces=undefined};
  for(&q.faces,0..)|*fc,f|fc.*=face(c,f,near,l.pos[3]);
  return q;
}
/// which lights hold a cube, kept from frame to frame: each slot follows
/// its light as it moves, its shadow easing in while the light is among
/// the most telling and out once it is not, then freed
pub const Casters=struct{
  /// one cube's holder
  pub const Slot=struct{
    /// whether a light holds it (its shadow showing or easing)
    held:bool=false,
    /// where its light was when last seen
    at:m.V3=.{0,0,0},
    /// which of this frame's lights it is (none: lost)
    light:?usize=null,
    /// how far its shadow has eased in (0..1)
    shown:f32=0,
    /// whether its light is still among the most telling (easing in) or
    /// not (easing out)
    wanted:bool=false,
  };
  /// the cubes' holders
  slots:[maxCubes]Slot=@splat(.{}),
  /// follow this frame's `lights`: each held slot finds its light again,
  /// the `count` most telling lights the camera can see (in `fr`, near the
  /// line from `eye` to `target`) are wanted, and every slot's shadow eases
  /// `dt` seconds toward shown (wanted) or gone (not; a slot freed once gone)
  pub fn update(c:*Casters,lights:[]const vertex.Light,eye:m.V3,target:m.V3,fr:*const m.Frustum,count:usize,dt:f32)void{
    // how many lights are looked at, and which a slot has found again
    const n=@min(lights.len,maxLights);
    var taken:[maxLights]bool=@splat(false);
    for(&c.slots)|*s|{
      s.light=null;
      if(!s.held)continue;
      // the nearest light not yet found by another slot, if it is near enough
      var best:?usize=null;
      var bestD:f32=follow;
      for(lights[0..n],0..)|l,i|{
        if(taken[i])continue;
        // how far this light is from where the slot's was
        const d=m.dist(m.v3(l.pos[0],l.pos[1],l.pos[2]),s.at);
        if(d<bestD){best=i;bestD=d;}
      }
      if(best)|b|{
        s.light=b;
        taken[b]=true;
      }else s.*=.{};
    }
    // every light's score, a held light's counted more
    var score:[maxLights]f32=undefined;
    for(lights[0..n],0..)|l,i|score[i]=telling(l,eye,target,fr)*(if(taken[i])keep else 1);
    // the most telling `count` lights, by score (none that scores nothing)
    var want:[maxLights]bool=@splat(false);
    for(0..@min(count,maxCubes))|_|{
      // the best not yet wanted
      var best:?usize=null;
      for(0..n)|i|{
        if(!want[i] and score[i]>0 and (best==null or score[i]>score[best.?]))best=i;
      }
      want[best orelse break]=true;
    }
    // the slots keep, or let go, what they hold
    for(&c.slots)|*s|if(s.light)|i|{s.wanted=want[i];};
    // wanted lights without a slot take a free one
    for(0..n)|i|if(want[i] and !taken[i]){
      for(&c.slots)|*s|if(!s.held){
        s.*=.{.held=true,.light=i,.wanted=true};
        taken[i]=true;
        break;
      };
    };
    // each shadow eases; a slot whose shadow is gone and unwanted is freed
    for(&c.slots)|*s|{
      if(!s.held)continue;
      s.shown=if(s.wanted)@min(1,s.shown+dt/fade)else@max(0,s.shown-dt/fade);
      if(!s.wanted and s.shown<=0){s.*=.{};continue;}
      const l=lights[s.light.?];
      s.at=m.v3(l.pos[0],l.pos[1],l.pos[2]);
    }
  }
  /// how much of slot `s`'s shadow shows, eased at both ends
  pub fn shownOf(s:Slot)f32{return m.smooth(s.shown);}
};
/// points of light a frame holds (light.zig `maxLights` is this one)
pub const maxLights=48;
/// how telling light `l` is for a cube: strong, far reaching and near the
/// line from the eye to what it looks at scores high; one the view cannot
/// see, or too dim, scores nothing
fn telling(l:vertex.Light,eye:m.V3,target:m.V3,fr:*const m.Frustum)f32{
  // where it is, how far it reaches and how strong it is
  const at=m.v3(l.pos[0],l.pos[1],l.pos[2]);
  const reach=l.pos[3];
  const strength=@max(l.col[0],@max(l.col[1],l.col[2]));
  if(strength<dimmest or reach<=0 or !fr.sphere(at,reach))return 0;
  // the nearest point to it on the line from the eye to what it looks at
  const gaze=target-eye;
  const along=m.clamp01(m.dot(at-eye,gaze)/@max(m.dot(gaze,gaze),m.eps));
  const d=m.dist(at,eye+gaze*m.splat3(along));
  return strength*reach*reach/(1+d*d);
}
/// the cubes: one depth image of `maxCubes` cubes, six layers each, drawn
/// into a cube at a time and read by the world shaders all at once
pub const Cubes=struct{
  /// the depth image, `maxCubes` × 6 layers
  image:vk.Image=.null_handle,
  /// the memory under it
  mem:vk.DeviceMemory=.null_handle,
  /// every cube, as a cube array (read)
  view:vk.ImageView=.null_handle,
  /// each face of each cube, its one layer (drawn into), cube by cube
  each:[maxCubes*faces]vk.ImageView=@splat(.null_handle),
  /// the compare sampler the shaders read it through
  sampler:vk.Sampler=.null_handle,
  /// texels along each side of a face
  res:u32=res,
  /// whether its layers have yet to be made readable (once, before its
  /// first frame)
  fresh:bool=true,
  /// make the cubes, `size` texels a face side; anything half made is
  /// freed again on failure
  pub fn init(c:*const Ctx,size:u32)ctx.Error!Cubes{
    // the cubes being made
    var q:Cubes=.{.res=size};
    q.create(c)catch|e|{
      q.deinit(c);
      return ctx.fold(e);
    };
    return q;
  }
  /// the steps of `init`: image, views, then the sampler
  fn create(q:*Cubes,c:*const Ctx)!void{
    q.image=try c.device.createImage(&.{
      .flags=.{.cube_compatible=true},
      .image_type=.@"2d",
      .format=format,
      .extent=.{.width=q.res,.height=q.res,.depth=1},
      .mip_levels=1,
      .array_layers=maxCubes*faces,
      .samples=.{.@"1"=true},
      .tiling=.optimal,
      .usage=.{.depth_stencil_attachment=true,.sampled=true},
      .sharing_mode=.exclusive,
      .initial_layout=.undefined,
    },null);
    q.mem=try c.imageMemory(q.image);
    q.view=try c.device.createImageView(&.{
      .image=q.image,
      .view_type=.cube_array,
      .format=format,
      .components=.{.r=.identity,.g=.identity,.b=.identity,.a=.identity},
      .subresource_range=layers(0,maxCubes),
    },null);
    for(&q.each,0..)|*v,i|v.*=try c.device.createImageView(&.{
      .image=q.image,
      .view_type=.@"2d_array",
      .format=format,
      .components=.{.r=.identity,.g=.identity,.b=.identity,.a=.identity},
      .subresource_range=.{.aspect_mask=.{.depth=true},.base_mip_level=0,.level_count=1,.base_array_layer=@intCast(i),.layer_count=1},
    },null);
    // a compare sampler: each tap answers how much of its 2x2 texels are
    // lit, across the faces' seams as one surface
    q.sampler=try c.device.createSampler(&.{
      .mag_filter=.linear,.min_filter=.linear,.mipmap_mode=.nearest,
      .address_mode_u=.clamp_to_edge,.address_mode_v=.clamp_to_edge,.address_mode_w=.clamp_to_edge,
      .mip_lod_bias=0,.anisotropy_enable=.false,.max_anisotropy=1,
      .compare_enable=.true,.compare_op=.less_or_equal,.min_lod=0,.max_lod=0,
      .border_color=.float_opaque_white,.unnormalized_coordinates=.false,
    },null);
  }
  /// free everything the cubes hold and leave them empty
  pub fn deinit(q:*Cubes,c:*const Ctx)void{
    c.device.destroySampler(q.sampler,null);
    for(q.each)|v|c.device.destroyImageView(v,null);
    c.device.destroyImageView(q.view,null);
    c.device.destroyImage(q.image,null);
    c.device.freeMemory(q.mem,null);
    q.*=.{};
  }
  /// what the shaders read the cubes through (light.glsl `cube_map`)
  pub fn info(q:*const Cubes)vk.DescriptorImageInfo{
    return.{.sampler=q.sampler,.image_view=q.view,.image_layout=.shader_read_only_optimal};
  }
  /// before the cubes' first frame: every layer made readable (what they
  /// hold is never read until drawn: a cube not drawn shows no shadow)
  pub fn ready(q:*Cubes,cmd:vk.CommandBufferProxy)void{
    if(!q.fresh)return;
    q.fresh=false;
    sw.barrier(cmd,q.image,layers(0,maxCubes),.undefined,.shader_read_only_optimal,
      .{},.{},.{.fragment_shader=true},.{.shader_sampled_read=true});
  }
  /// make cube `i` ready to be drawn into, its faces one by one (`open`).
  /// (What earlier frames read of it is done first.)
  pub fn begin(q:*const Cubes,cmd:vk.CommandBufferProxy,i:usize)void{
    sw.barrier(cmd,q.image,layers(i,1),.undefined,.depth_attachment_optimal,
      .{.fragment_shader=true},.{},
      .{.early_fragment_tests=true,.late_fragment_tests=true},.{.depth_stencil_attachment_write=true,.depth_stencil_attachment_read=true});
  }
  /// open the casters' scope of cube `i`'s face `f`: cleared to the far
  /// plane, one view
  pub fn open(q:*const Cubes,cmd:vk.CommandBufferProxy,i:usize,f:usize)void{
    // the depth attachment: the face, cleared to the far plane
    const d:vk.RenderingAttachmentInfo=.{
      .image_view=q.each[i*faces+f],
      .image_layout=.depth_attachment_optimal,
      .resolve_mode=.{},
      .resolve_image_layout=.undefined,
      .load_op=.clear,
      .store_op=.store,
      .clear_value=.{.depth_stencil=.{.depth=1,.stencil=0}},
    };
    // the whole of a face
    const area:vk.Rect2D=.{.offset=.{.x=0,.y=0},.extent=.{.width=q.res,.height=q.res}};
    cmd.beginRendering(&.{
      .render_area=area,
      .layer_count=1,
      .view_mask=views,
      .color_attachment_count=0,
      .p_color_attachments=null,
      .p_depth_attachment=&d,
    });
    cmd.setViewport(0,&.{.{.x=0,.y=0,.width=m.f(q.res),.height=m.f(q.res),.min_depth=0,.max_depth=1}});
    cmd.setScissor(0,&.{area});
  }
  /// close a face's scope
  pub fn close(_:*const Cubes,cmd:vk.CommandBufferProxy)void{cmd.endRendering();}
  /// hand cube `i`, every face drawn, to the world's fragment shaders
  pub fn end(q:*const Cubes,cmd:vk.CommandBufferProxy,i:usize)void{
    sw.barrier(cmd,q.image,layers(i,1),.depth_attachment_optimal,.shader_read_only_optimal,
      .{.late_fragment_tests=true},.{.depth_stencil_attachment_write=true},
      .{.fragment_shader=true},.{.shader_sampled_read=true});
  }
};
/// `n` cubes' layers from cube `first` on
fn layers(first:usize,n:usize)vk.ImageSubresourceRange{
  return.{.aspect_mask=.{.depth=true},.base_mip_level=0,.level_count=1,.base_array_layer=@intCast(first*faces),.layer_count=@intCast(n*faces)};
}
/// the test helpers
const testing=std.testing;
test"each face draws a direction where Vulkan's cube lookup reads it"{
  // a cube round a point, and its planes
  const c=m.v3(3,4.5,-2);
  const near:f32=0.4;
  const far:f32=9;
  // directions every way, none on a face's edge
  const dirs=[_]m.V3{
    m.v3(1,0.3,-0.2),m.v3(-1,0.4,0.6),m.v3(0.2,1,-0.5),m.v3(0.3,-1,0.7),
    m.v3(-0.6,0.2,1),m.v3(0.5,-0.4,-1),m.v3(0.9,-0.8,0.1),m.v3(-0.1,0.95,0.9),
  };
  for(dirs)|d|{
    // Vulkan's face for it: its largest part's axis and sign
    // its parts as a row (picked by a runtime index), and how large each is
    const dv:m.Vice(f32,3)=d;
    const ad:m.Vice(f32,3)=@abs(d);
    const axis:usize=if(ad[0]>=ad[1] and ad[0]>=ad[2])0 else if(ad[1]>=ad[2])1 else 2;
    const f=axis*2+@as(usize,if(dv[axis]<0)1 else 0);
    // the spec's table: sc, tc and ma for that face
    const ma=ad[axis];
    const sc:f32=switch(f){0=>-d[2],1=>d[2],2,3,4=>d[0],5=>-d[0],else=>unreachable};
    const tc:f32=switch(f){0,1,4,5=>-d[1],2=>d[2],3=>-d[2],else=>unreachable};
    // a point out that way, through the face's matrix
    const k:f32=2.5;
    const p=c+d*m.splat3(k);
    const q=m.mulV(face(c,f,near,far),.{p[0],p[1],p[2],1});
    try testing.expectApproxEqAbs(sc/ma,q[0]/q[3],1e-5);
    try testing.expectApproxEqAbs(tc/ma,q[1]/q[3],1e-5);
    try testing.expectApproxEqAbs(depth(near,far,ma*k),q[2]/q[3],1e-5);
  }
  try testing.expectApproxEqAbs(@as(f32,0),depth(near,far,near),1e-6);
  try testing.expectApproxEqAbs(@as(f32,1),depth(near,far,far),1e-6);
}
test"a light keeps its cube as it moves; shadows ease in and out, never pop"{
  // a camera looking at the origin
  const eye=m.v3(0,10,12);
  const target=m.v3(0,0,0);
  const fr=m.Frustum.of(m.mul(m.perspective(1.0,1.5,0.1,200),m.lookAt(eye,target,m.v3(0,1,0))));
  // three lights: a strong one near what is looked at, two weaker further off
  var ls=[_]vertex.Light{
    .{.pos=.{0,1,0,8},.col=.{1,1,1,0}},
    .{.pos=.{6,1,-3,4},.col=.{0.5,0.5,0.5,0}},
    .{.pos=.{-5,1,-6,4},.col=.{0.4,0.4,0.4,0}},
  };
  var c:Casters=.{};
  c.update(&ls,eye,target,&fr,2,0.1);
  // the two most telling hold cubes, easing in
  var held:usize=0;
  for(c.slots)|s|if(s.held){
    held+=1;
    try testing.expect(s.light.?!=2);
    try testing.expectApproxEqAbs(0.1/fade,s.shown,1e-5);
  };
  try testing.expectEqual(@as(usize,2),held);
  // the strong light drifts and comes later in the list: it keeps its slot
  const before=for(c.slots,0..)|s,i|{if(s.held and s.light.?==0)break i;}else unreachable;
  const moved=ls[0];
  ls[0]=ls[2];
  ls[2]=moved;
  ls[2].pos[0]+=0.3;
  c.update(&ls,eye,target,&fr,2,0.1);
  try testing.expectEqual(@as(?usize,2),c.slots[before].light);
  // asked for one cube only: the other light's shadow eases out a step at a time, then frees
  const other=1-before;
  const was=c.slots[other].shown;
  c.update(&ls,eye,target,&fr,1,0.1);
  try testing.expect(c.slots[other].held and !c.slots[other].wanted);
  try testing.expectApproxEqAbs(was-0.1/fade,c.slots[other].shown,1e-5);
  for(0..20)|_|c.update(&ls,eye,target,&fr,1,0.1);
  try testing.expect(!c.slots[other].held);
  try testing.expect(c.slots[before].held and c.slots[before].shown==1);
}
test"a face sees what lies inside it, and a sphere across its edge, never what lies behind"{
  // a light, and points out along each axis
  const c=m.v3(1,2,3);
  for(axes,0..)|ax,f|{
    const p=c+ax[2]*m.splat3(4);
    try testing.expect(sees(c,f,p,0.1));
    // the opposite face sees none of it
    try testing.expect(!sees(c,f^1,p,0.1));
    // out past this face's edge, just over it: seen only once large enough to reach in
    const q=c+ax[2]*m.splat3(2)+ax[0]*m.splat3(2.5);
    try testing.expect(!sees(c,f,q,0.1));
    try testing.expect(sees(c,f,q,0.5));
  }
}
