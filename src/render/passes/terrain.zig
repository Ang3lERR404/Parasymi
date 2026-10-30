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
  .vert=@embedFile("terrain.vert"),.frag=@embedFile("terrain.frag"),
  .bindings=&.{pipeline.binding(vertex.Terrain,0,.vertex)},
  .attrs=&pipeline.attrs(vertex.Terrain,0,0),
};
/// draws every live chunk's ground the camera can see, one draw each
pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
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
