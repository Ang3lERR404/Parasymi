//! parts: library meshes (the wolf, nodes, motes, structures), one
//! instanced draw per mesh with a per-instance transform (or, for beams,
//! motes and the skinned wolf, the parameters part.vert places them by).
const lib = @import("../../lib.zig");
const std = lib.std;
const sliceAsBytes = std.mem.sliceAsBytes;
const vk = lib.engine.vk;
const m = lib.engine.core.math;
const vertex = lib.vertex;
const pipeline = lib.engine.gfx.pipeline;
const meshlib = lib.meshlib;
const ctx = lib.engine.gfx.ctx;
const Ctx = ctx.Ctx;
const Buffer = lib.engine.gfx.buffer.Buffer;
const pass = R.pass;
const R = lib.renderer;

pub const MAX = 1 << 15;
/// skinned parts' bones a frame can hold
pub const MAX_BONES = 256;

const bindings = &[_]vk.VertexInputBindingDescription{
  pipeline.binding(vertex.Mesh, 0, .vertex), pipeline.binding(vertex.PartInstance, 1, .instance), pipeline.binding(vertex.Skin, 2, .vertex),
  pipeline.binding(vertex.Grow, 3, .vertex),
};
const attrs = &(pipeline.attrs(vertex.Mesh, 0, 0) ++ pipeline.attrs(vertex.PartInstance, 1, 5) ++ pipeline.attrs(vertex.Skin, 2, 16) ++ pipeline.attrs(vertex.Grow, 3, 21));

pub const desc:pass.Desc = .{
  .vert = @embedFile("part.vert"), .frag = @embedFile("part.frag"),
  .bindings = bindings, .attrs = attrs, .per_sample = true,
};

/// this frame's instances and bones, and where each mesh's run of instances
/// starts and how long it is (the glass pass draws the same runs)
pub const Frame = struct {
  inst:Buffer = .{},
  bones:Buffer = .{},
  first:[meshlib.SLOTS]u32 = undefined,
  counts:[meshlib.SLOTS]u32 = @splat(0),
  /// the push constants both passes draw with (the bones' address in them)
  push:R.WorldPush = undefined,
};

pub fn initFrame(c:*const Ctx) ctx.Error!Frame {
  var f:Frame = .{.inst = try Buffer.init(c, MAX * @sizeOf(vertex.PartInstance), .{.vertex_buffer = true})};
  errdefer f.inst.deinit(c);
  f.bones = try Buffer.init(c, MAX_BONES * @sizeOf(m.M4), .{.storage_buffer = true, .shader_device_address = true});
  return f;
}
pub fn deinitFrame(f:*Frame, c:*const Ctx) void {
  f.inst.deinit(c);
  f.bones.deinit(c);
}

/// upload every instance and bone (before any pass draws them).
pub fn prepare(r:*R.Renderer, f:*Frame, scene:*const R.Scene, stats:*R.Stats) void {
  stats.parts = pass.upload(vertex.PartInstance, &f.inst, &scene.parts, &f.first, &f.counts, MAX);
  f.bones.write(0, sliceAsBytes(scene.bones[0..@min(scene.bones.len, MAX_BONES)]));
  const at = f.bones.address(&r.ctx);
  f.push = scene.push;
  f.push.bones = .{@truncate(at), @truncate(at >> 32)};
}

/// their solid fragments.
pub fn record(r:*R.Renderer, f:*Frame, cmd:vk.CommandBufferProxy, _:*const R.Scene, stats:*R.Stats) void {
  draw(r, f, cmd, stats, .parts);
}

fn draw(r:*R.Renderer, f:*const Frame, cmd:vk.CommandBufferProxy, stats:*R.Stats, p:R.Pass) void {
  if (stats.parts == 0) return;
  cmd.bindPipeline(.graphics, r.pipe(p));
  cmd.pushConstants(r.layout(.world), pass.stages, 0, @sizeOf(R.WorldPush), &f.push);
  cmd.bindVertexBuffers(0, &.{r.ext.meshes.buf, f.inst.buf, r.ext.skins.buf, r.ext.grows.buf}, &.{0, 0, 0, 0});
  for (0..meshlib.SLOTS) |i| {
    if (f.counts[i] == 0 or (p == .parts_glass and !r.ext.part_glassy[i])) continue;
    const mesh = if (p == .parts_shadow) R.caster(i) else i;
    cmd.draw(r.ext.part_ranges[mesh][1], f.counts[i], r.ext.part_ranges[mesh][0], f.first[i]);
    stats.draws += 1;
  }
}

/// the parts' see-through fragments (sap and resin, shadows, beams, the
/// halo), drawn once every solid surface is down: the same instances,
/// blended over what is there, writing no depth.
pub const glass = struct {
  pub const desc:pass.Desc = .{
    .vert = @embedFile("part.vert"), .frag = @embedFile("part_glass.frag"),
    .bindings = bindings, .attrs = attrs,
    .blend = true, .depth_write = false, .nearer = true, .per_sample = true,
  };
  pub fn record(r:*R.Renderer, _:*void, cmd:vk.CommandBufferProxy, _:*const R.Scene, stats:*R.Stats) void {
    draw(r, &r.frames[r.fi].pass.parts, cmd, stats, .parts_glass);
  }
};

/// the parts as the key light sees them, into every cascade of its shadow
/// map: the wolf skinned as drawn, structures swaying and growing (what is
/// light itself, the beams, motes and the halo, casts none; part.vert
/// under SHADOW)
pub const shadow = struct {
  pub const desc:pass.Desc = .{
    .vert = @embedFile("part_shadow.vert"), .frag = lib.engine.shadow_frag,
    .bindings = bindings, .attrs = attrs, .target = .shadow,
  };
  pub fn record(r:*R.Renderer, _:*void, cmd:vk.CommandBufferProxy, _:*const R.Scene, stats:*R.Stats) void {
    draw(r, &r.frames[r.fi].pass.parts, cmd, stats, .parts_shadow);
  }
};

