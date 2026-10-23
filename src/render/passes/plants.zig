//! plants: every species' grown mesh variants, instanced; animation lives in plant.vert.
const std = @import("std");
const sliceAsBytes = std.mem.sliceAsBytes;
const vk = @import("vulkan");
const vertex = @import("../../gfx/vertex.zig");
const pipeline = @import("../../gfx/pipeline.zig");
const ctx = @import("../../gfx/ctx.zig");
const Ctx = ctx.Ctx;
const Buffer = @import("../../gfx/buffer.zig").Buffer;
const pass = @import("../pass.zig");
const R = @import("../renderer.zig");

pub const MAX = 1 << 16;

pub const desc:pass.Desc = .{
  .vert = "plant.vert", .frag = "plant.frag",
  .bindings = &.{pipeline.binding(vertex.Mesh, 0, .vertex), pipeline.binding(vertex.PlantInstance, 1, .instance)},
  .attrs = &(pipeline.attrs(vertex.Mesh, 0, 0) ++ pipeline.attrs(vertex.PlantInstance, 1, 5)),
  // decision: blending on for the confluence's translucent petals; every
  // other plant fragment is opaque (alpha 1), so they are unchanged. The
  // confluence is the last species, so its petals blend over every plant.
  .blend = true,
};

pub const Frame = struct { inst:Buffer = .{} };

pub fn initFrame(c:*const Ctx) ctx.Error!Frame {
  return .{.inst = try Buffer.init(c, MAX * @sizeOf(vertex.PlantInstance), .{.vertex_buffer = true})};
}
pub fn deinitFrame(f:*Frame, c:*const Ctx) void { f.inst.deinit(c); }

pub fn record(r:*R.Renderer, f:*Frame, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
  var n:u32 = 0;
  var first:[R.PLANT_MESHES]u32 = undefined;
  var counts:[R.PLANT_MESHES]u32 = undefined;
  for (scene.instances, 0..) |list, i| {
    const k:u32 = @intCast(@min(list.len, MAX - n));
    first[i] = n;
    counts[i] = k;
    f.inst.write(n * @sizeOf(vertex.PlantInstance), sliceAsBytes(list[0..k]));
    n += k;
  }
  if (n == 0) return;
  cmd.bindPipeline(.graphics, r.pipe(.plants));
  cmd.pushConstants(r.layout(desc.layout), pass.stages, 0, @sizeOf(R.WorldPush), &scene.push);
  cmd.bindVertexBuffers(0, &.{r.meshes.buf, f.inst.buf}, &.{0, 0});
  for (0..R.PLANT_MESHES) |i| {
    if (counts[i] == 0) continue;
    cmd.draw(r.plant_ranges[i][1], counts[i], r.plant_ranges[i][0], first[i]);
    stats.draws += 1;
  }
  stats.instances = n;
}
