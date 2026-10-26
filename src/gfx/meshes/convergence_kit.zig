//! the lineages mixed: what grows where symbiote and parasite have become
//! one body, shared by the confluence (a plant, grown through keys) and
//! the convergent structures (grown on their growth splines, gfx/growth.zig:
//! the `*On` pieces). Not one laid over the other (a braid below, a cage above) but
//! woven through each other at every scale, so neither is ever seen alone:
//! - a stalk (`weave`) is the parasites' lattice with every other strand a
//!   symbiote's: green strands wound one way, each wandering a little off
//!   its course as a living thing does, pale strands wound the other way,
//!   exact; where it parts into a cage the two cross, and where they cross
//!   they fuse into a violet knot, neither one's colour. The core they
//!   share is banded with both saps;
//! - its sap (`sac`) is both at once, never stirred smooth: the
//!   symbiotes' amber and the parasites' pale blue swirl round each other
//!   in arms, violet where they mingle;
//! - its counts are the parasites' exact fives (`FOLD`), turned evenly
//!   and grown alike, but what each of the five carries is a symbiote's,
//!   each a little different from the next: a frond of the lineage's
//!   lilac bearing green leaflets (`frond`), a calyx of five pale
//!   frondlets holding warm living petals (`bloom`);
//! - it roots both ways (`foot`): a pale bulb half sunk in the soil, its
//!   five exact pale roots between the green braided roots of a symbiote.
//! A cage's strands carry how far they have parted in tu.y, as the
//! parasites' do. The confluence is grown through keys (sizes passed in,
//! never counts, so every key keeps one vertex layout).
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const mg = @import("../meshgen.zig");
const color = @import("engine").core.color;
const vertex = @import("../vertex.zig");
const species = @import("../../sim/species.zig");
const growth = @import("../growth.zig");
const Rng = @import("engine").core.rng.Rng;
const pal = @import("palette.zig");
const pk = @import("parasite_kit.zig");

const V3 = m.V3;
const v3 = m.v3;
const Rgba8 = color.Rgba8;
const Section = pk.Section;

/// the symbiotes' half: their strands, leaves and resin sap
pub const green = pal.vine;
pub const leaf_dark = pal.leaf_dark;
pub const leaf_lite = pal.leaf_lite;
pub const amber = pal.sap;
/// the parasites' half: their skin, pearl, fronds and thin sap
pub const pale = pk.skin;
pub const pearl = pk.pearl;
pub const lilac = pk.lilac;
pub const blue = pk.sac;
/// where they meet: neither one's colour
pub const violet = color.rgb(0.58, 0.36, 0.9).toRgba8(255);
/// a knot where a strand of each crosses and fuses
pub const knot = color.rgb(0.8, 0.68, 0.98).toRgba8(255);
/// a living petal: warm, blushing violet toward its tip
pub const petal_base = color.rgb(0.96, 0.56, 0.24).toRgba8(255);
pub const petal_tip = color.rgb(0.76, 0.44, 0.98).toRgba8(255);
/// the core they share, banded with both: sapwood and the parasites' core
const core_sym = pal.sapwood_dark;
const core_par = pk.core;
/// how many of everything: the parasites' count, exactly
pub const FOLD = pk.FOLD;
/// points a weave may have along it
const MAX = m.MAX_SPLINE;

// ---- the weave ----

pub const Weave = struct {
  /// strands each way: as many green as pale
  n:u32 = FOLD,
  twist:f32 = pk.TWIST,
  sides:u32 = 4,
  /// how far a green strand wanders off its exact course (a pale one
  /// never does)
  wobble:f32 = 0.08,
  /// a knot where two cross, a multiple of a strand's radius, only where
  /// parted at least `knot_from`
  knot:f32 = 1.55,
  knot_from:f32 = 0.3,
  /// bands of the two saps up the core
  bands:f32 = 5,
  seed:u64 = 0,
  part:vertex.Part = .stem,
};

/// a strand's angle round the weave `u` along it: the green (`way` 1)
/// wandering a little, the pale (`way` -1) exact
fn strandAngle(w:Weave, si:usize, way:f32, u:f32) f32 {
  const a = m.ratio(si, w.n) * m.tau + way * w.twist * u;
  return if (way > 0) a + mg.strandTurn(w.seed +% si * mg.STRAND_SALT, u, w.wobble) else a;
}

fn strandRadius(w:Weave, si:usize, way:f32, u:f32, open:f32) f32 {
  return if (way > 0) open * mg.strandSwell(w.seed +% si * mg.STRAND_SALT, u, w.wobble) else open;
}

