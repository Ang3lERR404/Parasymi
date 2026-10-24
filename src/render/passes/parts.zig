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

const bindings = &[_]vk.VertexInputBindingDescription{pipeline.binding(vertex.Mesh, 0, .vertex), pipeline.binding(vertex.PartInstance, 1, .instance)};
const attrs = &(pipeline.attrs(vertex.Mesh, 0, 0) ++ pipeline.attrs(vertex.PartInstance, 1, 5));

pub const desc:pass.Desc = .{
  .vert = "part.vert", .frag = "part.frag",
  .bindings = bindings, .attrs = attrs, .per_sample = true,
};

/// this frame's instances, and where each mesh's run of them starts and how
/// long it is (the glass pass draws the same runs)
pub const Frame = struct {
  inst:Buffer = .{},
  first:[meshlib.SLOTS]u32 = undefined,
  counts:[meshlib.SLOTS]u32 = @splat(0),
};

pub fn initFrame(c:*const Ctx) ctx.Error!Frame {
  return .{.inst = try Buffer.init(c, MAX * @sizeOf(vertex.PartInstance), .{.vertex_buffer = true})};
}
pub fn deinitFrame(f:*Frame, c:*const Ctx) void { f.inst.deinit(c); }

/// upload every instance and draw their solid fragments.
pub fn record(r:*R.Renderer, f:*Frame, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
  var n:u32 = 0;
  for (scene.parts, 0..) |list, i| {
    const k:u32 = @intCast(@min(list.len, MAX - n));
    f.first[i] = n;
    f.counts[i] = k;
    f.inst.write(n * @sizeOf(vertex.PartInstance), sliceAsBytes(list[0..k]));
    n += k;
  }
  stats.parts = n;
  draw(r, f, cmd, scene, stats, .parts);
}

fn draw(r:*R.Renderer, f:*const Frame, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats, p:R.Pass) void {
  if (stats.parts == 0) return;
  cmd.bindPipeline(.graphics, r.pipe(p));
  cmd.pushConstants(r.layout(.world), pass.stages, 0, @sizeOf(R.WorldPush), &scene.push);
  cmd.bindVertexBuffers(0, &.{r.meshes.buf, f.inst.buf}, &.{0, 0});
  for (0..meshlib.SLOTS) |i| {
    if (f.counts[i] == 0 or (p == .parts_glass and !r.part_glassy[i])) continue;
    cmd.draw(r.part_ranges[i][1], f.counts[i], r.part_ranges[i][0], f.first[i]);
    stats.draws += 1;
  }
}

/// the parts' see-through fragments (sap and resin, shadows, beams, the
/// halo), drawn once every solid surface is down: the same instances,
/// blended over what is there, writing no depth.
pub const glass = struct {
  pub const desc:pass.Desc = .{
    .vert = "part.vert", .frag = "part_glass.frag",
    .bindings = bindings, .attrs = attrs,
    .blend = true, .depth_write = false, .per_sample = true,
  };
  pub fn record(r:*R.Renderer, _:*void, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
    draw(r, &r.frames[r.fi].pass.parts, cmd, scene, stats, .parts_glass);
  }
};
