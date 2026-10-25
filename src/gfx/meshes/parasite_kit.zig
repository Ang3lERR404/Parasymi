//! the parasitic lineage's body, shared by its plants (`plant`, the
//! `coil` form) and its structures: alien, not hostile, and plainly a
//! deviation from the symbiotes. A symbiote winds its strands tight round
//! its core, each a little different from the next; a parasite's strands
//! come up woven the same way (both ways at once), then part from the core
//! into an open lattice cage (`lattice`), pearl beads where they cross, the
//! core thinned inside it and sacs of thin-film sap hanging on it in plain
//! view (`organs`), and gather to it again. And it is too exact: all of it
//! comes in fives (`FOLD`), turned evenly and grown alike (one seed for
//! every frond of a crown), never by a golden angle; and it repeats
//! itself, each frond ending in a small cage of its own crowned in turn
//! (`pod`). A pale pearl skin, lilac fronds, a bulbous foot half sunk in
//! the soil, pale roots. On a structure every piece grows on its growth
//! splines (gfx/growth.zig); a plant grows by tu.x and its cage parts as
//! it matures (plant.vert: tu.y how far each strand has parted).
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");
const growth = @import("../growth.zig");
const vertex = @import("../vertex.zig");
const species = @import("../../sim/species.zig");
const Rng = @import("../../core/rng.zig").Rng;

const V3 = m.V3;
const v3 = m.v3;
const Rgba8 = color.Rgba8;

/// the lineage's colours: its skin, the core showing between its strands,
/// pearl where it is youngest, its fronds, its sap
pub const skin = color.rgb(0.56, 0.54, 0.62).toRgba8(255);
pub const core = color.rgb(0.39, 0.37, 0.45).toRgba8(255);
pub const pearl = color.rgb(0.78, 0.74, 0.84).toRgba8(255);
pub const lilac = color.rgb(0.68, 0.62, 0.82).toRgba8(255);
pub const sac = color.rgb(0.46, 0.62, 0.86).toRgba8(255);
/// how many of everything it grows, turned evenly
pub const FOLD:u32 = 5;
/// the turn its strands make along a stalk, each way (radians)
pub const TWIST:f32 = 1.6 * m.pi;
/// a plain weave of it (a nerve) is wound by something alive, but tighter
/// than a symbiote's
pub const WOBBLE:f32 = 0.05;
/// points a lattice may have along it
const MAX = m.MAX_SPLINE;

/// a lattice's cross-section at one point along it: the core's radius, the
/// radius its strands lie at woven tight, the radius they have parted to
/// (never less), and their own radius
pub const Section = struct { core:f32, tight:f32, open:f32, strand:f32 };

/// how far a section has parted: 0 woven tight .. toward 1 far off its core
pub fn parting(s:Section) f32 { return if (s.open > m.EPS) 1 - s.tight / s.open else 0; }

pub const Lattice = struct {
  /// strands each way
  n:u32 = FOLD,
  /// the turn each makes along it (radians)
  twist:f32 = TWIST,
  sides:u32 = 4,
  /// pearl beads where its strands cross, a multiple of a strand's radius
  /// (0: none), only where parted at least `node_from`
  node:f32 = 1.9,
  node_from:f32 = 0.3,
  part:vertex.Part = .stem,
  core:Rgba8 = core,
  strand:Rgba8 = skin,
  bead:Rgba8 = pearl,
};