fn round(at:V3, nv:V3, bv:V3, a:f32, r:f32) V3 { return at + (nv * m.splat3(@cos(a)) + bv * m.splat3(@sin(a))) * m.splat3(r); }

/// the weave along `spine` (tu.x `ts`, cross-sections `sec` as a
/// parasite's lattice): a core banded with both saps, `w.n` green strands
/// wound one way and as many pale ones the other, lifting off the core into
/// a cage where parted (tu.y how far, so plant.vert parts it as it grows),
/// and a violet knot wherever a green and a pale strand cross, parted.
pub fn weave(b:*mg.Builder, spine:[]const V3, ts:[]const f32, sec:[]const Section, w:Weave) Allocator.Error!void {
  const n = spine.len;
  assert(n >= 2 and n <= MAX and ts.len == n and sec.len == n);
  var fn_:[MAX]V3 = undefined;
  var fb:[MAX]V3 = undefined;
  mg.transport(spine, fn_[0..n], fb[0..n]);
  var rs:[MAX]f32 = undefined;
  var cs:[MAX]Rgba8 = undefined;
  for (rs[0..n], cs[0..n], sec, 0..) |*r, *c, s, i| {
    r.* = s.core;
    c.* = color.mix(core_sym, core_par, 0.5 + 0.5 * @sin(m.ratio(i, n - 1) * w.bands * m.tau));
  }
  try b.tubeC(spine, ts, rs[0..n], cs[0..n], null, w.part, 8);
  var us:[MAX]f32 = undefined;
  var path:[MAX]V3 = undefined;
  for ([_]f32{1, -1}) |way| for (0..w.n) |si| {
    for (path[0..n], rs[0..n], us[0..n], cs[0..n], sec, 0..) |*p, *r, *u, *c, s, i| {
      const k = m.ratio(i, n - 1);
      p.* = round(spine[i], fn_[i], fb[i], strandAngle(w, si, way, k), strandRadius(w, si, way, k, s.open));
      r.* = s.strand;
      u.* = pk.parting(s);
      // each paler where it is parted, as young growth is
      c.* = if (way > 0) color.mix(green, leaf_lite, u.* * 0.45) else color.mix(pale, pearl, u.* * 0.6);
    }
    try b.tubeC(path[0..n], ts, rs[0..n], cs[0..n], us[0..n], w.part, w.sides);
  };
  // decision: knots are left out at the coarsest level of detail, where
  // they are under a pixel
  if (w.knot <= 0 or b.lod + 1 >= mg.LODS) return;
  // pale strand j meets green strand j - k every pi / (n twist) along it
  const every = m.pi / (m.f(w.n) * w.twist);
  var k:u32 = 1;
  while (m.f(k) * every < 1) : (k += 1) {
    const u = m.f(k) * every;
    const x = u * m.f(n - 1);
    const lo = m.floorTo(usize, x);
    const hi = @min(lo + 1, n - 1);
    const f = x - m.f(lo);
    const s:Section = .{
      .core = m.lerp(sec[lo].core, sec[hi].core, f), .tight = m.lerp(sec[lo].tight, sec[hi].tight, f),
      .open = m.lerp(sec[lo].open, sec[hi].open, f), .strand = m.lerp(sec[lo].strand, sec[hi].strand, f),
    };
    const pt = pk.parting(s);
    if (pt < w.knot_from) continue;
    const at = m.lerpV(spine[lo], spine[hi], f);
    const nv = m.norm(m.lerpV(fn_[lo], fn_[hi], f));
    const bv = m.norm(m.lerpV(fb[lo], fb[hi], f));
    for (0..w.n) |j| {
      const i = (j + w.n - k % w.n) % w.n;
      const p_pale = round(at, nv, bv, strandAngle(w, j, -1, u), strandRadius(w, j, -1, u, s.open));
      const p_green = round(at, nv, bv, strandAngle(w, i, 1, u), strandRadius(w, i, 1, u, s.open));
      const mk = b.mark();
      // fused where they cross: drawn out a little along both
      try mg.ellipsoid(b, .{
        .center = (p_pale + p_green) * m.splat3(0.5), .radii = m.splat3(s.strand * w.knot),
        .col = knot, .part = w.part, .rings = 4, .segs = 6, .t = m.lerp(ts[lo], ts[hi], f),
      });
      for (b.v.items[mk..]) |*vx| vx.tu[1] = pt;
    }
  }
}

