//! mesh: CONDUIT. a living root that digs up out of the soil near its
//! tile's back edge, arches over the tile and digs back in near its front
//! edge (+X, "forward"); the next conduit's root comes up where this one
//! went down, so a chain is joined under the ground whichever way it turns.
//! A core of sapwood (part `.core`: essence carried through it swells and
//! tints it as it passes, part.vert) wound tight in a weave of smaller
//! roots running over and under each other; branchlets peel off the weave
//! and rejoin it, and leaves sit over the top in twos and threes, swept
//! forward the way it carries, as weed combs out downstream. Soil is heaped
//! where it breaks the ground, rootlets reaching into it.
//! `left`/`right`: the same root turning in from the tile's +Z / -Z edge.
//! It grows along a growth spline (gfx/growth.zig) through its spine: up
//! out of the soil at its back edge (where the root behind went down),
//! over, and down in at its front.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("engine").core.color;
const noise = @import("engine").core.noise;
const vertex = @import("../vertex.zig");
const Rng = @import("engine").core.rng.Rng;
const kit = @import("structure_kit.zig");
const growth = @import("../growth.zig");

const V3 = m.V3;
const v3 = m.v3;

/// rings along the root, and the control points its spline runs through
const RES = 48;
pub const CTRL = 11;
/// how high its arch stands over the ground, how deep its ends lie at the
/// tile's edges, and how far the peak leans back from the middle (it
/// rises long and dives short: the way it carries)
pub const PEAK:f32 = 0.23;
const DEPTH:f32 = 0.12;
const SKEW:f32 = 0.4;
/// how far a straight one wanders sideways over its tile
const MEANDER:f32 = 0.06;
const CORE_R:f32 = 0.036;
/// the core flares where it breaks the ground
pub const FLARE:f32 = 0.25;
/// the weave: strands each way round the core, their girth, how many turns
/// they make along it and how far over and under they pass each other
const STRAND_R:f32 = 0.011;
const SINK:f32 = 0.35;
const OVER:f32 = 0.75;
/// branchlets peeling off the weave and rejoining it
const RUNNER_R:f32 = 0.008;
const RUNNER_OUT:f32 = 0.04;
/// leaves: their length, width, how far apart a cluster's splay
const LEAF_LEN:f32 = 0.11;
const LEAF_W:f32 = 0.04;
const LEAF_SPLAY:f32 = 0.55;
const LEAF_LIFT:f32 = 0.3;
const TWIG_LEN:f32 = 0.03;
/// the soil it heaps diving in: mounds (how far on, how wide) running on
/// ahead of it, smaller as they go
const RIDGE = [_][2]f32{.{0.012, 0.072}, .{0.07, 0.058}, .{0.12, 0.04}};

pub const Arch = struct {
  /// 0 straight across from `from` to `to` (x); ±1 turning in from the
  /// tile's +Z / -Z edge to its front
  turn:f32 = 0,
  from:f32 = -0.5,
  to:f32 = 0.5,
  peak:f32 = PEAK,
  depth:f32 = DEPTH,
  core_r:f32 = CORE_R,
  /// strands wound each way round the core (even, so over and under
  /// alternate all the way round) and the turns each makes along it
  strands:u32 = 4,
  turns:f32 = 2,
  /// its core's part (none: a braided conduit lays its own cores)
  core:?vertex.Part = .core,
  /// clusters of leaves over its top: how many leaves each
  leaves:[]const u8 = &.{2, 3, 2, 3, 2},
  runners:bool = true,
  seed:u64,
};

/// where along its tile (s 0..1) it runs over the ground, x and z
pub fn plan(a:Arch, s:f32) [2]f32 {
  if (a.turn == 0) return .{m.lerp(a.from, a.to, s), MEANDER * @sin(m.tau * s) * @sin(m.pi * s)};
  // a quarter circle from the side edge's middle to the front edge's
  const t = m.pi + s * m.pi / 2;
  return .{0.5 + 0.5 * @cos(t), a.turn * (0.5 + 0.5 * @sin(t))};
}

/// its height over the ground at s: up out of the soil steeply, a round
/// arch leaning back, steeply down again
pub fn height(a:Arch, s:f32) f32 {
  const w = s + SKEW * s * (1 - s);
  const b = @max(@sin(m.pi * w), 0);
  return -a.depth + (a.peak + a.depth) * 0.5 * (b + @sqrt(b));
}

