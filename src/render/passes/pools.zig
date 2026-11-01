//! pools: the rain pooled in the ground's dips, grown on the GPU from the
//! moisture field (render/passes/moisture.zig, its alpha past 1) as a
//! surface of water over every texel near the view (pools.vert/.frag).
//! Nothing goes up: each quad is its instance index and the field; where it
//! is dry, every quad folds away.
const lib=@import("../../lib.zig");
/// the Vulkan bindings
const vk=lib.engine.vk;
/// what a pass declares
const pass=renderer.pass;
/// the garden's renderer: its scene and stats
const renderer=lib.renderer;
/// the pools' pipeline: no vertex buffers, blended over the solids, testing
/// depth but writing none
pub const desc:pass.Desc=.{
  .vert=@embedFile("pools.vert"),.frag=@embedFile("pools.frag"),
  .bindings=&.{},.attrs=&.{},
  .depthWrite=false,.blend=true,
};
/// vertices each quad runs: its two triangles
const vertsPerQuad=6;
/// how many quads: texels along each side of the grid round the view,
/// squared (pools.vert COLS)
const quads=96*96;
/// draws every quad, one instanced draw
pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  cmd.bindPipeline(.graphics,r.pipe(.pools));
  cmd.pushConstants(r.layout(desc.layout),pass.stages,0,@sizeOf(renderer.WorldPush),&scene.push);
  cmd.draw(vertsPerQuad,quads,0,0);
  stats.draws+=1;
}
