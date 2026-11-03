//! terrain: one draw per resident chunk mesh (built by renderer.syncWorld).
const lib=@import("../../lib.zig");
/// the Vulkan bindings
const vk=lib.engine.vk;
/// the garden's vertex layouts: one ground vertex
const vertex=lib.vertex;
/// builds vertex bindings and attributes from a layout
const pipeline=lib.engine.gfx.pipeline;
/// what a pass declares
const pass=renderer.pass;
/// the garden's renderer: its chunk slots and culling sphere
const renderer=lib.renderer;
/// all the maths: the view frustum
const m=lib.engine.core.math;
/// the ground pipeline: terrain.vert and terrain.frag
pub const desc:pass.Desc=.{
  .vert=@embedFile("terrain.vert"),.frag=@embedFile("terrain.frag"),.rayFrag=@embedFile("terrain_ray.frag"),
  .bindings=&.{pipeline.binding(vertex.Terrain,0,.vertex)},
  .attrs=&pipeline.attrs(vertex.Terrain,0,0),
};
/// draws every live chunk's ground the camera can see, one draw each
pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  // (none of it on the main menu's dark stage)
  if(scene.stage)return;
  cmd.bindPipeline(.graphics,r.pipe(.terrain));
  cmd.pushConstants(r.layout(desc.layout),pass.stages,0,@sizeOf(renderer.WorldPush),&scene.push);
  // no offset into a chunk's buffer
  const zero=[_]vk.DeviceSize{0};
  // only chunks the camera can see
  const view=m.Frustum.of(scene.push.vp);
  for(r.ext.slots.items)|s|{
    if(!s.live or s.count==0)continue;
    if(!view.sphere(m.v3(s.centre[0],renderer.chunkMidY,s.centre[1]),renderer.chunkRadius))continue;
    cmd.bindVertexBuffers(0,&.{s.buf.buf},&zero);
    cmd.draw(s.count,1,0,0);
    stats.draws+=1;
    stats.chunks+=1;
  }
}
/// the ground seen from straight above into the overhead map: how it glows
/// (its ley) and how high it stands, for the fog to read (fog.frag). The map
/// keeps what was drawn into it, so each frame draws only a few chunks: any
/// not yet in it first, then the rest in their turn, so its glow keeps up
/// with ley sight and the ley lines sealing.
pub const overhead=struct{
  /// terrain.vert and terrain.frag with OVERHEAD: placed in the map,
  /// writing glow and height
  pub const desc:pass.Desc=.{
    .vert=@embedFile("terrain_overhead.vert"),.frag=@embedFile("terrain_overhead.frag"),
    .bindings=&.{pipeline.binding(vertex.Terrain,0,.vertex)},
    .attrs=&pipeline.attrs(vertex.Terrain,0,0),
    .depth=false,.target=.overhead,
  };
  /// chunks drawn into the map a frame
  const perFrame=4;
  /// draws a few live chunks' ground into the map: those not in it yet,
  /// then the next in turn, each placed by its own square of the map
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
    // (none of it on the main menu's dark stage)
    if(scene.stage)return;
    cmd.bindPipeline(.graphics,r.pipe(.terrainOverhead));
    // every chunk slot, and how many are drawn so far
    const slots=r.ext.slots.items;
    var n:u32=0;
    for(slots)|*s|{
      if(n>=perFrame)break;
      if(!s.live or s.overhead or s.count==0)continue;
      draw(r,cmd,scene,s);
      n+=1;
    }
    // the rest of the frame's draws refresh the next in turn
    var tries:usize=0;
    while(n<perFrame and tries<slots.len):(tries+=1){
      r.ext.overheadTurn=(r.ext.overheadTurn+1)%slots.len;
      const s=&slots[r.ext.overheadTurn];
      if(!s.live or s.count==0)continue;
      draw(r,cmd,scene,s);
      n+=1;
    }
    stats.draws+=n;
  }
  /// one chunk's ground into the map, pushed the map's frame for its square
  fn draw(r:*renderer.Renderer,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,s:*renderer.Slot)void{
    // the scene's push, seen from over the chunk's square of the map
    var push=scene.push;
    push.vp=lib.engine.render.volume.overheadOf(s.centre);
    cmd.pushConstants(r.layout(pass.Layout.world),pass.stages,0,@sizeOf(renderer.WorldPush),&push);
    // no offset into the chunk's buffer
    const zero=[_]vk.DeviceSize{0};
    cmd.bindVertexBuffers(0,&.{s.buf.buf},&zero);
    cmd.draw(s.count,1,0,0);
    s.overhead=true;
  }
};
