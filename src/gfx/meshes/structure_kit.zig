//! the symbiotic lineage's body: shared pieces for grown structures, in
//! the plants' language (a woven root mat they rise from, grown vines with
//! leaves along them, and pods of the wolf's resin sap, dense at the base,
//! see-through toward the top, with no light of its own), and its plants
//! built of the same (`plant`, the `herb` form). Not a mesh itself; the
//! structure meshes use it. Given an `On`, a piece grows on a structure's
//! growth splines (gfx/growth.zig) instead of with the structure as a
//! whole; a plant grows by tu.x (plant.vert).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("engine").core.color;
const Rng = @import("engine").core.rng.Rng;
const growth = @import("../growth.zig");
const species = @import("../../sim/species.zig");

const V3 = m.V3;
const v3 = m.v3;

/// where a piece grows: off spline `id` of skeleton `k`, `u` along it
pub const On = struct {
  k:*growth.Skeleton,
  id:growth.Id,
  u:f32 = 0,
};

/// `n` braided roots radiating from the centre out to `reach`, hugging the
/// ground and sinking into it at their ends.
/// On a spline, each root is a branch off it growing with it.
pub fn rootMat(b:*mg.Builder, n:u32, reach:f32, girth:f32, seed:u64, on:?On) Allocator.Error!void {
  var rng = Rng.init(seed);
  for (0..n) |i| {
    const a = (m.f(i) + rng.range(-0.25, 0.25)) / m.f(n) * m.tau;
    const from = v3(@cos(a) * 0.08, 0.06, @sin(a) * 0.08);
    const to = v3(@cos(a) * reach * rng.range(0.8, 1.05), -0.04, @sin(a) * reach * rng.range(0.8, 1.05));
    var c:[6]V3 = undefined;
    mg.growthPath(.{.start = from, .direction = m.norm(to - from), .length = m.len(to - from), .wobble = 0.25, .seed = seed +% i * 41}, &c);
    if (on) |o| {
      const root = o.k.branch(o.id, o.u, &c, .{.after = .with});
      try o.k.braid(b, root, .{.girth = girth, .wobble = pal.STRAND_WOBBLE, .seed = seed +% i * 7, .core = pal.core, .strand = pal.vine, .t0 = 0.05});
      continue;
    }
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
/// leaves along it. On a spline, it is a branch off it (grown once that
/// is done, `from` moved onto it), its leaves opening as it passes them.
pub fn leafyVine(b:*mg.Builder, from:V3, to:V3, r0:f32, curl:f32, leaves:u32, t0:f32, t1:f32, seed:u64, on:?On) Allocator.Error!void {
  const g:mg.Growth = .{.start = from, .direction = m.norm(to - from), .length = m.len(to - from), .wobble = 0.18, .curl = curl, .seed = seed};
  if (on) |o| {
    const vine = o.k.vine(o.id, o.u, g, 7, .{});
    try o.k.tube(b, vine, .{.r0 = r0, .col = pal.vine, .sides = 5, .t0 = t0, .t1 = t1});
    try o.k.leaves(b, vine, .{.n = leaves, .len = 0.18, .width = 0.06, .t0 = t0, .t1 = t1, .col = pal.leaf_dark, .tip = pal.leaf_lite, .seed = seed +% 3});
    return;
  }
  var c:[7]V3 = undefined;
  mg.growthPath(g, &c);
  var p:[18]V3 = undefined;
  m.splineResample(&c, &p);
  var ts:[18]f32 = undefined;
  var rs:[18]f32 = undefined;
  mg.taperRadii(r0, 0.3, &rs);
  for (&ts, 0..) |*t, j| t.* = m.lerp(t0, t1, m.ratio(j, 17));
  try b.tubeR(&p, &ts, &rs, pal.vine, .stem, 5);
  try mg.leavesAlong(b, &p, leaves, 0.18, 0.06, 0.15, 0.85, t0, t1, pal.leaf_dark, pal.leaf_lite, seed +% 3);
}

/// how much later each foot leaf unfolds than the one before (a share of
/// the whole growth)
const FOOT_STAGGER:f32 = 0.025;

/// a pod of resin sap: tu.y runs from its dense base (0) to its thin
/// crown (1), which the resin shading reads.
pub fn resinPod(b:*mg.Builder, center:V3, radii:V3, rings:u32, segs:u32) Allocator.Error!void {
  const start = b.mark();
  try mg.ellipsoid(b, .{.center = center, .radii = radii, .col = pal.sap, .part = .resin, .rings = rings, .segs = segs, .t = 0.6});
  for (b.v.items[start..]) |*vx| vx.tu[1] = m.clamp01((vx.pos[1] - (center[1] - radii[1])) / (2 * radii[1]));
}

/// broad leaves in a ring at the foot, all on one envelope. On a spline,
/// they unfold from their bases one after another as its front passes.
pub fn footLeaves(b:*mg.Builder, n:u32, r:f32, len:f32, width:f32, seed:u64, on:?On) Allocator.Error!void {
  var rng = Rng.init(seed);
  for (0..n) |i| {
    const a = (m.f(i) + rng.range(-0.2, 0.2)) / m.f(n) * m.tau;
    const dir = m.norm(v3(@cos(a), 0.25, @sin(a)));
    const base = v3(@cos(a) * r, 0.08, @sin(a) * r);
    const s = b.mark();
    try b.blade(base, dir, len * rng.range(0.85, 1.1), width, 0.7, pal.leaf_dark, pal.leaf_lite, 0.4, .leaf);
    if (on) |o| try o.k.on(b, s, o.id, o.u, .{.from = base, .delay = FOOT_STAGGER * m.f(i)});
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

/// the lineage's braid: how far a strand turns round its stem per unit of
/// the stem's length per unit of its radius (a germinator trunk's pitch),
/// so thin stems and thick trunks wind alike
const PITCH:f32 = 0.46;
/// a stem thicker than this braids six strands round its core, else four
const THICK:f32 = 0.1;
/// braided roots a rooted symbiote spreads into the soil
const ROOTS = 5;
/// the golden angle: leaves and offshoots turn by it, each a little apart
const GOLDEN:f32 = 2.39996;

/// a symbiote (the `herb` form) grown from its genome, in the lineage's
/// body: a braided stem, strands wound tight round a darker core, each a
/// little different, flaring into a mat of braided roots sinking into the
/// soil (`rooted`), a rosette of broad leaves at its foot, leafy vines
/// twining up it, leaves up it on one envelope, braided offshoots ending in
/// buds or small blooms, and its bloom opening out of a bead of resin sap
/// held in a cup of sepals. Grown by tu.x (plant.vert); deterministic per
/// `seed` and `variant`.
pub fn plant(b:*mg.Builder, g:species.Genome, seed:u64, variant:u32, rooted:bool) Allocator.Error!void {
  var rng = Rng.init(seed);
  const strand = g.stem_col.toRgba8(255);
  const core = color.shade(g.stem_col, 0.55);
  const leaf = color.shade(g.leaf_col, 0.6);
  const leaf_tip = g.leaf_col.toRgba8(255);

  // the stem: a grown vine rising from the root, flaring where it meets
  // the ground so it grows out of the soil rather than standing on it
  const RES = 32;
  const lean = v3(rng.range(-0.08, 0.08), 1, rng.range(-0.08, 0.08));
  const stem:mg.Growth = .{
    .start = v3(0, 0, 0), .direction = m.norm(lean), .length = g.stem_h,
    .wobble = g.wobble, .curl = g.curl, .taper = 0.35, .seed = seed ^ 0x57E4,
  };
  var ctrl:[17]V3 = undefined;
  const cn = @as(usize, @max(@min(g.segments, 16), 3)) + 1;
  mg.growthPath(stem, ctrl[0..cn]);
  var spine:[RES]V3 = undefined;
  m.splineResample(ctrl[0..cn], &spine);
  var ts:[RES]f32 = undefined;
  var radii:[RES]f32 = undefined;
  mg.taperRadii(g.stem_r, stem.taper, &radii);
  for (&ts, &radii, 0..) |*t, *r, i| {
    const k = m.ratio(i, RES - 1);
    t.* = k;
    if (rooted) {
      const low = 1 - k;
      r.* *= 1 + 0.9 * low * low * low * low * low * low;
    }
  }
  const strands:u32 = if (g.stem_r > THICK) 6 else 4;
  try mg.braid(b, &spine, &ts, &radii, strands, PITCH * g.stem_h / g.stem_r, pal.STRAND_WOBBLE, seed ^ 0xB4A1, core, strand);

  if (rooted) {
    // the root mat: braided roots leaving the flare, arching down to hug
    // the ground and sinking into it at their ends
    for (0..ROOTS) |i| {
      const a = (m.f(i) + rng.range(-0.25, 0.25)) / ROOTS * m.tau + m.f(variant);
      const out = v3(@cos(a), 0, @sin(a));
      const reach = g.stem_r * rng.range(9, 12);
      var c:[6]V3 = undefined;
      for (&c, 0..) |*p, j| {
        const s = m.ratio(j, c.len - 1);
        p.* = out * m.splat3(m.lerp(g.stem_r * 0.6, reach, s)) + v3(0, g.stem_r * (2 * (1 - s) * (1 - s) + 0.3 * s * (1 - s) - s * s), 0);
      }
      mg.grow(&c, .{.start = c[0], .direction = m.norm(c[5] - c[0]), .length = m.len(c[5] - c[0]), .wobble = 0.25, .seed = seed +% i * 41});
      var p:[12]V3 = undefined;
      m.splineResample(&c, &p);
      var rt:[12]f32 = undefined;
      var rr:[12]f32 = undefined;
      for (&rt, &rr, 0..) |*t, *r, j| {
        const k = m.ratio(j, 11);
        t.* = 0.04 * (1 - k);
        r.* = g.stem_r * 0.7 * m.lerp(1, 0.35, k);
      }
      try mg.braid(b, &p, &rt, &rr, 3, 2.2, pal.STRAND_WOBBLE, seed +% i * 7, core, strand);
    }
    // the rosette: broad leaves lying out round the foot, unfolding first
    for (0..g.rosette) |i| {
      const a = (m.f(i) + rng.range(-0.2, 0.2)) / m.f(g.rosette) * m.tau + m.f(variant) * 0.7 + 0.5;
      const out = v3(@cos(a), 0, @sin(a));
      const base = out * m.splat3(g.stem_r * 1.2) + v3(0, g.stem_r * 1.5, 0);
      try b.blade(base, m.norm(out + v3(0, 0.3, 0)), g.leaf_len * rng.range(1.05, 1.25), g.leaf_w * 1.3, 0.7, leaf, leaf_tip, 0.04, .leaf);
    }
  }

  // leafy vines twining up the stem from its foot, rooted at it and
  // tapering to a point at both ends, small leaves along them
  for (0..g.vines) |vi| {
    const N = 10;
    const VR = 28;
    const k0:f32 = 0.03;
    const k1 = rng.range(0.55, 0.7);
    const turns = rng.range(1.2, 1.6);
    const a0 = m.f(vi) / m.f(g.vines) * m.tau + rng.float() * m.tau;
    const vr = g.stem_r * 0.32;
    var c:[N]V3 = undefined;
    for (&c, 0..) |*p, j| {
      const s = m.ratio(j, N - 1);
      const k = m.lerp(k0, k1, s);
      const a = a0 + s * turns * m.tau;
      const ri:usize = @intFromFloat(k * (RES - 1));
      p.* = m.alongPath(&spine, k) + v3(@cos(a), 0, @sin(a)) * m.splat3(radii[ri] * 1.05 + vr);
    }
    mg.grow(&c, .{.start = c[0], .direction = m.norm(c[N - 1] - c[0]), .length = m.len(c[N - 1] - c[0]), .wobble = 0.06, .seed = seed +% vi * 83});
    var p:[VR]V3 = undefined;
    m.splineResample(&c, &p);
    var vt:[VR]f32 = undefined;
    var vs:[VR]f32 = undefined;
    for (&vt, &vs, 0..) |*t, *r, j| {
      const s = m.ratio(j, VR - 1);
      t.* = m.lerp(k0, k1, s);
      r.* = @max(vr * @sqrt(@sin(m.pi * s)), 2e-4);
    }
    try b.tubeR(&p, &vt, &vs, color.mix(strand, leaf_tip, 0.25), .stem, 5);
    try mg.leavesAlong(b, &p, 4, g.leaf_len * 0.4, g.leaf_w * 0.55, 0.2, 0.9, k0, k1, leaf, leaf_tip, seed +% vi * 29);
  }

  // leaves in a phyllotactic spiral up the stem, all on one envelope: the
  // lowest longest and drooping most, rising and shortening toward the
  // crown, their bases tucked into the stem
  const from = g.leaf_from;
  for (0..g.leaves) |i| {
    const k = from + (0.92 - from) * m.ratio(i, @max(g.leaves, 1));
    const up = m.ratio(i, @max(g.leaves, 1));
    const at = m.alongPath(&spine, k);
    const ang = m.f(i) * GOLDEN + m.f(variant);
    const dir = m.norm(v3(@cos(ang), 0.15 + 0.45 * up, @sin(ang)));
    const len = g.leaf_len * m.lerp(1.25, 0.55, up) * rng.range(0.93, 1.07);
    const droop = g.leaf_droop * m.lerp(1.3, 0.6, up);
    const base = at - v3(@cos(ang), 0, @sin(ang)) * m.splat3(g.stem_r * 0.4);
    try b.blade(base, dir, len, g.leaf_w * m.lerp(1.1, 0.8, up), droop, leaf, leaf_tip, k, .leaf);
  }

  // thorns: small, short, pressed to the stem
  for (0..g.thorns) |i| {
    const k = 0.15 + 0.7 * rng.float();
    const ang = m.f(i) * GOLDEN * 1.3;
    try b.cone(m.alongPath(&spine, k), m.norm(v3(@cos(ang), 0.4, @sin(ang))), 0.045, 0.01, color.shade(g.bloom_col, 0.7), k, .thorn);
  }

  // prop roots: braided, from low on the stem down into the soil close
  // round the foot, small leaves along them
  const prop = m.alongPath(&spine, 0.2);
  for (0..g.tendrils) |i| {
    const ang = m.ratio(i, g.tendrils) * m.tau + 0.4 + 0.3 * m.f(variant);
    const spread = g.stem_r * 3 + g.stem_h * 0.12;
    const reach = v3(@cos(ang) * spread, -prop[1] * 0.98, @sin(ang) * spread);
    var tc:[7]V3 = undefined;
    mg.growthPath(.{
      .start = prop, .direction = m.norm(reach), .length = m.len(reach),
      .wobble = g.tendril_wobble, .curl = g.tendril_curl, .seed = seed +% i * 31,
    }, &tc);
    var tp:[20]V3 = undefined;
    m.splineResample(&tc, &tp);
    var tt:[20]f32 = undefined;
    var tr:[20]f32 = undefined;
    mg.taperRadii(g.stem_r * 0.4, 0.3, &tr);
    for (&tt, 0..) |*t, j| t.* = m.lerp(0.2, 0.05, m.ratio(j, 19));
    try mg.braid(b, &tp, &tt, &tr, 3, 2.4, pal.STRAND_WOBBLE, seed +% i * 17, core, strand);
    try mg.leavesAlong(b, &tp, 3, g.leaf_len * 0.4, g.leaf_w * 0.55, 0.12, 0.6, 0.2, 0.05, leaf, leaf_tip, seed +% i * 13);
  }

  // offshoots: braided side stems leaving the main one between the
  // leaves, each curving up to the light and ending in a bud or a small
  // bloom; they come up pressed to the stem (meshgen `shootFold`)
  const shoot_r = g.stem_r * 0.55;
  // (below a tree's crown too: they branch from the trunk)
  const shoot_from = @max(from * 0.6, 0.3);
  var srng = Rng.init(seed ^ 0x0FF5);
  const shoots = mg.shootCount(g, &srng);
  for (0..shoots) |i| {
    const k = m.lerp(shoot_from, 0.85, (m.f(i) + srng.range(0.2, 0.8)) / m.f(shoots));
    const ang = m.f(i) * GOLDEN * 1.7 + 1.1 + m.f(variant) * 0.9 + srng.range(-0.3, 0.3);
    const len = g.stem_h * srng.range(0.32, 0.46) * m.lerp(1.15, 0.75, k);
    const sh = mg.shootPath(&spine, k, k, ang, len, srng.range(0.3, 0.6), seed +% i * 211);
    var st:[mg.SHOOT_RES]f32 = undefined;
    var sr:[mg.SHOOT_RES]f32 = undefined;
    for (&st, &sr, 0..) |*t, *r, j| {
      const s = m.ratio(j, mg.SHOOT_RES - 1);
      t.* = m.lerp(sh.t0, sh.t1, s);
      r.* = shoot_r * m.lerp(1, 0.55, s);
    }
    const s0 = b.mark();
    try mg.braid(b, &sh.path, &st, &sr, 3, PITCH * len / shoot_r, pal.STRAND_WOBBLE, seed +% i * 101, core, strand);
    mg.shootFoldNearest(b, s0, &sh.path);
    const lv = b.mark();
    try mg.leavesAlong(b, &sh.path, 2, g.leaf_len * 0.45, g.leaf_w * 0.6, 0.25, 0.7, sh.t0, sh.t1, leaf, leaf_tip, seed +% i * 59);
    mg.shootFoldAlong(b, lv, &sh.path);
    const s = b.mark();
    if (srng.float() < 0.5)
      try mg.flower(b, g, sh.at, sh.axis, srng.range(0.55, 0.7), m.f(variant) + m.f(i), sh.t1, .{.resin = pal.sap})
    else
      try mg.bud(b, g, sh.at, sh.axis, srng.range(0.65, 0.85), m.f(i) * 1.3, sh.t1);
    mg.shootFold(b, s, 1);
  }

  // the bloom: its bead of resin in the cup of sepals, the petals rising
  // from its crown
  try mg.flower(b, g, spine[RES - 1], m.norm(spine[RES - 1] - spine[RES - 4]), 1, m.f(variant), 1, .{.resin = pal.sap});
}
