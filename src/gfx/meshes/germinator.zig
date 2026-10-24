//! mesh: GERMINATOR. a small tree that weaves: a woven trunk flaring into
//! its roots, its crown splitting into five boughs that rise round a core
//! of resin sap held up in a calyx, then arch over it and hold their flower
//! cups out above it. The structure tips the cups to pour the essences it
//! weaves from into the core (`cup`, `pool`, `pour`), spins them round the
//! sapwood spindle running up through it (`core`, `vortex`) and winds a
//! seed of them on the spindle (`thread`, `seed`, `winding`); those pieces
//! are emitted by it, each built here in its own space. `whole` is all of
//! it at rest: the placement preview.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("structure_kit.zig");
const color = @import("../../core/color.zig");
const Rng = @import("../../core/rng.zig").Rng;

const V3 = m.V3;
const v3 = m.v3;

/// how tall the tree stands (to the top of its cups)
pub const TALL:f32 = 1.8;
pub const BOUGHS = 5;
/// where the trunk splits into its boughs
const TRUNK_H:f32 = 0.62;
/// the core of resin sap the boughs rise round, held in the calyx
pub const CORE_AT = v3(0, 1.0, 0);
pub const CORE_R = v3(0.27, 0.29, 0.27);
/// where the streams fall into the core: its crown
pub const CORE_TOP = CORE_AT + v3(0, CORE_R[1] * 0.8, 0);
/// the bough tips the cups stand on: this far out from the trunk's axis,
/// this high
const TIP_OUT:f32 = 0.38;
const TIP_Y:f32 = 1.64;
/// a cup's lip, where it pours from (in its own space: its spout toward
/// +x, opening up +y)
pub const CUP_LIP = v3(0.11, 0.095, 0);
/// the seed spun on the spindle: its radius at its fullest
pub const SEED_R:f32 = 0.08;
/// the seed's shape: taller than wide, drawn to a point at its crown
const SEED_TALL:f32 = 1.28;
const SEED_POINT:f32 = 0.35;

const cup_heart = color.rgb(0.34, 0.5, 0.24);
const cup_rim = color.rgb(0.86, 0.8, 0.52);
const cup_stamen = color.rgb(0.82, 0.78, 0.6);
/// essence is coloured per instance (the item it is): white under its tint
const essence_white = color.rgb(1, 1, 1).toRgba8(255);

/// bough `k`'s heading round the trunk
pub fn boughAngle(k:usize) f32 { return m.ratio(k, BOUGHS) * m.tau + 0.3; }

/// where bough `k`'s cup stands
pub fn tip(k:usize) V3 {
  const a = boughAngle(k);
  return v3(@cos(a) * TIP_OUT, TIP_Y, @sin(a) * TIP_OUT);
}

/// turns a cup's own space so its spout faces in, toward the core, from bough `k`
pub fn cupFacing(k:usize) f32 { return -(boughAngle(k) + m.pi); }

pub fn build(b:*mg.Builder) Allocator.Error!void { try tree(b); }

fn tree(b:*mg.Builder) Allocator.Error!void {
  try kit.rootMat(b, 8, 1.0, 0.08, 0x6E41);
  try kit.footLeaves(b, 7, 0.3, 0.48, 0.19, 0x6E42);
  try trunk(b);
  for (0..BOUGHS) |k| try bough(b, k);
  try calyx(b);
  try spindle(b);
}

/// the trunk: strands woven round a dark core, flared where it roots,
/// leaning a little as anything grown does
fn trunk(b:*mg.Builder) Allocator.Error!void {
  const N = 14;
  var ctrl:[5]V3 = undefined;
  mg.growthPath(.{.start = v3(0, 0, 0), .direction = v3(0, 1, 0), .length = TRUNK_H + 0.06, .wobble = 0.3, .seed = 0x6E43}, &ctrl);
  ctrl[ctrl.len - 1] = v3(0, TRUNK_H + 0.06, 0);
  var spine:[N]V3 = undefined;
  m.splineResample(&ctrl, &spine);
  var ts:[N]f32 = undefined;
  var rs:[N]f32 = undefined;
  for (&ts, &rs, spine, 0..) |*t, *r, p, i| {
    const k = m.ratio(i, N - 1);
    t.* = p[1] / TALL;
    r.* = 0.1 + 0.09 * @exp(-k * 5) - 0.015 * k;
  }
  try mg.braid(b, &spine, &ts, &rs, 6, 2.6, pal.STRAND_WOBBLE, 0x6E44, pal.core, pal.vine);
}

