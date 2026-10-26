//! the radiant (celestial) lineage's body, shared by its plants (`plant`,
//! the celestial bloom, the `radiant` form; `star`, the vesper, the `star`
//! form) and its structures (the diamond, `cut` + `shards`). A radiant thing is never grown: it is
//! gathered. It has no root, no stem, no growth spline and nothing that
//! swells or scales up; it is made of rigid fragments joined to nothing
//! (petals, threads, motes, facets), and each comes in from afar on its own
//! way, turning round the heart as it comes, and settles in its place in
//! its turn, the heart first, the last to close last. Once gathered it
//! hangs together by light alone (threads of it, `thread`), turning
//! slowly and drifting a little apart and back; it never bends from a root.
//!
//! Every vertex built here belongs to one fragment (`fragment`), which
//! carries to the shaders (common.glsl `fragmentOf`): tu.x its assembly
//! order (0 first .. 1 last), tu.y its `Ring` (a thread adds how far it is
//! from what it holds, `THREAD`, so its heart end stays put), colour alpha
//! its bearing round the heart. The shaders gather it (common.glsl
//! `gatherAway`, `gatherIn`): plant.vert by the bloom's growth, part.vert
//! by how far its halo (or its own growing in) has come. A new radiant
//! thing is built from these pieces and gathered the same way, never with
//! the symbiotes' kits or the growth splines.
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const mg = @import("../meshgen.zig");
const color = @import("engine").core.color;
const vertex = @import("../vertex.zig");
const species = @import("../../sim/species.zig");
const mineral = @import("mineral_kit.zig");
const Rng = @import("engine").core.rng.Rng;

const V3 = m.V3;
const v3 = m.v3;
const Rgba8 = color.Rgba8;

/// what each fragment belongs to (tu.y): the shaders move each its own way
/// (plant.vert `SPIN` turns them by it). A radiant structure's body is its
/// `core`.
pub const Ring = enum(u8) { core, inner, middle, outer, motes, halo, leaves };
/// tu.y a thread adds at its heart end (0 at what it holds; common.glsl
/// `RADIANT_THREAD`)
pub const THREAD:f32 = 0.9;

pub const Fragment = struct {
  /// when it settles among the rest: 0 the first .. 1 the last
  order:f32,
  ring:Ring,
  /// the way it lies from the heart (radians from +x toward +z), the way
  /// it comes in from
  bearing:f32 = 0,
};

/// mark every vertex built since `start` as one fragment
pub fn fragment(b:*mg.Builder, start:usize, f:Fragment) void {
  assert(f.order >= 0 and f.order <= 1);
  const a:u8 = @intFromFloat(@mod(f.bearing, m.tau) / m.tau * 255);
  for (b.v.items[start..]) |*v| {
    v.tu = .{f.order, m.f(@intFromEnum(f.ring))};
    v.col.a = a;
  }
}

/// a thread of light along a grown path, tapering to a point at both ends
/// (not a fragment by itself: it belongs to what it holds); returns its far
/// end
pub fn thread(b:*mg.Builder, g:mg.Growth, r:f32, col:Rgba8) Allocator.Error!V3 {
  var ctrl:[6]V3 = undefined;
  mg.growthPath(g, &ctrl);
  var path:[14]V3 = undefined;
  m.splineResample(&ctrl, &path);
  var ts:[14]f32 = undefined;
  var radii:[14]f32 = undefined;
  for (&ts, &radii, 0..) |*t, *rr, j| {
    const k = m.ratio(j, 13);
    t.* = k;
    // (sin pi is a hair below 0 in f32: clamp it, or the tip is NaN)
    rr.* = r * @sqrt(@max(0, @sin(m.pi * k))) + r * 0.05;
  }
  try b.tubeR(&path, &ts, &radii, col, .bloom, 4);
  return path[13];
}

pub const Core = struct {
  /// the bloom's radius (`Genome.bloom_r`): everything is sized by it
  r:f32,
  body:Rgba8,
  lite:Rgba8,
  /// stamens in its crown
  stamens:u32 = 7,
  seed:u64,
};