/// a stalk's sections (as the parasites': woven at its foot, parting into a
/// cage over `s.from..s.to`, gathering again) at `pts.len` points
pub fn sections(s:pk.Stalk, out:[]Section) void {
  for (out, 0..) |*c, i| c.* = pk.section(s, m.ratio(i, out.len - 1));
}

// ---- sap ----

pub const Sac = struct {
  center:V3,
  radii:V3,
  t:f32,
  /// the arms of each sap swirling round it, and the turns they make from
  /// its foot to its crown
  arms:u32 = 2,
  swirl:f32 = 0.9,
  /// turns the swirl about its axis (so no two sacs swirl alike)
  phase:f32 = 0,
  rings:u32 = 10,
  segs:u32 = 14,
};

/// a sac of both saps (part `.bloom`: see-through, its hue its colour):
/// amber and pale blue swirling round each other in arms from its foot to
/// its crown, violet between them where they mingle; never one colour
pub fn sac(b:*mg.Builder, s:Sac) Allocator.Error!void {
  const mk = b.mark();
  try mg.ellipsoid(b, .{.center = s.center, .radii = s.radii, .col = violet, .part = .bloom, .rings = s.rings, .segs = s.segs, .t = s.t});
  for (b.v.items[mk..]) |*vx| vx.col = marbled(s, vx.pos);
}

/// a sac's colour at `p`: a smooth field of position, so its shared
/// vertices agree
fn marbled(s:Sac, p:V3) Rgba8 {
  const d = (p - s.center) / s.radii;
  const ph = m.atan2(d[2], d[0]);
  const band = @sin(m.f(s.arms) * ph + s.swirl * m.tau * d[1] + s.phase);
  const k = m.clamp01(0.5 + band * 0.9);
  return if (k < 0.5) color.mix(amber, violet, m.smooth(k * 2)) else color.mix(violet, blue, m.smooth(k * 2 - 1));
}

// ---- fronds ----

pub const Frond = struct {
  from:V3,
  /// the way it leans out (horizontal, unit)
  out:V3,
  len:f32,
  r:f32,
  rise:f32 = 1.1,
  curl:f32 = 3.0,
  /// green leaflet pairs along it, each pair a little different
  pairs:u32,
  leaf_len:f32,
  leaf_w:f32,
  /// it ends rolled up in a crozier this many turns (a fern's young tip)
  coil:f32 = 1.2,
  t0:f32,
  t1:f32,
  /// one seed for a crown's fronds makes them alike (the parasites'
  /// exactness); `leaf_seed` differs per frond (the symbiotes' leaflets)
  seed:u64,
  leaf_seed:u64,
};

/// how many points a frond's control polygon has: its arc, then its coil
const ARC = 8;
const COIL = 6;
const FROND_RES = 30;

/// a frond: a lilac stem arching out of `from`, exact as the parasites'
/// are, greening toward its tip where it rolls up into a crozier as a
/// fern's does, with pairs of green leaflets along it, longest near its
/// foot, each pair its own; furled nubs on the coil
pub fn frond(b:*mg.Builder, f:Frond) Allocator.Error!void {
  var c:[ARC + COIL]V3 = undefined;
  frondCtrl(f, &c);
  try frondAlong(b, f, &c, null);
}

/// a frond grown on its own spline off `parent` at `u` (`o` when), its
/// leaflets unfolding as the front passes them; returns its spline
pub fn frondOn(b:*mg.Builder, k:*growth.Skeleton, parent:growth.Id, u:f32, f:Frond, o:growth.Branch) Allocator.Error!growth.Id {
  var c:[ARC + COIL]V3 = undefined;
  frondCtrl(f, &c);
  const id = k.branch(parent, u, &c, o);
  try frondAlong(b, f, &c, .{.k = k, .id = id});
  return id;
}

const On = struct { k:*growth.Skeleton, id:growth.Id };

/// a frond's control points: its arc, then the coil of its crozier
fn frondCtrl(f:Frond, c:*[ARC + COIL]V3) void {
  pk.frondPath(f.from, f.out, f.len, f.rise, f.curl, f.seed, c[0..ARC]);
  // the crozier: the heading turns on, ever tighter, about the frond's side
  const side = m.norm(m.cross(v3(0, 1, 0), f.out));
  var d = m.norm(c[ARC - 1] - c[ARC - 2]);
  const up = m.cross(d, side);
  var step = m.len(c[ARC - 1] - c[ARC - 2]) * 0.8;
  for (0..COIL) |j| {
    const a = m.ratio(j + 1, COIL) * f.coil * m.tau;
    d = m.norm(m.norm(c[ARC - 1] - c[ARC - 2]) * m.splat3(@cos(a)) - up * m.splat3(@sin(a)));
    c[ARC + j] = c[ARC + j - 1] + d * m.splat3(step);
    step *= 0.72;
  }
}

