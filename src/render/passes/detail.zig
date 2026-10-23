//! detail: the ground's grass, clods and stones, grown on the GPU. Each
//! chunk near the view draws its detail records (one per tile that has
//! any) as instances; detail.vert builds each tile's blades or stones from
//! its record and the vertex index, and sways the grass in the garden wind.
//! Shaded by terrain.frag, like the ground they stand on.
const vk = @import("vulkan");
const vertex = @import("../../gfx/vertex.zig");
const pipeline = @import("../../gfx/pipeline.zig");
const pass = R.pass;
const R = @import("../renderer.zig");
const m = @import("../../core/math.zig");
const ck = @import("../../world/chunk.zig");

pub const desc:pass.Desc = .{
  .vert = "detail.vert", .frag = "terrain.frag",
  .bindings = &.{pipeline.binding(vertex.DetailTile, 0, .instance)},
  .attrs = &pipeline.attrs(vertex.DetailTile, 0, 0),
};

/// vertices each tile's instance runs: up to 8 grass blades of 3, or two
/// faceted lumps of 10 triangles on soil (what a tile does not use folds
/// away). Matches detail.vert.
pub const VERTS_PER_TILE = 60;
/// how far from the view's focus (tiles, to a chunk's nearest edge) the
/// detail is drawn
const DETAIL_R:f32 = 28;
const HALF:f32 = @as(f32, @floatFromInt(ck.SIZE)) / 2;

pub fn record(r:*R.Renderer, _:*void, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
  cmd.bindPipeline(.graphics, r.pipe(.detail));
  cmd.pushConstants(r.layout(desc.layout), pass.stages, 0, @sizeOf(R.WorldPush), &scene.push);
  const zero = [_]vk.DeviceSize{0};
  const focus = [2]f32{scene.push.view[0], scene.push.view[1]};
  const view = m.Frustum.of(scene.push.vp);
  for (r.slots.items) |s| {
    if (!s.live or s.tiles == 0) continue;
    if (!view.sphere(m.v3(s.centre[0], R.CHUNK_MID_Y, s.centre[1]), R.CHUNK_RADIUS)) continue;
    const dx = @max(@abs(s.centre[0] - focus[0]) - HALF, 0);
    const dz = @max(@abs(s.centre[1] - focus[1]) - HALF, 0);
    if (dx * dx + dz * dz > DETAIL_R * DETAIL_R) continue;
    cmd.bindVertexBuffers(0, &.{s.detail.buf}, &zero);
    cmd.draw(VERTS_PER_TILE, s.tiles, 0, 0);
    stats.draws += 1;
  }
}