/// the lattice along `spine` (tu.x `ts`, cross-sections `sec`): a core,
/// and `l.n` strands wound each way round it at exactly even turns, lying
/// in it where woven and lifting off it into a cage where parted, paling to
/// pearl as they go; a bead where two cross once parted. Each strand's tu.y
/// is how far it has parted there (`parting`).
pub fn lattice(b:*mg.Builder, spine:[]const V3, ts:[]const f32, sec:[]const Section, l:Lattice) Allocator.Error!void {
  const n = spine.len;
  assert(n >= 2 and n <= MAX and ts.len == n and sec.len == n);
  var fn_:[MAX]V3 = undefined;
  var fb:[MAX]V3 = undefined;
  mg.transport(spine, fn_[0..n], fb[0..n]);
  var rs:[MAX]f32 = undefined;
  for (rs[0..n], sec) |*r, s| r.* = s.core;
  try b.tubeR(spine, ts, rs[0..n], l.core, l.part, 8);
  var us:[MAX]f32 = undefined;
  var cs:[MAX]Rgba8 = undefined;
  for (rs[0..n], us[0..n], cs[0..n], sec) |*r, *u, *c, s| {
    r.* = s.strand;
    u.* = parting(s);
    c.* = color.mix(l.strand, l.bead, u.* * 0.6);
  }
  var path:[MAX]V3 = undefined;
  for ([_]f32{1, -1}) |way| for (0..l.n) |si| {
    for (path[0..n], 0..) |*p, i| p.* = round(spine[i], fn_[i], fb[i], strandAngle(l, si, way, m.ratio(i, n - 1)), sec[i].open);
    try b.tubeC(path[0..n], ts, rs[0..n], cs[0..n], us[0..n], l.part, l.sides);
  };
  // decision: beads are left out at the coarsest level of detail, where
  // they are under a pixel
  if (l.node <= 0 or b.lod + 1 >= mg.LODS) return;
  // strand i one way meets one the other way wherever twice its turn is a
  // whole share of the circle: every pi / (n twist) along it, n at a time
  const every = m.pi / (m.f(l.n) * l.twist);
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
    const pt = parting(s);
    if (pt < l.node_from) continue;
    const at = m.lerpV(spine[lo], spine[hi], f);
    const nv = m.norm(m.lerpV(fn_[lo], fn_[hi], f));
    const bv = m.norm(m.lerpV(fb[lo], fb[hi], f));
    for (0..l.n) |si| {
      const mk = b.mark();
      try mg.ellipsoid(b, .{
        .center = round(at, nv, bv, strandAngle(l, si, 1, u), s.open), .radii = m.splat3(s.strand * l.node),
        .col = l.bead, .part = l.part, .rings = 4, .segs = 6, .t = m.lerp(ts[lo], ts[hi], f),
      });
      for (b.v.items[mk..]) |*vx| vx.tu[1] = pt;
    }
  }
}

fn strandAngle(l:Lattice, si:usize, way:f32, u:f32) f32 { return m.ratio(si, l.n) * m.tau + way * l.twist * u; }
fn round(at:V3, nv:V3, bv:V3, a:f32, r:f32) V3 { return at + (nv * m.splat3(@cos(a)) + bv * m.splat3(@sin(a))) * m.splat3(r); }

/// a stalk's shape: woven tight at its foot, parting into a cage over
/// `from..to` of it and gathering again above
pub const Stalk = struct {
  /// its radius at its middle, as a braid's
  girth:f32,
  /// how far its strands part where they part most, a multiple of the
  /// radius they are woven at (0: a plain weave)
  part:f32 = 2.6,
  from:f32 = 0.15,
  to:f32 = 0.85,
  /// how hard it swells into its foot
  foot:f32 = 0.9,
  twist:f32 = TWIST,
  sides:u32 = 4,
  node:f32 = 1.9,
};

/// how far a stalk's cage has opened at `u` (0 woven .. 1 widest): eased
/// both ways, so its strands leave the core and gather to it with no kink
pub fn parted(s:Stalk, u:f32) f32 {
  if (u <= s.from or u >= s.to) return 0;
  const c = @cos(m.pi * (u - s.from) / (s.to - s.from));
  return 1 - c * c * c * c;
}

/// a stalk's cross-section at `u` along it: woven as a braid is (the same
/// core and strands), its core thinning to a filament where the cage opens
pub fn section(s:Stalk, u:f32) Section {
  const low = 1 - u;
  const g = s.girth * m.lerp(1.15, 0.75, u) * (1 + s.foot * low * low * low * low * low);
  const w = parted(s, u);
  const tight = g * mg.BRAID_OFF;
  return .{.core = g * mg.BRAID_CORE * (1 - 0.65 * w), .tight = tight, .open = tight * (1 + s.part * w), .strand = g * mg.BRAID_STRAND * (1 - 0.3 * w)};
}

