//! shared pieces for grown structures, in the plants' language: a woven
//! root mat they rise from, grown vines with leaves along them, and pods of
//! the wolf's resin sap (dense at the base, see-through toward the top,
//! with no light of its own). Not a mesh itself; the structure meshes use it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");
const Rng = @import("../../core/rng.zig").Rng;

const V3 = m.V3;
const v3 = m.v3;

/// `n` braided roots radiating from the centre out to `reach`, hugging the
/// ground and sinking into it at their ends.
pub fn rootMat(b:*mg.Builder, n:u32, reach:f32, girth:f32, seed:u64) Allocator.Error!void {
  var rng = Rng.init(seed);
  for (0..n) |i| {
    const a = (m.f(i) + rng.range(-0.25, 0.25)) / m.f(n) * m.tau;
    const from = v3(@cos(a) * 0.08, 0.06, @sin(a) * 0.08);
    const to = v3(@cos(a) * reach * rng.range(0.8, 1.05), -0.04, @sin(a) * reach * rng.range(0.8, 1.05));
    var c:[6]V3 = undefined;
    mg.growthPath(.{.start = from, .direction = m.norm(to - from), .length = m.len(to - from), .wobble = 0.25, .seed = seed +% i * 41}, &c);
    var p:[12]V3 = undefined;
    m.splineResample(&c, &p);
    var ts:[12]f32 = undefined;
    var rs:[12]f32 = undefined;
    for (&ts, &rs, 0..) |*t, *r, j| {
      const k = m.ratio(j, 11);
      t.* = 0.05 * (1 - k);
      r.* = girth * m.lerp(1, 0.35, k);
    }
    try mg.braid(b, &p, &ts, &rs, 3, 2.2, pal.STRAND_WOBBLE, seed +% i * 7, pal.core, pal.vine);
  }
}

/// a grown vine from `from` toward `to`, tapering, with `leaves` small
/// leaves along it.
pub fn leafyVine(b:*mg.Builder, from:V3, to:V3, r0:f32, curl:f32, leaves:u32, t0:f32, t1:f32, seed:u64) Allocator.Error!void {
  var c:[7]V3 = undefined;
  mg.growthPath(.{.start = from, .direction = m.norm(to - from), .length = m.len(to - from), .wobble = 0.18, .curl = curl, .seed = seed}, &c);
  var p:[18]V3 = undefined;
  m.splineResample(&c, &p);
  var ts:[18]f32 = undefined;
  var rs:[18]f32 = undefined;
  mg.taperRadii(r0, 0.3, &rs);
  for (&ts, 0..) |*t, j| t.* = m.lerp(t0, t1, m.ratio(j, 17));
  try b.tubeR(&p, &ts, &rs, pal.vine, .stem, 5);
  try mg.leavesAlong(b, &p, leaves, 0.18, 0.06, 0.15, 0.85, t0, t1, pal.leaf_dark, pal.leaf_lite, seed +% 3);
}

/// a pod of resin sap: tu.y runs from its dense base (0) to its thin
/// crown (1), which the resin shading reads.
pub fn resinPod(b:*mg.Builder, center:V3, radii:V3, rings:u32, segs:u32) Allocator.Error!void {
  const start = b.mark();
  try mg.ellipsoid(b, .{.center = center, .radii = radii, .col = pal.sap, .part = .resin, .rings = rings, .segs = segs, .t = 0.6});
  for (b.v.items[start..]) |*vx| vx.tu[1] = m.clamp01((vx.pos[1] - (center[1] - radii[1])) / (2 * radii[1]));
}

/// broad leaves in a ring at the foot, all on one envelope.
pub fn footLeaves(b:*mg.Builder, n:u32, r:f32, len:f32, width:f32, seed:u64) Allocator.Error!void {
  var rng = Rng.init(seed);
  for (0..n) |i| {
    const a = (m.f(i) + rng.range(-0.2, 0.2)) / m.f(n) * m.tau;
    const dir = m.norm(v3(@cos(a), 0.25, @sin(a)));
    try b.blade(v3(@cos(a) * r, 0.08, @sin(a) * r), dir, len * rng.range(0.85, 1.1), width, 0.7, pal.leaf_dark, pal.leaf_lite, 0.4, .leaf);
  }
}


/// a root grown from `from` along `dir` (heading down into the soil),
/// tapering to a hair, with two forks splitting off its far half.
pub fn rootlet(b:*mg.Builder, from:V3, dir:V3, len:f32, r0:f32, seed:u64) Allocator.Error!void {
  var rng = Rng.init(seed);
  var c:[6]V3 = undefined;
  mg.growthPath(.{.start = from, .direction = dir, .length = len, .wobble = 0.35, .seed = seed}, &c);
  var p:[12]V3 = undefined;
  m.splineResample(&c, &p);
  var ts:[12]f32 = undefined;
  var rs:[12]f32 = undefined;
  mg.taperRadii(r0, 0.12, &rs);
  for (&ts, 0..) |*t, j| t.* = m.ratio(j, 11) * 0.3;
  try b.tubeR(&p, &ts, &rs, pal.root_bark, .stem, 5);
  for (0..2) |f| {
    const k:usize = 4 + f * 3;
    const side = m.norm(m.cross(dir, v3(0, 1, 0)));
    const sgn:f32 = if (f == 0) 1 else -1;
    const fd = m.norm(dir + side * m.splat3(sgn * rng.range(0.5, 0.9)) + v3(0, -0.2, 0));
    var fc:[4]V3 = undefined;
    mg.growthPath(.{.start = p[k], .direction = fd, .length = len * rng.range(0.35, 0.5), .wobble = 0.4, .seed = seed +% f * 13}, &fc);
    var fp:[8]V3 = undefined;
    m.splineResample(&fc, &fp);
    var ft:[8]f32 = undefined;
    var fr:[8]f32 = undefined;
    mg.taperRadii(rs[k] * 0.75, 0.15, &fr);
    for (&ft) |*t| t.* = ts[k];
    try b.tubeR(&fp, &ft, &fr, pal.root_bark, .stem, 4);
  }
}
