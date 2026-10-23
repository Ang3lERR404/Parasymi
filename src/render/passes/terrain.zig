//! terrain: one draw per resident chunk mesh (built by renderer.syncWorld).
const vk = @import("vulkan");
const vertex = @import("../../gfx/vertex.zig");
const pipeline = @import("../../gfx/pipeline.zig");
const pass = @import("../pass.zig");
const R = @import("../renderer.zig");
const ck = @import("../../world/chunk.zig");

pub const desc:pass.Desc = .{
  .vert = "terrain.vert", .frag = "terrain.frag",
  .bindings = &.{pipeline.binding(vertex.Terrain, 0, .vertex)},
  .attrs = &pipeline.attrs(vertex.Terrain, 0, 0),
};

/// how far from the view's focus (tiles, to a chunk's nearest edge) the
/// ground's detail is drawn
const DETAIL_R:f32 = 22;
const HALF:f32 = @as(f32, @floatFromInt(ck.SIZE)) / 2;

pub fn record(r:*R.Renderer, _:*void, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
  cmd.bindPipeline(.graphics, r.pipe(.terrain));
  cmd.pushConstants(r.layout(desc.layout), pass.stages, 0, @sizeOf(R.WorldPush), &scene.push);
  const zero = [_]vk.DeviceSize{0};
  // grass and stones are fine detail: drawn only on chunks near the view
  const focus = [2]f32{scene.push.view[0], scene.push.view[1]};
  for (r.slots.items) |s| {
    if (!s.live or s.count == 0) continue;
    cmd.bindVertexBuffers(0, &.{s.buf.buf}, &zero);
    const dx = @max(@abs(s.centre[0] - focus[0]) - HALF, 0);
    const dz = @max(@abs(s.centre[1] - focus[1]) - HALF, 0);
    const near = dx * dx + dz * dz < DETAIL_R * DETAIL_R;
    cmd.draw(if (near) s.count else s.ground, 1, 0, 0);
    stats.draws += 1;
    stats.chunks += 1;
  }
}
