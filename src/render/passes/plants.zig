//! plants: every species' grown mesh variants, instanced; animation lives in plant.vert.
const std = @import("std");
const sliceAsBytes = std.mem.sliceAsBytes;
const vk = @import("vulkan");
const vertex = @import("../../gfx/vertex.zig");
const pipeline = @import("../../gfx/pipeline.zig");
const ctx = @import("../../gfx/ctx.zig");
const Ctx = ctx.Ctx;
const Buffer = @import("../../gfx/buffer.zig").Buffer;
const pass = R.pass;
const R = @import("../renderer.zig");

pub const MAX = 1 << 16;

// binding 2: the same mesh buffer, offset to the next growth key, so a
// confluence blends toward it (see Renderer.plant_morph)
const bindings = &[_]vk.VertexInputBindingDescription{pipeline.binding(vertex.Mesh, 0, .vertex), pipeline.binding(vertex.PlantInstance, 1, .instance), pipeline.binding(vertex.Mesh, 2, .vertex)};
const attrs = &(pipeline.attrs(vertex.Mesh, 0, 0) ++ pipeline.attrs(vertex.PlantInstance, 1, 5) ++ pipeline.attrs(vertex.MeshPose, 2, 10));

pub const desc:pass.Desc = .{
  .vert = "plant.vert", .frag = "plant.frag",
  .bindings = bindings, .attrs = attrs, .per_sample = true,
};

/// this frame's instances, and where each mesh's run of them starts and how
/// long it is (the glass pass draws the same runs)
pub const Frame = struct {
  inst:Buffer = .{},
  first:[R.PLANT_MESHES]u32 = undefined,
  counts:[R.PLANT_MESHES]u32 = @splat(0),
};

pub fn initFrame(c:*const Ctx) ctx.Error!Frame {
  return .{.inst = try Buffer.init(c, MAX * @sizeOf(vertex.PlantInstance), .{.vertex_buffer = true})};
}
pub fn deinitFrame(f:*Frame, c:*const Ctx) void { f.inst.deinit(c); }

/// upload every instance and draw their solid fragments.
pub fn record(r:*R.Renderer, f:*Frame, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
  var n:u32 = 0;
  for (scene.instances, 0..) |list, i| {
    const k:u32 = @intCast(@min(list.len, MAX - n));
    f.first[i] = n;
    f.counts[i] = k;
    f.inst.write(n * @sizeOf(vertex.PlantInstance), sliceAsBytes(list[0..k]));
    n += k;
  }
  stats.instances = n;
  draw(r, f, cmd, scene, stats, .plants);
}

fn draw(r:*R.Renderer, f:*const Frame, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats, p:R.Pass) void {
  if (stats.instances == 0) return;
  cmd.bindPipeline(.graphics, r.pipe(p));
  cmd.pushConstants(r.layout(.world), pass.stages, 0, @sizeOf(R.WorldPush), &scene.push);
  cmd.bindVertexBuffers(0, &.{r.meshes.buf, f.inst.buf}, &.{0, 0});
  for (0..R.PLANT_MESHES) |i| {
    if (f.counts[i] == 0) continue;
    cmd.bindVertexBuffers(2, &.{r.meshes.buf}, &.{r.plant_morph[i]});
    cmd.draw(r.plant_ranges[i][1], f.counts[i], r.plant_ranges[i][0], f.first[i]);
    stats.draws += 1;
  }
}

/// the plants' see-through fragments (thin petals, a confluence's sap, a
/// placement preview), drawn once every solid surface is down: the same
/// instances, blended over what is there, writing no depth.
pub const glass = struct {
  pub const desc:pass.Desc = .{
    .vert = "plant.vert", .frag = "plant_glass.frag",
    .bindings = bindings, .attrs = attrs,
    .blend = true, .depth_write = false, .per_sample = true,
  };
  pub fn record(r:*R.Renderer, _:*void, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
    draw(r, &r.frames[r.fi].pass.plants, cmd, scene, stats, .plants_glass);
  }
};