fn frondAlong(b:*mg.Builder, f:Frond, c:*const [ARC + COIL]V3, on:?On) Allocator.Error!void {
  var p:[FROND_RES]V3 = undefined;
  m.splineResample(c, &p);
  const stem = b.mark();
  var ts:[FROND_RES]f32 = undefined;
  var rs:[FROND_RES]f32 = undefined;
  var cs:[FROND_RES]Rgba8 = undefined;
  for (&ts, &rs, &cs, 0..) |*t, *r, *cl, j| {
    const k = m.ratio(j, FROND_RES - 1);
    t.* = m.lerp(f.t0, f.t1, k);
    r.* = f.r * m.lerp(1, 0.18, k);
    cl.* = color.mix(lilac, leaf_lite, m.smooth(m.clamp01((k - 0.45) / 0.5)));
  }
  try b.tubeC(&p, &ts, &rs, &cs, null, .tendril, 5);
  if (on) |o| try o.k.along(b, stem, o.id);
  // where the arc ends and the coil begins along the resampled frond
  const arc_end:f32 = 0.7;
  var rng = Rng.init(f.leaf_seed);
  for (0..f.pairs) |j| {
    const k = m.lerp(0.2, arc_end, m.ratio(j, @max(f.pairs, 2) - 1));
    const at = m.alongPath(&p, k);
    const tan = m.norm(m.alongPath(&p, @min(k + 0.02, 1)) - m.alongPath(&p, @max(k - 0.02, 0)));
    const sd = m.norm(m.cross(tan, v3(0, 1, 0)));
    const len = f.leaf_len * (1 - 0.6 * m.smooth(m.ratio(j, @max(f.pairs, 2) - 1)));
    const pair = b.mark();
    for ([_]f32{1, -1}) |sgn| {
      const dir = m.norm(sd * m.splat3(sgn) + tan * m.splat3(0.5 + rng.range(-0.12, 0.12)) + v3(0, rng.range(0.05, 0.25), 0));
      try mg.blade(b, at, dir, len * rng.range(0.85, 1.12), f.leaf_w * rng.range(0.85, 1.1), 0.4, leaf_dark, leaf_lite, m.lerp(f.t0, f.t1, k), .leaf);
    }
    if (on) |o| try o.k.on(b, pair, o.id, o.k.nearest(o.id, at), .{.from = at});
  }
  // decision: furled nubs only at full detail; past `LOD_AT[0]` they are
  // under a pixel
  if (b.lod > 0) return;
  const side = m.norm(m.cross(v3(0, 1, 0), f.out));
  for (0..4) |j| {
    const k = m.lerp(arc_end + 0.04, 0.95, m.ratio(j, 3));
    const at = m.alongPath(&p, k);
    const r = f.r * m.lerp(1, 0.18, k);
    const nubs = b.mark();
    for ([_]f32{1, -1}) |sgn| {
      try mg.ellipsoid(b, .{.center = at + side * m.splat3(sgn * r * 1.2), .radii = m.splat3(r * 0.85), .col = leaf_lite, .part = .leaf, .rings = 3, .segs = 5, .t = m.lerp(f.t0, f.t1, k)});
    }
    if (on) |o| try o.k.on(b, nubs, o.id, o.k.nearest(o.id, at), .{.from = at});
  }
}

// ---- flowers ----

pub const Bloom = struct {
  heart:V3,
  /// a petal's length (the flower's size)
  len:f32,
  t:f32 = 1,
  /// 0 a closed bud .. 1 open
  open:f32 = 1,
  spin:f32 = 0,
  petals:u32 = FOLD,
  base:Rgba8 = petal_base,
  tip:Rgba8 = petal_tip,
  seed:u64,
};

