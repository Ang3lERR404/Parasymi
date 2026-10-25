//! mesh: LITHOPHAGE. a parasite that eats stone: a bulbous foot half sunk
//! in the soil, pale roots gripping the ground round it, a stalk of three
//! strands wound tight rising into a great translucent bladder (its crop),
//! clasped by five lilac fronds curling up its flank and in over its crown.
//! What it draws from the ground condenses into a crystal inside the crop
//! (`crystal`, emitted); sapped away, the crystal runs down out of the
//! crop's lip as a stream of grit (`germinator_pour`, emitted) into a
//! cup on its foot (`germinator_pool`). Its roots out to the nodes it
//! drains are its own (`root`, `root_far`).
//! Its stalk is the lineage's lattice (parasite_kit): woven at the foot,
//! parting into a cage round two sacs on its core, gathering at the neck.
//! It grows on a hidden stalk (gfx/growth.zig): the foot swells and its
//! roots spread with it, the stalk rises, its sacs swell as it passes, the
//! crop swells out of its top and the fronds clasp it last, all at once.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");
const growth = @import("../growth.zig");
const pk = @import("parasite_kit.zig");
const mineral = @import("mineral_kit.zig");
const Rng = @import("../../core/rng.zig").Rng;

const V3 = m.V3;
const v3 = m.v3;

/// the stalk's top, where the crop sits on it
const NECK = v3(0, 0.34, 0);
const STALK:pk.Stalk = .{.girth = 0.032, .part = 2.4, .from = 0.2, .to = 0.85};
const STALK_PACE:f32 = 1.8;
/// the crop: its centre and radii; what condenses hangs at its heart
pub const CROP_AT = v3(0, 0.5, 0);
pub const CROP_R = v3(0.15, 0.17, 0.15);
/// fronds clasping the crop
const CLASP = pk.FOLD;
/// control points along one, and how far off the crop's skin it is held
const CLASP_CTRL = 9;
const CLASP_OFF:f32 = 0.07;
/// where grit leaves the crop (its lip, low on its +X flank) and the cup
/// on the foot it runs down into
pub const LIP = CROP_AT + v3(CROP_R[0] * 0.8, -CROP_R[1] * 0.55, 0);
pub const CUP_AT = v3(0.15, 0.065, 0.0);
const CUP_PETALS = pk.FOLD;
/// the foot
const FOOT_AT = v3(0, -0.015, 0);
const FOOT_R = v3(0.13, 0.085, 0.13);

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var k = growth.Skeleton.begin(b);
  const stalk = k.trunk(&.{v3(0, -0.03, 0), v3(0.015, 0.12, -0.01), v3(-0.012, 0.24, 0.008), NECK}, .{.pace = STALK_PACE});
  try pk.foot(b, &k, stalk, FOOT_AT, FOOT_R);
  try pk.roots(b, &k, stalk, pk.FOLD, 0.26, 0.016, 0x1170);
  try pk.stalk(b, &k, stalk, STALK);
  try pk.organs(b, &k, stalk, STALK, 2, 0.6);
  // the cup on the foot, opening as the foot swells: a whorl of short pale
  // lobes cupped round where the grit pools
  for (0..CUP_PETALS) |i| {
    const a = m.ratio(i, CUP_PETALS) * m.tau;
    const s = b.mark();
    try mg.petal(b, .{
      .base = CUP_AT - v3(0, 0.012, 0), .out = v3(@cos(a), 0, @sin(a)), .len = 0.05, .width = 0.028,
      .rise = 0.75, .flare = 0.35, .cup = 0.6, .col = pk.skin, .tip = pk.pearl, .t = 0.1, .part = .leaf,
    });
    try k.on(b, s, stalk, 0.2, .{.from = CUP_AT});
  }
  // the crop, swelling out of the stalk's top
  try pk.bladder(b, &k, stalk, 1, CROP_AT, CROP_R, 1, .{.from = NECK});
  // its lip: a short pale spout pursed on its flank
  const lip = b.mark();
  try b.tube(&.{LIP - v3(0.03, -0.012, 0), LIP, LIP + v3(0.012, -0.012, 0)}, &.{0.9, 0.9, 0.9}, 0.018, 0.012, pk.pearl, .stem, 7);
  try k.on(b, lip, stalk, 1, .{.from = NECK, .delay = 0.05});
  // fronds out of its foot pole, up its flank over the outside and curling
  // in over its crown, alike
  for (0..CLASP) |i| {
    const a = (m.f(i) + 0.5) / CLASP * m.tau;
    var c:[CLASP_CTRL]V3 = undefined;
    for (&c, 0..) |*p, j| {
      const f = m.ratio(j, CLASP_CTRL - 1);
      // its polar angle from the crop's foot round to past its crown, held
      // just off its skin, the tip curling in and down toward the crown
      const th = m.lerp(m.pi, -0.15, f);
      const lift = 1 + CLASP_OFF + 0.25 * f * f * f;
      const tw = a + 0.35 * f;
      p.* = CROP_AT + v3(@sin(th) * @cos(tw) * CROP_R[0] * lift, @cos(th) * CROP_R[1] * (1 + CLASP_OFF) - 0.05 * f * f * f * f, @sin(th) * @sin(tw) * CROP_R[2] * lift);
    }
    mg.grow(c[1..], .{.start = c[1], .direction = v3(0, 1, 0), .length = 0.5, .wobble = 0.12, .seed = 0x1180});
    const id = k.branch(stalk, 1, &c, .{.delay = 0.05});
    try k.tube(b, id, .{.r0 = 0.013, .tip = 0.15, .col = pk.lilac, .part = .tendril, .sides = 5, .t0 = 0.75, .t1 = 1});
  }
  // a pearl nub at the crop's crown the fronds curl over
  const nub = b.mark();
  try mg.ellipsoid(b, .{.center = CROP_AT + v3(0, CROP_R[1] * 0.98, 0), .radii = v3(0.028, 0.02, 0.028), .col = pk.pearl, .rings = 5, .segs = 8, .t = 1});
  try k.on(b, nub, stalk, 1, .{.from = NECK, .delay = 0.08});
  k.finish(b);
}

