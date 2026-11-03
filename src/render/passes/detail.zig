//! detail: the ground's grass, clods and stones, grown on the GPU. Each
//! chunk near the view draws its detail records (one per tile that has
//! any) as instances; detail.vert builds each tile's blades or stones from
//! its record and the vertex index, and sways the grass in the garden wind.
//! Shaded by terrain.frag, like the ground they stand on.
const lib=@import("../../lib.zig");
/// the Vulkan bindings
const vk=lib.engine.vk;
/// the garden's vertex layouts: one detail record per instance
const vertex=lib.vertex;
/// builds vertex bindings and attributes from a layout
const pipeline=lib.engine.gfx.pipeline;
/// what a pass declares, and the upload helpers
const pass=renderer.pass;
/// the garden's renderer: its scene, slots and culling sphere
const renderer=lib.renderer;
/// all the maths: the view frustum, conversions
const m=lib.engine.core.math;
/// one chunk, for its width
const ck=lib.ck;
/// the detail pipeline: detail.vert grows each record, terrain.frag shades it
pub const desc:pass.Desc=.{
  .vert=@embedFile("detail.vert"),.frag=@embedFile("terrain.frag"),.rayFrag=@embedFile("terrain_ray.frag"),
  .bindings=&.{pipeline.binding(vertex.DetailTile,0,.instance)},
  .attrs=&pipeline.attrs(vertex.DetailTile,0,0),
};
/// vertices each tile's instance runs: two rounded lumps of 32 triangles
/// on soil, then up to 96 curved grass blades of 5 triangles, in tufts
/// (what a tile does not use folds away). Matches detail.vert.
pub const vertsPerTile=192+96*15;
/// how far from the view's focus (tiles, to a chunk's nearest edge) the
/// detail is drawn
const detailR:f32=28;
/// half a chunk's width, from its centre to its edge (tiles)
const half:f32=m.f(ck.sizeTiles)/2;
/// draws the detail of every live chunk in view and near the focus, one
/// instanced draw a chunk, each tile one instance
pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  // (none of it on the main menu's dark stage)
  if(scene.stage)return;
  cmd.bindPipeline(.graphics,r.pipe(.detail));
  cmd.pushConstants(r.layout(desc.layout),pass.stages,0,@sizeOf(renderer.WorldPush),&scene.push);
  // no offset into a chunk's detail buffer
  const zero=[_]vk.DeviceSize{0};
  // what the camera looks at (x, z)
  const focus=m.Vice(f32,2){scene.push.view[0],scene.push.view[1]};
  // the camera's view, for culling chunks out of it
  const view=m.Frustum.of(scene.push.vp);
  for(r.ext.slots.items)|s|{
    if(!s.live or s.tiles==0)continue;
    if(!view.sphere(m.v3(s.centre[0],renderer.chunkMidY,s.centre[1]),renderer.chunkRadius))continue;
    // how far the chunk's nearest edge lies from the focus, across and down
    const dx=@max(@abs(s.centre[0]-focus[0])-half,0);
    const dz=@max(@abs(s.centre[1]-focus[1])-half,0);
    if(dx*dx+dz*dz>detailR*detailR)continue;
    cmd.bindVertexBuffers(0,&.{s.detail.buf},&zero);
    cmd.draw(vertsPerTile,s.tiles,0,0);
    stats.draws+=1;
  }
}
