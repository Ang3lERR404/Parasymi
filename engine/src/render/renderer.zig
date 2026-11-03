//! frame orchestration: acquire, record every pass, submit, present. What
//! gets drawn is the game's: it hands `Renderer` one namespace naming its
//! passes (shape in `pass` below), push constants, scene and stats, and
//! the state of its own it keeps on the renderer. Passes record in the
//! order listed, by target: the shadow casters into the key light's shadow
//! map, what is seen from above into the overhead map, then the world into
//! the HDR image, the air over it (volume.zig), then the screen. A new pass
//! is one new file plus one line in the game's list.
/// the standard library
const std=@import("std");
/// the allocator the renderer and its lists are made with
const Allocator=std.mem.Allocator;
/// a slice seen as its bytes, for uploading instance runs
const sliceAsBytes=std.mem.sliceAsBytes;
/// one value seen as its bytes, for uploading the lighting record
const asBytes=std.mem.asBytes;
/// the Vulkan bindings: command buffers, semaphores, fences, queries
const vk=@import("vulkan");
/// the window library: the framebuffer size, and waiting while minimised
const glfw=@import("zglfw");
/// all the maths: vectors and the small conversions
const m=@import("../core/math.zig");
/// the registry the game's pass list is read through
const registry=@import("../core/registry.zig");
/// the Vulkan context and its error fold
const ctx=@import("../gfx/ctx.zig");
/// the device context everything is made on and drawn with
const Ctx=ctx.Ctx;
/// the swapchain module: the swapchain, ranges and image barriers
const sw=@import("../gfx/swapchain.zig");
/// a GPU buffer: per-frame lighting, retired buffers, the capture
const Buffer=@import("../gfx/buffer.zig").Buffer;
/// pipeline construction, for each pass and the push layouts
const pipeline=@import("../gfx/pipeline.zig");
/// the post chain module: HDR image, glow, antialiasing
const postMod=@import("post.zig");
/// light that moves: shadow cascades and points of light
const light=@import("light.zig");
/// points of light that cast shadows: their cubes and which lights hold them
const cube=@import("cube.zig");
/// shadows traced as rays: what casts them, caught and built each frame
const raysMod=@import("rays.zig");
/// the air: the overhead map, the field, the volume and its composite
const Volume=@import("volume.zig").Volume;
/// what the field is kept in (volume.zig)
const fieldFormat=@import("volume.zig").fieldFormat;
/// the post chain: the world's HDR image, its glow and the smoothing
const Post=postMod.Post;
/// the HDR image's format, which world passes draw into
const hdrFormat=postMod.hdrFormat;
/// how edges are smoothed: off, FXAA or MSAA at 2, 4 or 8 samples
pub const Antialias=postMod.Antialias;
/// the UI pass every game can list (as `ui`): the HUD batch, drawn last
pub const ui=@import("passes/ui.zig");
/// the shape of a render pass module. Each pass declares
///   desc:Desc                          its shaders, vertex layout and state
///   Frame                              per-frame resources (optional)
///   initFrame(c) Error!Frame / deinitFrame(*Frame, c)
///                                      (Frame fields default to empty)
///   prepare(r, *Frame, scene, stats)   upload this frame's data (optional;
///                                      every pass's, before any draws)
///   record(r, *Frame, cmd, scene, stats) draw it
/// Passes record in declaration order inside their target's scope.
pub const pass=struct{
  /// which push-constant block the pass uses: the game's world block, or
  /// the UI's (`ui.Push`)
  pub const Layout=enum{
    /// the game's world block (`G.Push`), with the shadow map's set (and
    /// the air's: the world's depth and the overhead map)
    world,
    /// the UI's block (`ui.Push`)
    ui
  };
  /// what a pass draws into: the key light's shadow map (depth alone, every
  /// cascade at once), the points of light's shadow cubes, the overhead
  /// map, the world's HDR image, the air's volume after it, or the screen
  /// after the world (and its glow): the UI
  pub const Target=enum{
    /// the key light's shadow map: depth alone, every cascade in one draw
    shadow,
    /// a face of a point of light's shadow cube (cube.zig): depth alone.
    /// Recorded once for each face of each cube held this frame, its push's
    /// `light` pointing at that face's matrix (light.glsl `CubeFace`) and
    /// `Renderer.cubeNow` saying which (cube × 6 + face), so a pass may draw only what lies
    /// inside that face within its light's reach (`Renderer.cubeSpheres`, `cube.sees`)
    cube,
    /// the overhead map: colour alone, seen from straight above (each draw
    /// pushes its own `vp`, `volume.overheadOf`), before the world; kept
    /// from frame to frame, so a pass redraws only what changed
    overhead,
    /// the field (volume.zig): the game's own state over the world, a
    /// texel a unit as the overhead map, each frame's step written whole
    /// from the last (read through set 1, volume.glsl `field_map`), after
    /// the overhead map and before the world, which reads the new step
    field,
    /// the world's HDR image
    world,
    /// the air's volume, half the screen's size, after the world: colour
    /// alone, reading the world's depth (volume.glsl)
    volume,
    /// the screen, after the world and its glow are composed
    screen,
    /// where shadows are traced as rays (rays.zig): nothing drawn into,
    /// nothing rasterized, first of all. The pass's vertex shader (built
    /// with CAPTURE) writes out where it places each vertex of each caster
    /// (light.glsl `capture`), its push's `light` pointing at its table;
    /// it hands the renderer each instance caught (`Renderer.rays`, `add`).
    /// Made only where the GPU can trace rays, recorded only while it does.
    capture
  };
  /// how a pass is drawn: its shaders, vertex layout, push block, depth and
  /// blend choices, and what it draws into
  pub const Desc=struct{
    /// SPIR-V, embedded by the module that compiled it (`@embedFile("x.vert")`)
    vert:[]const u8,
    /// (the fragment shader's SPIR-V, the same way)
    frag:[]const u8,
    /// the same fragment shader built with RAY (light.glsl: its shadows
    /// traced as rays while the renderer traces them), taken in place of
    /// `frag` where the GPU can trace rays; null: `frag` everywhere
    rayFrag:?[]const u8=null,
    /// the vertex buffers it reads and how each steps
    bindings:[]const vk.VertexInputBindingDescription,
    /// the fields it reads from them, by location
    attrs:[]const vk.VertexInputAttributeDescription,
    /// which push block it uses
    layout:Layout=.world,
    /// whether it tests depth
    depth:bool=true,
    /// with `depth`: whether it writes depth (a glass pass only tests it)
    depthWrite:bool=true,
    /// with `depth`: only what lies strictly nearer passes. A glass pass
    /// draws the same instances as its solid pass at the very same depth
    /// (`invariant gl_Position`): the fragments the solid pass kept fail
    /// it before they are shaded, the see-through ones (which wrote no
    /// depth there) pass.
    nearer:bool=false,
    /// whether it blends over what is there by its alpha
    blend:bool=false,
    /// with `blend`: add its colour onto what is there instead (light
    /// laid on light), what is there's alpha kept where its own is 0
    additive:bool=false,
    /// what it draws into
    target:Target=.world,
    /// with MSAA, shade every sample: its fragments choose for themselves
    /// whether they are solid or see-through, so the edge between the two
    /// (and the silhouette it makes) lies inside the pixel, not on geometry
    perSample:bool=false,
  };
  /// the shader stages every push constant block is seen by
  pub const stages:vk.ShaderStageFlags=.{.vertex=true,.fragment=true};
  /// write each mesh's run of instances into `buf` back to back (at most
  /// `max` in all), noting where each run starts and how long it is;
  /// returns how many were written.
  pub fn upload(comptime I:type,buf:*Buffer,lists:[]const[]const I,first:[]u32,counts:[]u32,max:u32)u32{
    // how many instances are written so far
    var n:u32=0;
    for(lists,0..)|list,i|{
      // how many of this run fit
      const k:u32=@intCast(@min(list.len,max-n));
      first[i]=n;
      counts[i]=k;
      buf.write(n*@sizeOf(I),sliceAsBytes(list[0..k]));
      n+=k;
    }
    return n;
  }
  /// `samples`: per pixel of the world's attachments (the screen has one)
  /// a pipeline for pass `d` with push `layout`, drawing into the shadow map,
  /// the HDR image or the `screen`-format swapchain as `d.target` says
  pub fn create(c:*const Ctx,comptime d:Desc,layout:vk.PipelineLayout,screen:vk.Format,samples:u32)ctx.Error!vk.Pipeline{
    // the pass's vertex shader
    const vs=try c.shader(d.vert);
    defer c.device.destroyShaderModule(vs,null);
    // the pass's fragment shader: its ray-traced build where rays can be
    const fs=if(d.rayFrag!=null and c.rayTracing)try c.shader(d.rayFrag.?)else try c.shader(d.frag);
    defer c.device.destroyShaderModule(fs,null);
    // whether it only writes out what its vertex shader places
    const caught=d.target==.capture;
    return pipeline.create(c,.{
      .vert=vs,.frag=fs,
      .bindings=d.bindings,.attrs=d.attrs,
      .layout=layout,
      .colorFormat=switch(d.target){.shadow,.cube,.capture=>.undefined,.field=>fieldFormat,.overhead,.world,.volume=>hdrFormat,.screen=>screen},
      .depth=d.depth and !caught,.depthWrite=d.depthWrite,.depthCompare=if(d.nearer).less else.less_or_equal,.depthAttachment=d.target==.shadow or d.target==.cube or d.target==.world,.blend=d.blend,.additive=d.additive,.cull=false,.discard=caught,
      .samples=postMod.sampleFlags(if(d.target==.world)samples else 1),.perSample=d.perSample,
      .viewMask=switch(d.target){.shadow=>light.views,.cube=>cube.views,else=>0},
      .depthBias=switch(d.target){.shadow=>light.bias,.cube=>cube.bias,else=>null},
    });
  }
};
/// frames in flight: the CPU records one while the GPU draws the other
pub const frames=2;
/// points of light a frame can hold (the rest of a scene's `lights` is dropped)
pub const maxLights=light.maxLights;
/// the renderer fails the way the graphics layer does.
pub const Error=ctx.Error;
/// a captured frame: 4 bytes a pixel, row by row from the top
pub const Shot=struct{
  /// its width, in pixels
  w:u32,
  /// its height, in pixels
  h:u32,
  /// the pixels, `w`×`h`×4 bytes
  px:[]const u8,
  /// whether each pixel is blue, green, red, alpha (else red first)
  bgra:bool
};
/// how fast the GPU times follow the frames (share of the way a frame)
const gpuEase:f32=0.05;
/// the renderer for a game `G`, which declares
///   name:[*:0]const u8      the game's name, as the driver is told it
///   passes                  a namespace of pass modules, one line each, in
///                           record order (list `ui` from this file to get the HUD)
///   Push                    the world passes' push constants, holding at
///                           least `vp:m.M4`, `eyeTime`, `view`, `sun:[4]f32`
///                           and `light:[2]u32` (light.glsl reads them)
///   Scene                   what one frame draws: at least `push:Push`,
///                           `clear:[3]f32` and `lights:[]const vertex.Light`
///                           (and `ui`, `uiTime` when it lists `ui`)
///   Stats                   a frame's counts: at least `draws`, `lights:u32`
///                           and `gpuMs:f32`, every field defaulted
///   Ext                     state of its own the renderer keeps (`r.ext`),
///                           handed to `init`
///   start(r) Error!void     (optional) once every pipeline is made
///   release(r) void         (optional) free what `Ext` holds on the GPU;
///                           also after a failed `init`, so it skips what is
///                           not made yet
///   carry(prev:Stats) Stats (optional) what a frame's counts start from
pub fn Renderer(comptime G:type)type{
  return struct{
    /// (the renderer's own type)
    const R=@This();
    /// the game's passes, as a registry
    const reg=registry.Registry(G.passes);
    /// which pass: one per module in the game's list
    pub const Pass=reg.Id;
    /// the world passes' push constants
    pub const Push=G.Push;
    /// what one frame draws
    pub const Scene=G.Scene;
    /// a frame's counts
    pub const Stats=G.Stats;
    /// what the GPU's time is told apart by: each pass (`Pass` order; a
    /// `cube` pass's time is the shadow cubes' together), then the glow,
    /// the composite, every shadow cube drawn and the traced shadows' build
    /// (`glow`, `compose`, `cubed`, `built`)
    pub const stageCount=reg.count+4;
    /// (the glow's stage)
    pub const glow=reg.count;
    /// (the composite's stage)
    pub const compose=reg.count+1;
    /// (the shadow cubes' stage: every `cube` pass into every cube held)
    pub const cubed=reg.count+2;
    /// (the traced shadows' build: what was caught, built into rays.zig's levels)
    pub const built=reg.count+3;
    /// time stamps a frame writes: one before it, one after each stage
    const stamps=stageCount+1;
    /// what one frame in flight holds: its command buffer, sync, pass
    /// resources, lighting record, time stamps and garbage
    const Frame=struct{
      /// the pool its command buffer comes from
      pool:vk.CommandPool=.null_handle,
      /// freed with its pool
      cmd:vk.CommandBuffer=undefined,
      /// signalled when the GPU is through this frame
      fence:vk.Fence=.null_handle,
      /// signalled when its swapchain image is acquired
      acquired:vk.Semaphore=.null_handle,
      /// each pass's per-frame resources, side by side
      pass:reg.Struct("Frame")=undefined,
      /// this frame's `light.Lighting`, which every world shader reads by address
      lighting:Buffer=.{},
      /// its GPU time stamps (null where the GPU keeps none), how many it
      /// wrote and the stage each one ends (the first: none)
      queries:vk.QueryPool=.null_handle,
      /// (how many time stamps it wrote)
      stamped:u32=0,
      /// (the stage each time stamp ends)
      stage:[stamps]u32=undefined,
      /// buffers retired while this frame was in flight; freed when it comes round again.
      garbage:std.ArrayList(Buffer)=.empty,
      /// where the field's texel under the scene's `probe` is copied out
      /// to, and whether this frame copied one
      probe:Buffer=.{},
      /// (whether it copied one)
      probing:bool=false,
      /// where the whole field is copied out to when the scene asks
      /// (`readField`), and whether this frame copied it
      whole:Buffer=.{},
      /// (whether it copied it)
      wholing:bool=false,
    };
    /// the allocator the renderer and its lists are made with
    gpa:Allocator,
    /// the window it draws into
    window:*glfw.Window,
    /// the Vulkan context
    ctx:Ctx,
    /// the swapchain the screen is presented through
    sc:sw.Swapchain,
    /// the HDR image the world is drawn into, and the glow taken from it
    post:Post=.{},
    /// the key light's shadow map
    shadow:light.Shadow=.{},
    /// the points of light's shadow cubes
    cubes:cube.Cubes=.{},
    /// which lights hold the cubes, kept from frame to frame
    casters:cube.Casters=.{},
    /// how many points of light may hold a cube (0 .. `cube.maxCubes`;
    /// `pointShadows` sets it)
    cubeCount:usize=cube.maxCubes,
    /// each cube held this frame, the light it is drawn round (xyz where,
    /// w how far it reaches), null for one not drawn: what a `cube` pass
    /// may cull to
    cubeSpheres:[cube.maxCubes]?m.Vice(f32,4)=@splat(null),
    /// while the `cube` passes record: which face of which cube they draw
    /// into (cube × `cube.faces` + face)
    cubeNow:usize=0,
    /// the wall clock when the last frame's light was written (s), for
    /// easing the shadows in and out
    clock:?f64=null,
    /// the air: the overhead map, the volume and its composite
    volume:Volume=.{},
    /// what shadows are traced through as rays, caught and built each
    /// frame (null where the GPU cannot trace rays)
    rays:?raysMod.Rays=null,
    /// whether shadows are traced as rays while the GPU can (`setRays`);
    /// else, or where it cannot, they are drawn into the maps
    trace:bool=true,
    /// whether presenting waits for the display's refresh
    vsync:bool,
    /// each frame in flight's resources
    frames:[frames]Frame=@splat(.{}),
    /// which frame in flight is being recorded
    fi:usize=0,
    /// the push layouts: the world block (with the shadow map's set) and the UI's
    layouts:[2]vk.PipelineLayout=@splat(.null_handle),
    /// each pass's pipeline, by `Pass`
    pipes:[reg.count]vk.Pipeline=@splat(.null_handle),
    /// buffers retired since the last frame began; any frame still in flight
    /// may use them, so they join the next frame's garbage (freed only once
    /// that frame, and every frame before it, has finished on the GPU).
    pending:std.ArrayList(Buffer)=.empty,
    /// the last frame's counts, which the next starts from
    stats:Stats=.{},
    /// set before `draw`: copy that frame (UI and all) out for `shot`
    capture:bool=false,
    /// where a captured frame lands, and whether it holds one
    shotBuf:Buffer=.{},
    /// (whether `shotBuf` holds a frame not yet taken)
    shotReady:bool=false,
    /// the GPU's time for each stage of a frame (ms, eased; `stageCount` of them)
    gpuMs:[stageCount]f32=@splat(0),
    /// the GPU's time for the whole frame (ms, eased)
    gpuTotal:f32=0,
    /// the field (volume.zig) under the point the scene last asked after
    /// (its optional `probe`, world x and z), as the GPU had it a frame or
    /// two ago: null until one comes back
    probed:?m.Vec(f32,4)=null,
    /// the whole field as the GPU last had it when the scene asked
    /// (`readField`), a frame or two old (`Volume.texelIn` reads it): empty
    /// until one comes back
    field:[]u8=&.{},
    /// how many times `field` has come back: a new count, a new field
    fieldReads:u32=0,
    /// the game's own state (see `G.Ext`)
    ext:G.Ext,
    /// `aa` falls back to the most samples the GPU offers (see `antialias`)
    pub fn init(gpa:Allocator,window:*glfw.Window,vsync:bool,aa:Antialias,ext:G.Ext)Error!*R{
      // the renderer, made on the heap so passes may point at it
      const r=try gpa.create(R);
      errdefer gpa.destroy(r);
      r.*=.{.gpa=gpa,.window=window,.vsync=vsync,.ctx=undefined,.sc=.{},.ext=ext};
      r.post.aa=aa;
      for(&r.frames)|*f|inline for(reg.ids)|id|{
        if(comptime reg.has(id,"Frame"))@field(f.pass,@tagName(id))=.{};
      };
      r.ctx=try Ctx.init(gpa,window,G.name);
      errdefer r.ctx.deinit(gpa);
      // everything below starts null, so a half-built renderer frees cleanly
      errdefer r.release();
      r.build()catch|e|return ctx.fold(e);
      if(@hasDecl(G,"start"))try G.start(r);
      return r;
    }
    /// the steps of `init`: swapchain, post chain, shadow map, each frame's
    /// resources, push layouts and every pipeline
    fn build(r:*R)!void{
      // the context, short
      const c=&r.ctx;
      // the window's size in pixels
      const fb=r.window.getFramebufferSize();
      r.sc=try sw.Swapchain.init(c,r.gpa,@intCast(fb[0]),@intCast(fb[1]),r.vsync,.null_handle);
      r.post=try Post.init(c,r.sc.format.format,r.sc.extent.width,r.sc.extent.height,r.fit(r.post.aa));
      r.shadow=try light.Shadow.init(c);
      r.cubes=try cube.Cubes.init(c,r.cubes.res);
      r.shadow.bindCubes(c,&r.cubes);
      if(c.rayTracing){
        r.rays=try raysMod.Rays.init(c,r.gpa);
        r.shadow.bindRays(c,r.rays.?.handle());
      }
      r.volume=try Volume.init(c,r.sc.extent.width,r.sc.extent.height,r.sc.depthView);
      for(&r.frames)|*f|{
        f.lighting=try Buffer.init(c,@sizeOf(light.Lighting),.{.storage_buffer=true,.shader_device_address=true});
        f.probe=try Buffer.init(c,Volume.texelBytes,.{.transfer_dst=true});
        if(comptime @hasField(Scene,"readField"))f.whole=try Buffer.init(c,Volume.fieldBytes,.{.transfer_dst=true});
        f.pool=try c.device.createCommandPool(&.{.flags=.{.reset_command_buffer=true},.queue_family_index=c.family},null);
        f.fence=try c.device.createFence(&.{.flags=.{.signaled=true}},null);
        f.acquired=try c.device.createSemaphore(&.{},null);
        if(c.props.limits.timestamp_compute_and_graphics==.true){
          f.queries=try c.device.createQueryPool(&.{.query_type=.timestamp,.query_count=stamps},null);
        }
        inline for(reg.ids)|id|{
          if(comptime reg.has(id,"Frame"))@field(f.pass,@tagName(id))=try reg.module(id).initFrame(c);
        }
        try c.device.allocateCommandBuffers(&.{.command_pool=f.pool,.level=.primary,.command_buffer_count=1},@ptrCast(&f.cmd));
      }
      r.layouts[@intFromEnum(pass.Layout.world)]=try pipeline.layout(c,@sizeOf(Push),&.{r.shadow.setLayout,r.volume.setLayout});
      r.layouts[@intFromEnum(pass.Layout.ui)]=try pipeline.layout(c,@sizeOf(ui.Push),&.{});
      try r.makePipes(false);
    }
    /// every pass's pipeline (or with `worldOnly`, those drawing into the
    /// world, after its sample count changed: the old ones must be destroyed)
    fn makePipes(r:*R,worldOnly:bool)Error!void{
      // the world's samples per pixel
      const n=r.post.aa.samples();
      inline for(reg.ids)|id|{
        // this pass's description
        const d=reg.module(id).desc;
        // (a capture pass only where rays can be traced)
        if((!worldOnly or d.target==.world) and (d.target!=.capture or r.ctx.rayTracing)){
          r.pipes[@intFromEnum(id)]=try pass.create(&r.ctx,d,r.layout(d.layout),r.sc.format.format,n);
        }
      }
    }
    /// the most samples per pixel both the world's colour and depth can take
    pub fn maxSamples(r:*const R)u32{
      // the GPU's limits
      const l=r.ctx.props.limits;
      // the sample counts both colour and depth allow, as bits
      const both:u32=@as(u32,@bitCast(l.framebuffer_color_sample_counts))&@as(u32,@bitCast(l.framebuffer_depth_sample_counts));
      // the most samples tried first, halved until both allow it
      var n:u32=8;
      while(n>1 and both&n==0)n/=2;
      return n;
    }
    /// `aa`, or MSAA with as many samples as the GPU can take
    fn fit(r:*const R,aa:Antialias)Antialias{
      // the most samples the GPU allows
      const most=r.maxSamples();
      // the mode being stepped down to fit
      var a=aa;
      while(a.samples()>most)a=@enumFromInt(@intFromEnum(a)-1);
      return a;
    }
    /// what the world is smoothed with now
    pub fn antialiasing(r:*const R)Antialias{return r.post.aa;}
    /// smooth edges another way (what the GPU can take of `aa`); waits for
    /// the GPU and remakes the world's images and pipelines
    pub fn antialias(r:*R,aa:Antialias)Error!void{
      // what the GPU can take of `aa`
      const a=r.fit(aa);
      if(a==r.post.aa)return;
      // the context, short
      const c=&r.ctx;
      c.device.deviceWaitIdle()catch|e|return ctx.fold(e);
      // whether the sample count changes, so the world's pipelines must be remade
      const remake=a.samples()!=r.post.aa.samples();
      try r.post.antialias(c,a);
      if(!remake)return;
      inline for(reg.ids)|id|{
        if(comptime reg.module(id).desc.target==.world){
          c.device.destroyPipeline(r.pipes[@intFromEnum(id)],null);
          r.pipes[@intFromEnum(id)]=.null_handle;
        }
      }
      try r.makePipes(true);
    }
    /// how many of the most telling points of light near the camera cast
    /// shadows (`count`, held to 0 .. `cube.maxCubes`; a light losing its
    /// place eases its shadow out), each in a cube `size` texels a face
    /// side (a new size waits for the GPU and makes the cubes anew)
    pub fn pointShadows(r:*R,count:usize,size:u32)Error!void{
      r.cubeCount=@min(count,cube.maxCubes);
      if(size==r.cubes.res or size==0)return;
      // the context, short
      const c=&r.ctx;
      c.device.deviceWaitIdle()catch|e|return ctx.fold(e);
      r.cubes.deinit(c);
      r.cubes=try cube.Cubes.init(c,size);
      r.shadow.bindCubes(c,&r.cubes);
    }
    /// trace shadows as rays (where the GPU can) or draw them into the
    /// maps, from the next frame on
    pub fn setRays(r:*R,on:bool)void{r.trace=on;}
    /// whether this frame's shadows are traced as rays
    pub fn tracing(r:*const R)bool{return r.trace and r.rays!=null;}
    /// wait for the display's refresh or not; remakes the swapchain
    pub fn setVsync(r:*R,on:bool)Error!void{
      if(on==r.vsync)return;
      r.vsync=on;
      try r.recreate();
    }
    /// the pipeline of pass `p`
    pub fn pipe(r:*const R,p:Pass)vk.Pipeline{return r.pipes[@intFromEnum(p)];}
    /// the push layout `l`
    pub fn layout(r:*const R,l:pass.Layout)vk.PipelineLayout{return r.layouts[@intFromEnum(l)];}
    /// wait for the GPU, free everything and the renderer itself
    pub fn deinit(r:*R)void{
      // nothing to recover: teardown proceeds even if the device was lost
      r.ctx.device.deviceWaitIdle()catch{};
      r.logTimes();
      r.release();
      r.ctx.deinit(r.gpa);
      r.gpa.destroy(r);
    }
    /// each stage's GPU time and the whole frame's, eased over the last
    /// frames, one line each (`gpu <pass> <ms>`, then `gpu total <ms>`):
    /// what a benchmark run reads once the window closes
    /// (tools/perf/bench.sh)
    fn logTimes(r:*const R)void{
      if(r.gpuTotal==0)return;
      inline for(reg.ids)|id|std.log.info("gpu {s} {d:.3}",.{@tagName(id),r.gpuMs[@intFromEnum(id)]});
      std.log.info("gpu glow {d:.3}",.{r.gpuMs[glow]});
      std.log.info("gpu compose {d:.3}",.{r.gpuMs[compose]});
      std.log.info("gpu cubes {d:.3}",.{r.gpuMs[cubed]});
      std.log.info("gpu rays {d:.3}",.{r.gpuMs[built]});
      if(r.rays)|*ra|std.log.info("rays: {d} triangles cast every light's shadows, {d} only the points'; levels refitted {d}, built {d}",.{ra.trisOf(.both),ra.trisOf(.points),ra.refitted,ra.rebuilt});
      std.log.info("gpu total {d:.3}",.{r.gpuTotal});
    }
    /// free every GPU object the renderer made (null handles are skipped).
    fn release(r:*R)void{
      // the context, short
      const c=&r.ctx;
      if(@hasDecl(G,"release"))G.release(r);
      for(&r.frames)|*f|{
        for(f.garbage.items)|*b|b.deinit(c);
        f.garbage.deinit(r.gpa);
      }
      for(r.pending.items)|*b|b.deinit(c);
      r.pending.deinit(r.gpa);
      for(&r.frames)|*f|{
        inline for(reg.ids)|id|{
          if(comptime reg.has(id,"Frame"))reg.module(id).deinitFrame(&@field(f.pass,@tagName(id)),c);
        }
        f.lighting.deinit(c);
        f.probe.deinit(c);
        f.whole.deinit(c);
        c.device.destroyQueryPool(f.queries,null);
        c.device.destroySemaphore(f.acquired,null);
        c.device.destroyFence(f.fence,null);
        c.device.destroyCommandPool(f.pool,null);
      }
      r.shotBuf.deinit(c);
      r.gpa.free(r.field);
      r.field=&.{};
      for(r.pipes)|p|c.device.destroyPipeline(p,null);
      for(r.layouts)|l|c.device.destroyPipelineLayout(l,null);
      r.post.deinit(c);
      r.volume.deinit(c);
      r.cubes.deinit(c);
      if(r.rays)|*ra|ra.deinit(c);
      r.rays=null;
      r.shadow.deinit(c);
      r.sc.deinit(c,r.gpa,false);
    }
    /// free `b` once no frame in flight can still be using it
    pub fn retire(r:*R,b:Buffer)Allocator.Error!void{
      if(b.buf==.null_handle)return;
      try r.pending.append(r.gpa,b);
    }
    /// remake the swapchain (and the post images) for the window's size,
    /// waiting while the window is minimised
    fn recreate(r:*R)Error!void{
      // the context, short
      const c=&r.ctx;
      // the window's size in pixels
      var fb=r.window.getFramebufferSize();
      while(fb[0]==0 or fb[1]==0){
        glfw.waitEvents();
        fb=r.window.getFramebufferSize();
        if(r.window.shouldClose())return;
      }
      c.device.deviceWaitIdle()catch|e|return ctx.fold(e);
      // the old swapchain, handed over and then freed
      const old=r.sc;
      r.sc=try sw.Swapchain.init(c,r.gpa,@intCast(fb[0]),@intCast(fb[1]),r.vsync,old.handle);
      // (a copy that can be freed)
      var o=old;
      o.deinit(c,r.gpa,false);
      try r.post.resize(c,r.sc.extent.width,r.sc.extent.height);
      try r.volume.resize(c,r.sc.extent.width,r.sc.extent.height,r.sc.depthView);
    }
    /// the screen's size, in pixels
    pub fn extent(r:*const R)m.Vice(f32,2){
      return.{m.f(r.sc.extent.width),m.f(r.sc.extent.height)};
    }
    /// draw one frame of `scene` (remaking the swapchain instead when
    /// `resized`); a frame with `capture` set is kept for `shot`
    pub fn draw(r:*R,scene:*const Scene,resized:bool)Error!void{
      defer r.capture=false;
      r.frame(scene,resized)catch|e|return ctx.fold(e);
    }
    /// the frame last drawn with `capture` set (once; null if none was, or
    /// the swapchain cannot be read). Valid until the next `draw`.
    pub fn shot(r:*R)?Shot{
      if(!r.shotReady)return null;
      r.shotReady=false;
      // the frame's size
      const w=r.sc.extent.width;
      const h=r.sc.extent.height;
      // whether the pixels come blue first
      const bgra=switch(r.sc.format.format){
        .b8g8r8a8_srgb,.b8g8r8a8_unorm=>true,
        else=>false,
      };
      return.{.w=w,.h=h,.px=r.shotBuf.map[0..@as(usize,w)*h*4],.bgra=bgra};
    }
    /// one frame: wait for its slot, free its garbage, acquire, record every
    /// pass, submit and present
    fn frame(r:*R,scene:*const Scene,resized:bool)!void{
      // the context, short
      const c=&r.ctx;
      // this frame in flight
      const f=&r.frames[r.fi];
      _=try c.device.waitForFences(&.{f.fence},.true,m.maxInt(u64));
      for(f.garbage.items)|*b|b.deinit(c);
      f.garbage.clearRetainingCapacity();
      try f.garbage.appendSlice(r.gpa,r.pending.items);
      r.pending.clearRetainingCapacity();
      r.readTimes(f);
      if(f.probing){
        r.probed=Volume.texelOf(f.probe.map[0..Volume.texelBytes]);
        f.probing=false;
      }
      if(f.wholing){
        if(r.field.len==0)r.field=try r.gpa.alloc(u8,Volume.fieldBytes);
        @memcpy(r.field,f.whole.map[0..Volume.fieldBytes]);
        r.fieldReads+%=1;
        f.wholing=false;
      }
      if(resized){try r.recreate();return;}
      // the acquired swapchain image
      const acq=c.device.acquireNextImageKHR(r.sc.handle,m.maxInt(u64),f.acquired,.null_handle)catch|e|switch(e){
        error.OutOfDateKHR=>{try r.recreate();return;},
        else=>return e,
      };
      // which swapchain image it is
      const img=acq.image_index;
      try c.device.resetFences(&.{f.fence});
      // a capture copies the finished screen into a buffer the CPU reads
      // whether this frame is captured
      const cap=r.capture and r.sc.readable;
      if(cap){
        // how many bytes a capture needs
        const size=@as(u64,r.sc.extent.width)*r.sc.extent.height*4;
        if(r.shotBuf.size<size){
          try r.retire(r.shotBuf);
          r.shotBuf=try Buffer.init(c,size,.{.transfer_dst=true});
        }
      }
      // the frame's command buffer, with its calls attached
      const cmd=vk.CommandBufferProxy.init(f.cmd,c.vkd);
      try cmd.resetCommandBuffer(.{});
      try cmd.beginCommandBuffer(&.{.flags=.{.one_time_submit=true}});
      if(f.queries!=.null_handle)cmd.resetQueryPool(f.queries,0,stamps);
      f.stamped=0;
      stamp(cmd,f,stageCount);
      // every pass's data up, then the shadow casters into the shadow map,
      // the world into the HDR image, its glow, then the screen: the world
      // and its glow composed (and with FXAA filtered), the UI over it
      // the frame's counts, started from the last if the game asks
      var stats:Stats=if(@hasDecl(G,"carry"))G.carry(r.stats)else.{};
      stats.gpuMs=r.gpuTotal;
      // a copy of the scene, its push constants pointed at the lighting
      var sc=scene.*;
      // whether this frame's shadows are traced as rays (the maps are
      // then cleared but nothing is drawn into them)
      const traced=r.tracing();
      if(r.rays)|*ra|ra.begin();
      stats.lights=r.lightUp(f,&sc,traced);
      inline for(reg.ids)|id|{
        if(comptime reg.has(id,"prepare"))reg.module(id).prepare(r,&@field(f.pass,@tagName(id)),&sc,&stats);
      }
      if(comptime targets(.capture))if(traced){
        // the rays' casters as drawn this frame, caught and built
        const ra=&r.rays.?;
        try ra.fit(c);
        ra.open(cmd);
        r.record(f,cmd,.capture,&sc,&stats);
        ra.close(cmd);
        try ra.build(c,cmd,r.fi);
        stamp(cmd,f,built);
      };
      r.cubes.ready(cmd);
      r.shadow.begin(cmd);
      if(!traced)r.record(f,cmd,.shadow,&sc,&stats);
      r.shadow.end(cmd);
      if(comptime targets(.cube))if(!traced){
        r.recordCubes(f,cmd,&sc,&stats);
        stamp(cmd,f,cubed);
      };
      r.volume.beginOverhead(cmd);
      cmd.bindDescriptorSets(.graphics,r.layout(.world),0,&.{r.shadow.set},null);
      r.record(f,cmd,.overhead,&sc,&stats);
      r.volume.endOverhead(cmd);
      if(comptime targets(.field)){
        r.volume.beginField(cmd);
        cmd.bindDescriptorSets(.graphics,r.layout(.world),0,&.{r.shadow.set,r.volume.readSet()},null);
        r.record(f,cmd,.field,&sc,&stats);
        r.volume.endField(cmd);
        if(comptime @hasField(Scene,"probe"))if(scene.probe)|at|{
          r.volume.probe(cmd,at,f.probe.buf);
          f.probing=true;
        };
        if(comptime @hasField(Scene,"readField"))if(scene.readField){
          r.volume.readAll(cmd,f.whole.buf);
          f.wholing=true;
        };
      }
      r.beginWorld(cmd,scene.clear);
      r.record(f,cmd,.world,&sc,&stats);
      cmd.endRendering();
      r.volume.beginVolume(cmd,r.sc.depth);
      cmd.bindDescriptorSets(.graphics,r.layout(.world),0,&.{r.shadow.set,r.volume.readSet()},null);
      r.record(f,cmd,.volume,&sc,&stats);
      r.volume.compose(cmd,r.post.hdr);
      r.post.glow(cmd);
      stamp(cmd,f,glow);
      r.beginScreen(cmd,img);
      r.post.compose(cmd,r.sc.extent);
      stamp(cmd,f,compose);
      r.record(f,cmd,.screen,&sc,&stats);
      r.end(cmd,img,cap);
      try cmd.endCommandBuffer();
      try r.submit(f,img);
      // how presenting went (out of date is handled below)
      const pres=c.device.queuePresentKHR(c.queue,&.{
        .wait_semaphore_count=1,
        .p_wait_semaphores=@ptrCast(&r.sc.done[img]),
        .swapchain_count=1,
        .p_swapchains=@ptrCast(&r.sc.handle),
        .p_image_indices=@ptrCast(&img),
      })catch|e|switch(e){
        error.OutOfDateKHR=>vk.Result.error_out_of_date_khr,
        else=>return e,
      };
      // decision: a capture waits for its frame (screenshots only)
      if(cap){
        _=try c.device.waitForFences(&.{f.fence},.true,m.maxInt(u64));
        r.shotReady=true;
      }
      r.fi=(r.fi+1)%frames;
      r.stats=stats;
      if(pres!=.success or acq.result==.suboptimal_khr)try r.recreate();
    }
    /// whether any of the game's passes draws into `target`
    fn targets(comptime target:pass.Target)bool{
      inline for(reg.ids)|id|if(reg.module(id).desc.target==target)return true;
      return false;
    }
    /// every pass drawing into `target`, in declaration order
    fn record(r:*R,f:*Frame,cmd:vk.CommandBufferProxy,comptime target:pass.Target,scene:*const Scene,stats:*Stats)void{
      inline for(reg.ids)|id|{
        if(comptime reg.module(id).desc.target==target){
          reg.module(id).record(r,&@field(f.pass,@tagName(id)),cmd,scene,stats);
          stamp(cmd,f,@intFromEnum(id));
        }
      }
    }
    /// every `cube` pass into each face of each shadow cube held this frame,
    /// one face at a time: the scene's push pointing at that face's matrix, `cubeNow`
    /// saying which (timed together, as the `cubed` stage)
    fn recordCubes(r:*R,f:*Frame,cmd:vk.CommandBufferProxy,scene:*const Scene,stats:*Stats)void{
      // where the frame's lighting record lies on the GPU
      const at=f.lighting.address(&r.ctx);
      for(r.cubeSpheres,0..)|sphere,i|{
        if(sphere==null)continue;
        r.cubes.begin(cmd,i);
        for(0..cube.faces)|fc|{
          // the scene as this face's casters see it: its matrix in place of the record
          var sc=scene.*;
          const face=at+light.faceAt(i,fc);
          sc.push.light=.{@truncate(face),@truncate(face>>32)};
          r.cubeNow=i*cube.faces+fc;
          r.cubes.open(cmd,i,fc);
          inline for(reg.ids)|id|{
            if(comptime reg.module(id).desc.target==.cube)reg.module(id).record(r,&@field(f.pass,@tagName(id)),cmd,&sc,stats);
          }
          r.cubes.close(cmd);
        }
        r.cubes.end(cmd,i);
      }
    }
    /// a time stamp once the GPU is through what was recorded before it,
    /// ending `stage`
    fn stamp(cmd:vk.CommandBufferProxy,f:*Frame,stage:u32)void{
      if(f.queries==.null_handle)return;
      cmd.writeTimestamp2(.{.all_commands=true},f.queries,f.stamped);
      f.stage[f.stamped]=stage;
      f.stamped+=1;
    }
    /// the time stamps `f` wrote when last drawn (its fence is signalled) into
    /// each stage's time and the whole frame's
    fn readTimes(r:*R,f:*Frame)void{
      if(f.stamped<2)return;
      // the time stamps read back
      var t:[stamps]u64=undefined;
      // whether they could all be read
      const res=r.ctx.device.getQueryPoolResults(f.queries,0,f.stamped,f.stamped*@sizeOf(u64),&t,@sizeOf(u64),.{.@"64"=true}) catch return;
      if(res!=.success)return;
      // how many milliseconds one GPU tick is
      const msPerTick=r.ctx.props.limits.timestamp_period/m.nsPerMs;
      for(1..f.stamped)|i|{
        // the time this stage took
        const ms=m.f(t[i]-%t[i-1])*msPerTick;
        r.gpuMs[f.stage[i]]+=(ms-r.gpuMs[f.stage[i]])*gpuEase;
      }
      // the whole frame's time
      const whole=m.f(t[f.stamped-1]-%t[0])*msPerTick;
      r.gpuTotal+=(whole-r.gpuTotal)*gpuEase;
    }
    /// write this frame's lighting (the cascades fitted to the view, the
    /// points of light) and point the scene's push constants at it; how many
    /// points it holds. `traced`: this frame's shadows are traced as rays
    /// (the record says so, and no cube is drawn: none has a sphere)
    fn lightUp(r:*R,f:*Frame,scene:*Scene,traced:bool)u32{
      // the push constants, which carry the eye, view and sun
      const p=&scene.push;
      // the eye, and the point looked at on the ground
      const eye=m.v3(p.eyeTime[0],p.eyeTime[1],p.eyeTime[2]);
      const target=m.v3(p.view[0],0,p.view[1]);
      // shadows reach the drawn world's far edge as the eye sees it
      const reach=m.dist(eye,target)+p.view[3];
      // the shadow cascades fitted to the view and the sun
      const cas=light.fit(p.vp,eye,target,reach,m.v3(p.sun[0],p.sun[1],p.sun[2]));
      // how many points of light it holds
      const n:u32=@intCast(@min(scene.lights.len,light.maxLights));
      // the lighting record
      var l:light.Lighting=.{
        .cascades=cas.mats,.texel=undefined,
        .info=.{m.f(n),cas.reach,if(traced)1 else 0,m.f(r.post.aa.samples())},
        .lights=undefined,
        .cubes=@splat(cube.none),
      };
      @memcpy(l.texel[0..light.cascades],&cas.texel);
      @memcpy(l.lights[0..n],scene.lights[0..n]);
      for(l.lights[0..n])|*pl|pl.col[3]=0;
      // the seconds since the last frame's light, by the wall clock (so the
      // shadows ease alike whatever the world's pace)
      const now=glfw.getTime();
      const dt:f32=if(r.clock)|was|@floatCast(@max(now-was,0))else 0;
      r.clock=now;
      // which lights hold the shadow cubes now, and each one's record
      const fr=m.Frustum.of(p.vp);
      r.casters.update(l.lights[0..n],eye,target,&fr,r.cubeCount,dt);
      for(r.casters.slots,&l.cubes,&r.cubeSpheres,0..)|s,*q,*sphere,i|{
        sphere.*=null;
        const li=s.light orelse continue;
        q.*=cube.record(l.lights[li],li,cube.Casters.shownOf(s));
        l.lights[li].col[3]=m.f(i+1);
        if(!traced)sphere.*=l.lights[li].pos;
      }
      f.lighting.write(0,asBytes(&l));
      // where the record sits on the GPU, split into two words for the push
      const at=f.lighting.address(&r.ctx);
      p.light=.{@truncate(at),@truncate(at>>32)};
      return n;
    }
    /// open the world's rendering scope: the HDR image and the depth buffer
    /// (with MSAA, multisampled ones resolved into the HDR image and the
    /// swapchain's depth, its first sample), the depth kept for the air.
    fn beginWorld(r:*R,cmd:vk.CommandBufferProxy,clear:m.Vice(f32,3))void{
      r.post.beginWorld(cmd);
      // whether the world draws multisampled
      const ms=r.post.multisampled();
      // (what the air read of the depth last frame is done first)
      sw.barrier(cmd,r.sc.depth,sw.depthRange(),.undefined,.depth_attachment_optimal,
        .{.early_fragment_tests=true,.late_fragment_tests=true,.color_attachment_output=true,.fragment_shader=true},.{.depth_stencil_attachment_write=true,.color_attachment_write=true},
        .{.early_fragment_tests=true,.late_fragment_tests=true,.color_attachment_output=true},.{.depth_stencil_attachment_write=true,.depth_stencil_attachment_read=true,.color_attachment_write=true});
      if(ms)sw.barrier(cmd,r.post.msDepth.image,sw.depthRange(),.undefined,.depth_attachment_optimal,
        .{.early_fragment_tests=true,.late_fragment_tests=true},.{.depth_stencil_attachment_write=true},
        .{.early_fragment_tests=true,.late_fragment_tests=true},.{.depth_stencil_attachment_write=true,.depth_stencil_attachment_read=true});
      // the world's colour attachment
      const color=[_]vk.RenderingAttachmentInfo{r.post.worldColor(clear)};
      // the depth attachment: the multisampled one (its first sample
      // resolved into the swapchain's), or the swapchain's, kept
      const depth:vk.RenderingAttachmentInfo=.{
        .image_view=if(ms)r.post.msDepth.views[0]else r.sc.depthView,
        .image_layout=.depth_attachment_optimal,
        .resolve_mode=if(ms).{.sample_zero=true}else.{},
        .resolve_image_view=if(ms)r.sc.depthView else.null_handle,
        .resolve_image_layout=if(ms).depth_attachment_optimal else.undefined,
        .load_op=.clear,
        .store_op=if(ms).dont_care else.store,
        .clear_value=.{.depth_stencil=.{.depth=1,.stencil=0}},
      };
      r.scope(cmd,&color,&depth);
    }
    /// open the screen's rendering scope: the swapchain image, no depth.
    fn beginScreen(r:*R,cmd:vk.CommandBufferProxy,img:u32)void{
      sw.barrier(cmd,r.sc.images[img],sw.colorRange(),.undefined,.color_attachment_optimal,
        .{.color_attachment_output=true},.{},
        .{.color_attachment_output=true},.{.color_attachment_write=true});
      // the swapchain image, not cleared (the composite covers it)
      const color=[_]vk.RenderingAttachmentInfo{.{
        .image_view=r.sc.views[img],
        .image_layout=.color_attachment_optimal,
        .resolve_mode=.{},
        .resolve_image_layout=.undefined,
        .load_op=.dont_care,
        .store_op=.store,
        .clear_value=.{.color=.{.float_32=.{0,0,0,1}}},
      }};
      r.scope(cmd,&color,null);
    }
    /// begin a rendering scope over the whole screen with `color` and `depth`,
    /// setting the viewport and scissor to match
    fn scope(r:*R,cmd:vk.CommandBufferProxy,color:[]const vk.RenderingAttachmentInfo,depth:?*const vk.RenderingAttachmentInfo)void{
      // the whole screen
      const area:vk.Rect2D=.{.offset=.{.x=0,.y=0},.extent=r.sc.extent};
      cmd.beginRendering(&.{
        .render_area=area,
        .layer_count=1,
        .view_mask=0,
        .color_attachment_count=@intCast(color.len),
        .p_color_attachments=color.ptr,
        .p_depth_attachment=depth,
      });
      cmd.setViewport(0,&.{.{
        .x=0,.y=0,
        .width=m.f(r.sc.extent.width),
        .height=m.f(r.sc.extent.height),
        .min_depth=0,.max_depth=1,
      }});
      cmd.setScissor(0,&.{area});
    }
    /// close the rendering scope and hand the image to presentation (with
    /// `cap`, copied into `shotBuf` on the way).
    fn end(r:*R,cmd:vk.CommandBufferProxy,img:u32,cap:bool)void{
      cmd.endRendering();
      if(cap)r.copyOut(cmd,img);
      sw.barrier(cmd,r.sc.images[img],sw.colorRange(),if(cap).transfer_src_optimal else.color_attachment_optimal,.present_src_khr,
        if(cap).{.copy=true}else.{.color_attachment_output=true},if(cap).{}else.{.color_attachment_write=true},
        .{},.{});
    }
    /// the screen image into `shotBuf`, left as a transfer's source
    fn copyOut(r:*R,cmd:vk.CommandBufferProxy,img:u32)void{
      sw.barrier(cmd,r.sc.images[img],sw.colorRange(),.color_attachment_optimal,.transfer_src_optimal,
        .{.color_attachment_output=true},.{.color_attachment_write=true},
        .{.copy=true},.{.transfer_read=true});
      cmd.copyImageToBuffer(r.sc.images[img],.transfer_src_optimal,r.shotBuf.buf,&.{.{
        .buffer_offset=0,
        .buffer_row_length=0,
        .buffer_image_height=0,
        .image_subresource=.{.aspect_mask=.{.color=true},.mip_level=0,.base_array_layer=0,.layer_count=1},
        .image_offset=.{.x=0,.y=0,.z=0},
        .image_extent=.{.width=r.sc.extent.width,.height=r.sc.extent.height,.depth=1},
      }});
      // the host reads it once the frame's fence is signalled
      // the barrier that makes the copy visible to the host
      const done=[_]vk.MemoryBarrier2{.{
        .src_stage_mask=.{.copy=true},
        .src_access_mask=.{.transfer_write=true},
        .dst_stage_mask=.{.host=true},
        .dst_access_mask=.{.host_read=true},
      }};
      cmd.pipelineBarrier2(&.{.memory_barrier_count=done.len,.p_memory_barriers=&done});
    }
    /// submit the frame's commands: wait on its acquired image, signal its
    /// image's done semaphore and the frame's fence
    fn submit(r:*R,f:*Frame,img:u32)!void{
      // the context, short
      const c=&r.ctx;
      // what it waits on: the image being acquired, before drawing colour
      const wait=[_]vk.SemaphoreSubmitInfo{.{.semaphore=f.acquired,.value=0,.stage_mask=.{.color_attachment_output=true},.device_index=0}};
      // what it signals: the image's done semaphore, for presenting
      const signal=[_]vk.SemaphoreSubmitInfo{.{.semaphore=r.sc.done[img],.value=0,.stage_mask=.{.all_commands=true},.device_index=0}};
      // the command buffer submitted
      const cbi=[_]vk.CommandBufferSubmitInfo{.{.command_buffer=f.cmd,.device_mask=0}};
      try c.device.queueSubmit2(c.queue,&.{.{
        .wait_semaphore_info_count=wait.len,
        .p_wait_semaphore_infos=&wait,
        .command_buffer_info_count=cbi.len,
        .p_command_buffer_infos=&cbi,
        .signal_semaphore_info_count=signal.len,
        .p_signal_semaphore_infos=&signal,
      }},f.fence);
    }
  };
}