/// a flower of both: a calyx of `FOLD` pale frondlets turned exactly evenly
/// and curling out alike, each tipped with a pearl, and between them living
/// petals cupped round a bead of both saps, each petal its own size and
/// lean; pearl filaments carrying the symbiotes' gold pollen stand in it.
/// Every size follows `open` (counts never do), so it keeps one layout.
pub fn bloom(b:*mg.Builder, f:Bloom) Allocator.Error!void {
  const op = f.open;
  try sac(b, .{
    .center = f.heart + v3(0, f.len * 0.12, 0), .radii = v3(f.len * 0.2, f.len * 0.24, f.len * 0.2),
    .t = f.t, .phase = f.spin * 3, .rings = 6, .segs = 9,
  });
  // the calyx: exact, alike
  for (0..FOLD) |i| {
    const a = f.spin + m.ratio(i, FOLD) * m.tau;
    var c:[6]V3 = undefined;
    pk.frondPath(f.heart, v3(@cos(a), 0, @sin(a)), f.len * 0.75, m.lerp(1.35, 0.2, op), m.lerp(-0.4, 2.4, op), f.seed ^ 0xCA1, &c);
    var p:[12]V3 = undefined;
    m.splineResample(&c, &p);
    try taper(b, &p, f.len * 0.04, 0.25, f.t, f.t, lilac, .tendril, 4);
    try mg.ellipsoid(b, .{.center = p[11], .radii = m.splat3(f.len * 0.045), .col = pearl, .part = .tendril, .rings = 4, .segs = 5, .t = f.t});
  }
  // the petals: living, each a little different
  var rng = Rng.init(f.seed ^ 0xB10);
  for (0..f.petals) |i| {
    const a = f.spin + (m.f(i) + 0.5) / m.f(f.petals) * m.tau + rng.range(-0.15, 0.15);
    const sc = rng.range(0.85, 1.12);
    try mg.petal(b, .{
      .base = f.heart, .out = v3(@cos(a), 0, @sin(a)),
      .len = f.len * sc * m.lerp(0.45, 1, op), .width = f.len * 0.4 * sc * m.lerp(0.45, 1, op),
      .rise = m.lerp(1.45, 0.8, op) + rng.range(-0.1, 0.1), .flare = m.lerp(-0.35, 0.85, op), .cup = 0.45,
      .col = f.base, .tip = f.tip, .t = f.t, .part = .leaf,
    });
  }
  try mg.stamens(b, .{
    .heart = f.heart + v3(0, f.len * 0.08, 0), .axis = v3(0, 1, 0), .n = FOLD,
    .len = f.len * m.lerp(0.25, 0.6, op), .r = f.len * 0.022, .anther = f.len * m.lerp(0.06, 0.13, op),
    .lean = m.lerp(0.05, 0.4, op), .arch = m.lerp(0.1, 0.55, op), .col = pearl, .t = f.t, .spin = f.spin, .seed = f.seed ^ 0x57A,
  });
}

// ---- rooting ----

pub const Foot = struct {
  at:V3 = v3(0, 0, 0),
  /// the bulb's radius across, and how far its roots reach
  r:f32,
  reach:f32,
  /// a root's radius at the bulb
  root_r:f32,
  t:f32 = 0,
  seed:u64,
};

/// rooted both ways: a pale bulb half sunk in the soil, pearl where it
/// swells toward the light; `FOLD` pale roots out of it, exactly even and
/// alike, and between each two a symbiote's green braided root, each its
/// own length and course, all reaching low over the ground and sinking in
pub fn foot(b:*mg.Builder, f:Foot) Allocator.Error!void {
  try pk.nodule(b, f.at + v3(0, f.r * 0.12, 0), v3(f.r, f.r * 0.5, f.r), f.t, pale, core_par, pearl);
  var rng = Rng.init(f.seed);
  for (0..FOLD) |i| {
    // pale: exact
    {
      const a = m.ratio(i, FOLD) * m.tau;
      var c:[6]V3 = undefined;
      rootPath(f.at, a, f.r * 0.6, f.reach, 0.25, f.seed ^ 0x9A1E, &c);
      var p:[12]V3 = undefined;
      m.splineResample(&c, &p);
      try taper(b, &p, f.root_r * 0.75, 0.04, f.t, f.t + 0.03, pearl, .stem, 5);
    }
    // green: each its own
    {
      const a = (m.f(i) + 0.5 + rng.range(-0.18, 0.18)) / m.f(FOLD) * m.tau;
      var c:[6]V3 = undefined;
      rootPath(f.at, a, f.r * 0.5, f.reach * rng.range(0.8, 1.1), 0.3, f.seed +% i * 41, &c);
      var p:[12]V3 = undefined;
      m.splineResample(&c, &p);
      var ts:[12]f32 = undefined;
      var rs:[12]f32 = undefined;
      for (&ts, &rs, 0..) |*t, *r, j| {
        const k = m.ratio(j, 11);
        t.* = f.t + 0.03 * (1 - k);
        r.* = f.root_r * 1.3 * m.lerp(1, 0.3, k);
      }
      try mg.braid(b, &p, &ts, &rs, 3, 2.2, pal.STRAND_WOBBLE, f.seed +% i * 7, pal.core, green);
    }
  }
}

