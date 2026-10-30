//! sky: the dome behind everything, drawn first as one full-screen triangle
//! without depth (the world draws over it). No vertex data.
const lib=@import("../../lib.zig");
/// the Vulkan bindings
const vk=lib.engine.vk;
/// what a pass declares
const pass=renderer.pass;
/// the garden's renderer: its scene and stats
const renderer=lib.renderer;
/// the sky pipeline: no vertices, no depth
pub const desc:pass.Desc=.{
  .vert=@embedFile("sky.vert"),.frag=@embedFile("sky.frag"),
  .bindings=&.{},.attrs=&.{},
  .depth=false,
};
/// draws the sky: one full-screen triangle
pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  cmd.bindPipeline(.graphics,r.pipe(.sky));
  cmd.pushConstants(r.layout(desc.layout),pass.stages,0,@sizeOf(renderer.WorldPush),&scene.push);
  cmd.draw(3,1,0,0);
  stats.draws+=1;
}