/// the stalk along spline `id`, grown along it
pub fn stalk(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, s:Stalk) Allocator.Error!void {
  var sp:[growth.RES]V3 = undefined;
  var ts:[growth.RES]f32 = undefined;
  var sec:[growth.RES]Section = undefined;
  k.path(id, 0, 1, &sp);
  for (&ts, &sec, 0..) |*t, *c, i| {
    const u = m.ratio(i, growth.RES - 1);
    t.* = u * 0.85;
    c.* = section(s, u);
  }
  const mk = b.mark();
  try lattice(b, &sp, &ts, &sec, .{.twist = s.twist, .sides = s.sides, .node = s.node});
  try k.along(b, mk, id);
}

/// where the `i`th of `n` sacs hangs in a stalk's cage (how far along it)
/// and how big it is: evenly over where it is parted, each filling `fill`
/// of the cage there, never touching the next
const Organ = struct { u:f32, r:f32 };
fn organ(s:Stalk, len:f32, i:usize, n:u32, fill:f32) Organ {
  const u = m.lerp(s.from, s.to, (m.f(i) + 0.5) / m.f(n));
  const c = section(s, u);
  const gap = (s.to - s.from) / m.f(n) * len;
  return .{.u = u, .r = @min((c.open - c.strand) * fill, gap * 0.42)};
}

/// `n` sacs of thin-film sap threaded on the core inside a stalk's cage
/// (spline `id`), swelling once its front reaches each
pub fn organs(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, s:Stalk, n:u32, fill:f32) Allocator.Error!void {
  for (0..n) |i| {
    const o = organ(s, k.get(id).len, i, n, fill);
    try bladder(b, k, id, o.u, k.point(id, o.u), v3(o.r, o.r * 1.15, o.r), o.u, .{});
  }
}

/// the bulbous foot at `at`, half sunk in the soil, swelling out of the
/// stalk's root as it starts
pub fn foot(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, at:V3, radii:V3) Allocator.Error!void {
  const s = b.mark();
  try nodule(b, at, radii, 0, skin, core, pearl);
  try k.on(b, s, id, 0, .{.from = at, .span = k.get(id).time * 0.3});
}

/// a bulb of the lineage's skin at `at`: pearl where it swells toward the
/// light, its core showing dark underneath, so it reads round however
/// pale (a smooth field of its normal, so shared vertices match)
pub fn nodule(b:*mg.Builder, at:V3, radii:V3, t:f32, sk:Rgba8, dark:Rgba8, light:Rgba8) Allocator.Error!void {
  const s = b.mark();
  try mg.ellipsoid(b, .{.center = at, .radii = radii, .col = sk, .rings = 9, .segs = 14, .t = t});
  for (b.v.items[s..]) |*vx| {
    const up = m.clamp01(0.5 + 0.5 * vx.nrm[1]);
    vx.col = if (up > 0.5) color.mix(sk, light, (up - 0.5) * 2) else color.mix(dark, sk, up * 2);
  }
}

/// the `i`th of `n` roots out of a foot, reaching `reach`: out low over the
/// ground, then down into it, every one alike
fn rootPath(i:usize, n:u32, reach:f32, seed:u64, c:*[6]V3) void {
  const a = m.ratio(i, n) * m.tau;
  const out = v3(@cos(a), 0, @sin(a));
  const from = out * m.splat3(0.05) + v3(0, 0.03, 0);
  for (c, 0..) |*p, j| {
    const f = m.ratio(j, 5);
    p.* = from + out * m.splat3(reach * f) + v3(0, 0.03 * @sin(m.pi * f * 0.8) - 0.09 * f * f, 0);
  }
  mg.grow(c, .{.start = from, .direction = out, .length = reach, .wobble = 0.3, .seed = seed});
}

/// `n` pale roots out of the foot, reaching `reach` and sinking into the
/// ground, each a branch growing with the stalk
pub fn roots(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, n:u32, reach:f32, r:f32, seed:u64) Allocator.Error!void {
  for (0..n) |i| {
    var c:[6]V3 = undefined;
    rootPath(i, n, reach, seed, &c);
    const root = k.branch(id, 0, &c, .{.after = .with});
    try k.tube(b, root, .{.r0 = r, .tip = 0.1, .col = pearl, .part = .tendril, .sides = 5, .t0 = 0, .t1 = 0.1});
  }
}

