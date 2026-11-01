//! moisture: the water in the garden's air, kept on the GPU as the engine's
//! field (render/volume.zig, a texel a unit over the world, wrapping), one
//! step a frame. `field` carries the last step on (moisture.frag): each
//! texel drifts along the wind, spreads into its neighbours and slowly
//! dries; then `sources` lays in what everything breathing moisture breathed
//! since (moisture_source.vert/.frag), each a soft disc. Two kinds: the low
//! mist (red), lying on the ground, and the cloud (green), gathering high
//! over what breathes it. Each step is as long as the world moved this
//! frame (`Scene.step`; none while frozen). The fog reads it (air.glsl),
//! so the mist and the cloud are drawn in the air.
const lib=@import("../../lib.zig");
/// the Vulkan bindings
const vk=lib.engine.vk;
/// the garden's vertex and instance layouts
const vertex=lib.vertex;
/// builds vertex bindings and attributes from a layout
const pipeline=lib.engine.gfx.pipeline;
/// the graphics context and how it fails
const ctx=lib.engine.gfx.ctx;
/// the graphics context, which buffers are made on
const Ctx=ctx.Ctx;
/// a GPU buffer: this frame's sources
const Buffer=lib.engine.gfx.buffer.Buffer;
/// what a pass declares
const pass=renderer.pass;
/// the garden's renderer: its scene and stats
const renderer=lib.renderer;
/// a slice seen as its bytes, for uploading the sources
const sliceAsBytes=lib.std.mem.sliceAsBytes;
/// the most things breathing moisture a frame lays in (the rest wait)
pub const max=256;
/// carries the field one step on: one full-screen triangle over all of it
pub const field=struct{
  /// the step: moisture.frag over every texel of the field
  pub const desc:pass.Desc=.{
    .vert=@embedFile("moisture.vert"),.frag=@embedFile("moisture.frag"),
    .bindings=&.{pipeline.binding(vertex.MoistureStep,0,.instance)},
    .attrs=&pipeline.attrs(vertex.MoistureStep,0,0),
    .depth=false,.target=.field,
  };
  /// this frame's step, as its one instance
  pub const Frame=struct{
    /// the step: how long it is
    inst:Buffer=.{},
  };
  /// makes one frame's buffer: room for the step
  pub fn initFrame(c:*const Ctx)ctx.Error!Frame{
    return.{.inst=try Buffer.init(c,@sizeOf(vertex.MoistureStep),.{.vertex_buffer=true})};
  }
  /// frees one frame's buffer
  pub fn deinitFrame(f:*Frame,c:*const Ctx)void{f.inst.deinit(c);}
  /// uploads how long this frame's step is
  pub fn prepare(_:*renderer.Renderer,f:*Frame,scene:*const renderer.Scene,_:*renderer.Stats)void{
    // the step, as its one instance
    const s=[_]vertex.MoistureStep{.{.dt=.{scene.step,0,0,0}}};
    f.inst.write(0,sliceAsBytes(&s));
  }
  /// draws the step
  pub fn record(r:*renderer.Renderer,f:*Frame,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
    cmd.bindPipeline(.graphics,r.pipe(.moistureField));
    cmd.pushConstants(r.layout(desc.layout),pass.stages,0,@sizeOf(renderer.WorldPush),&scene.push);
    cmd.bindVertexBuffers(0,&.{f.inst.buf},&.{0});
    cmd.draw(3,1,0,0);
    stats.draws+=1;
  }
};
/// what everything breathing moisture breathed since the last step, added
/// onto the step just carried on: one soft disc each, six vertices
pub const sources=struct{
  /// the discs: laid onto the field, added to what is there
  pub const desc:pass.Desc=.{
    .vert=@embedFile("moisture_source.vert"),.frag=@embedFile("moisture_source.frag"),
    .bindings=&.{pipeline.binding(vertex.Moisture,0,.instance)},
    .attrs=&pipeline.attrs(vertex.Moisture,0,0),
    .depth=false,.blend=true,.additive=true,.target=.field,
  };
  /// this frame's sources, and how many
  pub const Frame=struct{
    /// this frame's sources
    inst:Buffer=.{},
    /// how many it holds
    n:u32=0,
  };
  /// makes one frame's buffer: room for every source
  pub fn initFrame(c:*const Ctx)ctx.Error!Frame{
    return.{.inst=try Buffer.init(c,max*@sizeOf(vertex.Moisture),.{.vertex_buffer=true})};
  }
  /// frees one frame's buffer
  pub fn deinitFrame(f:*Frame,c:*const Ctx)void{f.inst.deinit(c);}
  /// uploads the scene's sources (as many as fit), each carrying this
  /// frame's step
  pub fn prepare(_:*renderer.Renderer,f:*Frame,scene:*const renderer.Scene,_:*renderer.Stats)void{
    f.n=@intCast(@min(scene.moisture.len,max));
    // the sources as uploaded, the step written into each
    var up:[max]vertex.Moisture=undefined;
    for(up[0..f.n],scene.moisture[0..f.n])|*u,s|{
      u.*=s;
      u.at[3]=scene.step;
    }
    if(f.n>0)f.inst.write(0,sliceAsBytes(up[0..f.n]));
  }
  /// lays them in, one instanced draw
  pub fn record(r:*renderer.Renderer,f:*Frame,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
    if(f.n==0)return;
    cmd.bindPipeline(.graphics,r.pipe(.moistureSources));
    cmd.pushConstants(r.layout(desc.layout),pass.stages,0,@sizeOf(renderer.WorldPush),&scene.push);
    cmd.bindVertexBuffers(0,&.{f.inst.buf},&.{0});
    cmd.draw(6,f.n,0,0);
    stats.draws+=1;
  }
};
