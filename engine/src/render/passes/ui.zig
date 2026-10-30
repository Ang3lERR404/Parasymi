//! ui: the HUD batch, drawn last, blended, without depth. A game lists it
//! in its passes as `ui`; its scene carries `ui:[]const vertex.Ui` and
//! `ui_time:f32`.
const std=@import("std");
const sliceAsBytes=std.mem.sliceAsBytes;
const vk=@import("vulkan");
const vertex=@import("../../gfx/vertex.zig");
const pipeline=@import("../../gfx/pipeline.zig");
const ctx=@import("../../gfx/ctx.zig");
const Ctx=ctx.Ctx;
const Buffer=@import("../../gfx/buffer.zig").Buffer;
const pass=@import("../renderer.zig").pass;
pub const max=1<<17;
pub const desc:pass.Desc=.{
  .vert=@embedFile("ui.vert"),.frag=@embedFile("ui.frag"),
  .bindings=&.{pipeline.binding(vertex.Ui,0,.vertex)},
  .attrs=&pipeline.attrs(vertex.Ui,0,0),
  .layout=.ui,.depth=false,.blend=true,.target=.screen,
};
/// screen size and time for the animated shapes
pub const Push=extern struct{screen:[2]f32,time:f32,pad:f32=0};
pub const Frame=struct{verts:Buffer=.{}};
pub fn initFrame(c:*const Ctx)ctx.Error!Frame{
  return.{.verts=try Buffer.init(c,max*@sizeOf(vertex.Ui),.{.vertex_buffer=true})};
}
pub fn deinitFrame(f:*Frame,c:*const Ctx)void{f.verts.deinit(c);}
// decision: `r`, `scene` and `stats` are whatever renderer the game made
// (render/renderer.zig `Renderer(G)`), which this pass is one of, so it
// cannot name their types
pub fn record(r:anytype,f:*Frame,cmd:vk.CommandBufferProxy,scene:anytype,stats:anytype)void{
  const n:u32=@intCast(@min(scene.ui.len,max));
  if(n==0)return;
  f.verts.write(0,sliceAsBytes(scene.ui[0..n]));
  cmd.bindPipeline(.graphics,r.pipe(.ui));
  const push:Push=.{.screen=r.extent(),.time=scene.uiTime};
  cmd.pushConstants(r.layout(desc.layout),pass.stages,0,@sizeOf(Push),&push);
  cmd.bindVertexBuffers(0,&.{f.verts.buf},&.{0});
  cmd.draw(n,1,0,0);
  stats.draws+=1;
}