/// a translucent bladder of thin-film sap (part `.bloom`: the instance's
/// `fade` makes it see-through) at `center`, swelling out of spline `id`
/// at `u` once its front reaches it
pub fn bladder(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, u:f32, center:V3, radii:V3, t:f32, o:growth.Skeleton.On) Allocator.Error!void {
  const s = b.mark();
  try mg.ellipsoid(b, .{.center = center, .radii = radii, .col = sac, .part = .bloom, .rings = 8, .segs = 12, .t = t});
  var on = o;
  if (on.from == null) on.from = k.point(id, u);
  try k.on(b, s, id, u, on);
}

/// a frond's control points from `from` out along `out` (horizontal, unit):
/// its heading starts at `rise` and turns ever faster (by `curl` at its tip;
/// negative turns it up), so it rises and arcs, never quite smooth. One
/// seed for a crown's fronds makes them alike, turned
pub fn frondPath(from:V3, out:V3, len:f32, rise:f32, curl:f32, seed:u64, pts:[]V3) void {
  const n = pts.len;
  pts[0] = from;
  for (1..n) |j| {
    const s = m.ratio(j, n - 1);
    const heading = rise - s * s * curl;
    const step = len / m.f(n - 1) * (1 - 0.55 * s);
    pts[j] = pts[j - 1] + (out * m.splat3(@cos(heading)) + v3(0, @sin(heading), 0)) * m.splat3(step);
  }
  mg.grow(pts, .{.start = from, .direction = m.norm(pts[n - 1] - from), .length = len, .wobble = 0.08, .seed = seed});
}

pub const Frond = struct {
  out:V3,
  len:f32,
  r:f32,
  rise:f32 = 1.25,
  curl:f32 = 5.2,
  /// its radius at its tip, a share of `r`
  tip:f32 = 0.12,
  t0:f32 = 0.6,
  seed:u64,
  grow:growth.Branch = .{},
};

/// a frond off spline `parent` at `u`, grown along its own spline, tapering
/// to its tip; returns its spline
pub fn frond(b:*mg.Builder, k:*growth.Skeleton, parent:growth.Id, u:f32, f:Frond) Allocator.Error!growth.Id {
  var c:[10]V3 = undefined;
  frondPath(k.point(parent, u), f.out, f.len, f.rise, f.curl, f.seed, &c);
  const id = k.branch(parent, u, &c, f.grow);
  try k.tube(b, id, .{.r0 = f.r, .tip = f.tip, .col = lilac, .part = .tendril, .sides = 5, .t0 = f.t0, .t1 = 1});
  return id;
}

/// a crown: `FOLD` fronds alike, turned evenly from `spin`
pub const Crown = struct {
  spin:f32 = 0,
  len:f32,
  r:f32,
  rise:f32 = 0.4,
  curl:f32 = -1.1,
  t0:f32 = 0.6,
  seed:u64,
  grow:growth.Branch = .{},
  /// each frond ends in a `pod` this long (0: tapering to a point)
  pod:f32 = 0,
};

/// a crown off spline `parent` at `u`, every frond growing at once
pub fn crown(b:*mg.Builder, k:*growth.Skeleton, parent:growth.Id, u:f32, c:Crown) Allocator.Error!void {
  const girth = podGirth(c.pod);
  for (0..FOLD) |i| {
    const a = c.spin + m.ratio(i, FOLD) * m.tau;
    const id = try frond(b, k, parent, u, .{
      .out = v3(@cos(a), 0, @sin(a)), .len = c.len, .r = c.r, .rise = c.rise, .curl = c.curl,
      .tip = if (c.pod > 0) @min(1, podFoot(girth) / c.r) else 0.12, .t0 = c.t0, .seed = c.seed, .grow = c.grow,
    });
    if (c.pod > 0) _ = try pod(b, k, id, .{.len = c.pod, .girth = girth, .seed = c.seed});
  }
}

pub const Pod = struct {
  len:f32,
  /// as a stalk's
  girth:f32,
  t:f32 = 1,
  part:vertex.Part = .tendril,
  skin:Rgba8 = skin,
  core:Rgba8 = core,
  pearl:Rgba8 = pearl,
  frond:Rgba8 = lilac,
  sac:Rgba8 = sac,
  seed:u64,
};