/// bough `k`: out of the trunk's crown, twisting a little as it rises
/// round the core (clear of it), out and up, then arching over to hold its
/// cup up above the core. Leaves along it and a leafy twig off its back.
fn bough(b:*mg.Builder, k:usize) Allocator.Error!void {
  const a = boughAngle(k);
  // (out from the axis, height) at each control point
  const at = [_][2]f32{
    .{0.04, TRUNK_H - 0.02}, .{0.17, 0.72}, .{0.32, 0.87}, .{0.39, 1.04},
    .{0.43, 1.26}, .{0.47, 1.47}, .{0.47, 1.6}, .{TIP_OUT, TIP_Y},
  };
  var ctrl:[at.len]V3 = undefined;
  for (&ctrl, at, 0..) |*c, p, j| {
    // it winds a little round the core on its way up, ending at its heading
    const ph = a - 0.4 * (1 - m.ratio(j, at.len - 1));
    c.* = v3(@cos(ph) * p[0], p[1], @sin(ph) * p[0]);
  }
  mg.grow(&ctrl, .{.start = ctrl[0], .direction = m.norm(ctrl[at.len - 1] - ctrl[0]), .length = m.len(ctrl[at.len - 1] - ctrl[0]), .wobble = 0.12, .seed = 0x6E50 +% k * 31});
  // the tip stays where the cup stands
  ctrl[at.len - 1] = tip(k);
  const N = 24;
  var path:[N]V3 = undefined;
  m.splineResample(&ctrl, &path);
  var ts:[N]f32 = undefined;
  var rs:[N]f32 = undefined;
  mg.taperRadii(0.055, 0.42, &rs);
  for (&ts, path) |*t, p| t.* = p[1] / TALL;
  try mg.braid(b, &path, &ts, &rs, 3, 3.2, pal.STRAND_WOBBLE, 0x6E60 +% k * 7, pal.core, pal.vine);
  try mg.leavesAlong(b, &path, 6, 0.24, 0.08, 0.3, 0.92, ts[0], ts[N - 1], pal.leaf_dark, pal.leaf_lite, 0x6E70 +% k * 11);

  // the crown: a twig off the bough's back, leaning out and up, and a
  // fan of leaves behind the cup
  const out = v3(@cos(a), 0, @sin(a));
  const from = m.alongPath(&path, 0.62);
  try kit.leafyVine(b, from, from + out * m.splat3(0.38) + v3(0, 0.3, 0), 0.022, 0.2, 5, from[1] / TALL, 1, 0x6E80 +% k * 13);
  const low = m.alongPath(&path, 0.4);
  try kit.leafyVine(b, low, low + out * m.splat3(0.34) + v3(0, 0.12, 0), 0.018, 0.25, 4, low[1] / TALL, 0.8, 0x6EB0 +% k * 17);
  var rng = Rng.init(0x6E90 +% k);
  const behind = m.alongPath(&path, 0.9);
  for (0..3) |i| {
    const side = v3(-out[2], 0, out[0]) * m.splat3((m.f(i) - 1) * 0.7 + rng.range(-0.1, 0.1));
    const dir = m.norm(out + side + v3(0, 0.7, 0));
    try b.blade(behind, dir, 0.27 * rng.range(0.85, 1.1), 0.1, 0.55, pal.leaf_dark, pal.leaf_lite, behind[1] / TALL, .leaf);
  }
}

/// the calyx on the trunk's crown: broad sepals cupped up round the
/// core's lower half, holding it
fn calyx(b:*mg.Builder) Allocator.Error!void {
  const heart = v3(0, TRUNK_H + 0.03, 0);
  for (0..6) |i| {
    const a = (m.f(i) + 0.5) / 6 * m.tau;
    const out = v3(@cos(a), 0, @sin(a));
    try mg.petal(b, .{
      .base = heart + out * m.splat3(0.05), .out = out, .len = 0.3, .width = 0.14,
      .rise = 0.85, .flare = 0.25, .cup = 0.5,
      .col = pal.leaf_dark, .tip = pal.leaf_lite, .t = heart[1] / TALL, .part = .leaf,
    });
  }
}

