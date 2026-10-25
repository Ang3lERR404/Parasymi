//! the lineages mixed: what grows where symbiote and parasite have become
//! one body, shared by the confluence and the sown hybrids (the `entwined`
//! form). Not one laid over the other (a braid below, a cage above) but
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
//! A plant grows by tu.x (plant.vert): it comes up drawn in to its axis
//! and opens as growth passes each piece, its cage parting from the foot
//! up (tu.y, as the parasites'); so a piece shares the tu.x of where it
//! grows from. The confluence is grown through keys instead (sizes passed
//! in, never counts, so every key keeps one vertex layout).
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");
const vertex = @import("../vertex.zig");
const species = @import("../../sim/species.zig");
const Rng = @import("../../core/rng.zig").Rng;
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
  var p:[FROND_RES]V3 = undefined;
  m.splineResample(&c, &p);
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
  // where the arc ends and the coil begins along the resampled frond
  const arc_end:f32 = 0.7;
  var rng = Rng.init(f.leaf_seed);
  for (0..f.pairs) |j| {
    const k = m.lerp(0.2, arc_end, m.ratio(j, @max(f.pairs, 2) - 1));
    const at = m.alongPath(&p, k);
    const tan = m.norm(m.alongPath(&p, @min(k + 0.02, 1)) - m.alongPath(&p, @max(k - 0.02, 0)));
    const sd = m.norm(m.cross(tan, v3(0, 1, 0)));
    const len = f.leaf_len * (1 - 0.6 * m.smooth(m.ratio(j, @max(f.pairs, 2) - 1)));
    for ([_]f32{1, -1}) |sgn| {
      const dir = m.norm(sd * m.splat3(sgn) + tan * m.splat3(0.5 + rng.range(-0.12, 0.12)) + v3(0, rng.range(0.05, 0.25), 0));
      try b.blade(at, dir, len * rng.range(0.85, 1.12), f.leaf_w * rng.range(0.85, 1.1), 0.4, leaf_dark, leaf_lite, m.lerp(f.t0, f.t1, k), .leaf);
    }
  }
  // decision: furled nubs only at full detail; past `LOD_AT[0]` they are
  // under a pixel
  if (b.lod > 0) return;
  for (0..4) |j| {
    const k = m.lerp(arc_end + 0.04, 0.95, m.ratio(j, 3));
    const at = m.alongPath(&p, k);
    const r = f.r * m.lerp(1, 0.18, k);
    for ([_]f32{1, -1}) |sgn| {
      try mg.ellipsoid(b, .{.center = at + side * m.splat3(sgn * r * 1.2), .radii = m.splat3(r * 0.85), .col = leaf_lite, .part = .leaf, .rings = 3, .segs = 5, .t = m.lerp(f.t0, f.t1, k)});
    }
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

/// a root from `at` toward bearing `a`: out of the bulb at `from`, low over
/// the ground to `reach`, then down into it
fn rootPath(at:V3, a:f32, from:f32, reach:f32, wobble:f32, seed:u64, c:*[6]V3) void {
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

/// points up an upright stalk `h` tall from `base`, leaning a little
/// (`lean`) and wandering as a grown thing does
fn stalkPath(base:V3, h:f32, lean:V3, wobble:f32, seed:u64, out:[]V3) void {
  var c:[7]V3 = undefined;
  mg.growthPath(.{.start = base, .direction = m.norm(v3(lean[0], 1, lean[2])), .length = h, .wobble = wobble, .curl = 0, .seed = seed}, &c);
  m.splineResample(&c, out);
}

// ---- the sown hybrids (the `entwined` form) ----

/// a sown hybrid from its genome (`body` says which); its variants differ
/// in proportion and in their symbiotic half alone (the parasitic half is
/// exact in every one)
pub fn plant(b:*mg.Builder, g:species.Genome, seed:u64) Allocator.Error!void {
  switch (g.body) {
    .weft => try weft(b, g, seed),
    .nerve => try nerve(b, g, seed),
    .drift => try drift(b, g, seed),
  }
}

/// the tu.x a stalk reaches at its top, in each hybrid: what stands on it
/// starts there
const WEFT_TOP:f32 = 0.35;
const NERVE_TOP:f32 = 0.55;
const DRIFT_TOP:f32 = 0.7;
const RES = 25;

/// a stalk of the weave from the foot up to `h`, its tu.x 0..`top`;
/// returns its top
fn stalk(b:*mg.Builder, g:species.Genome, s:pk.Stalk, h:f32, top:f32, rng:*Rng, seed:u64) Allocator.Error!V3 {
  return stalkTwisted(b, g, s, h, top, pk.TWIST, rng, seed);
}

/// `stalk` with its strands turning `twist` each way (fewer crossings on a
/// short one, so its knots never crowd)
fn stalkTwisted(b:*mg.Builder, g:species.Genome, s:pk.Stalk, h:f32, top:f32, twist:f32, rng:*Rng, seed:u64) Allocator.Error!V3 {
  var sp:[RES]V3 = undefined;
  stalkPath(v3(0, 0, 0), h, v3(rng.range(-0.04, 0.04), 0, rng.range(-0.04, 0.04)), g.wobble, seed ^ 0x57A1, &sp);
  var ts:[RES]f32 = undefined;
  var sec:[RES]Section = undefined;
  for (&ts, 0..) |*t, i| t.* = m.ratio(i, RES - 1) * top;
  sections(s, &sec);
  try weave(b, &sp, &ts, &sec, .{.twist = twist, .seed = seed ^ 0x3EA});
  return sp[RES - 1];
}

/// WEFTSTONE: a loomfern of the lithophage's body. A short weave out of a
/// rooted foot, holding up a crop of both saps with a grit crystal
/// standing in it, and five fronds arching out of its neck exactly alike,
/// their leaflets every one their own, their tips rolled into croziers.
fn weft(b:*mg.Builder, g:species.Genome, seed:u64) Allocator.Error!void {
  var rng = Rng.init(seed);
  const h = g.stem_h * rng.range(0.9, 1.1);
  try foot(b, .{.r = g.stem_r * 1.8, .reach = g.stem_r * 7, .root_r = g.stem_r * 0.32, .seed = seed ^ 0xF007});
  const neck = try stalkTwisted(b, g, .{.girth = g.stem_r, .part = rng.range(2.0, 2.4), .from = 0.18, .to = 0.82}, h, WEFT_TOP, 0.9 * m.pi, &rng, seed);
  // the crop, and the grit it weaves standing in it
  const cr = g.bloom_r * rng.range(0.92, 1.08);
  const crop = neck + v3(0, cr * 0.7, 0);
  try sac(b, .{.center = crop, .radii = v3(cr, cr * 1.15, cr), .t = WEFT_TOP + 0.03, .phase = rng.range(0, m.tau)});
  var crng = Rng.init(seed ^ 0xC7A);
  for (0..FOLD) |i| {
    const a = m.ratio(i, FOLD) * m.tau;
    const dir = m.norm(v3(@cos(a) * 0.45, 1, @sin(a) * 0.45));
    try @import("mineral_kit.zig").crystal(b, .{
      .base = crop - v3(0, cr * 0.4, 0), .dir = dir, .len = cr * crng.range(0.8, 1.05), .r = cr * 0.18,
      .col = color.rgb(0.6, 0.56, 0.52).toRgba8(255), .tip = color.rgb(0.82, 0.76, 0.92).toRgba8(255), .part = .thorn,
    }, &crng);
  }
  // fronds out of its neck, exactly even and alike
  const spin = rng.range(0, m.tau);
  const reach = h * rng.range(2.1, 2.5);
  for (0..FOLD) |i| {
    const a = spin + m.ratio(i, FOLD) * m.tau;
    try frond(b, .{
      .from = neck, .out = v3(@cos(a), 0, @sin(a)), .len = reach, .r = g.stem_r * 0.28,
      .rise = 1.05, .curl = 3.1, .pairs = g.leaves, .leaf_len = g.leaf_len, .leaf_w = g.leaf_w,
      .t0 = WEFT_TOP, .t1 = 1, .seed = seed ^ 0xF20D, .leaf_seed = seed +% i * 131,
    });
  }
}

/// NERVECROWN: a gathering crown of the ganglion's body. A rosette of
/// broad leaves, each its own, a pale nerve running down every midrib to
/// the foot; a short weave up to a knot of five pearl nodules round a sac
/// of both saps, a second five above them turned half a step; round the
/// knot living petals and lilac fronds in turn, stamens on its crown.
fn nerve(b:*mg.Builder, g:species.Genome, seed:u64) Allocator.Error!void {
  var rng = Rng.init(seed);
  const h = g.stem_h * rng.range(0.9, 1.1);
  try foot(b, .{.r = g.stem_r * 1.8, .reach = g.stem_r * 7, .root_r = g.stem_r * 0.3, .seed = seed ^ 0xF007});
  // the rosette: the symbiotes' golden turn, every leaf its own
  for (0..g.leaves) |i| {
    const a = m.f(i) * 2.39996 + rng.range(-0.2, 0.2);
    const t = 0.04 + 0.015 * m.f(i);
    const base = v3(@cos(a) * g.stem_r * 1.1, 0.03 + 0.004 * m.f(i), @sin(a) * g.stem_r * 1.1);
    const dir = m.norm(v3(@cos(a), 0.35 + rng.range(-0.1, 0.1), @sin(a)));
    const len = g.leaf_len * rng.range(0.82, 1.1);
    const droop = g.leaf_droop * rng.range(0.8, 1.2);
    try b.blade(base, dir, len, g.leaf_w * rng.range(0.85, 1.1), droop, leaf_dark, leaf_lite, t, .leaf);
    // its nerve, down the midrib to the foot: riding the leaf (the same
    // tu, so it opens with it), pale, ending in a pearl
    var cs:[mg.BLADE_SEGS + 1]V3 = undefined;
    mg.bladeSpine(&cs, base, dir, len, droop);
    var p:[mg.BLADE_SEGS + 1]V3 = undefined;
    var ts:[mg.BLADE_SEGS + 1]f32 = undefined;
    var rs:[mg.BLADE_SEGS + 1]f32 = undefined;
    var us:[mg.BLADE_SEGS + 1]f32 = undefined;
    var nc:[mg.BLADE_SEGS + 1]Rgba8 = undefined;
    for (&p, &ts, &rs, &us, &nc, cs, 0..) |*q, *tt, *r, *u, *c, cp, j| {
      const k = m.ratio(j, mg.BLADE_SEGS) * 0.85;
      q.* = m.lerpV(base, cp, 0.85) + v3(0, g.leaf_w * 0.06 + 0.002, 0);
      tt.* = t;
      r.* = @max(g.leaf_w * 0.05 * (1 - 0.6 * k), 2e-4);
      u.* = k;
      c.* = color.mix(pale, pearl, k);
    }
    try b.tubeC(&p, &ts, &rs, &nc, &us, .leaf, 4);
  }
  const top = try stalkTwisted(b, g, .{.girth = g.stem_r, .part = rng.range(2.0, 2.4), .from = 0.2, .to = 0.8}, h, NERVE_TOP, 1.1 * m.pi, &rng, seed);
  // the knot: a sac of both saps, two rings of five pearl nodules round it
  const sr = g.bloom_r * 0.42;
  const heart = top + v3(0, sr * 0.8, 0);
  try sac(b, .{.center = heart, .radii = v3(sr, sr * 1.1, sr), .t = NERVE_TOP + 0.05, .phase = rng.range(0, m.tau)});
  const spin = rng.range(0, m.tau);
  for (0..2) |ring| for (0..FOLD) |i| {
    const a = spin + (m.f(i) + 0.5 * m.f(ring)) / m.f(FOLD) * m.tau;
    const y = if (ring == 0) -sr * 0.2 else sr * 0.55;
    const rr = sr * (if (ring == 0) @as(f32, 1.0) else 0.78);
    const nr = sr * (if (ring == 0) @as(f32, 0.36) else 0.27);
    // pale all round (a ganglion's knot, not dark seeds)
    try pk.nodule(b, heart + v3(@cos(a) * rr, y, @sin(a) * rr), v3(nr, nr * 0.9, nr), NERVE_TOP + 0.08, pale, color.mix(pale, core_par, 0.4), pearl);
  };
  // the crown round it: petals and fronds in turn, five each
  var prng = Rng.init(seed ^ 0xC20);
  for (0..FOLD) |i| {
    const a = spin + m.ratio(i, FOLD) * m.tau;
    const sc = prng.range(0.85, 1.12);
    try mg.petal(b, .{
      .base = top + v3(0, sr * 0.1, 0), .out = v3(@cos(a), 0, @sin(a)), .len = g.bloom_r * sc, .width = g.bloom_r * 0.45 * sc,
      .rise = 0.95 + prng.range(-0.12, 0.12), .flare = 0.8, .cup = 0.5, .col = petal_base, .tip = petal_tip, .t = NERVE_TOP + 0.1, .part = .leaf,
    });
    const fa = a + m.pi / m.f(FOLD);
    var c:[8]V3 = undefined;
    pk.frondPath(heart + v3(0, sr * 0.6, 0), v3(@cos(fa), 0, @sin(fa)), g.bloom_r * 0.9, 1.3, 4.2, seed ^ 0xF20D, &c);
    var p:[16]V3 = undefined;
    m.splineResample(&c, &p);
    try taper(b, &p, g.stem_r * 0.2, 0.15, NERVE_TOP + 0.1, 1, lilac, .tendril, 5);
  }
  try mg.stamens(b, .{
    .heart = heart + v3(0, sr * 0.95, 0), .axis = v3(0, 1, 0), .n = FOLD,
    .len = g.bloom_r * 0.45, .r = g.bloom_r * 0.022, .anther = g.bloom_r * 0.11,
    .lean = 0.4, .arch = 0.55, .col = pearl, .t = 1, .spin = spin, .seed = seed ^ 0x57A,
  });
}

/// DRIFTBRAID: a sporecaster of the braided conduit's body. A tall weave
/// out of a rooted foot, four lanes of sapwood (each tinted as a lane's
/// load tints it) winding up its core through the cage; at its top a
/// spore sac of both saps pursed into a pearl pore, and a crown of five
/// lilac fronds flaring round it, alike, each carrying leaves of its own
/// and ending in a flower of both.
fn drift(b:*mg.Builder, g:species.Genome, seed:u64) Allocator.Error!void {
  var rng = Rng.init(seed);
  const h = g.stem_h * rng.range(0.9, 1.1);
  try foot(b, .{.r = g.stem_r * 1.9, .reach = g.stem_r * 7.5, .root_r = g.stem_r * 0.34, .seed = seed ^ 0xF007});
  const s:pk.Stalk = .{.girth = g.stem_r, .part = rng.range(3.0, 3.4), .from = 0.12, .to = rng.range(0.78, 0.84)};
  var sp:[RES]V3 = undefined;
  stalkPath(v3(0, 0, 0), h, v3(rng.range(-0.03, 0.03), 0, rng.range(-0.03, 0.03)), g.wobble, seed ^ 0x57A1, &sp);
  var ts:[RES]f32 = undefined;
  var sec:[RES]Section = undefined;
  for (&ts, 0..) |*t, i| t.* = m.ratio(i, RES - 1) * DRIFT_TOP;
  sections(s, &sec);
  try weave(b, &sp, &ts, &sec, .{.seed = seed ^ 0x3EA});
  // the lanes: four sapwood cores wound round each other up the core,
  // laid bare where the cage parts
  var fn_:[RES]V3 = undefined;
  var fb:[RES]V3 = undefined;
  mg.transport(&sp, &fn_, &fb);
  const tints = [4]Rgba8{pal.sapwood, color.mix(pal.sapwood, amber, 0.45), color.mix(pal.sapwood, violet, 0.5), color.mix(pal.sapwood, blue, 0.5)};
  for (tints, 0..) |tint, li| {
    var p:[RES]V3 = undefined;
    var rs:[RES]f32 = undefined;
    for (&p, &rs, sec, 0..) |*q, *r, c, i| {
      const u = m.ratio(i, RES - 1);
      const a = m.ratio(li, 4) * m.tau + u * 3.2 * m.tau;
      q.* = round(sp[i], fn_[i], fb[i], a, c.tight * 0.42);
      r.* = c.tight * 0.3;
    }
    try b.tubeR(&p, &ts, &rs, tint, .stem, 5);
  }
  // the spore sac and its pore
  const top = sp[RES - 1];
  const sr = g.bloom_r * rng.range(0.95, 1.08);
  const heart = top + v3(0, sr * 0.85, 0);
  try sac(b, .{.center = heart, .radii = v3(sr, sr * 1.2, sr), .t = DRIFT_TOP + 0.04, .arms = 3, .phase = rng.range(0, m.tau)});
  const pore = heart + v3(0, sr * 1.15, 0);
  try pk.nodule(b, pore, v3(sr * 0.32, sr * 0.22, sr * 0.32), DRIFT_TOP + 0.08, pale, core_par, pearl);
  // the crown: five fronds flaring and curling down, exactly alike, each
  // with its own leaves and a flower at its tip
  const spin = rng.range(0, m.tau);
  var lrng = Rng.init(seed ^ 0x1EA);
  for (0..FOLD) |i| {
    const a = spin + m.ratio(i, FOLD) * m.tau;
    var c:[10]V3 = undefined;
    pk.frondPath(pore, v3(@cos(a), 0, @sin(a)), h * 0.5, 0.55, 2.2, seed ^ 0xF20D, &c);
    var p:[20]V3 = undefined;
    m.splineResample(&c, &p);
    const t0 = DRIFT_TOP + 0.08;
    try taper(b, &p, g.stem_r * 0.3, 0.45, t0, 0.97, lilac, .tendril, 5);
    try mg.leavesAlong(b, &p, g.leaves / 2, g.leaf_len, g.leaf_w, 0.25, 0.8, t0, 0.97, leaf_dark, leaf_lite, seed +% i * 97 +% lrng.below(1000));
    try bloom(b, .{.heart = p[19], .len = g.bloom_r * 0.55, .t = 1, .spin = a, .petals = g.petals, .seed = seed ^ 0xB1});
  }
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