/// `foot` on a structure: the bulb swelling out of spline `id`'s start,
/// every root a branch growing with it
pub fn footOn(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, f:Foot) Allocator.Error!void {
  const bulb = b.mark();
  try pk.nodule(b, f.at + v3(0, f.r * 0.12, 0), v3(f.r, f.r * 0.5, f.r), f.t, pale, core_par, pearl);
  try k.on(b, bulb, id, 0, .{.from = f.at, .span = k.get(id).time * 0.3});
  var rng = Rng.init(f.seed);
  for (0..FOLD) |i| {
    var c:[6]V3 = undefined;
    rootPath(f.at, m.ratio(i, FOLD) * m.tau, f.r * 0.6, f.reach, 0.25, f.seed ^ 0x9A1E, &c);
    const pale_root = k.branch(id, 0, &c, .{.after = .with});
    try k.tube(b, pale_root, .{.r0 = f.root_r * 0.75, .tip = 0.04, .col = pearl, .sides = 5, .t0 = f.t, .t1 = f.t + 0.03});
    rootPath(f.at, (m.f(i) + 0.5 + rng.range(-0.18, 0.18)) / m.f(FOLD) * m.tau, f.r * 0.5, f.reach * rng.range(0.8, 1.1), 0.3, f.seed +% i * 41, &c);
    const green_root = k.branch(id, 0, &c, .{.after = .with});
    try k.braid(b, green_root, .{.girth = f.root_r * 1.3, .tip = 0.3, .wobble = pal.STRAND_WOBBLE, .seed = f.seed +% i * 7, .core = pal.core, .strand = green, .t0 = f.t + 0.03, .t1 = f.t});
  }
}

/// a weave grown along spline `id` (its tu.x `t0`..`t1`), sections from
/// `s`; returns where on it each section lies, for what rides inside
pub fn weaveOn(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, s:pk.Stalk, w:Weave, t0:f32, t1:f32, sp:*[growth.RES]V3, sec:*[growth.RES]Section) Allocator.Error!void {
  var ts:[growth.RES]f32 = undefined;
  k.path(id, 0, 1, sp);
  for (&ts, 0..) |*t, i| t.* = m.lerp(t0, t1, m.ratio(i, growth.RES - 1));
  sections(s, sec);
  const mk = b.mark();
  try weave(b, sp, &ts, sec, w);
  try k.along(b, mk, id);
}

/// a root from `at` toward bearing `a`: out of the bulb at `from`, low over
/// the ground to `reach`, then down into it
pub fn rootPath(at:V3, a:f32, from:f32, reach:f32, wobble:f32, seed:u64, c:*[6]V3) void {
  const out = v3(@cos(a), 0, @sin(a));
  const s = at + out * m.splat3(from) + v3(0, 0.02, 0);
  for (c, 0..) |*p, j| {
    const k = m.ratio(j, 5);
    p.* = s + out * m.splat3((reach - from) * k) + v3(0, 0.02 * @sin(m.pi * k * 0.8) - 0.1 * k * k * reach, 0);
  }
  mg.grow(c, .{.start = s, .direction = out, .length = reach - from, .wobble = wobble, .seed = seed});
}

/// a tube along `p`, `r` at its root tapering to `tip` of it, tu.x
/// `t0`..`t1`, never thinner than a tube keeps its caps at
pub fn taper(b:*mg.Builder, p:[]const V3, r:f32, tip:f32, t0:f32, t1:f32, col:Rgba8, part:vertex.Part, sides:u32) Allocator.Error!void {
  var ts:[MAX]f32 = undefined;
  var rs:[MAX]f32 = undefined;
  for (ts[0..p.len], rs[0..p.len], 0..) |*t, *q, j| {
    const k = m.ratio(j, p.len - 1);
    t.* = m.lerp(t0, t1, k);
    q.* = @max(r * m.lerp(1, tip, k), 2e-4);
  }
  try b.tubeR(p, ts[0..p.len], rs[0..p.len], col, part, sides);
}

// ---- the confluence (grown through keys) ----

