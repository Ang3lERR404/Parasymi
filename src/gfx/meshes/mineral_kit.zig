//! shared pieces for the ground's minerals: crystals and faceted stones,
//! flat-faced (each face its own normal) so they catch the light as cut
//! planes. Not a mesh itself; the node meshes use it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");
const vertex = @import("../vertex.zig");
const Rng = @import("../../core/rng.zig").Rng;

const V3 = m.V3;
const v3 = m.v3;

/// one flat-shaded triangle, facing away from `inside`
pub fn facet(b:*mg.Builder, p:[3]V3, inside:V3, col:[3]color.Rgba8, t:f32, part:vertex.Part) Allocator.Error!void {
  var n = m.norm(m.cross(p[1] - p[0], p[2] - p[0]));
  const flip = m.dot(n, m.centroid(p[0], p[1], p[2]) - inside) < 0;
  if (flip) n = -n;
  const order = if (flip) [3]usize{0, 2, 1} else [3]usize{0, 1, 2};
  for (order) |i| try b.put(p[i], n, col[i], t, 0, part);
}

pub const Crystal = struct {
  base:V3,
  dir:V3,
  len:f32,
  r:f32,
  sides:u32 = 6,
  /// fraction of the length taken by the pointed termination
  point:f32 = 0.28,
  col:color.Rgba8,
  tip:color.Rgba8,
  part:vertex.Part = .bloom,
};

/// a crystal: a faceted prism rising from its base (sunk a little) to a
/// pyramidal point, its faces slightly uneven like a grown crystal
pub fn crystal(b:*mg.Builder, c:Crystal, rng:*Rng) Allocator.Error!void {
  const side = m.norm(m.cross(c.dir, if (@abs(c.dir[1]) < m.NEAR_PARALLEL) v3(0, 1, 0) else v3(1, 0, 0)));
  const fwd = m.cross(c.dir, side);
  const top = c.base + c.dir * m.splat3(c.len * (1 - c.point));
  const apex = c.base + c.dir * m.splat3(c.len);
  const inside = c.base + c.dir * m.splat3(c.len * 0.5);
  const foot = c.base - c.dir * m.splat3(c.r);
  var lo:[8]V3 = undefined;
  var hi:[8]V3 = undefined;
  const turn = rng.range(0, m.tau);
  for (0..c.sides) |i| {
    const a = turn + m.tau * m.ratio(i, c.sides);
    const rr = c.r * rng.range(0.85, 1.12);
    const o = side * m.splat3(@cos(a) * rr) + fwd * m.splat3(@sin(a) * rr);
    lo[i] = c.base + o;
    hi[i] = top + o * m.splat3(rng.range(0.85, 1.0));
  }
  for (0..c.sides) |i| {
    const j = (i + 1) % c.sides;
    try facet(b, .{lo[i], lo[j], hi[j]}, inside, .{c.col, c.col, c.tip}, 0.3, c.part);
    try facet(b, .{lo[i], hi[j], hi[i]}, inside, .{c.col, c.tip, c.tip}, 0.3, c.part);
    try facet(b, .{hi[i], hi[j], apex}, inside, .{c.tip, c.tip, c.tip}, 1, c.part);
    try facet(b, .{lo[i], foot, lo[j]}, inside, .{c.col, c.col, c.col}, 0, c.part);
  }
}

/// a faceted stone half sunk in the ground: two irregular rings of points
/// between a flat-ish crown and a buried bottom
pub fn stone(b:*mg.Builder, at:V3, r:f32, flat:f32, col:color.Rgba8, lite:color.Rgba8, rng:*Rng) Allocator.Error!void {
  const S = 7;
  var mid:[S]V3 = undefined;
  var up:[S]V3 = undefined;
  const turn = rng.range(0, m.tau);
  for (0..S) |i| {
    const a = turn + m.tau * m.ratio(i, S) + rng.range(-0.2, 0.2);
    const rr = r * rng.range(0.8, 1.15);
    mid[i] = at + v3(@cos(a) * rr, r * flat * rng.range(0.1, 0.35), @sin(a) * rr);
    const a2 = a + m.pi / m.f(S);
    up[i] = at + v3(@cos(a2) * rr * 0.62, r * flat * rng.range(0.7, 0.95), @sin(a2) * rr * 0.62);
  }
  const crown = at + v3(r * rng.range(-0.1, 0.1), r * flat * 1.05, r * rng.range(-0.1, 0.1));
  const bottom = at - v3(0, r * flat * 0.5, 0);
  const inside = at + v3(0, r * flat * 0.3, 0);
  for (0..S) |i| {
    const j = (i + 1) % S;
    try facet(b, .{mid[i], mid[j], up[i]}, inside, .{col, col, lite}, 0.4, .stem);
    try facet(b, .{mid[j], up[j], up[i]}, inside, .{col, lite, lite}, 0.4, .stem);
    try facet(b, .{up[i], up[j], crown}, inside, .{lite, lite, lite}, 0.5, .stem);
    try facet(b, .{mid[i], bottom, mid[j]}, inside, .{col, col, col}, 0.4, .stem);
  }
}