/// the heart everything gathers to, the first fragment: a luminous core
/// and its nucleus, a little taller than wide, like a seed, with a crown of
/// stamens rising out of its top and arching out, each a thread of light
/// tipped with a bead of it (their roots sunk in the core)
pub fn core(b:*mg.Builder, c:Core, rng:*Rng) Allocator.Error!void {
  const R = c.r;
  const s = b.mark();
  try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(R * 0.4, R * 0.48, R * 0.4), .col = c.body, .part = .bloom, .rings = 6, .segs = 8});
  try mg.ellipsoid(b, .{.center = v3(0, R * 0.04, 0), .radii = m.splat3(R * 0.22), .col = c.lite, .part = .bloom, .rings = 4, .segs = 6});
  for (0..c.stamens) |i| {
    const a = m.ratio(i, c.stamens) * m.tau + rng.range(-0.2, 0.2);
    const out = v3(@cos(a), 0, @sin(a));
    const from = out * m.splat3(R * 0.12) + v3(0, R * 0.3, 0);
    const len = R * rng.range(0.55, 0.8);
    const tip = try thread(b, .{.start = from, .direction = m.norm(out * m.splat3(0.55) + v3(0, 1, 0)), .length = len, .wobble = 0.3, .curl = 0.08, .seed = c.seed +% i * 13}, R * 0.03, c.lite);
    try mg.ellipsoid(b, .{.center = tip, .radii = m.splat3(R * 0.06), .col = c.lite, .part = .bloom, .rings = 3, .segs = 5});
  }
  fragment(b, s, .{.order = 0, .ring = .core});
}

pub const Whorl = struct {
  n:u32,
  ring:Ring,
  /// how far out from the heart its petals float, and how high (shares of
  /// the radius)
  at:f32,
  y:f32,
  /// a petal's length and width (shares of the radius), and its shape
  len:f32,
  w:f32,
  rise:f32,
  flare:f32,
  cup:f32,
  /// the assembly orders its first and last petal settle at
  order:[2]f32,
  /// turned half a petal on from the whorl inside it
  offset:bool = false,
  col:Rgba8,
  /// toward its tips, where the light inside it gathers
  tip:Rgba8,
};

/// a whorl of petals floating free round the heart, a gap off it, each its
/// own fragment held to the core by a thread of light from the core's
/// flank to its claw (`seed` its threads' wander)
pub fn whorl(b:*mg.Builder, R:f32, wh:Whorl, lite:Rgba8, seed:u64, rng:*Rng) Allocator.Error!void {
  const off = if (wh.offset) m.pi / m.f(wh.n) else 0;
  for (0..wh.n) |i| {
    const a = m.ratio(i, wh.n) * m.tau + off + rng.range(-0.12, 0.12);
    const out = v3(@cos(a), 0, @sin(a));
    const base = out * m.splat3(R * wh.at) + v3(0, R * (wh.y + rng.range(-0.05, 0.05)), 0);
    const f:Fragment = .{.order = m.lerp(wh.order[0], wh.order[1], m.ratio(i, wh.n)), .ring = wh.ring, .bearing = a};
    const s = b.mark();
    try mg.petal(b, .{
      .base = base, .out = out,
      .len = R * wh.len * rng.range(0.9, 1.1), .width = R * wh.w,
      .rise = wh.rise + rng.range(-0.1, 0.1), .flare = wh.flare, .cup = wh.cup,
      .col = wh.col, .tip = wh.tip, .part = .leaf,
    });
    fragment(b, s, f);
    // the thread: from just inside the core's skin to just short of the claw
    try tether(b, out * m.splat3(R * 0.3) + v3(0, -R * 0.05, 0), base - out * m.splat3(R * 0.04), R * 0.022, lite, seed +% i * 7, f);
  }
}

/// a thread of light from the heart (`from`) to what it holds (`to`), part
/// of that fragment, its heart end marked to stay with the core (`THREAD`)
fn tether(b:*mg.Builder, from:V3, to:V3, r:f32, lite:Rgba8, seed:u64, f:Fragment) Allocator.Error!void {
  const s = b.mark();
  _ = try thread(b, .{.start = from, .direction = m.norm(to - from), .length = m.len(to - from), .wobble = 0.25, .curl = 0.1, .seed = seed}, r, lite);
  fragment(b, s, f);
  for (b.v.items[s..]) |*v| {
    const along = m.clamp01(m.dot(v.pos - from, to - from) / m.dot(to - from, to - from));
    v.tu[1] += (1 - along) * THREAD;
  }
}

pub const Leaves = struct {
  n:u32,
  /// how far out from under the heart they float, and how far below it
  /// (shares of the radius)
  at:f32,
  y:f32,
  /// a leaf's length, half-width and droop (as a blade's, not shares)
  len:f32,
  w:f32,
  droop:f32,
  order:[2]f32,
  col:Rgba8,
  tip:Rgba8,
};

