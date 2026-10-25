//! mesh: ARSTHRAXIA. a woven stalk rising from a root mat, leaves along it,
//! opening at the top into a broad flower over which its core of research
//! energy condenses. The structure emits the rest, each built here in its
//! own space: the satellite saps spinning round the core (`satellite`),
//! the core (`core`), the wisps of energy drawn from the satellites into it
//! (`wisp`) and the offshoots research grows off its stalk (`shoot`).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");
const kit = @import("structure_kit.zig");

const V3 = m.V3;
const v3 = m.v3;
/// how tall the stalk stands, to the flower's heart
pub const HEIGHT:f32 = 1.5;
/// how wide the stalk's bundle is drawn (its profile is a unit across)
const GIRTH:f32 = 1.6;
const petal_heart = color.rgb(0.30, 0.22, 0.46);
const petal_rim = color.rgb(0.62, 0.5, 0.86);
const stamen = color.rgb(0.8, 0.74, 0.9);
/// research energy is light: white under the shading's own colours
const energy_white = color.rgb(1, 1, 1).toRgba8(255);

/// the stalk's radius up its height: a flared foot, a waist, a swelling
/// under the flower.
fn stalkProfile(k:f32) f32 { return 0.14 * (1 - 0.45 * k) + 0.05 * @exp(-k * 12) + 0.03 * @exp(-(1 - k) * 10); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try kit.rootMat(b, 6, 0.9, 0.07, 0x7B01, null);
  try kit.footLeaves(b, 6, 0.25, 0.5, 0.18, 0x7B02, null);
  const s = b.mark();
  try mg.bundle(b, stalkProfile, 6, 3.2, pal.STRAND_WOBBLE, 0x7B03, pal.core, color.rgb(0.36, 0.3, 0.46).toRgba8(255));
  b.xform(s, m.scale3(v3(GIRTH, HEIGHT, GIRTH)));
  // leaves along the stalk, as along any vine
  var spine:[10]V3 = undefined;
  for (&spine, 0..) |*p, i| p.* = v3(0, HEIGHT * m.ratio(i, 9), 0);
  try mg.leavesAlong(b, &spine, 5, 0.4, 0.12, 0.25, 0.8, 0.25, 0.8, pal.leaf_dark, pal.leaf_lite, 0x7B04);
  // the flower: a broad outer whorl opening wide, an inner one cupping
  // the core that condenses over it
  const heart = v3(0, HEIGHT - 0.02, 0);
  for (0..9 + 5) |i| {
    const outer = i < 9;
    const a = if (outer) m.ratio(i, 9) * m.tau else (m.f(i - 9) + 0.5) / 5 * m.tau;
    try mg.petal(b, .{
      .base = heart, .out = v3(@cos(a), 0, @sin(a)),
      .len = if (outer) 0.62 else 0.42, .width = if (outer) 0.3 else 0.22,
      .rise = if (outer) 0.55 else 1.15, .flare = if (outer) 0.7 else 0.4, .cup = 0.4,
      .col = petal_heart.toRgba8(255), .tip = petal_rim.toRgba8(255), .part = .leaf,
    });
  }
  // stamens arching out of its heart beneath the core
  try mg.stamens(b, .{
    .heart = heart, .axis = v3(0, 1, 0), .n = 9, .len = 0.32, .r = 0.009, .anther = 0.055,
    .lean = 0.4, .arch = 0.6, .col = stamen.toRgba8(255), .seed = 0x7B05,
  });
}

/// where an offshoot leaves the stalk's axis, `k` (0..1) up it: inside the
/// stalk, so it grows out of it
pub fn stalkAt(k:f32) V3 { return v3(0, HEIGHT * k, 0); }

/// mesh: ARSTHRAXIA SATELLITE. a small sap of resin held in two grown vine
/// bands, one of those the old core split into; spun round the core.
pub const satellite = struct {
  pub const R:f32 = 0.075;

  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try kit.resinPod(b, v3(0, 0, 0), v3(R, R, R), 8, 12);
    // two bands wrapping it, pole to pole, crossing
    const arcs = [_][4]f32{ .{0.15, 0.3, 2.99, 2.4}, .{0.2, 3.5, 2.9, 5.6} };
    try mg.bands(b, v3(0, 0, 0), v3(R, R, R), &arcs, 1, 0.008, 0.12, 0x0B5, pal.vine);
  }
};

