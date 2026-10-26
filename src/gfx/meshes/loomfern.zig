//! mesh: LOOMFERN. a fern that weaves: a short woven bole on a root mat,
//! opening into a crown of fronds arching out, their leaflets in pairs
//! along them, two young fronds still rolled tight in croziers at the
//! heart. Up through the middle rises a slender spindle out of a calyx
//! (essence it is fed stands in the calyx, `germinator_pool`); the sheaf
//! of fibre it weaves forms on the spindle (`sheaf`), drawn from the
//! fronds by threads (`thread`), and finished sheaves are laid at its foot.
//! It grows on a hidden bole (gfx/growth.zig): the roots spread with it,
//! then the fronds rise out of the crown one after another, their leaflets
//! unfolding as each front passes, the croziers last, then the calyx opens
//! and the spindle rises.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("engine").core.color;
const kit = @import("structure_kit.zig");
const growth = @import("../growth.zig");
const Rng = @import("engine").core.rng.Rng;

const V3 = m.V3;
const v3 = m.v3;

/// the bole: how high its crown stands, its girth at the foot
pub const CROWN = v3(0, 0.15, 0);
const BOLE_R:f32 = 0.06;
const BOLE_PACE:f32 = 1.6;
/// fronds round the crown, their control points, and how much later each
/// rises than the one before (the skeleton's time)
pub const FRONDS = 7;
const FROND_CTRL = 7;
const FROND_STAGGER:f32 = 0.06;
const RACHIS_R:f32 = 0.014;
/// leaflets: pairs along each frond from `PINNA_FROM` to its tip, longest
/// near its foot
const PINNAE = 14;
const PINNA_FROM:f32 = 0.22;
const PINNA_LEN:f32 = 0.115;
const PINNA_W:f32 = 0.019;
/// the spindle: from the crown up to its tip; the sheaf sits on it at `SHEAF_AT`
pub const SPINDLE_TOP = v3(0, 0.46, 0);
pub const SHEAF_AT = v3(0, 0.33, 0);
const SPINDLE_R:f32 = 0.011;
/// the calyx round the spindle's foot, and where its pool of essence stands
const SEPALS = 5;
pub const POOL_AT = CROWN + v3(0, 0.035, 0);
/// a sheaf's height and girth at its waist and at its ends (its unit size)
pub const SHEAF_H:f32 = 0.17;
const SHEAF_WAIST:f32 = 0.018;
const SHEAF_END:f32 = 0.045;
const SHEAF_STRANDS = 16;
/// fibre: the colour of the item it weaves, younger toward the tips
const fibre = color.rgb(0.47, 0.66, 0.35).toRgba8(255);
const fibre_dark = color.rgb(0.33, 0.48, 0.24).toRgba8(255);
const fibre_lite = color.rgb(0.62, 0.78, 0.45).toRgba8(255);

/// a frond's control points (deterministic per frond), from the crown
/// arching out and over, its tip curling back under as a crozier unrolled
pub fn frondCtrl(i:usize) [FROND_CTRL]V3 {
  var rng = Rng.init(0x10F + i * 97);
  const a = (m.f(i) + rng.range(-0.18, 0.18)) / FRONDS * m.tau;
  const out = v3(@cos(a), 0, @sin(a));
  const up = v3(0, 1, 0);
  const reach = rng.range(0.9, 1.1);
  const lift = rng.range(0.85, 1.12);
  const ks = [FROND_CTRL][2]f32{.{0.02, 0}, .{0.07, 0.17}, .{0.19, 0.31}, .{0.33, 0.36}, .{0.45, 0.3}, .{0.52, 0.2}, .{0.5, 0.15}};
  var c:[FROND_CTRL]V3 = undefined;
  for (&c, ks) |*p, k| p.* = CROWN + out * m.splat3(k[0] * reach) + up * m.splat3(k[1] * lift);
  return c;
}

