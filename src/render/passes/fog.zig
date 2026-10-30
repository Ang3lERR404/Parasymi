//! fog: the air the garden stands in, marched on the GPU after the world at
//! half the screen's size (fog.frag): a haze over everything, mist lying low
//! on the ground and pooled in the hollows, the key light falling through it
//! in shafts where plants and structures shade it, the points of light and
//! the ley lines glowing in it. One full-screen triangle; the engine lays it
//! over the world (render/volume.zig). No vertex data.
const lib=@import("../../lib.zig");
/// the Vulkan bindings
const vk=lib.engine.vk;
/// what a pass declares
const pass=renderer.pass;
/// the garden's renderer: its scene and stats
const renderer=lib.renderer;
/// the fog pipeline: no vertices, no depth, into the volume
pub const desc:pass.Desc=.{
  .vert=@embedFile("fog.vert"),.frag=@embedFile("fog.frag"),
  .bindings=&.{},.attrs=&.{},
  .depth=false,.target=.volume,
};
/// marches the air: one full-screen triangle
pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  cmd.bindPipeline(.graphics,r.pipe(.fog));
  cmd.pushConstants(r.layout(desc.layout),pass.stages,0,@sizeOf(renderer.WorldPush),&scene.push);
  cmd.draw(3,1,0,0);
  stats.draws+=1;
}