/// mesh: LITHOPHAGE CRYSTAL. what the crop condenses from the ground: a
/// cluster of faceted crystals (part `.prism`, no light of their own) about
/// its own origin, a unit `CRYSTAL_R` across; the structure grows it with
/// what it has drawn and shrinks it as it saps it away.
pub const crystal = struct {
  pub const R:f32 = 0.09;
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    var rng = Rng.init(0x117C);
    const body = color.rgb(0.62, 0.5, 0.86).toRgba8(255);
    const tip = color.rgb(1.0, 0.86, 0.6).toRgba8(255);
    // points out every way from the heart, as it grows in sap
    for (0..9) |i| {
      const th = m.f(i) * 2.39996;
      const y = m.lerp(0.85, -0.85, m.ratio(i, 8));
      const rr = @sqrt(1 - y * y);
      const dir = m.norm(v3(@cos(th) * rr, y, @sin(th) * rr));
      try mineral.crystal(b, .{
        .base = dir * m.splat3(-R * 0.25), .dir = dir, .len = R * rng.range(0.85, 1.15), .r = R * rng.range(0.22, 0.3),
        .col = body, .tip = tip, .part = .prism,
      }, &rng);
    }
  }
};

/// mesh: LITHOPHAGE ROOT. a pale root from the foot out along +X to the
/// node on the next tile, arching low and digging into it, splitting into
/// gripping rootlets there; `root_far` the same to a node on a diagonal.
/// It grows out along its own spline as it reaches (emitted with that as
/// `grown`), the rootlets last, and withers back down it.
pub const root = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void { try reaching(b, 0.86, 0x11A0); }
};
pub const root_far = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void { try reaching(b, 0.86 * m.sqrt2, 0x11A1); }
};

fn reaching(b:*mg.Builder, reach:f32, seed:u64) Allocator.Error!void {
  var k = growth.Skeleton.begin(b);
  var c:[7]V3 = undefined;
  for (&c, 0..) |*p, j| {
    const f = m.ratio(j, 6);
    p.* = v3(0.07 + (reach - 0.07) * f, 0.02 + 0.07 * @sin(m.pi * f) * (1 - 0.4 * f) - 0.06 * f * f * f, 0);
  }
  mg.grow(&c, .{.start = c[0], .direction = v3(1, 0, 0), .length = reach, .wobble = 0.25, .seed = seed});
  const r = k.trunk(&c, .{});
  try k.tube(b, r, .{.r0 = 0.02, .tip = 0.35, .col = pk.pearl, .part = .tendril, .sides = 6, .t0 = 0, .t1 = 0.2});
  // gripping the node: rootlets clawing down round it
  const end = k.point(r, 1);
  for (0..pk.FOLD) |i| {
    const a = m.ratio(i, pk.FOLD) * m.tau;
    const out = v3(@cos(a), 0, @sin(a));
    var g:[5]V3 = undefined;
    for (&g, 0..) |*p, j| {
      const f = m.ratio(j, 4);
      p.* = end + out * m.splat3(0.08 * @sin(f * 1.4)) + v3(0, -0.07 * f * f, 0);
    }
    const id = k.branch(r, 1, &g, .{});
    try k.tube(b, id, .{.r0 = 0.009, .tip = 0.1, .col = pk.lilac, .part = .tendril, .sides = 4, .t0 = 0.2, .t1 = 0.25});
  }
  k.finish(b);
}