pub fn build(b:*mg.Builder) Allocator.Error!void { try grown(b, .{.seed = 0xC0D}); }
pub const left = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void { try grown(b, .{.turn = 1, .seed = 0xC1D}); }
};
pub const right = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void { try grown(b, .{.turn = -1, .seed = 0xC2D}); }
};

/// one arch on a skeleton of its own: it grows up out of the soil at its
/// back edge, over and down into it at its front.
fn grown(b:*mg.Builder, a:Arch) Allocator.Error!void {
  var k = growth.Skeleton.begin(b);
  _ = try arch(b, &k, a);
  k.finish(b);
}

/// the control points of an arch's spine (what its growth spline runs
/// through), the same every time for the same arch
pub fn spineCtrl(a:Arch) [CTRL]V3 {
  var rng = Rng.init(a.seed);
  return spineWith(a, &rng);
}

fn spineWith(a:Arch, rng:*Rng) [CTRL]V3 {
  var ctrl:[CTRL]V3 = undefined;
  for (&ctrl, 0..) |*c, i| {
    const s = m.ratio(i, CTRL - 1);
    const xz = plan(a, s);
    // never quite smooth, the ends held where the neighbours' meet them
    const j = 0.012 * @sin(m.pi * s);
    c.* = v3(xz[0] + j * rng.range(-1, 1), height(a, s) + j * rng.range(-0.5, 0.5), xz[1] + j * rng.range(-1, 1));
  }
  return ctrl;
}

/// the root: its spine (tu.x 0 where it enters .. 1 where it leaves), the
/// spline it grows along on `k` (returned). The core and its weave grow
/// along it as its front digs on; leaves unfold and soil heaps up as the
/// front passes them.
pub fn arch(b:*mg.Builder, k:*growth.Skeleton, a:Arch) Allocator.Error!growth.Id {
  var rng = Rng.init(a.seed);
  const ctrl = spineWith(a, &rng);
  const spine = k.trunk(&ctrl, .{});
  const start = b.mark();
  var sp:[RES]V3 = undefined;
  m.splineResample(&ctrl, &sp);
  var ts:[RES]f32 = undefined;
  var rs:[RES]f32 = undefined;
  var cols:[RES]color.Rgba8 = undefined;
  for (&ts, &rs, &cols, sp, 0..) |*t, *r, *c, p, i| {
    const u = m.ratio(i, RES - 1);
    t.* = u;
    const knot = 0.15 * noise.grad(a.seed, u * 6, 0.5);
    const flare = FLARE * @exp(-p[1] * p[1] / 0.0012);
    r.* = a.core_r * (1 + knot + flare);
    c.* = color.mix(pal.sapwood_dark, pal.sapwood, m.clamp01(0.55 + 2.5 * noise.grad(a.seed +% 1, u * 9, 1.5)));
  }
  if (a.core) |part| try b.tubeC(&sp, &ts, &rs, &cols, null, part, 8);

  var fn_:[RES]V3 = undefined;
  var fb:[RES]V3 = undefined;
  mg.transport(&sp, &fn_, &fb);
  try weave(b, a, &sp, &ts, &rs, &fn_, &fb);
  if (a.runners) for ([_][2]f32{.{0.2, 0.42}, .{0.55, 0.8}}, [_]f32{1, -1}) |span, side| try runner(b, &sp, &rs, span, side);
  try k.along(b, start, spine);
  for (a.leaves, 0..) |n, ci| {
    const u = m.lerp(0.2, 0.78, (m.f(ci) + 0.5) / m.f(a.leaves.len));
    const s = b.mark();
    try cluster(b, &sp, &rs, u, n, if (ci % 2 == 0) 1 else -1, &rng);
    try k.on(b, s, spine, u, .{});
  }
  // where it breaks the ground, coming up and going down
  for (1..RES) |i| {
    const y0 = sp[i - 1][1];
    const y1 = sp[i][1];
    if ((y0 < 0) == (y1 < 0)) continue;
    const at = m.lerpV(sp[i - 1], sp[i], y0 / (y0 - y1));
    // away from the arch: back where it comes up, on where it goes down
    const away = m.norm(if (y1 > y0) sp[i - 1] - sp[i] else sp[i] - sp[i - 1]);
    const s = b.mark();
    try ground(b, at, m.norm(v3(away[0], 0, away[2])), a.core_r, y1 < y0, &rng);
    try k.on(b, s, spine, k.nearest(spine, at), .{.from = at});
  }
  return spine;
}