/// the point `u` along frond `i` (0 its foot .. 1 its tip)
pub fn frondAt(i:usize, u:f32) V3 {
  const c = frondCtrl(i);
  var p:[growth.RES]V3 = undefined;
  m.splineResample(&c, &p);
  return m.alongPath(&p, u);
}

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var k = growth.Skeleton.begin(b);
  const bole = k.trunk(&.{v3(0, -0.04, 0), v3(0.008, CROWN[1] * 0.5, -0.006), CROWN}, .{.pace = BOLE_PACE});
  try kit.rootMat(b, 5, 0.42, 0.04, 0x10F1, .{.k = &k, .id = bole});
  {
    var sp:[growth.RES]V3 = undefined;
    var ts:[growth.RES]f32 = undefined;
    var rs:[growth.RES]f32 = undefined;
    k.path(bole, 0, 1, &sp);
    for (&ts, &rs, 0..) |*t, *r, i| {
      const u = m.ratio(i, growth.RES - 1);
      t.* = u * 0.3;
      // flared at its foot, swelling again under the crown
      r.* = BOLE_R * (0.75 + 0.5 * @exp(-u * 6) + 0.25 * @exp(-(1 - u) * 7));
    }
    const s = b.mark();
    try mg.braid(b, &sp, &ts, &rs, 5, 2.4, pal.STRAND_WOBBLE, 0x10F2, pal.core, pal.vine);
    try k.along(b, s, bole);
  }
  for (0..FRONDS) |i| try frond(b, &k, bole, i);
  for (0..2) |i| try crozier(b, &k, bole, i);
  // the calyx: sepals cupped round the spindle's foot, opening once the
  // fronds are out
  const spindle = k.branch(bole, 1, &.{CROWN, CROWN + v3(0.006, 0.12, 0.004), SHEAF_AT, SPINDLE_TOP}, .{.delay = 0.1});
  for (0..SEPALS) |i| {
    const a = (m.f(i) + 0.3) / SEPALS * m.tau;
    const s = b.mark();
    try mg.petal(b, .{
      .base = CROWN, .out = v3(@cos(a), 0, @sin(a)), .len = 0.085, .width = 0.042,
      .rise = 1.0, .flare = 0.6, .cup = 0.55, .col = pal.core, .tip = pal.leaf_lite, .t = 0.35, .part = .leaf,
    });
    try k.on(b, s, spindle, 0, .{.from = CROWN, .delay = 0.02 * m.f(i)});
  }
  try k.tube(b, spindle, .{.r0 = SPINDLE_R, .tip = 0.25, .col = pal.root_lite, .sides = 5, .t0 = 0.35, .t1 = 1});
  // a bud closing the spindle's tip, stamens peeping out of it
  const bud = b.mark();
  try mg.ellipsoid(b, .{.center = SPINDLE_TOP, .radii = v3(0.016, 0.022, 0.016), .col = pal.leaf_dark, .part = .leaf, .rings = 5, .segs = 7, .t = 1});
  try mg.stamens(b, .{.heart = SPINDLE_TOP + v3(0, 0.014, 0), .axis = v3(0, 1, 0), .n = 5, .len = 0.04, .r = 0.0025, .anther = 0.01, .lean = 0.4, .arch = 0.5, .col = pal.leaf_lite, .seed = 0x10F9});
  try k.on(b, bud, spindle, 1, .{});
  k.finish(b);
}