/// a pod's girth for its length, and how wide it is at its foot (where
/// the frond it ends meets it)
pub fn podGirth(len:f32) f32 { return len * 0.085; }
pub fn podFoot(girth:f32) f32 { return girth * 1.15 * (mg.BRAID_OFF + mg.BRAID_STRAND); }

/// the lineage's body again, small, from `at` along `axis`: its strands
/// woven at its foot, parting round a sac of sap and gathering at its
/// crown into a pearl bead, out of which `FOLD` frondlets spring alike,
/// rising, arcing out and curling down softly, tapering to points
pub fn podAt(b:*mg.Builder, at:V3, axis:V3, p:Pod) Allocator.Error!void {
  const N = 9;
  const s:Stalk = .{.girth = p.girth, .part = 2.2, .from = 0, .to = 1, .foot = 0, .twist = m.pi, .sides = 3, .node = 0};
  var sp:[N]V3 = undefined;
  var ts:[N]f32 = undefined;
  var sec:[N]Section = undefined;
  for (&sp, &ts, &sec, 0..) |*q, *t, *c, i| {
    const u = m.ratio(i, N - 1);
    q.* = at + axis * m.splat3(p.len * u);
    t.* = p.t;
    c.* = section(s, u);
  }
  try lattice(b, &sp, &ts, &sec, .{.twist = s.twist, .sides = s.sides, .node = 0, .part = p.part, .core = p.core, .strand = p.skin, .bead = p.pearl});
  const mid = section(s, 0.5);
  const r = (mid.open - mid.strand) * 0.6;
  try mg.ellipsoid(b, .{.center = at + axis * m.splat3(p.len * 0.5), .radii = v3(r, r * 1.15, r), .col = p.sac, .part = .bloom, .rings = 5, .segs = 8, .t = p.t});
  const top = sp[N - 1];
  try mg.ellipsoid(b, .{.center = top, .radii = m.splat3(p.girth), .col = p.pearl, .part = p.part, .rings = 4, .segs = 6, .t = p.t});
  // decision: frondlets only at full detail; past `LOD_AT[0]` they are
  // under a pixel
  if (b.lod > 0) return;
  // they rise the way the pod points, laid out in a frame turned with it
  // about the vertical (so the pods of a crown stay alike, turned)
  const side = if (@abs(axis[1]) < m.NEAR_PARALLEL) m.norm(m.cross(axis, v3(0, 1, 0))) else v3(1, 0, 0);
  const fwd = m.cross(side, axis);
  for (0..FOLD) |i| {
    const a = m.ratio(i, FOLD) * m.tau;
    var c:[6]V3 = undefined;
    frondPath(v3(0, 0, 0), v3(@cos(a), 0, @sin(a)), p.len * 0.55, 0.9, 2.6, p.seed ^ 0x90D, &c);
    for (&c) |*q| q.* = top + side * m.splat3(q[0]) + axis * m.splat3(q[1]) + fwd * m.splat3(q[2]);
    try frondTube(b, &c, p.girth * 0.45, 0.05, p.t, p.t, p.frond, p.part, 3);
  }
}

/// a pod at the tip of frond `id`, the way it ends, grown along a spline of
/// its own once the frond is done; returns that spline
pub fn pod(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, p:Pod) Allocator.Error!growth.Id {
  const at = k.point(id, 1);
  const ax = k.tangent(id, 1);
  const pid = k.branch(id, 1, &.{at, at + ax * m.splat3(p.len * 0.5), at + ax * m.splat3(p.len)}, .{});
  const mk = b.mark();
  try podAt(b, at, ax, p);
  try k.along(b, mk, pid);
  return pid;
}

/// a tube through control points `c` (resampled smooth), `r` at its root
/// tapering to `tip` of it, tu.x `t0`..`t1`
fn frondTube(b:*mg.Builder, c:[]const V3, r:f32, tip:f32, t0:f32, t1:f32, col:Rgba8, part:vertex.Part, sides:u32) Allocator.Error!void {
  const N = 14;
  var path:[N]V3 = undefined;
  m.splineResample(c, &path);
  var ts:[N]f32 = undefined;
  var rs:[N]f32 = undefined;
  for (&ts, &rs, 0..) |*t, *q, j| {
    const f = m.ratio(j, N - 1);
    t.* = m.lerp(t0, t1, f);
    q.* = r * m.lerp(1, tip, f);
  }
  try b.tubeR(&path, &ts, &rs, col, part, sides);
}

