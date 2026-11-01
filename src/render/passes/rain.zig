//! rain: drops grown on the GPU over every spot near the view, falling
//! wherever the moisture field rains (render/passes/moisture.zig, its
//! blue), as many as the rain is heavy, splashing where they land
//! (rain.vert/.frag). Nothing goes up: each drop is its instance index and
//! the field; where it is dry, every drop folds away.
const lib=@import("../../lib.zig");
/// the Vulkan bindings
const vk=lib.engine.vk;
/// what a pass declares
const pass=renderer.pass;
/// the garden's renderer: its scene and stats
const renderer=lib.renderer;
/// the rain pipeline: no vertex buffers, blended over the world, testing
/// depth but writing none
pub const desc:pass.Desc=.{
  .vert=@embedFile("rain.vert"),.frag=@embedFile("rain.frag"),
  .bindings=&.{},.attrs=&.{},
  .depthWrite=false,.blend=true,
};
/// vertices each drop runs: its streak's two triangles, then its splash's
const vertsPerDrop=12;
/// how many drops: spots along each side of the grid round the view,
/// squared, in two layers (rain.vert COLS, LAYERS)
const drops=136*136*2;
/// draws every drop, one instanced draw
pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  cmd.bindPipeline(.graphics,r.pipe(.rain));
  cmd.pushConstants(r.layout(desc.layout),pass.stages,0,@sizeOf(renderer.WorldPush),&scene.push);
  cmd.draw(vertsPerDrop,drops,0,0);
  stats.draws+=1;
}