/// one frond: a green rachis arching out of the crown, a pair of leaflets
/// at each step along it, each pair unfolding as the front passes
fn frond(b:*mg.Builder, k:*growth.Skeleton, bole:growth.Id, i:usize) Allocator.Error!void {
  const c = frondCtrl(i);
  const id = k.branch(bole, 1, &c, .{.delay = FROND_STAGGER * m.f(i)});
  try k.tube(b, id, .{.r0 = RACHIS_R, .tip = 0.2, .col = pal.vine, .sides = 5, .t0 = 0.3, .t1 = 1});
  var rng = Rng.init(0x10FA + i * 31);
  for (0..PINNAE) |j| {
    const u = m.lerp(PINNA_FROM, 0.95, m.ratio(j, PINNAE - 1));
    const at = k.point(id, u);
    const tan = k.tangent(id, u);
    const side = m.norm(m.cross(tan, v3(0, 1, 0)));
    // shortest toward the tip, swept on along the frond
    const len = PINNA_LEN * (1 - 0.72 * m.smooth(m.ratio(j, PINNAE - 1))) * rng.range(0.9, 1.08);
    const s = b.mark();
    for ([_]f32{1, -1}) |sgn| {
      const dir = m.norm(side * m.splat3(sgn) + tan * m.splat3(0.55) + v3(0, 0.12, 0));
      try b.blade(at, dir, len, PINNA_W * (1 - 0.5 * m.ratio(j, PINNAE - 1)), 0.45, pal.leaf_dark, pal.leaf_lite, m.lerp(0.3, 1, u), .leaf);
    }
    try k.on(b, s, id, u, .{});
  }
}

/// a young frond still rolled up: rising from the crown, its tip coiled
/// into a tight spiral (a crozier), its leaflets furled to nubs along it
fn crozier(b:*mg.Builder, k:*growth.Skeleton, bole:growth.Id, i:usize) Allocator.Error!void {
  const a = (m.f(i) * 3.4 + 1.1);
  const out = v3(@cos(a), 0, @sin(a));
  const side = m.norm(m.cross(out, v3(0, 1, 0)));
  const rise = CROWN + out * m.splat3(0.035) + v3(0, 0.16 + 0.04 * m.f(i), 0);
  // the coil: a spiral in the plane of `out` and up, closing as it turns
  const N = 10;
  var c:[N + 2]V3 = undefined;
  c[0] = CROWN + out * m.splat3(0.015);
  c[1] = CROWN + out * m.splat3(0.03) + v3(0, 0.08, 0);
  for (0..N) |j| {
    const f = m.ratio(j, N - 1);
    const th = f * 1.6 * m.tau;
    const r = 0.04 * (1 - 0.8 * f);
    c[j + 2] = rise + out * m.splat3(r * @sin(th)) + v3(0, r * @cos(th), 0) + side * m.splat3(0.004 * f);
  }
  const id = k.branch(bole, 1, &c, .{.delay = FROND_STAGGER * FRONDS + 0.04 * m.f(i), .pace = 1.4});
  var sp:[growth.RES]V3 = undefined;
  var ts:[growth.RES]f32 = undefined;
  var rs:[growth.RES]f32 = undefined;
  k.path(id, 0, 1, &sp);
  for (&ts, &rs, 0..) |*t, *r, j| {
    const u = m.ratio(j, growth.RES - 1);
    t.* = m.lerp(0.3, 0.8, u);
    r.* = RACHIS_R * 1.1 * (1 - 0.75 * u);
  }
  // furled young green, paler at the coil where it is newest
  var cols:[growth.RES]color.Rgba8 = undefined;
  for (&cols, 0..) |*cl, j| cl.* = color.mix(pal.vine, pal.leaf_lite, m.ratio(j, growth.RES - 1));
  const s = b.mark();
  try b.tubeC(&sp, &ts, &rs, &cols, null, .stem, 6);
  // furled leaflets: small nubs along the coil's outside
  for (0..6) |j| {
    const u = m.lerp(0.35, 0.9, m.ratio(j, 5));
    const at = k.point(id, u);
    const r = RACHIS_R * 1.1 * (1 - 0.75 * u);
    for ([_]f32{1, -1}) |sgn| {
      try mg.ellipsoid(b, .{.center = at + side * m.splat3(sgn * r * 1.3), .radii = m.splat3(r * 0.9), .col = pal.leaf_lite, .part = .leaf, .rings = 3, .segs = 5, .t = 0.8});
    }
  }
  try k.along(b, s, id);
}