/// the spindle: a sapwood needle up through the core, from the calyx's
/// heart to just over the core's crown, tapering to a point at both ends
fn spindle(b:*mg.Builder) Allocator.Error!void {
  const N = 12;
  const y0 = TRUNK_H + 0.02;
  const y1 = CORE_AT[1] + CORE_R[1] + 0.1;
  var path:[N]V3 = undefined;
  var ts:[N]f32 = undefined;
  var rs:[N]f32 = undefined;
  for (&path, &ts, &rs, 0..) |*p, *t, *r, i| {
    const k = m.ratio(i, N - 1);
    p.* = v3(0, m.lerp(y0, y1, k), 0);
    t.* = p.*[1] / TALL;
    r.* = @max(0.014 * @sqrt(@sin(m.pi * k)), 2e-4);
  }
  try b.tubeR(&path, &ts, &rs, pal.sapwood, .stem, 6);
}

/// mesh: GERMINATOR CUP. a flower cup on a bough's tip, opening up +y, its
/// spout petal reaching out along +x (where it pours from, `CUP_LIP`),
/// stamens rising from its heart.
pub const cup = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try mg.ellipsoid(b, .{.center = v3(0, 0.012, 0), .radii = v3(0.036, 0.03, 0.036), .col = pal.vine, .rings = 5, .segs = 8, .t = 0.95});
    const n = 7;
    for (0..n) |i| {
      const a = m.ratio(i, n) * m.tau;
      const out = v3(@cos(a), 0, @sin(a));
      const spout = i == 0;
      try mg.petal(b, .{
        .base = v3(0, 0.01, 0) + out * m.splat3(0.02), .out = out,
        .len = if (spout) 0.14 else 0.12, .width = if (spout) 0.05 else 0.06,
        .rise = 1.15, .flare = if (spout) 0.9 else 0.45, .cup = 0.55,
        .col = cup_heart.toRgba8(255), .tip = cup_rim.toRgba8(255), .t = 0.97, .part = .leaf,
      });
    }
    try mg.stamens(b, .{
      .heart = v3(0, 0.02, 0), .axis = v3(0, 1, 0), .n = 6, .len = 0.075, .r = 0.004, .anther = 0.016,
      .lean = 0.22, .arch = 0.3, .col = cup_stamen.toRgba8(255), .t = 0.97, .seed = 0x6EA0,
    });
  }
};

/// mesh: GERMINATOR POOL. the essence standing in a cup: a lens of it, a
/// unit across (scaled by how much there is). Still (tu.x < 0).
pub const pool = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(1, 0.22, 1), .col = essence_white, .part = .essence, .rings = 5, .segs = 10, .t = -1});
  }
};

/// mesh: GERMINATOR POUR. a stream of essence poured from a cup into the
/// core, running straight up +y over 0..1 (tu.x the way it flows); placed
/// along its fall as a curve (part.vert). It leaves the lip full, narrows
/// as it falls, and closes to a point at both ends.
pub const pour = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const N = 24;
    var path:[N]V3 = undefined;
    var ts:[N]f32 = undefined;
    var rs:[N]f32 = undefined;
    for (&path, &ts, &rs, 0..) |*p, *t, *r, i| {
      const k = m.ratio(i, N - 1);
      p.* = v3(0, k, 0);
      t.* = k;
      r.* = @max(0.017 * (1 - 0.45 * k) * m.pow(f32, @sin(m.pi * k), 0.3), 2e-4);
    }
    try b.tubeR(&path, &ts, &rs, essence_white, .essence, 6);
  }
};

/// mesh: GERMINATOR VORTEX. one arm of the whirl spun in the core: a
/// standing ribbon of essence spiralling in from the core's wall to the
/// spindle, sinking as it goes as a whirlpool does (tu.x 0 at the wall ..
/// 1 at the spindle). The structure turns one per essence round the axis.
pub const vortex = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const N = 28;
    var path:[N]V3 = undefined;
    var ts:[N]f32 = undefined;
    var ws:[N]f32 = undefined;
    var hs:[N]f32 = undefined;
    for (&path, &ts, &ws, &hs, 0..) |*p, *t, *w, *h, i| {
      const u = m.ratio(i, N - 1);
      const r = m.lerp(0.225, 0.03, m.pow(f32, u, 0.75));
      const a = u * 1.3 * m.tau;
      p.* = v3(@cos(a) * r, m.lerp(0.06, -0.07, u), @sin(a) * r);
      t.* = u;
      const ends = @sqrt(@sin(m.pi * m.lerp(0.04, 0.96, u)));
      w.* = 0.011 * ends;
      h.* = m.lerp(0.075, 0.03, u) * ends;
    }
    try mg.loft(b, &path, &ts, &ws, &hs, v3(0, 1, 0), ring, essence_white, .essence, 8);
  }
  fn ring(a:f32) [2]f32 { return .{@cos(a), @sin(a)}; }
};

