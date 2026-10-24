//! mesh: WOLF BELLY. a sac of sap on the gut, skinned to the spine: an egg
//! rounded and full below, drawing in smoothly toward the ribs above, its
//! back sunk in the body so only the swell shows. Convex everywhere, so
//! its near side (the only side drawn) never folds away. A net of grown
//! vines wraps it (tapering at both ends, leaves along them) and a belly
//! button sits sunk in the sap at the front.
//!
//! tu.x on every vertex is how much of the gut it is (1 low and in front,
//! 0 toward the ribs): that share of it moves with the skeleton's gut bone,
//! which swells, drops and pushes forward as the belly fills, while its top
//! stays with the spine. The belly button's vertices carry tu.y =
//! NAVEL: the shader raises it from inside the sap to the surface, and on
//! out, the fuller the belly.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");
const color = @import("../../core/color.zig");
const skel = @import("wolf_skeleton.zig");
const Sculpt = @import("sculpt_kit.zig").Sculpt;

const V3 = m.V3;
const v3 = m.v3;

/// the gut's centre in the waist bone's frame, and its radii: across,
/// down, up (toward the ribs) and forward
pub const CENTRE = skel.GUT_AT;
pub const RX:f32 = 0.11;
pub const DOWN:f32 = 0.095;
pub const UP:f32 = 0.15;
pub const RZ:f32 = 0.086;
/// how far the sac narrows toward its top (share of its width)
const TAPER:f32 = 0.38;
/// tu.y marking the belly button for the shader
pub const NAVEL:f32 = 2;

const RINGS = 30;
const SIDES = 40;

/// a point on the sac at `th` (0 bottom .. pi top) and `ph` around (0 the
/// right side, pi/2 the front), `lift` times out from its surface, in the
/// waist's frame
fn surface(th:f32, ph:f32, lift:f32) V3 {
  const y = -@cos(th);
  const r = @sin(th);
  const up = @max(y, 0);
  const narrow = 1 - TAPER * up * up;
  return CENTRE + v3(@cos(ph) * r * RX * narrow, y * (if (y > 0) UP else DOWN), @sin(ph) * r * RZ * narrow) * m.splat3(lift);
}

fn normal(th:f32, ph:f32) V3 {
  const e:f32 = 1e-3;
  const t0 = @max(th, 2 * e);
  const t1 = @min(t0, m.pi - 2 * e);
  const dt = surface(t1 + e, ph, 1) - surface(t1 - e, ph, 1);
  const dp = surface(t1, ph + e, 1) - surface(t1, ph - e, 1);
  const n = m.norm(m.cross(dp, dt));
  const out = surface(t1, ph, 1) - CENTRE;
  return if (m.dot(n, out) < 0) -n else n;
}

