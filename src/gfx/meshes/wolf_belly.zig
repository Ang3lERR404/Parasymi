//! mesh: WOLF BELLY. a sac of sap on the gut, skinned to the spine: an egg
//! rounded and full below, drawing in smoothly toward the ribs above, its
//! back sunk in the body so only the swell shows. Convex everywhere, so
//! its near side (the only side drawn) never folds away. A net of grown
//! vines wraps it (tapering at both ends, leaves along them) and a belly
//! button sits sunk in the sap at the front.
//!
//! tu.x on every vertex is how much of the gut it is (1 low and in front,
//! 0 toward the ribs): that share of it moves with the skeleton's gut bone,
//! which swells, rounds out toward a ball, drops and pushes forward as the
//! belly fills, while its top stays with the spine. The sac and its net
//! carry tu.y = BELLY: as it fills the shader folds creases into it, one
//! down its middle and one across it, deepening the fuller it is (crossing
//! at the belly button, `crossing`). The belly button is sap like the sac,
//! a knot with a puckered ring round it, its vertices tu.y = NAVEL: the
//! shader raises it from inside the sap to the surface, and on out.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");
const color = @import("../../core/color.zig");
const vertex = @import("../vertex.zig");
const skel = @import("wolf_skeleton.zig");
const Sculpt = @import("sculpt_kit.zig").Sculpt;

const V3 = m.V3;
const v3 = m.v3;

/// the gut's centre in the waist bone's frame, and its radii: across,
/// down, up (toward the ribs) and forward
pub const CENTRE = skel.GUT_AT;
pub const RX:f32 = skel.GUT_R[0];
pub const DOWN:f32 = skel.GUT_R[1];
/// (it reaches up under the pectorals, so the two meet with no bare hide
/// between them)
pub const UP:f32 = skel.GUT_UP;
pub const RZ:f32 = skel.GUT_R[2];
/// how far the sac narrows toward its top (share of its width)
const TAPER:f32 = 0.12;
/// tu.y marking the sac (creased by the shader) and the belly button
pub const BELLY:f32 = 3;
pub const NAVEL:f32 = 4;
/// the belly button: how far round from the bottom it sits, and how deep
/// in the sap at rest
const NAVEL_TH:f32 = m.pi * 0.47;
const NAVEL_LIFT:f32 = 0.86;

/// where the creases cross (the belly button, on the sac's surface), in
/// the bind pose (wolf space)
pub fn crossing() V3 {
  return v3(0, skel.HIP_Y + skel.WAIST_AT[1], skel.WAIST_AT[2]) + surface(NAVEL_TH, m.half_pi, 1);
}

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

/// how much of the gut a point at `th` is (`share`)
fn gut(th:f32) f32 { return share(-@cos(th) * (if (@cos(th) < 0) UP else DOWN))[0]; }

/// `scale` times a smooth step of x over `from`..`from + span`, and its
/// slope in x
fn ramp(x:f32, from:f32, span:f32, scale:f32) [2]f32 {
  const u = (x - from) / span;
  if (u <= 0 or u >= 1) return .{scale * m.smooth(m.clamp01(u)), 0};
  return .{scale * m.smooth(u), scale * 6 * u * (1 - u) / span};
}

/// how far up the sac (share of `UP`) it starts being held to the body
const PIN:f32 = 0.55;
/// how much of the gut a point `yr` above the gut's centre is, and how fast
/// that changes going up: all of it up past the middle (so the whole sac
/// swells round, up toward the ribs as well), easing to none at its top
/// where it hangs from them. Above the middle the gut is its upper bone,
/// which lifts nothing past where the waist holds it, so this easing never
/// folds the swollen sac over itself.
fn share(yr:f32) [2]f32 {
  const r = ramp(yr / UP, PIN, 1 - PIN, 1);
  return .{1 - r[0], -r[1] / UP};
}

/// the gut's two bones part across its middle, where both take a point
/// alike: below, `gut` (the sac drops and rounds out full), above,
/// `gut_top` (the sac rounds out as wide but keeps its top). How much of
/// the gut a point `yr` above its centre is of the lower, and its slope.
const PART:f32 = 0.04;
fn lower(yr:f32) [2]f32 {
  const r = ramp(yr, -PART, 2 * PART, 1);
  return .{1 - r[0], -r[1]};
}