/// leaves floating free beneath the heart, each its own fragment, lifting
/// a little and drooping to their tips, held up to the core's underside by
/// a thread of light (a gathered thing may carry living leaves; nothing
/// roots them)
pub fn leaves(b:*mg.Builder, R:f32, l:Leaves, lite:Rgba8, seed:u64, rng:*Rng) Allocator.Error!void {
  for (0..l.n) |i| {
    const a = m.ratio(i, l.n) * m.tau + rng.range(-0.15, 0.15);
    const out = v3(@cos(a), 0, @sin(a));
    const base = out * m.splat3(R * l.at) + v3(0, -R * (l.y + rng.range(-0.15, 0.15)), 0);
    const f:Fragment = .{.order = m.lerp(l.order[0], l.order[1], m.ratio(i, l.n)), .ring = .leaves, .bearing = a};
    const s = b.mark();
    try b.blade(base, m.norm(out + v3(0, 0.3, 0)), l.len * rng.range(0.85, 1.1), l.w, l.droop, l.col, l.tip, 1, .leaf);
    fragment(b, s, f);
    try tether(b, out * m.splat3(R * 0.12) + v3(0, -R * 0.4, 0), base - out * m.splat3(R * 0.05), R * 0.018, lite, seed +% i * 11, f);
  }
}

/// motes of light, each its own fragment on its own bearing, waiting to
/// spiral in to the heart (the shaders carry them in and fade them as they
/// are taken up, over and over)
pub fn motes(b:*mg.Builder, R:f32, n:u32, col:Rgba8, rng:*Rng) Allocator.Error!void {
  for (0..n) |i| {
    const a = m.ratio(i, n) * m.tau + rng.range(-0.3, 0.3);
    const s = b.mark();
    try mg.ellipsoid(b, .{.center = v3(@cos(a), 0, @sin(a)) * m.splat3(R * 0.5), .radii = m.splat3(R * rng.range(0.04, 0.07)), .col = col, .part = .bloom, .rings = 3, .segs = 4});
    fragment(b, s, .{.order = m.ratio(i, n), .ring = .motes, .bearing = a});
  }
}

/// a thin ring of light round it all, `r` out, tilted `tilt` radians: the
/// last to close (`order`)
pub fn halo(b:*mg.Builder, r:f32, thick:f32, tilt:f32, order:f32, col:Rgba8) Allocator.Error!void {
  const s = b.mark();
  var ring:[25]V3 = undefined;
  var ts:[25]f32 = undefined;
  for (&ring, &ts, 0..) |*p, *t, j| {
    const a = m.ratio(j, 24) * m.tau;
    const q = v3(@cos(a) * r, 0, @sin(a) * r);
    p.* = v3(q[0], q[1] * @cos(tilt) - q[2] * @sin(tilt), q[1] * @sin(tilt) + q[2] * @cos(tilt));
    t.* = 1;
  }
  try b.tube(&ring, &ts, thick, thick, col, .bloom, 4);
  fragment(b, s, .{.order = order, .ring = .halo});
}

/// sides of a `cut` crystal
pub const CUT_SIDES = 8;

pub const Cut = struct {
  /// rows from its bottom point to its top one: height, radius, twist (in
  /// half sides; a row half a side on from the next staggers the facets
  /// between them); a point is a row of radius 0
  rows:[]const [3]f32,
  /// rows below this are `deep`, the rest `lite`
  deep_rows:usize,
  deep:Rgba8,
  lite:Rgba8,
  part:vertex.Part = .prism,
};

