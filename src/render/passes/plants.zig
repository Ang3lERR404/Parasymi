//! plants: every species' grown mesh variants, instanced; animation lives in plant.vert.
const vk = @import("engine").vk;
const vertex = @import("../../gfx/vertex.zig");
const pipeline = @import("engine").gfx.pipeline;
const ctx = @import("engine").gfx.ctx;
const Ctx = ctx.Ctx;
const Buffer = @import("engine").gfx.buffer.Buffer;
const pass = R.pass;
const R = @import("../renderer.zig");

pub const MAX = 1 << 16;

// binding 2: the same mesh buffer, offset to the next growth key, so a
// confluence blends toward it (see the renderer's `Ext.plant_morph`)
const bindings = &[_]vk.VertexInputBindingDescription{pipeline.binding(vertex.Mesh, 0, .vertex), pipeline.binding(vertex.PlantInstance, 1, .instance), pipeline.binding(vertex.Mesh, 2, .vertex)};
const attrs = &(pipeline.attrs(vertex.Mesh, 0, 0) ++ pipeline.attrs(vertex.PlantInstance, 1, 5) ++ pipeline.attrs(vertex.MeshPose, 2, 10));

pub const desc:pass.Desc = .{
  .vert = @embedFile("plant.vert"), .frag = @embedFile("plant.frag"),
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

/// upload every instance (before any pass draws them).
pub fn prepare(r:*R.Renderer, f:*Frame, scene:*const R.Scene, stats:*R.Stats) void {
  _ = r;
  stats.instances = pass.upload(vertex.PlantInstance, &f.inst, &scene.instances, &f.first, &f.counts, MAX);
}

/// their solid fragments.
pub fn record(r:*R.Renderer, f:*Frame, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
  draw(r, f, cmd, scene, stats, .plants);
}

fn draw(r:*R.Renderer, f:*const Frame, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats, p:R.Pass) void {
  if (stats.instances == 0) return;
  cmd.bindPipeline(.graphics, r.pipe(p));
  cmd.pushConstants(r.layout(.world), pass.stages, 0, @sizeOf(R.WorldPush), &scene.push);
  cmd.bindVertexBuffers(0, &.{r.ext.meshes.buf, f.inst.buf}, &.{0, 0});
  for (0..R.PLANT_MESHES) |i| {
    if (f.counts[i] == 0) continue;
    const mesh = if (p == .plants_shadow) R.caster(i) else i;
    cmd.bindVertexBuffers(2, &.{r.ext.meshes.buf}, &.{r.ext.plant_morph[mesh]});
    cmd.draw(r.ext.plant_ranges[mesh][1], f.counts[i], r.ext.plant_ranges[mesh][0], f.first[i]);
    stats.draws += 1;
  }
}

/// the plants' see-through fragments (thin petals, a confluence's sap, a
/// placement preview), drawn once every solid surface is down: the same
/// instances, blended over what is there, writing no depth.
pub const glass = struct {
  pub const desc:pass.Desc = .{
    .vert = @embedFile("plant.vert"), .frag = @embedFile("plant_glass.frag"),
    .bindings = bindings, .attrs = attrs,
    .blend = true, .depth_write = false, .nearer = true, .per_sample = true,
  };
  pub fn record(r:*R.Renderer, _:*void, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
    draw(r, &r.frames[r.fi].pass.plants, cmd, scene, stats, .plants_glass);
  }
};

/// the plants as the key light sees them, into every cascade of its shadow
/// map: the same instances, swaying and growing as they are drawn (what
/// is light itself or clear sap casts none; plant.vert under SHADOW)
pub const shadow = struct {
  pub const desc:pass.Desc = .{
    .vert = @embedFile("plant_shadow.vert"), .frag = @import("engine").shadow_frag,
    .bindings = bindings, .attrs = attrs, .target = .shadow,
  };
  pub fn record(r:*R.Renderer, _:*void, cmd:vk.CommandBufferProxy, scene:*const R.Scene, stats:*R.Stats) void {
    draw(r, &r.frames[r.fi].pass.plants, cmd, scene, stats, .plants_shadow);
  }
};