/// mesh: ARSTHRAXIA CORE. the research energy condensing where the old sap
/// core stood: a ball of light a unit across (tu.x < 0 marks it from a
/// wisp); the structure sizes it by how far the unit has condensed.
pub const core = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(1, 1, 1), .col = energy_white, .part = .energy, .rings = 12, .segs = 18, .t = -1});
  }
};

/// mesh: ARSTHRAXIA WISP. a thread of energy a satellite sheds into the
/// core, running straight up +y over 0..1 (tu.x 0 at the satellite .. 1 at
/// the core); placed along its fall as a curve (part.vert). It closes to a
/// point at both ends.
pub const wisp = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const N = 20;
    var path:[N]V3 = undefined;
    var ts:[N]f32 = undefined;
    var rs:[N]f32 = undefined;
    for (&path, &ts, &rs, 0..) |*p, *t, *r, i| {
      const k = m.ratio(i, N - 1);
      p.* = v3(0, k, 0);
      t.* = k;
      r.* = @max(0.024 * m.pow(f32, @sin(m.pi * k), 0.5) * (1 - 0.4 * k), 2e-4);
    }
    try b.tubeR(&path, &ts, &rs, energy_white, .energy, 6);
  }
};

/// an offshoot's path from where it leaves the stalk (the origin) out
/// along +x, curving up toward the light as it goes
pub const SHOOT_N = 16;
pub fn shootPath(out:*[SHOOT_N]V3) void {
  const N = 7;
  const LEN:f32 = 0.6;
  var ctrl:[N]V3 = undefined;
  ctrl[0] = v3(0, 0, 0);
  for (1..N) |j| {
    const s = m.ratio(j, N - 1);
    // heading turns from a low rise toward upright, mostly in its outer half
    const h = m.lerp(0.3, 1.3, s * s);
    ctrl[j] = ctrl[j - 1] + v3(@cos(h), @sin(h), 0) * m.splat3(LEN / (N - 1));
  }
  mg.grow(&ctrl, .{.start = ctrl[0], .direction = m.norm(ctrl[N - 1]), .length = LEN, .wobble = 0.12, .curl = 0.03, .seed = 0x7B21});
  m.splineResample(&ctrl, out);
}

/// where an offshoot's flower opens, in its own space, and which way
pub fn shootTip() struct { at:V3, axis:V3 } {
  var p:[SHOOT_N]V3 = undefined;
  shootPath(&p);
  return .{.at = p[SHOOT_N - 1], .axis = m.norm(p[SHOOT_N - 1] - p[SHOOT_N - 4])};
}

/// mesh: ARSTHRAXIA SHOOT. an offshoot research grows off the stalk: a
/// grown side stem leaving it along +x and curving up, leaves along it,
/// opening into a small flower like the crown's (a satellite of its own
/// hovers over it, emitted). Its root lies inside the stalk.
pub const shoot = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    var path:[SHOOT_N]V3 = undefined;
    shootPath(&path);
    var ts:[SHOOT_N]f32 = undefined;
    var rs:[SHOOT_N]f32 = undefined;
    for (&ts, &rs, 0..) |*t, *r, j| {
      const s = m.ratio(j, SHOOT_N - 1);
      t.* = m.lerp(0.4, 1, s);
      // tapering, but not to nothing: its flower sits on its tip
      r.* = 0.034 * m.lerp(1, 0.4, s);
    }
    try b.tubeR(&path, &ts, &rs, pal.vine, .stem, 5);
    try mg.leavesAlong(b, &path, 3, 0.17, 0.055, 0.2, 0.75, 0.45, 0.85, pal.leaf_dark, pal.leaf_lite, 0x7B22);
    const tip = shootTip();
    for (0..7) |i| {
      const a = m.ratio(i, 7) * m.tau;
      try mg.petal(b, .{
        .base = tip.at, .out = v3(@cos(a), 0, @sin(a)),
        .len = 0.17, .width = 0.09, .rise = 0.9, .flare = 0.6, .cup = 0.4,
        .col = petal_heart.toRgba8(255), .tip = petal_rim.toRgba8(255), .t = 1, .part = .leaf,
      });
    }
    try mg.stamens(b, .{
      .heart = tip.at, .axis = tip.axis, .n = 6, .len = 0.1, .r = 0.004, .anther = 0.02,
      .lean = 0.35, .arch = 0.5, .col = stamen.toRgba8(255), .t = 1, .seed = 0x7B23,
    });
  }
};