/// a cut crystal: rows of points round its axis, faced flat between each
/// pair, each face a little uneven like a grown one. Every facet is a
/// fragment of its own, gathered from the bottom point up to the top one,
/// coming in from the way it faces; each row's facets in turn round it.
pub fn cut(b:*mg.Builder, c:Cut, rng:*Rng) Allocator.Error!void {
  const S = CUT_SIDES;
  assert(c.rows.len >= 2 and c.rows.len <= MAX_ROWS);
  var pts:[MAX_ROWS][S]V3 = undefined;
  for (c.rows, pts[0..c.rows.len]) |rg, *row| for (row, 0..) |*p, i| {
    const a = (m.f(i) + rg[2] * 0.5) / S * m.tau;
    const r = rg[1] * rng.range(0.92, 1.08);
    p.* = v3(@cos(a) * r, rg[0] + rng.range(-0.006, 0.006) * @min(1, rg[1] * 20), @sin(a) * r);
  };
  const inside = v3(0, 0.01, 0);
  const spans = c.rows.len - 1;
  for (0..spans) |k| {
    const lo = pts[k];
    const hi = pts[k + 1];
    const cl = if (k < c.deep_rows) c.deep else c.lite;
    const ch = if (k + 1 < c.deep_rows) c.deep else c.lite;
    // a point is a ring of one place: the faces along it vanish
    const lo0 = c.rows[k][1] == 0;
    const hi0 = c.rows[k + 1][1] == 0;
    for (0..S) |i| {
      const j = (i + 1) % S;
      const f:Fragment = .{.order = CUT_SHARE * (m.f(k) + m.ratio(i, S)) / m.f(spans), .ring = .core, .bearing = (m.f(i) + 0.5) / S * m.tau};
      const s = b.mark();
      // the upper row sits half a side on: stagger between them
      if (c.rows[k + 1][2] > c.rows[k][2]) {
        if (!lo0) try mineral.facet(b, .{lo[i], lo[j], hi[i]}, inside, .{cl, cl, ch}, 0, c.part);
        if (!hi0) try mineral.facet(b, .{hi[i], lo[j], hi[j]}, inside, .{ch, cl, ch}, 0, c.part);
      } else {
        if (!hi0) try mineral.facet(b, .{lo[i], hi[j], hi[i]}, inside, .{cl, ch, ch}, 0, c.part);
        if (!lo0) try mineral.facet(b, .{lo[i], lo[j], hi[j]}, inside, .{cl, cl, ch}, 0, c.part);
      }
      fragment(b, s, f);
    }
  }
}

const MAX_ROWS = 12;
/// the share of the assembly order a cut's own facets take; shards grown
/// out of it come after
const CUT_SHARE:f32 = 0.8;

/// small crystals grown out of a cut one at its foot (`at` below its
/// heart), leaning away, each a fragment settling after its facets
pub fn shards(b:*mg.Builder, n:u32, at:f32, c:Cut, rng:*Rng) Allocator.Error!void {
  for (0..n) |i| {
    const a = (m.f(i) + rng.range(-0.15, 0.15)) / m.f(n) * m.tau + 0.4;
    const s = b.mark();
    try mineral.crystal(b, .{
      .base = v3(@cos(a) * 0.05, at, @sin(a) * 0.05),
      .dir = m.norm(v3(@cos(a) * 0.9, 0.6, @sin(a) * 0.9)),
      .len = rng.range(0.12, 0.17), .r = rng.range(0.022, 0.03), .col = c.deep, .tip = c.lite, .part = c.part,
    }, rng);
    fragment(b, s, .{.order = m.lerp(CUT_SHARE, 1, m.ratio(i + 1, n)), .ring = .core, .bearing = a});
  }
}

/// a celestial bloom (the `radiant` form): a flower whose petals are not
/// joined to it. Its `core` holds three whorls of petals floating free
/// round it (an upright inner cup, a middle whorl, an outer one opening
/// wide), each bound to it by a thread of light, and motes of light
/// spiralling in to it; a thin tilted `halo` rings it all. The origin is
/// the core.
pub fn plant(b:*mg.Builder, g:species.Genome, seed:u64, variant:u32) Allocator.Error!void {
  var rng = Rng.init(seed);
  const body = g.stem_col.toRgba8(255);
  const lite = g.bloom_col.toRgba8(255);
  // petals pale toward their tips, where the light inside them gathers
  const pale = color.mix(lite, color.rgb(1, 1, 1).toRgba8(255), 0.6);
  const R = g.bloom_r;
  try core(b, .{.r = R, .body = body, .lite = lite, .seed = seed}, &rng);
  // the whorls, innermost first, each turned half a petal on from the last
  const whorls = [_]Whorl{
    .{.n = 5, .ring = .inner, .at = 0.62, .y = -0.05, .len = 1.0, .w = 0.26, .rise = 1.3, .flare = 0.5, .cup = 0.7, .order = .{0.12, 0.3}, .col = lite, .tip = pale},
    .{.n = 6 + variant % 2, .ring = .middle, .at = 1.1, .y = -0.2, .len = 1.25, .w = 0.3, .rise = 0.95, .flare = 0.6, .cup = 0.6, .order = .{0.3, 0.55}, .offset = true, .col = body, .tip = pale},
    .{.n = 8 + variant % 2, .ring = .outer, .at = 1.6, .y = -0.4, .len = 1.4, .w = 0.28, .rise = 0.6, .flare = 0.7, .cup = 0.5, .order = .{0.5, 0.8}, .col = body, .tip = pale},
  };
  for (whorls, 0..) |wh, k| try whorl(b, R, wh, lite, seed +% k * 97, &rng);
  try motes(b, R, 9, lite, &rng);
  try halo(b, R * 1.55, R * 0.025, 0.35, 0.95, lite);
}

