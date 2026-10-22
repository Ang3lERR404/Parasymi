//! ui: the HUD batch, drawn last, blended, without depth.
const std = @import("std");
const sliceAsBytes = std.mem.sliceAsBytes;
const vk = @import("vulkan");
const vertex = @import("../../gfx/vertex.zig");
const pipeline = @import("../../gfx/pipeline.zig");
const Ctx = @import("../../gfx/ctx.zig").Ctx;
const Buffer = @import("../../gfx/buffer.zig").Buffer;
const pass = @import("../pass.zig");
const R = @import("../renderer.zig");

pub const MAX = 1 << 17;

pub const desc:pass.Desc = .{
  .vert = "ui.vert", .frag = "ui.frag",
  .bindings = &.{pipeline.binding(vertex.Ui, 0, .vertex)},
  .attrs = &pipeline.attrs(vertex.Ui, 0, 0),
  .layout = .ui, .depth = false, .blend = true,
};

/// screen size and time for the animated shapes
pub const Push = extern struct { screen:[2]f32, time:f32, pad:f32 = 0 };

pub const Frame = struct { verts:Buffer };

pub fn initFrame(c:*const Ctx) !Frame {
  return .{.verts = try Buffer.init(c, MAX * @sizeOf(vertex.Ui), .{.vertex_buffer = true})};
}
pub fn deinitFrame(f:*Frame, c:*const Ctx) void { f.verts.deinit(c); }

pub fn record(r:*R.Renderer, f:*Frame, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) !void {
  const n:u32 = @intCast(@min(scene.ui.len, MAX));
  if (n == 0) return;
  f.verts.write(0, sliceAsBytes(scene.ui[0..n]));
  cmd.bindPipeline(.graphics, r.pipe(.ui));
  const push:Push = .{.screen = r.extent(), .time = scene.ui_time};
  cmd.pushConstants(r.layout(desc.layout), pass.stages, 0, @sizeOf(Push), &push);
  cmd.bindVertexBuffers(0, &.{f.verts.buf}, &.{0});
  cmd.draw(n, 1, 0, 0);
  stats.draws += 1;
}