/// tu.x where the two trunks have fused into one, and where the weave
/// gives onto its canopy
const FUSE_T:f32 = 0.42;
const CANOPY_T:f32 = 0.78;

/// how each part of a confluence has come along at `growth` (0..1)
const Grown = struct {
  /// the trunks' height and girth
  rise:f32,
  /// the boughs' reach
  reach:f32,
  /// its flowers opening
  bloom:f32,

  fn at(gr:f32) Grown {
    return .{
      .rise = m.lerp(0.3, 1, m.smooth(m.clamp01(gr / 0.5))),
      .reach = m.lerp(0.05, 1, m.smooth(m.clamp01((gr - 0.2) / 0.55))),
      .bloom = m.smooth(m.clamp01((gr - 0.7) / 0.3)),
    };
  }
};

/// the confluence at `growth` (0..1): where the lineages first met, so the
/// meeting is told from the ground up. Out of opposite corners of its
/// ground rise a symbiote's braided trunk, leafy, on green braided roots,
/// and a parasite's lattice stalk, sacs hanging in its cage, on a pale
/// bulb and exact roots; they wind round each other, closing in as they
/// climb, and fuse into one weave of both (green and pale strands, violet
/// knots) that opens into five boughs, each a frond of both lineages
/// ending in a flower of both, round a great sac of both saps crowned by a
/// flower of its own. Nothing appears or vanishes with growth (what is not
/// yet grown is small), so every key keeps one vertex layout.
pub fn confluence(b:*mg.Builder, g:species.Genome, seed:u64, gr:f32) Allocator.Error!void {
  const gw = Grown.at(gr);
  var rng = Rng.init(seed);
  const H = g.stem_h * gw.rise;
  const fuse_h = H * 0.42;
  const top_h = H * 0.78;
  const R = g.stem_r * m.lerp(0.55, 1, gw.rise);
  // where the trunks stand apart, at the foot, and the turn they make
  const apart:f32 = 0.42 * gw.rise;
  const turn:f32 = 1.15 * m.pi;
  const a0 = rng.range(0, m.tau);
  const N = 25;
  for ([_]f32{0, 1}) |side| {
    const sym = side == 0;
    var sp:[N]V3 = undefined;
    var ts:[N]f32 = undefined;
    for (&sp, &ts, 0..) |*q, *t, i| {
      const u = m.ratio(i, N - 1);
      // closing in as they climb, eased so they meet tangent to the axis;
      // the last stretch runs on up inside the fused weave
      const close = 1 - m.smooth(m.clamp01(u / 0.92));
      const a = a0 + side * m.pi + turn * u;
      q.* = v3(@cos(a) * apart * close, fuse_h * 1.12 * u, @sin(a) * apart * close);
      t.* = FUSE_T * 1.12 * u;
    }
    const base = sp[0];
    if (sym) {
      var rs:[N]f32 = undefined;
      for (&rs, 0..) |*r, i| {
        const u = m.ratio(i, N - 1);
        r.* = R * 0.62 * (1 + 0.7 * m.pow(f32, 1 - u, 5)) * m.lerp(1, 0.55, u);
      }
      try mg.braid(b, &sp, &ts, &rs, 6, 2.6, pal.STRAND_WOBBLE * 1.5, seed ^ 0x5B, pal.core, green);
      try mg.leavesAlong(b, &sp, 4, R * 1.6 * gw.reach + 0.01, R * 0.55 * gw.reach + 0.004, 0.25, 0.85, ts[0], ts[N - 1], leaf_dark, leaf_lite, seed ^ 0x1EF);
      // green braided roots splaying out of its foot, each its own
      for (0..4) |i| {
        const a = a0 + (m.f(i) - 1.5) * 0.7 + rng.range(-0.2, 0.2);
        var c:[6]V3 = undefined;
        rootPath(base, a, R * 0.3, R * 2.6 * rng.range(0.85, 1.1) + 0.05, 0.25, seed +% i * 53, &c);
        var p:[12]V3 = undefined;
        m.splineResample(&c, &p);
        var rt:[12]f32 = undefined;
        var rr:[12]f32 = undefined;
        for (&rt, &rr, 0..) |*t, *r, j| {
          const k = m.ratio(j, 11);
          t.* = 0.04 * (1 - k);
          r.* = R * 0.3 * m.lerp(1, 0.35, k);
        }
        try mg.braid(b, &p, &rt, &rr, 3, 2.2, pal.STRAND_WOBBLE, seed +% i * 7, pal.core, green);
      }
    } else {
      const st:pk.Stalk = .{.girth = R * 0.6, .part = 1.9, .from = 0.15, .to = 0.78, .foot = 0.8};
      var sec:[N]Section = undefined;
      sections(st, &sec);
      try pk.lattice(b, &sp, &ts, &sec, .{});
      // its sacs, on the core inside the cage
      for (0..3) |i| {
        const u = m.lerp(st.from, st.to, (m.f(i) + 0.5) / 3);
        const c = pk.section(st, u);
        const r = @max((c.open - c.strand) * 0.6, 1e-3);
        try mg.ellipsoid(b, .{.center = m.alongPath(&sp, u), .radii = v3(r, r * 1.15, r), .col = blue, .part = .bloom, .rings = 6, .segs = 9, .t = u * FUSE_T});
      }
      try pk.nodule(b, base + v3(0, R * 0.15, 0), v3(R * 1.05, R * 0.5, R * 1.05), 0, pale, core_par, pearl);
      for (0..FOLD) |i| {
        const a = a0 + m.pi + (m.ratio(i, FOLD) - 0.5) * 2.2;
        var c:[6]V3 = undefined;
        rootPath(base, a, R * 0.7, R * 3.4 + 0.05, 0.2, seed ^ 0x9A1E, &c);
        var p:[12]V3 = undefined;
        m.splineResample(&c, &p);
        try taper(b, &p, R * 0.16, 0.04, 0, 0.04, pearl, .stem, 5);
      }
    }
  }

  // the fused weave: out of where they meet up to the canopy
  {
    var sp:[N]V3 = undefined;
    var ts:[N]f32 = undefined;
    var c:[5]V3 = undefined;
    for (&c, 0..) |*q, i| {
      const u = m.ratio(i, 4);
      q.* = v3(rng.range(-0.03, 0.03) * u, m.lerp(fuse_h * 0.85, top_h, u), rng.range(-0.03, 0.03) * u);
    }
    m.splineResample(&c, &sp);
    for (&ts, 0..) |*t, i| t.* = m.lerp(FUSE_T * 0.85, CANOPY_T, m.ratio(i, N - 1));
    const st:pk.Stalk = .{.girth = R * 0.85, .part = 2.1, .from = 0.2, .to = 0.85, .foot = 0.5};
    var sec:[N]Section = undefined;
    sections(st, &sec);
    try weave(b, &sp, &ts, &sec, .{.seed = seed ^ 0xC0F});
  }

  // the canopy: a great sac of both saps at the top, a flower of both on
  // it, and five boughs arching out round it, alike, each its own leaves
  // and a flower of both at its tip
  const top = v3(0, top_h, 0);
  const sr = g.bloom_r * 0.55 * m.lerp(0.35, 1, gw.reach);
  const heart = top + v3(0, sr * 0.9, 0);
  try sac(b, .{.center = heart, .radii = v3(sr, sr * 1.15, sr), .t = CANOPY_T + 0.04, .arms = 3, .swirl = 1.1, .phase = a0});
  const spin = a0 + 0.3;
  for (0..FOLD) |i| {
    const a = spin + m.ratio(i, FOLD) * m.tau;
    var c:[ARC + COIL]V3 = undefined;
    pk.frondPath(top + v3(0, sr * 0.2, 0), v3(@cos(a), 0, @sin(a)), g.stem_h * 0.4 * gw.reach, 0.75, 1.9, seed ^ 0xB0F, c[0..10]);
    var p:[24]V3 = undefined;
    m.splineResample(c[0..10], &p);
    try taper(b, &p, R * 0.32, 0.4, CANOPY_T, 0.97, lilac, .tendril, 6);
    try mg.leavesAlong(b, &p, 4, R * 1.5 * gw.reach + 0.01, R * 0.5 * gw.reach + 0.004, 0.2, 0.8, CANOPY_T, 0.97, leaf_dark, leaf_lite, seed +% i * 211);
    try bloom(b, .{.heart = p[23], .len = g.bloom_r * 0.5 * m.lerp(0.3, 1, gw.reach), .t = 1, .open = gw.bloom, .spin = a, .petals = FOLD, .seed = seed ^ 0xB1});
  }
  // the crowning flower lifts clear of the sac as it opens
  try bloom(b, .{.heart = heart + v3(0, sr * (1.05 + 0.3 * gw.bloom), 0), .len = g.bloom_r * m.lerp(0.3, 1, gw.reach), .t = 1, .open = gw.bloom, .spin = spin, .petals = g.petals, .seed = seed ^ 0xB2});
}