/// the vesper (the `star` form): an evening star's flower, the radiant body
/// brought down to hang `stem_h` over its tile with nothing under it. Its
/// `core` (dusk violet, gold light, five stamens) holds a small upright cup
/// of petals and, turned half a petal on, a star of long narrow rays lying
/// open round it; beneath, `leaves` float free (it was spliced from both
/// lineages' herbs). Motes come in to it; no halo (that is the sky
/// bloom's). The origin is its tile; plant.vert brings each piece down to
/// it out of the sky.
pub fn star(b:*mg.Builder, g:species.Genome, seed:u64, variant:u32) Allocator.Error!void {
  var rng = Rng.init(seed);
  const body = g.stem_col.toRgba8(255);
  const lite = g.bloom_col.toRgba8(255);
  const pale = color.mix(lite, color.rgb(1, 1, 1).toRgba8(255), 0.55);
  const R = g.bloom_r;
  const start = b.mark();
  try core(b, .{.r = R, .body = body, .lite = lite, .stamens = 5, .seed = seed}, &rng);
  const whorls = [_]Whorl{
    .{.n = g.petals, .ring = .inner, .at = 0.55, .y = 0.02, .len = 0.85, .w = 0.24, .rise = 1.25, .flare = 0.45, .cup = 0.7, .order = .{0.1, 0.24}, .col = lite, .tip = pale},
    // the star: long narrow rays lying nearly open, paling to gold points
    .{.n = g.petals, .ring = .middle, .at = 0.95, .y = -0.12, .len = 2.3 + 0.25 * m.f(variant % 2), .w = 0.17, .rise = 0.3, .flare = 0.15, .cup = 0.35, .order = .{0.28, 0.55}, .offset = true, .col = body, .tip = lite},
  };
  for (whorls, 0..) |wh, k| try whorl(b, R, wh, lite, seed +% k * 97, &rng);
  const lc = g.leaf_col.toRgba8(255);
  try leaves(b, R, .{
    .n = g.leaves, .at = 1.0, .y = 1.6, .len = g.leaf_len, .w = g.leaf_w, .droop = g.leaf_droop,
    .order = .{0.6, 0.85}, .col = lc, .tip = color.mix(lc, body, 0.5),
  }, lite, seed +% 0x1EAF, &rng);
  try motes(b, R, 7, lite, &rng);
  b.xform(start, m.translate(v3(0, g.stem_h, 0)));
}

/// every vertex since `start` is gathered: a fragment with a valid order
/// and ring, on no growth spline
fn expectGathered(b:*const mg.Builder, start:usize) !void {
  try std.testing.expect(b.v.items.len > start);
  for (b.v.items[start..]) |v| {
    try std.testing.expect(v.tu[0] >= 0 and v.tu[0] <= 1);
    // a real place and facing (nothing degenerate)
    for (0..3) |i| try std.testing.expect(v.pos[i] == v.pos[i] and v.nrm[i] == v.nrm[i]);
    const ring = @floor(v.tu[1] + 0.01);
    try std.testing.expect(ring >= 0 and ring <= @intFromEnum(Ring.leaves));
  }
  // nothing of it is on a growth spline
  try std.testing.expect(b.grow.items.len <= start);
}

test "a celestial bloom, a vesper and a cut crystal are wholly gathered fragments" {
  var b:mg.Builder = .{.gpa = std.testing.allocator};
  defer b.deinit();
  try plant(&b, species.get(.bloom).genome, 7, 0);
  try expectGathered(&b, 0);
  // the vesper too, hanging over its tile: nothing of it reaches the ground
  const v = b.mark();
  try star(&b, species.get(.vesper).genome, 7, 1);
  try expectGathered(&b, v);
  for (b.v.items[v..]) |x| try std.testing.expect(x.pos[1] > 0.05);
  const s = b.mark();
  var rng = Rng.init(3);
  const c:Cut = .{.rows = &.{.{-0.2, 0, 0}, .{0, 0.1, 1}, .{0.2, 0, 0}}, .deep_rows = 1, .deep = color.rgb(1, 1, 1).toRgba8(255), .lite = color.rgb(1, 1, 1).toRgba8(255)};
  try cut(&b, c, &rng);
  try shards(&b, 3, -0.1, c, &rng);
  try expectGathered(&b, s);
  // the cut's facets gather from its foot up
  try std.testing.expect(b.v.items[s].tu[0] < b.v.items[b.mark() - 1].tu[0]);
}
