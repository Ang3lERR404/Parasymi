//! terrain: one draw per resident chunk mesh (built by renderer.syncWorld).
const lib = @import("../../lib.zig");
const vk = lib.engine.vk;
const vertex = lib.vertex;
const pipeline = lib.engine.gfx.pipeline;
const pass = R.pass;
const R = lib.renderer;
const m = lib.engine.core.math;

pub const desc:pass.Desc = .{
  .vert = @embedFile("terrain.vert"), .frag = @embedFile("terrain.frag"),
  .bindings = &.{pipeline.binding(vertex.Terrain, 0, .vertex)},
  .attrs = &pipeline.attrs(vertex.Terrain, 0, 0),
};

pub fn record(r:*R.Renderer, _:*void, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
  cmd.bindPipeline(.graphics, r.pipe(.terrain));
  cmd.pushConstants(r.layout(desc.layout), pass.stages, 0, @sizeOf(R.WorldPush), &scene.push);
  const zero = [_]vk.DeviceSize{0};
  // only chunks the camera can see
  const view = m.Frustum.of(scene.push.vp);
  for (r.ext.slots.items) |s| {
    if (!s.live or s.count == 0) continue;
    if (!view.sphere(m.v3(s.centre[0], R.CHUNK_MID_Y, s.centre[1]), R.CHUNK_RADIUS)) continue;
    cmd.bindVertexBuffers(0, &.{s.buf.buf}, &zero);
    cmd.draw(s.count, 1, 0, 0);
    stats.draws += 1;
    stats.chunks += 1;
  }
}

