//! mesh: ARSTHRAXIA. a woven stalk rising from a root mat, leaves along it,
//! opening at the top into a broad flower over which its core of research
//! energy condenses. The structure emits the rest, each built here in its
//! own space: the satellite saps spinning round the core (`satellite`),
//! the core (`core`), the wisps of energy drawn from the satellites into it
//! (`wisp`) and the offshoots research grows off its stalk (`shoot`).
//! Both grow on hidden growth splines (gfx/growth.zig): the stalk with
//! its roots, leaves unfolding up it, the flower opening at its top, then
//! (`FORM`) the core; an offshoot by research's progress, its satellite
//! once its flower is open (`SHOOT_FORM`).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");
const kit = @import("structure_kit.zig");
const growth = @import("../growth.zig");

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
/// the last share of its growth, its flower open, over which the core
/// and its satellites form (placed by the structure: `growth.formed`)
pub const FORM:f32 = 0.25;
/// likewise an offshoot's satellite, over the last of the offshoot's growth
pub const SHOOT_FORM:f32 = 0.3;
/// the stalk grows this slowly per unit of its length
const STALK_PACE:f32 = 1.2;
/// how much later each petal opens than the one before
const PETAL_STAGGER:f32 = 0.025;

/// the stalk's radius up its height: a flared foot, a waist, a swelling
/// under the flower.
fn stalkProfile(k:f32) f32 { return 0.14 * (1 - 0.45 * k) + 0.05 * @exp(-k * 12) + 0.03 * @exp(-(1 - k) * 10); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var sk = growth.Skeleton.begin(b);
  sk.tail = FORM;
  // the stalk's spline, straight up its axis (the bundle wanders round it)
  const stalk = sk.trunk(&.{v3(0, 0, 0), v3(0, HEIGHT, 0)}, .{.pace = STALK_PACE});
  try kit.rootMat(b, 6, 0.9, 0.07, 0x7B01, .{.k = &sk, .id = stalk});
  try kit.footLeaves(b, 6, 0.25, 0.5, 0.18, 0x7B02, .{.k = &sk, .id = stalk, .u = 0.08});
  const s = b.mark();
  try mg.bundle(b, stalkProfile, 6, 3.2, pal.STRAND_WOBBLE, 0x7B03, pal.core, color.rgb(0.36, 0.3, 0.46).toRgba8(255));
  b.xform(s, m.scale3(v3(GIRTH, HEIGHT, GIRTH)));
  try sk.along(b, s, stalk);
  // leaves along the stalk, as along any vine
  try sk.leaves(b, stalk, .{.n = 5, .len = 0.4, .width = 0.12, .from = 0.25, .to = 0.8, .t0 = 0.25, .t1 = 0.8, .col = pal.leaf_dark, .tip = pal.leaf_lite, .seed = 0x7B04});
  // the flower: a broad outer whorl opening wide, an inner one cupping
  // the core that condenses over it, petal after petal, outer first
  const heart = v3(0, HEIGHT - 0.02, 0);
  for (0..9 + 5) |i| {
    const outer = i < 9;
    const a = if (outer) m.ratio(i, 9) * m.tau else (m.f(i - 9) + 0.5) / 5 * m.tau;
    const p = b.mark();
    try mg.petal(b, .{
      .base = heart, .out = v3(@cos(a), 0, @sin(a)),
      .len = if (outer) 0.62 else 0.42, .width = if (outer) 0.3 else 0.22,
      .rise = if (outer) 0.55 else 1.15, .flare = if (outer) 0.7 else 0.4, .cup = 0.4,
      .col = petal_heart.toRgba8(255), .tip = petal_rim.toRgba8(255), .part = .leaf,
    });
    try sk.on(b, p, stalk, 1, .{.from = heart, .delay = PETAL_STAGGER * m.f(i)});
  }
  // stamens arching out of its heart beneath the core, once it is open
  const st = b.mark();
  try mg.stamens(b, .{
    .heart = heart, .axis = v3(0, 1, 0), .n = 9, .len = 0.32, .r = 0.009, .anther = 0.055,
    .lean = 0.4, .arch = 0.6, .col = stamen.toRgba8(255), .seed = 0x7B05,
  });
  try sk.on(b, st, stalk, 1, .{.from = heart, .delay = PETAL_STAGGER * (9 + 5)});
  sk.finish(b);
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
  var ctrl:[SHOOT_CTRL]V3 = undefined;
  shootCtrl(&ctrl);
  m.splineResample(&ctrl, out);
}

/// the control points an offshoot's path runs through
const SHOOT_CTRL = 7;
fn shootCtrl(ctrl:*[SHOOT_CTRL]V3) void {
  const N = SHOOT_CTRL;
  const LEN:f32 = 0.6;
  ctrl[0] = v3(0, 0, 0);
  for (1..N) |j| {
    const s = m.ratio(j, N - 1);
    // heading turns from a low rise toward upright, mostly in its outer half
    const h = m.lerp(0.3, 1.3, s * s);
    ctrl[j] = ctrl[j - 1] + v3(@cos(h), @sin(h), 0) * m.splat3(LEN / (N - 1));
  }
  mg.grow(ctrl, .{.start = ctrl[0], .direction = m.norm(ctrl[N - 1]), .length = LEN, .wobble = 0.12, .curl = 0.03, .seed = 0x7B21});
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
/// hovers over it, emitted, `SHOOT_FORM`). Its root lies inside the stalk.
/// It grows along its own growth spline by research's progress.
pub const shoot = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    var sk = growth.Skeleton.begin(b);
    sk.tail = SHOOT_FORM;
    var ctrl:[SHOOT_CTRL]V3 = undefined;
    shootCtrl(&ctrl);
    const stem = sk.trunk(&ctrl, .{});
    // tapering, but not to nothing: its flower sits on its tip
    try sk.tube(b, stem, .{.r0 = 0.034, .tip = 0.4, .col = pal.vine, .sides = 5, .t0 = 0.4, .t1 = 1});
    try sk.leaves(b, stem, .{.n = 3, .len = 0.17, .width = 0.055, .from = 0.2, .to = 0.75, .t0 = 0.45, .t1 = 0.85, .col = pal.leaf_dark, .tip = pal.leaf_lite, .seed = 0x7B22});
    const tip = shootTip();
    for (0..7) |i| {
      const a = m.ratio(i, 7) * m.tau;
      const p = b.mark();
      try mg.petal(b, .{
        .base = tip.at, .out = v3(@cos(a), 0, @sin(a)),
        .len = 0.17, .width = 0.09, .rise = 0.9, .flare = 0.6, .cup = 0.4,
        .col = petal_heart.toRgba8(255), .tip = petal_rim.toRgba8(255), .t = 1, .part = .leaf,
      });
      try sk.on(b, p, stem, 1, .{.from = tip.at, .delay = PETAL_STAGGER * 0.5 * m.f(i)});
    }
    const st = b.mark();
    try mg.stamens(b, .{
      .heart = tip.at, .axis = tip.axis, .n = 6, .len = 0.1, .r = 0.004, .anther = 0.02,
      .lean = 0.35, .arch = 0.5, .col = stamen.toRgba8(255), .t = 1, .seed = 0x7B23,
    });
    try sk.on(b, st, stem, 1, .{.from = tip.at, .delay = PETAL_STAGGER * 3.5});
    sk.finish(b);
  }
};