/// mesh: LOOMFERN SHEAF. a bundle of fibre a unit `SHEAF_H` tall standing
/// on its middle: strands gathered at the waist by a twist of root, flaring
/// at both ends, each drawn to a point; it forms on the spindle as the fern
/// weaves (the structure grows it by the weave) and is laid at its foot.
pub const sheaf = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    var rng = pal.rngFor("loomfern_sheaf");
    const N = 14;
    for (0..SHEAF_STRANDS) |i| {
      const a0 = (m.f(i) + rng.range(-0.3, 0.3)) / SHEAF_STRANDS * m.tau;
      const ring = rng.range(0.55, 1.0);
      const twist = rng.range(0.35, 0.55);
      const lo = rng.range(0.85, 1.0);
      const hi = rng.range(0.85, 1.0);
      var path:[N]V3 = undefined;
      var ts:[N]f32 = undefined;
      var rs:[N]f32 = undefined;
      var cols:[N]color.Rgba8 = undefined;
      for (&path, &ts, &rs, &cols, 0..) |*p, *t, *r, *cl, j| {
        const f = m.ratio(j, N - 1);
        const y = m.lerp(-0.5 * lo, 0.5 * hi, f);
        const flare = m.lerp(SHEAF_WAIST, SHEAF_END, m.pow(f32, @abs(y) * 2, 1.6)) * ring;
        const a = a0 + twist * y * 2;
        p.* = v3(@cos(a) * flare, y * SHEAF_H, @sin(a) * flare);
        t.* = f;
        // drawn to a point at both ends
        r.* = 0.0042 * @max(@sqrt(@sin(m.pi * f)), 0.08);
        cl.* = color.mix(fibre_dark, fibre_lite, m.clamp01(0.3 + 0.7 * @abs(y) * 2 * rng.range(0.6, 1.0)));
      }
      try b.tubeC(&path, &ts, &rs, &cols, null, .stem, 4);
    }
    // the twist of root binding its waist, wound twice round, its ends
    // tucked in under it
    const W = 28;
    var path:[W]V3 = undefined;
    var ts:[W]f32 = undefined;
    var rs:[W]f32 = undefined;
    for (&path, &ts, &rs, 0..) |*p, *t, *r, j| {
      const f = m.ratio(j, W - 1);
      const a = f * 2.1 * m.tau;
      const rr = SHEAF_WAIST * 1.25 + 0.002 * @sin(f * m.pi);
      p.* = v3(@cos(a) * rr, (f - 0.5) * 0.022, @sin(a) * rr);
      t.* = 0.5;
      r.* = 0.0045 * @max(@sqrt(@sin(m.pi * f)), 0.15);
    }
    try b.tubeR(&path, &ts, &rs, pal.root_lite, .stem, 5);
  }
};

/// mesh: LOOMFERN THREAD. a fibre drawn from a frond's leaflet to the sheaf:
/// built straight up +Y over 0..1 (bent on the GPU along its curve), a
/// strand twisting as it is drawn, as thick at either end (it is drawn
/// from one end and wound in at the other).
pub const thread = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const N = 24;
    var path:[N]V3 = undefined;
    var ts:[N]f32 = undefined;
    var rs:[N]f32 = undefined;
    var cols:[N]color.Rgba8 = undefined;
    for (&path, &ts, &rs, &cols, 0..) |*p, *t, *r, *cl, i| {
      const f = m.ratio(i, N - 1);
      const w = 0.004 * @sin(m.pi * f);
      p.* = v3(w * @cos(f * 5 * m.tau), f, w * @sin(f * 5 * m.tau));
      t.* = f;
      r.* = @max(0.0032 * @sqrt(@sin(m.pi * m.lerp(0.03, 0.97, f))), 2e-4);
      cl.* = color.mix(fibre, fibre_lite, 0.5 + 0.5 * @sin(f * 9));
    }
    try b.tubeC(&path, &ts, &rs, &cols, null, .stem, 4);
  }
};