/// how much of the gut a point at `th` is: all of it below the middle,
/// none toward the top
fn gut(th:f32) f32 { return 1 - m.smooth(m.clamp01((-@cos(th) - 0.1) / 0.75)); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const start = b.mark();
  const R = RINGS + 1;
  const C = SIDES + 1;
  var pts:[R * C]V3 = undefined;
  var nrm:[R * C]V3 = undefined;
  var cols:[R * C]color.Rgba8 = undefined;
  var us:[R * C]f32 = undefined;
  for (0..R) |i| for (0..C) |j| {
    const th = m.ratio(i, RINGS) * m.pi;
    // round the other way, so the sheet faces out
    const ph = (1 - m.ratio(j, SIDES)) * m.tau;
    const at = i * C + j;
    pts[at] = surface(th, ph, 1);
    nrm[at] = normal(th, ph);
    cols[at] = pal.sap;
    us[at] = 0;
  };
  try mg.patch(b, R, C, &pts, &nrm, &cols, &us, 0, .bloom);
  // tu.x: how much of the gut each vertex is
  for (b.v.items[start..]) |*vx| {
    const y = (vx.pos[1] - CENTRE[1]);
    const th = m.pi / 2.0 + m.asin(m.clamp(y / (if (y > 0) UP else DOWN), -1, 1));
    vx.tu[0] = gut(th);
  }

  // the net: grown vines from under the gut up over it, twisting, the
  // front ones running on toward the ribs; tapering at both ends, leaves
  // lying along them
  for (0..6) |vi| {
    const a0 = m.ratio(vi, 6) * m.tau + 0.3;
    const front = @sin(a0) > 0.3;
    const top:f32 = if (front) 0.88 else 0.66;
    var path:[22]V3 = undefined;
    var vts:[22]f32 = undefined;
    var rs:[22]f32 = undefined;
    for (&path, &vts, &rs, 0..) |*p, *t, *r, j| {
      const k = m.ratio(j, 21);
      const th = m.lerp(0.12, top, k) * m.pi;
      p.* = surface(th, a0 + k * 0.9, 1.04);
      t.* = gut(th);
      r.* = @max(0.0072 * @sqrt(@sin(m.pi * k)), 0.0005);
    }
    try b.tubeR(&path, &vts, &rs, pal.wolf_vine, .stem, 5);
    for ([_]usize{ 7, 14 }) |j| {
      const th = m.lerp(0.12, top, m.ratio(j, 21)) * m.pi;
      try kit.leaf(b, .{
        .base = path[j], .along = m.norm(path[j - 1] - path[j + 1]), .out = normal(th, a0 + m.ratio(j, 21) * 0.9),
        .len = 0.045, .width = 0.014, .lift = 0.35, .curl = 0.4, .cup = 0.3,
        .col = pal.wolf_leaf_dark, .tip = pal.wolf_leaf_lite, .t = vts[j],
      });
    }
  }

  // the belly button: a small knot of vine sunk in the sap at the front of
  // the gut, a puckered ring around it
  const nth = m.pi * 0.47;
  const at = surface(nth, m.pi / 2.0, 0.78);
  const out = normal(nth, m.pi / 2.0);
  const navel = b.mark();
  const knot = color.mix(pal.wolf_core, pal.wolf_vine, 0.3);
  try mg.ellipsoid(b, .{ .center = at, .radii = v3(0.011, 0.013, 0.009), .col = knot, .rings = 6, .segs = 9, .t = 1 });
  var ring:[13]V3 = undefined;
  var rts:[13]f32 = undefined;
  const side = v3(1, 0, 0);
  const up = m.norm(m.cross(out, side));
  for (&ring, &rts, 0..) |*p, *t, j| {
    const a = m.ratio(j, 12) * m.tau;
    p.* = at - out * m.splat3(0.004) + (side * m.splat3(@cos(a)) + up * m.splat3(@sin(a))) * m.splat3(0.017);
    t.* = 1;
  }
  try b.tube(&ring, &rts, 0.0045, 0.0045, knot, .stem, 5);
  for (b.v.items[navel..]) |*vx| vx.tu[1] = NAVEL;

  // into the waist's place in the bind pose: the gut with the gut bone,
  // the rest with the spine, the hips below it and the ribs above
  for (b.v.items[start..], try b.skinOf(start)) |vx, *k| {
    const y = vx.pos[1];
    const g = vx.tu[0];
    var w:[skel.COUNT]f32 = @splat(0);
    const low = 0.5 * m.smooth(m.clamp01(-y / 0.09));
    const high = 0.6 * m.smooth(m.clamp01((y - 0.06) / 0.1));
    w[@intFromEnum(skel.Bone.gut)] = g;
    w[@intFromEnum(skel.Bone.pelvis)] = (1 - g) * low;
    w[@intFromEnum(skel.Bone.chest)] = (1 - g) * high;
    w[@intFromEnum(skel.Bone.waist)] = (1 - g) * (1 - low - high);
    k.* = Sculpt.pack(&w);
  }
  b.xform(start, skel.bind()[@intFromEnum(skel.Bone.waist)]);
}

test "the belly is full below and narrows toward the ribs" {
  const mid = surface(m.pi / 2.0, 0, 1)[0] - CENTRE[0];
  const high = surface(m.pi * 0.85, 0, 1)[0] - CENTRE[0];
  try std.testing.expect(mid > 0.1);
  try std.testing.expect(high < mid * 0.6);
  try std.testing.expect(gut(m.pi * 0.25) > 0.95 and gut(m.pi * 0.95) < 0.05);
}