/// a parasite plant (the `coil` form), from its genome: upright and exactly
/// symmetric, its variants differing in proportion alone. A bulbous foot
/// half sunk in the soil and `FOLD` pale roots; the stalk woven tight out
/// of it, parting into a tall cage with its sacs (`thorns` of them) on the
/// core inside, gathering at its neck round a bulb of sap; and a crown of
/// `FOLD` fronds rising like a candelabrum, each ending in a pod crowned in
/// turn. tu.x is height (the crown 0.85..1); plant.vert parts the cage
/// (tu.y) and opens the crown as it matures.
pub fn plant(b:*mg.Builder, g:species.Genome, seed:u64) Allocator.Error!void {
  var rng = Rng.init(seed);
  const sk = g.stem_col.toRgba8(255);
  const dark = color.shade(g.stem_col, 0.7);
  const light = color.mix(sk, color.rgb(1, 0.97, 1).toRgba8(255), 0.45);
  const frond_c = g.leaf_col.toRgba8(255);
  const sap = g.bloom_col.toRgba8(255);
  const h = g.stem_h * rng.range(0.9, 1.1);
  const s:Stalk = .{.girth = g.stem_r, .part = rng.range(2.6, 3.2), .from = 0.12, .to = rng.range(0.74, 0.82)};

  // the stalk, dead upright
  const N = 25;
  var sp:[N]V3 = undefined;
  var ts:[N]f32 = undefined;
  var sec:[N]Section = undefined;
  for (&sp, &ts, &sec, 0..) |*q, *t, *c, i| {
    const u = m.ratio(i, N - 1);
    q.* = v3(0, h * u, 0);
    t.* = u * 0.85;
    c.* = section(s, u);
  }
  try lattice(b, &sp, &ts, &sec, .{.core = dark, .strand = sk, .bead = light});
  try nodule(b, v3(0, g.stem_r * 0.3, 0), v3(g.stem_r * 2.4, g.stem_r * 1.2, g.stem_r * 2.4), 0, sk, dark, light);
  for (0..FOLD) |i| {
    var c:[6]V3 = undefined;
    rootPath(i, FOLD, g.stem_r * 4.5, seed ^ 0x2007, &c);
    try frondTube(b, &c, g.stem_r * 0.45, 0.1, 0, 0.03, light, .stem, 4);
  }
  // its sacs, on the core inside the cage
  for (0..g.thorns) |i| {
    const o = organ(s, h, i, g.thorns, 0.6);
    try mg.ellipsoid(b, .{.center = v3(0, h * o.u, 0), .radii = v3(o.r, o.r * 1.15, o.r), .col = sap, .part = .bloom, .rings = 6, .segs = 9, .t = o.u * 0.85});
  }

  // a bulb at its neck, the crown springing round it
  const neck = sp[N - 1];
  try mg.ellipsoid(b, .{
    .center = neck + v3(0, g.bloom_r * 0.45, 0), .radii = v3(g.bloom_r * 0.8, g.bloom_r, g.bloom_r * 0.8),
    .col = sap, .part = .bloom, .rings = 7, .segs = 9, .t = 1,
  });
  const plen = h * 0.2;
  const girth = podGirth(plen);
  const r = g.stem_r * 0.45;
  const frond_seed = seed ^ 0xF20D;
  for (0..g.tendrils) |i| {
    const a = m.ratio(i, g.tendrils) * m.tau;
    var c:[10]V3 = undefined;
    frondPath(neck, v3(@cos(a), 0, @sin(a)), h * 0.55, 0.35, -1.15, frond_seed, &c);
    try frondTube(b, &c, r, @min(1, podFoot(girth) / r), 0.85, 1, frond_c, .tendril, 5);
    const ax = m.norm(c[9] - c[8]);
    try podAt(b, c[9], ax, .{.len = plen, .girth = girth, .skin = sk, .core = dark, .pearl = light, .frond = frond_c, .sac = sap, .seed = frond_seed});
  }
}
