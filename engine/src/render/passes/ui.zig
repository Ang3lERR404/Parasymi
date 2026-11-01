//! ui: the HUD batch, drawn last, blended, without depth. A game lists it
//! in its passes as `ui`; its scene carries `ui:[]const vertex.Ui` and
//! `uiTime:f32`.
/// the standard library
const std=@import("std");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=@import("../../core/math.zig");
/// a slice seen as its bytes, for copying the quads into the buffer
const sliceAsBytes=std.mem.sliceAsBytes;
/// the Vulkan bindings: the command buffer it records into
const vk=@import("vulkan");
/// the GPU layouts: the UI quad corner it draws
const vertex=@import("../../gfx/vertex.zig");
/// pipeline helpers, for the quad's vertex binding and attributes
const pipeline=@import("../../gfx/pipeline.zig");
/// the Vulkan context and its error fold
const ctx=@import("../../gfx/ctx.zig");
/// the device context its buffers are made with
const Ctx=ctx.Ctx;
/// a host-visible GPU buffer, the quads written straight into it
const Buffer=@import("../../gfx/buffer.zig").Buffer;
/// the renderer's pass vocabulary: `Desc`, the push stages
const pass=@import("../renderer.zig").pass;
/// the most quad corners drawn in one frame; any past it are dropped
pub const max=1<<17;
/// how the pass draws: the UI shaders over the quad corners, no depth,
/// blended over the finished frame on the screen
pub const desc:pass.Desc=.{
  .vert=@embedFile("ui.vert"),.frag=@embedFile("ui.frag"),
  .bindings=&.{pipeline.binding(vertex.Ui,0,.vertex)},
  .attrs=&pipeline.attrs(vertex.Ui,0,0),
  .layout=.ui,.depth=false,.blend=true,.target=.screen,
};
/// screen size and time for the animated shapes
pub const Push=extern struct{screen:m.Vice(f32,2),time:f32,pad:f32=0};
/// what each frame in flight holds: the buffer its quads are written into
/// (`verts`)
pub const Frame=struct{verts:Buffer=.{}};
/// a frame's quad buffer, room for `max` corners
pub fn initFrame(c:*const Ctx)ctx.Error!Frame{
  return.{.verts=try Buffer.init(c,max*@sizeOf(vertex.Ui),.{.vertex_buffer=true})};
}
/// free a frame's quad buffer
pub fn deinitFrame(f:*Frame,c:*const Ctx)void{f.verts.deinit(c);}
// decision: `r`, `scene` and `stats` are whatever renderer the game made
// (render/renderer.zig `Renderer(G)`), which this pass is one of, so it
// cannot name their types
/// draw the scene's UI quads over the frame: copied into this frame's
/// buffer, `max` at most, one draw for all of them
pub fn record(r:anytype,f:*Frame,cmd:vk.CommandBufferProxy,scene:anytype,stats:anytype)void{
  // how many corners are drawn
  const n:u32=@intCast(@min(scene.ui.len,max));
  if(n==0)return;
  f.verts.write(0,sliceAsBytes(scene.ui[0..n]));
  cmd.bindPipeline(.graphics,r.pipe(.ui));
  // the screen's size and the UI's clock, for the animated shapes
  const push:Push=.{.screen=r.extent(),.time=scene.uiTime};
  cmd.pushConstants(r.layout(desc.layout),pass.stages,0,@sizeOf(Push),&push);
  cmd.bindVertexBuffers(0,&.{f.verts.buf},&.{0});
  cmd.draw(n,1,0,0);
  stats.draws+=1;
}