/// mesh: GERMINATOR THREAD. a thread of essence drawn off the whirl and
/// wound in onto the seed: spiralling from the core's wall in to the
/// spindle (tu.x 0 .. 1), tapering to a point at both ends.
pub const thread = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const N = 32;
    var path:[N]V3 = undefined;
    var ts:[N]f32 = undefined;
    var rs:[N]f32 = undefined;
    for (&path, &ts, &rs, 0..) |*p, *t, *r, i| {
      const u = m.ratio(i, N - 1);
      const rad = m.lerp(0.2, SEED_R * 0.75, m.smooth(u));
      const a = u * 1.6 * m.tau;
      p.* = v3(@cos(a) * rad, 0.05 * (1 - u) + 0.025 * @sin(m.pi * u), @sin(a) * rad);
      t.* = u;
      r.* = @max(0.0055 * @sqrt(@sin(m.pi * u)), 2e-4);
    }
    try b.tubeR(&path, &ts, &rs, essence_white, .essence, 5);
  }
};

/// the seed's surface, its unit size: a point at `th` down from its crown,
/// `ph` round it
fn seedAt(th:f32, ph:f32, out:f32) V3 {
  const y = @cos(th) * SEED_TALL;
  const narrow = 1 - SEED_POINT * m.smooth(m.clamp01(y / SEED_TALL));
  return v3(@sin(th) * @cos(ph) * narrow * out, y * out, @sin(th) * @sin(ph) * narrow * out);
}

/// mesh: GERMINATOR SEED. the kernel spun on the spindle, a unit across:
/// an egg drawn to a point at its crown. Still essence (tu.x < 0),
/// coloured as the seed being woven.
pub const seed = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const start = b.mark();
    try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(1, SEED_TALL, 1), .col = essence_white, .part = .essence, .rings = 8, .segs = 10, .t = -1});
    // drawn to its point: a smooth field of height, so shared vertices move alike
    for (b.v.items[start..]) |*vx| {
      const narrow = 1 - SEED_POINT * m.smooth(m.clamp01(vx.pos[1] / SEED_TALL));
      vx.pos[0] *= narrow;
      vx.pos[2] *= narrow;
    }
  }
};

/// mesh: GERMINATOR WINDING. one essence's thread wound round the seed,
/// crown to foot, as on a spindle (tu.x the way it is wound on), the seed's
/// unit size; the structure tilts one per essence so they cross.
pub const winding = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const N = 48;
    var path:[N]V3 = undefined;
    var ts:[N]f32 = undefined;
    var rs:[N]f32 = undefined;
    for (&path, &ts, &rs, 0..) |*p, *t, *r, i| {
      const u = m.ratio(i, N - 1);
      p.* = seedAt(m.lerp(0.3, m.pi - 0.25, u), u * 3.5 * m.tau, 1.05);
      t.* = u;
      r.* = @max(0.075 * @sqrt(@sin(m.pi * u)), 2e-4);
    }
    try b.tubeR(&path, &ts, &rs, essence_white, .essence, 5);
  }
};

/// mesh: GERMINATOR CORE. the core of resin sap at its own origin; the
/// structure turns it with what spins inside it, so its bubbles swirl too.
/// Thinner than a pod's resin (it never thickens past `CORE_THIN` toward
/// its base), so what spins in it shows through.
pub const core = struct {
  const CORE_THIN:f32 = 0.55;
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const start = b.mark();
    try kit.resinPod(b, v3(0, 0, 0), CORE_R, 12, 16);
    for (b.v.items[start..]) |*vx| vx.tu[1] = m.lerp(CORE_THIN, 1, vx.tu[1]);
  }
};

/// mesh: GERMINATOR (whole). the tree with its core and cups at rest: what
/// the gardener sees before putting one down.
pub const whole = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try tree(b);
    var s = b.mark();
    try core.build(b);
    b.xform(s, m.translate(CORE_AT));
    for (0..BOUGHS) |k| {
      s = b.mark();
      try cup.build(b);
      b.xform(s, m.chain(&.{m.translate(tip(k)), m.rotY(cupFacing(k))}));
    }
  }
};
