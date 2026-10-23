//! parts: library meshes (the wolf, nodes, motes, structures), one
//! instanced draw per mesh with a per-instance transform (or, for the tail
//! and the motes, the parameters part.vert places them by).
const std = @import("std");
const sliceAsBytes = std.mem.sliceAsBytes;
const vk = @import("vulkan");
const vertex = @import("../../gfx/vertex.zig");
const pipeline = @import("../../gfx/pipeline.zig");
const meshlib = @import("../../gfx/meshlib.zig");
const ctx = @import("../../gfx/ctx.zig");
const Ctx = ctx.Ctx;
const Buffer = @import("../../gfx/buffer.zig").Buffer;
const pass = R.pass;
const R = @import("../renderer.zig");

pub const MAX = 1 << 15;

pub const desc:pass.Desc = .{
  .vert = "part.vert", .frag = "part.frag",
  .bindings = &.{pipeline.binding(vertex.Mesh, 0, .vertex), pipeline.binding(vertex.PartInstance, 1, .instance)},
  .attrs = &(pipeline.attrs(vertex.Mesh, 0, 0) ++ pipeline.attrs(vertex.PartInstance, 1, 5)),
  // everything is opaque except translucent sap (instance fade < 1)
  .blend = true,
};

pub const Frame = struct { inst:Buffer = .{} };

pub fn initFrame(c:*const Ctx) ctx.Error!Frame {
  return .{.inst = try Buffer.init(c, MAX * @sizeOf(vertex.PartInstance), .{.vertex_buffer = true})};
}
pub fn deinitFrame(f:*Frame, c:*const Ctx) void { f.inst.deinit(c); }

pub fn record(r:*R.Renderer, f:*Frame, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
  var n:u32 = 0;
  var first:[meshlib.SLOTS]u32 = undefined;
  var counts:[meshlib.SLOTS]u32 = undefined;
  for (scene.parts, 0..) |list, i| {
    const k:u32 = @intCast(@min(list.len, MAX - n));
    first[i] = n;
    counts[i] = k;
    f.inst.write(n * @sizeOf(vertex.PartInstance), sliceAsBytes(list[0..k]));
    n += k;
  }
  if (n == 0) return;
  cmd.bindPipeline(.graphics, r.pipe(.parts));
  cmd.pushConstants(r.layout(desc.layout), pass.stages, 0, @sizeOf(R.WorldPush), &scene.push);
  cmd.bindVertexBuffers(0, &.{r.meshes.buf, f.inst.buf}, &.{0, 0});
  for (0..meshlib.SLOTS) |i| {
    if (counts[i] == 0) continue;
    cmd.draw(r.part_ranges[i][1], counts[i], r.part_ranges[i][0], first[i]);
    stats.draws += 1;
  }
  stats.parts = n;
}
