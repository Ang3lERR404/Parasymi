//! detail: the ground's grass, clods and stones, grown on the GPU. Each
//! chunk near the view draws its detail records (one per tile that has
//! any) as instances; detail.vert builds each tile's blades or stones from
//! its record and the vertex index, and sways the grass in the garden wind.
//! Shaded by terrain.frag, like the ground they stand on.
const lib=@import("../../lib.zig");
const vk=lib.engine.vk;
const vertex=lib.vertex;
const pipeline=lib.engine.gfx.pipeline;
const pass=renderer.pass;
const renderer=lib.renderer;
const m=lib.engine.core.math;
const ck=lib.ck;
pub const desc:pass.Desc=.{
  .vert=@embedFile("detail.vert"),.frag=@embedFile("terrain.frag"),
  .bindings=&.{pipeline.binding(vertex.DetailTile,0,.instance)},
  .attrs=&pipeline.attrs(vertex.DetailTile,0,0),
};
/// vertices each tile's instance runs: up to 8 grass blades of 3, or two
/// faceted lumps of 10 triangles on soil (what a tile does not use folds
/// away). Matches detail.vert.
pub const vertsPerTile=60;
/// how far from the view's focus (tiles, to a chunk's nearest edge) the
/// detail is drawn
const detailR:f32=28;
const half:f32=m.f(ck.sizeTiles)/2;
pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  cmd.bindPipeline(.graphics,r.pipe(.detail));
  cmd.pushConstants(r.layout(desc.layout),pass.stages,0,@sizeOf(renderer.WorldPush),&scene.push);
  const zero=[_]vk.DeviceSize{0};
  const focus=[2]f32{scene.push.view[0],scene.push.view[1]};
  const view=m.Frustum.of(scene.push.vp);
  for(r.ext.slots.items)|s|{
    if(!s.live or s.tiles==0)continue;
    if(!view.sphere(m.v3(s.centre[0],renderer.chunkMidY,s.centre[1]),renderer.chunkRadius))continue;
    const dx=@max(@abs(s.centre[0]-focus[0])-half,0);
    const dz=@max(@abs(s.centre[1]-focus[1])-half,0);
    if(dx*dx+dz*dz>detailR*detailR)continue;
    cmd.bindVertexBuffers(0,&.{s.detail.buf},&zero);
    cmd.draw(vertsPerTile,s.tiles,0,0);
    stats.draws+=1;
  }
}