/// smaller roots wound over and under each other round the core, each set
/// turning its own way. A strand of one set passes outside a strand of the
/// other where they cross when its index and theirs sum even, inside when
/// odd: plain weave, from each strand's own place alone.
fn weave(b:*mg.Builder, a:Arch, sp:[]const V3, ts:[]const f32, rs:[]const f32, fn_:[]const V3, fb:[]const V3) Allocator.Error!void {
  const n = m.f(a.strands);
  const sr = STRAND_R * a.core_r / CORE_R;
  for (0..2) |set| for (0..a.strands) |i| {
    const sgn:f32 = if (set == 0) 1 else -1;
    // the second set sits halfway between the first
    const shift = if (set == 0) m.pi / n else 0;
    const start = (m.f(i) + 0.5 * m.f(set)) * m.tau / n;
    const parity:f32 = if (i % 2 == 0) 1 else -1;
    var path:[RES]V3 = undefined;
    var r:[RES]f32 = undefined;
    for (&path, &r, 0..) |*q, *rr, j| {
      const u = ts[j];
      const wind = a.turns * m.tau * u;
      const th = start + sgn * wind;
      // where the other set's strands lie here decides over or under
      const other = th + sgn * wind - shift;
      const off = rs[j] + sr * SINK + sgn * parity * sr * OVER * @cos(n * other / 2);
      q.* = sp[j] + (fn_[j] * m.splat3(@cos(th)) + fb[j] * m.splat3(@sin(th))) * m.splat3(off);
      // drawn to a point at both ends, under the soil
      rr.* = sr * (0.2 + 0.8 * m.smooth(m.clamp01(@min(u, 1 - u) / 0.1)));
    }
    const col = color.mix(pal.root_bark, pal.root_lite, if ((i + set) % 2 == 0) 0.25 else 0.7);
    try b.tubeR(&path, ts, &r, col, .stem, 5);
  };
}

/// a branchlet peeling off the weave beside the root (side 1 its left,
/// -1 its right) and winding back into it further on, pointed at both ends
fn runner(b:*mg.Builder, sp:[]const V3, rs:[]const f32, span:[2]f32, side:f32) Allocator.Error!void {
  var c:[6]V3 = undefined;
  for (&c, 0..) |*p, k| {
    const f = m.ratio(k, 5);
    const u = m.lerp(span[0], span[1], f);
    const at = m.alongPath(sp, u);
    const tan = tangent(sp, u);
    const out = m.norm(m.cross(v3(0, 1, 0), tan));
    const bulge = @sin(m.pi * f);
    const r = radiusAt(rs, u);
    p.* = at + out * m.splat3(side * (r + STRAND_R + RUNNER_OUT * bulge)) + v3(0, 0.6 * r + 0.012 * bulge, 0);
  }
  var p:[16]V3 = undefined;
  m.splineResample(&c, &p);
  var ts:[16]f32 = undefined;
  var r:[16]f32 = undefined;
  for (&ts, &r, 0..) |*t, *rr, j| {
    const f = m.ratio(j, 15);
    t.* = m.lerp(span[0], span[1], f);
    rr.* = RUNNER_R * (0.15 + 0.85 * @sin(m.pi * f));
  }
  try b.tubeR(&p, &ts, &r, pal.root_lite, .stem, 4);
}

/// a short twig off the top of the weave at `u`, bearing `n` leaves swept
/// forward along the root (splayed a little either side)
fn cluster(b:*mg.Builder, sp:[]const V3, rs:[]const f32, u:f32, n:u8, side:f32, rng:*Rng) Allocator.Error!void {
  const at = m.alongPath(sp, u);
  const tan = tangent(sp, u);
  const up = m.norm(v3(0, 1, 0) - tan * m.splat3(tan[1]));
  const flat = m.norm(v3(tan[0], 0, tan[2]));
  const out = m.norm(m.cross(v3(0, 1, 0), flat));
  const r = radiusAt(rs, u);
  const from = at + up * m.splat3(r + STRAND_R) + out * m.splat3(side * r * 0.4);
  const tip = from + m.norm(up + flat * m.splat3(0.9) + out * m.splat3(side * 0.3)) * m.splat3(TWIG_LEN);
  try b.tube(&.{from, tip}, &.{u, u}, RUNNER_R * 0.8, RUNNER_R * 0.45, pal.root_lite, .stem, 4);
  for (0..n) |l| {
    const a = (m.f(l) - 0.5 * m.f(n - 1)) * LEAF_SPLAY + side * 0.12 + rng.range(-0.08, 0.08);
    const dir = m.norm(flat * m.splat3(@cos(a)) + out * m.splat3(@sin(a)) + v3(0, LEAF_LIFT, 0));
    // the middle leaf of three the longest
    const len = LEAF_LEN * rng.range(0.85, 1.1) * (if (n == 3 and l == 1) @as(f32, 1.2) else 1);
    try mg.blade(b, tip, dir, len, LEAF_W, 0.4, pal.leaf_dark, pal.leaf_lite, u, .leaf);
  }
}

