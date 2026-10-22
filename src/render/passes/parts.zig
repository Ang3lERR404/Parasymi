//! parts: rigid library meshes (the wolf, nodes, motes, structures), one
//! instanced draw per mesh with a per-instance transform, plus the frame's
//! live geometry (already in world space) drawn once with its own instance.
const std = @import("std");
const sliceAsBytes = std.mem.sliceAsBytes;
const asBytes = std.mem.asBytes;
const vk = @import("vulkan");
const vertex = @import("../../gfx/vertex.zig");
const pipeline = @import("../../gfx/pipeline.zig");
const meshlib = @import("../../gfx/meshlib.zig");
const ctx = @import("../../gfx/ctx.zig");
const Ctx = ctx.Ctx;
const Buffer = @import("../../gfx/buffer.zig").Buffer;
const pass = @import("../pass.zig");
const R = @import("../renderer.zig");

pub const MAX = 1 << 15;
/// vertices of live geometry per frame
pub const MAX_LIVE = 1 << 16;

pub const desc:pass.Desc = .{
  .vert = "part.vert", .frag = "part.frag",
  .bindings = &.{pipeline.binding(vertex.Mesh, 0, .vertex), pipeline.binding(vertex.PartInstance, 1, .instance)},
  .attrs = &(pipeline.attrs(vertex.Mesh, 0, 0) ++ pipeline.attrs(vertex.PartInstance, 1, 5)),
  // everything is opaque except translucent sap (instance fade < 1)
  .blend = true,
};

pub const Frame = struct { inst:Buffer = .{}, live:Buffer = .{} };

pub fn initFrame(c:*const Ctx) ctx.Error!Frame {
  var f:Frame = .{.inst = try Buffer.init(c, (MAX + 1) * @sizeOf(vertex.PartInstance), .{.vertex_buffer = true})};
  errdefer f.inst.deinit(c);
  f.live = try Buffer.init(c, MAX_LIVE * @sizeOf(vertex.Mesh), .{.vertex_buffer = true});
  return f;
}
pub fn deinitFrame(f:*Frame, c:*const Ctx) void {
  f.inst.deinit(c);
  f.live.deinit(c);
}

pub fn record(r:*R.Renderer, f:*Frame, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
  var n:u32 = 0;
  var first:[meshlib.count]u32 = undefined;
  var counts:[meshlib.count]u32 = undefined;
  for (scene.parts, 0..) |list, i| {
    const k:u32 = @intCast(@min(list.len, MAX - n));
    first[i] = n;
    counts[i] = k;
    f.inst.write(n * @sizeOf(vertex.PartInstance), sliceAsBytes(list[0..k]));
    n += k;
  }
  const live:u32 = @intCast(@min(scene.live.len, MAX_LIVE));
  if (n == 0 and live == 0) return;
  cmd.bindPipeline(.graphics, r.pipe(.parts));
  cmd.pushConstants(r.layout(desc.layout), pass.stages, 0, @sizeOf(R.WorldPush), &scene.push);
  cmd.bindVertexBuffers(0, &.{r.meshes.buf, f.inst.buf}, &.{0, 0});
  for (0..meshlib.count) |i| {
    if (counts[i] == 0) continue;
    cmd.draw(r.part_ranges[i][1], counts[i], r.part_ranges[i][0], first[i]);
    stats.draws += 1;
  }
  if (live > 0) {
    // the live instance sits right after the library instances (MAX + 1 slots)
    f.inst.write(n * @sizeOf(vertex.PartInstance), asBytes(&scene.live_inst));
    f.live.write(0, sliceAsBytes(scene.live[0..live]));
    cmd.bindVertexBuffers(0, &.{f.live.buf, f.inst.buf}, &.{0, 0});
    cmd.draw(live, 1, 0, n);
    stats.draws += 1;
  }
  stats.parts = n;
}