/// how far the full gut bones lift a point `yr` above the gut's centre
/// (negative: drop it), the lower and the upper
fn reach(yr:f32) [2]f32 {
  return .{skel.GUT_GROW[1] * yr + skel.GUT_SHIFT[1], skel.GUT_GROW_TOP[1] * yr + skel.GUT_SHIFT[1]};
}

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
    vx.tu[0] = share(vx.pos[1] - CENTRE[1])[0];
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

  // (the leaves keep theirs: it is how far along them, for their stir)
  for (b.v.items[start..]) |*vx| if (vx.part != @intFromEnum(vertex.Part.leaf)) {
    vx.tu[1] = BELLY;
  };

  // the belly button: a small knot of sap sunk in the sac at the front of
  // the gut, a puckered ring of sap around it, all one with the sac
  const nth = NAVEL_TH;
  const at = surface(nth, m.half_pi, NAVEL_LIFT);
  const out = normal(nth, m.half_pi);
  const navel = b.mark();
  const knot = pal.sap;
  try mg.ellipsoid(b, .{ .center = at, .radii = v3(0.0068, 0.008, 0.0056), .col = knot, .part = .bloom, .rings = 8, .segs = 12, .t = 1 });
  var ring:[13]V3 = undefined;
  var rts:[13]f32 = undefined;
  const side = v3(1, 0, 0);
  const up = m.norm(m.cross(out, side));
  for (&ring, &rts, 0..) |*p, *t, j| {
    const a = m.ratio(j, 12) * m.tau;
    p.* = at - out * m.splat3(0.0025) + (side * m.splat3(@cos(a)) + up * m.splat3(@sin(a))) * m.splat3(0.0105);
    t.* = 1;
  }
  try b.tube(&ring, &rts, 0.003, 0.003, knot, .bloom, 8);
  for (b.v.items[navel..]) |*vx| vx.tu[1] = NAVEL;

  // into the waist's place in the bind pose: the gut with the gut bones,
  // the rest with the spine, the hips below it and the ribs above. The
  // weights change with height alone, and the gut swells the sac to three
  // times its size, so its normals turn by how fast the weights change up
  // it too (each weight's slope, carried in the skin), not by the blended
  // bones alone
  for (b.v.items[start..], try b.skinOf(start)) |vx, *k| {
    const y = vx.pos[1];
    const g = vx.tu[0];
    const dg = if (vx.tu[1] == NAVEL) 0 else share(y - CENTRE[1])[1];
    const lo = lower(y - CENTRE[1]);
    var w:[skel.COUNT]f32 = @splat(0);
    var dw:[skel.COUNT]f32 = @splat(0);
    const low = ramp(-y, 0, 0.09, 0.5);
    const high = ramp(y, 0.06, 0.1, 0.6);
    const dlow = -low[1];
    const dhigh = high[1];
    w[@intFromEnum(skel.Bone.gut)] = g * lo[0];
    dw[@intFromEnum(skel.Bone.gut)] = dg * lo[0] + g * lo[1];
    w[@intFromEnum(skel.Bone.gut_top)] = g * (1 - lo[0]);
    dw[@intFromEnum(skel.Bone.gut_top)] = dg * (1 - lo[0]) - g * lo[1];
    w[@intFromEnum(skel.Bone.pelvis)] = (1 - g) * low[0];
    dw[@intFromEnum(skel.Bone.pelvis)] = -dg * low[0] + (1 - g) * dlow;
    w[@intFromEnum(skel.Bone.chest)] = (1 - g) * high[0];
    dw[@intFromEnum(skel.Bone.chest)] = -dg * high[0] + (1 - g) * dhigh;
    w[@intFromEnum(skel.Bone.waist)] = (1 - g) * (1 - low[0] - high[0]);
    dw[@intFromEnum(skel.Bone.waist)] = -dg * (1 - low[0] - high[0]) - (1 - g) * (dlow + dhigh);
    var grad:[skel.COUNT]V3 = undefined;
    for (&grad, dw) |*q, d| q.* = v3(0, d, 0);
    k.* = Sculpt.packWith(&w, &grad);
  }
  b.xform(start, skel.bind()[@intFromEnum(skel.Bone.waist)]);
}

test "the belly is full below and narrows toward the ribs" {
  const mid = surface(m.half_pi, 0, 1)[0] - CENTRE[0];
  const high = surface(m.pi * 0.85, 0, 1)[0] - CENTRE[0];
  try std.testing.expect(mid > 0.1);
  try std.testing.expect(high < mid * 0.6);
  try std.testing.expect(gut(m.pi * 0.25) > 0.95 and gut(m.pi * 0.95) < 0.05);
}

test "the gut's shares change up the sac as their slopes say" {
  const e:f32 = 1e-4;
  var k:usize = 1;
  while (k < 200) : (k += 1) {
    const yr = m.lerp(-DOWN, UP, m.ratio(k, 200));
    const fd = (share(yr + e)[0] - share(yr - e)[0]) / (2 * e);
    try std.testing.expectApproxEqAbs(fd, share(yr)[1], 0.05 + 0.02 * @abs(fd));
    const fl = (lower(yr + e)[0] - lower(yr - e)[0]) / (2 * e);
    try std.testing.expectApproxEqAbs(fl, lower(yr)[1], 0.05 + 0.02 * @abs(fl));
  }
}

test "the swelling sac never folds over itself, however full" {
  for ([_]f32{ 0.25, 0.5, 1 }) |fill| {
    var last:f32 = -1e9;
    var k:usize = 0;
    while (k <= 400) : (k += 1) {
      const yr = m.lerp(-DOWN, UP, m.ratio(k, 400));
      const g = share(yr)[0];
      const lo = lower(yr)[0];
      const r = reach(yr);
      const h = yr + fill * g * (lo * r[0] + (1 - lo) * r[1]);
      try std.testing.expect(h > last);
      last = h;
    }
    // and its top stays where it hangs from the ribs
    try std.testing.expectApproxEqAbs(UP, last, 1e-4);
  }
}