/// soil heaped where the root breaks the ground at `at`, clods round it,
/// and rootlets reaching on into the soil away from the arch. Where it
/// dives (`ahead`) it pushes a ridge of soil on before it, the way it
/// carries, as a mole's run does.
fn ground(b:*mg.Builder, at:V3, away:V3, r:f32, ahead:bool, rng:*Rng) Allocator.Error!void {
  const side = m.norm(m.cross(v3(0, 1, 0), away));
  const heaps:usize = if (ahead) RIDGE.len else 1;
  for (RIDGE[0..heaps]) |h| {
    const c = at + away * m.splat3(h[0] * r / CORE_R);
    const hr = h[1] * r / CORE_R;
    try mg.ellipsoid(b, .{.center = v3(c[0], -0.006, c[2]), .radii = v3(hr, hr * 0.6, hr), .col = pal.soil, .rings = 5, .segs = 9});
  }
  for (0..3) |k| {
    const a = m.f(k) * 2.1 + rng.range(-0.4, 0.4);
    const d = rng.range(0.06, 0.09);
    const p = at + (side * m.splat3(@cos(a)) + away * m.splat3(@sin(a))) * m.splat3(d);
    const cr = rng.range(0.011, 0.018);
    try mg.ellipsoid(b, .{.center = v3(p[0], 0.002, p[2]), .radii = v3(cr, cr * 0.7, cr * 1.1), .col = pal.soil_dark, .rings = 3, .segs = 5});
  }
  for ([_]f32{1, -1}, 0..) |sgn, k| {
    const dir = m.norm(away * m.splat3(0.5) + side * m.splat3(sgn * 0.8) + v3(0, -0.45, 0));
    try kit.rootlet(b, at + v3(0, r * 0.5, 0), dir, rng.range(0.12, 0.17), r * 0.32, rng.next() | k);
  }
}

/// the core's girth at `u` along it
fn radiusAt(rs:[]const f32, u:f32) f32 {
  const k = u * m.f(rs.len - 1);
  const i = @min(m.floorTo(usize, k), rs.len - 2);
  return m.lerp(rs[i], rs[i + 1], k - m.f(i));
}

fn tangent(sp:[]const V3, u:f32) V3 {
  return m.norm(m.alongPath(sp, @min(u + 0.02, 1)) - m.alongPath(sp, @max(u - 0.02, 0)));
}

/// mesh: CONDUIT TAP. a side root a conduit sends from under its middle
/// along +X to the plant on the next tile: woven as the conduit's own, it
/// comes up beside it, arches low over the ground and digs in at the
/// plant's foot, splitting into rootlets around it. It grows along its own
/// spline by how far it has reached (emitted with that as `grown`), the
/// rootlets last, and withers back down it.
pub const tap = struct {
  pub const REACH:f32 = 0.74;
  /// how much later each rootlet spreads than the one before
  const ROOTLET_STAGGER:f32 = 0.04;
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    var k = growth.Skeleton.begin(b);
    const spine = try arch(b, &k, .{.from = 0, .to = REACH, .peak = 0.1, .depth = 0.07, .core_r = 0.02, .strands = 2, .turns = 1.5, .core = .stem, .leaves = &.{2}, .runners = false, .seed = 0x7A9});
    const end = v3(REACH, -0.02, 0);
    for ([_]f32{-0.9, -0.1, 0.8}, 0..) |a, i| {
      const s = b.mark();
      try kit.rootlet(b, end, m.norm(v3(@cos(a) * 0.8, -0.45, @sin(a) * 0.8)), 0.24, 0.014, 0x7AA +% i * 29);
      try k.on(b, s, spine, 1, .{.from = end, .delay = ROOTLET_STAGGER * m.f(i)});
    }
    k.finish(b);
  }
};
