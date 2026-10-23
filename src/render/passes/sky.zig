//! sky: the dome behind everything, drawn first as one full-screen triangle
//! without depth (the world draws over it). No vertex data.
const vk = @import("vulkan");
const pass = R.pass;
const R = @import("../renderer.zig");

pub const desc:pass.Desc = .{
  .vert = "sky.vert", .frag = "sky.frag",
  .bindings = &.{}, .attrs = &.{},
  .depth = false,
};

pub fn record(r:*R.Renderer, _:*void, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
  cmd.bindPipeline(.graphics, r.pipe(.sky));
  cmd.pushConstants(r.layout(desc.layout), pass.stages, 0, @sizeOf(R.WorldPush), &scene.push);
  cmd.draw(3, 1, 0, 0);
  stats.draws += 1;
}
