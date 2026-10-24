//! procedural mesh construction. No asset files: every plant is grown from its
//! species genome by composing a few primitives (tube, blade, cone).
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const m = @import("../core/math.zig");
const Rng = @import("../core/rng.zig").Rng;
const vertex = @import("vertex.zig");
const species = @import("../sim/species.zig");
const color = @import("../core/color.zig");
const noise = @import("../core/noise.zig");

const V3 = m.V3;
const PV = vertex.Mesh;
const MAX_SPINE = m.MAX_SPLINE;
pub const BLADE_SEGS = 8;
/// mesh variants grown per species, so neighbouring plants differ in shape.
pub const VARIANTS = 4;
const MAX_SIDES = 16;
const MAX_LOFT = 24;
/// most rows or columns a patch may have
const MAX_PATCH = 128;

/// levels of detail every mesh is built at: 0 full, then each level keeps
/// every other ring/row along a surface and half its sides around (see
/// `Builder.lod`), so far things draw with a fraction of the vertices.
pub const LODS = 3;
/// eye distance at which each level after the first takes over
pub const LOD_AT = [LODS - 1]f32{36, 70};

/// braids: the core's and each strand's share of the radius, how far out
/// the strands run (share of the radius), and the seed step between strands
pub const BRAID_CORE:f32 = 0.72;
pub const BRAID_STRAND:f32 = 0.26;
pub const BRAID_OFF:f32 = 0.8;
pub const STRAND_SALT = 7919;
/// a strand's wander: noise frequency along it, and how far its turn and
/// its distance out stray (per unit of wobble)
const STRAND_FREQ:f32 = 3;
const STRAND_TURN:f32 = 4;
const STRAND_SWELL:f32 = 3;

/// how far a braid strand (seeded `sd`) strays round the core at `u` along it.
pub fn strandTurn(sd:u64, u:f32, wobble:f32) f32 { return wobble * STRAND_TURN * noise.grad(sd, u * STRAND_FREQ, 0.5); }
/// how far out a braid strand runs at `u` along it, as a factor of its rest.
pub fn strandSwell(sd:u64, u:f32, wobble:f32) f32 { return 1 + wobble * STRAND_SWELL * noise.grad(sd, u * STRAND_FREQ, 7.5); }

/// the level of detail for something `dist` from the eye.
pub fn lodAt(dist:f32) u32 {
  var l:u32 = 0;
  for (LOD_AT) |d| {
    if (dist > d) l += 1;
  }
  return l;
}

/// indices 0, s, 2s, .. and always the last, for keeping every s-th of `n`
/// points along a surface (s = 1 keeps them all). Returns how many.
pub fn stride(n:usize, s:usize, out:[]usize) usize {
  var k:usize = 0;
  var i:usize = 0;
  while (i < n - 1) : (i += s) {
    out[k] = i;
    k += 1;
  }
  out[k] = n - 1;
  return k + 1;
}

pub const Builder = struct {
  gpa:Allocator,
  v:std.ArrayList(PV) = .empty,
  /// skin weights beside `v`, as far as the last skinned vertex (see `skinOf`)
  skin:std.ArrayList(vertex.Skin) = .empty,
  /// the level of detail being built (0 full): primitives keep every
  /// `step()`-th ring along their length and `around()` of their sides, the
  /// same way every time, so growth keys built at one level still match
  lod:u32 = 0,

  /// how many points along a surface to step over at this level
  pub fn step(b:*const Builder) usize { return @as(usize, 1) << @intCast(b.lod); }
  /// how many sides a ring keeps at this level (never fewer than `min`)
  pub fn around(b:*const Builder, sides:u32, min:u32) u32 { return @max(@min(sides, min), sides >> @intCast(b.lod)); }

  pub fn deinit(b:*Builder) void {
    b.v.deinit(b.gpa);
    b.skin.deinit(b.gpa);
  }

  /// the skin weights of every vertex since `start`, to be filled in
  /// (vertices before it without any are left unskinned)
  pub fn skinOf(b:*Builder, start:usize) Allocator.Error![]vertex.Skin {
    try b.skin.appendNTimes(b.gpa, .{}, b.v.items.len -| b.skin.items.len);
    return b.skin.items[start..b.v.items.len];
  }

  pub fn put(b:*Builder, p:V3, n:V3, col:color.Rgba8, t:f32, u:f32, part:vertex.Part) Allocator.Error!void {
    try b.v.append(b.gpa, .{.pos = p, .nrm = m.norm(n), .col = col, .tu = .{t, u}, .part = @intFromEnum(part)});
  }

  /// apply a transform to every vertex added since `start` (build in a unit
  /// space, then place/scale into the final part space).
  pub fn xform(b:*Builder, start:usize, mat:m.M4) void {
    const nm = m.inverse(mat); // normals use the inverse-transpose
    for (b.v.items[start..]) |*v| {
      const p = m.mulV(mat, .{v.pos[0], v.pos[1], v.pos[2], 1});
      v.pos = .{p[0], p[1], p[2]};
      const n:m.V3 = .{
        nm[0][0] * v.nrm[0] + nm[0][1] * v.nrm[1] + nm[0][2] * v.nrm[2],
        nm[1][0] * v.nrm[0] + nm[1][1] * v.nrm[1] + nm[1][2] * v.nrm[2],
        nm[2][0] * v.nrm[0] + nm[2][1] * v.nrm[1] + nm[2][2] * v.nrm[2],
      };
      v.nrm = m.norm(n);
    }
  }

  pub fn mark(b:*const Builder) usize { return b.v.items.len; }

  /// tube along a spine, `sides` facets, radius tapering from r0 to r1.
  pub fn tube(b:*Builder, spine:[]const V3, ts:[]const f32, r0:f32, r1:f32, col:color.Rgba8, part:vertex.Part, sides:u32) Allocator.Error!void {
    var radii:[MAX_SPINE]f32 = undefined;
    const last = m.f(spine.len - 1);
    for (0..spine.len) |i| radii[i] = m.lerp(r0, r1, m.f(i) / last);
    try b.tubeR(spine, ts, radii[0..spine.len], col, part, sides);
  }

  /// watertight tube: one ring per spine point, oriented by a frame carried
  /// smoothly along the curve (parallel transport) so consecutive segments
  /// share their rings exactly, with both ends capped.
  pub fn tubeR(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, col:color.Rgba8, part:vertex.Part, sides:u32) Allocator.Error!void {
    var cols:[MAX_SPINE]color.Rgba8 = undefined;
    @memset(cols[0..spine.len], col);
    try b.tubeC(spine, ts, radii, cols[0..spine.len], null, part, sides);
  }

  /// `tubeR` with a colour per ring (a gradient along the tube, shared rings
  /// so it never steps), and optionally `us[i]` written to tu.y.
  pub fn tubeC(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, cols:[]const color.Rgba8, us:?[]const f32, part:vertex.Part, full_sides:u32) Allocator.Error!void {
    assert(spine.len >= 2 and spine.len <= MAX_SPINE and full_sides <= MAX_SIDES and cols.len == spine.len);
    const sides = b.around(full_sides, 3);
    var rings:[MAX_SPINE][MAX_SIDES]V3 = undefined;
    var norms:[MAX_SPINE][MAX_SIDES]V3 = undefined;
    const n = spine.len;
    var fn_:[MAX_SPINE]V3 = undefined;
    var fb:[MAX_SPINE]V3 = undefined;
    transport(spine, fn_[0..n], fb[0..n]);
    for (0..n) |i| {
      for (0..sides) |k| {
        const a = m.ratio(k, sides) * m.tau;
        const dir = fn_[i] * m.splat3(@cos(a)) + fb[i] * m.splat3(@sin(a));
        norms[i][k] = dir;
        rings[i][k] = spine[i] + dir * m.splat3(radii[i]);
      }
    }
    // rings kept at this level of detail (the frames came from all of them)
    var keep:[MAX_SPINE]usize = undefined;
    const kn = stride(n, b.step(), &keep);
    for (0..kn - 1) |j| for (0..sides) |k| {
      const k1 = (k + 1) % sides;
      const q = [4]usize{k, k1, k1, k};
      const r = [4]usize{keep[j], keep[j], keep[j + 1], keep[j + 1]};
      for ([_]usize{0, 1, 2, 0, 2, 3}) |c| try b.put(rings[r[c]][q[c]], norms[r[c]][q[c]], cols[r[c]], ts[r[c]], uOf(us, r[c]), part);
    };
    // caps (skipped where the tube tapers to a point anyway)
    for ([_]usize{0, n - 1}) |i| {
      if (radii[i] < 1e-4) continue;
      const out = if (i == 0) m.norm(spine[0] - spine[1]) else m.norm(spine[n - 1] - spine[n - 2]);
      for (0..sides) |k| {
        const k1 = (k + 1) % sides;
        try b.put(spine[i], out, cols[i], ts[i], uOf(us, i), part);
        try b.put(rings[i][k], out, cols[i], ts[i], uOf(us, i), part);
        try b.put(rings[i][k1], out, cols[i], ts[i], uOf(us, i), part);
      }
    }
  }

  fn uOf(us:?[]const f32, i:usize) f32 { return if (us) |s| s[i] else 0; }

  /// curved blade (leaf/petal). `dir` horizontal outward, droops along its length.
  pub fn blade(b:*Builder, base:V3, dir:V3, len:f32, width:f32, droop:f32, col:color.Rgba8, tip:color.Rgba8, t:f32, part:vertex.Part) Allocator.Error!void {
    var cs:[BLADE_SEGS + 1]V3 = undefined;
    bladeSpine(&cs, base, dir, len, droop);
    try b.sheet(&cs, m.norm(m.cross(dir, m.v3(0, 1, 0))), width, col, tip, t, part);
  }

  /// a blade whose midrib follows the smooth spline through `path`, its
  /// width lying along `side`.
  pub fn bladeAlong(b:*Builder, path:[]const V3, side:V3, width:f32, col:color.Rgba8, tip:color.Rgba8, t:f32, part:vertex.Part) Allocator.Error!void {
    var cs:[BLADE_SEGS + 1]V3 = undefined;
    m.splineResample(path, &cs);
    try b.sheet(&cs, side, width, col, tip, t, part);
  }

  /// the leaf surface along a midrib: rows of (left, centre, right) shared
  /// between neighbouring quads, with one smooth normal per row so the leaf
  /// bends without seams or light breaks.
  fn sheet(b:*Builder, cs:*const [BLADE_SEGS + 1]V3, side:V3, width:f32, col:color.Rgba8, tip:color.Rgba8, t:f32, part:vertex.Part) Allocator.Error!void {
    const segs = BLADE_SEGS;
    var ws:[segs + 1]f32 = undefined;
    for (0..segs + 1) |i| {
      const k = m.f(i) / segs;
      ws[i] = width * @sin(k * m.pi) * (1 - 0.3 * k);
    }
    var ns:[segs + 1]V3 = undefined;
    for (0..segs + 1) |i| {
      const tan = cs[@min(i + 1, segs)] - cs[if (i == 0) 0 else i - 1];
      ns[i] = m.norm(m.cross(tan, side));
    }
    var keep:[segs + 1]usize = undefined;
    const kn = stride(segs + 1, b.step(), &keep);
    for (0..kn - 1) |j| {
      const i = keep[j];
      const ia = keep[j + 1];
      const k0 = m.f(i) / segs;
      const k1 = m.f(ia) / segs;
      // a slight raised midrib keeps the blade from reading as a flat card
      const rib0 = cs[i] + ns[i] * m.splat3(ws[i] * 0.25);
      const rib1 = cs[ia] + ns[ia] * m.splat3(ws[ia] * 0.25);
      const quads = [2][4]V3{
        .{cs[i] + side * m.splat3(ws[i]), rib0, rib1, cs[ia] + side * m.splat3(ws[ia])},
        .{rib0, cs[i] - side * m.splat3(ws[i]), cs[ia] - side * m.splat3(ws[ia]), rib1},
      };
      const c0 = color.mix(col, tip, k0);
      const c1 = color.mix(col, tip, k1);
      for (quads) |q| {
        const cols = [4]color.Rgba8{c0, c0, c1, c1};
        const kk = [4]f32{k0, k0, k1, k1};
        const nn = [4]V3{ns[i], ns[i], ns[ia], ns[ia]};
        for ([_]usize{0, 1, 2, 0, 2, 3}) |v| try b.put(q[v], nn[v], cols[v], t, kk[v], part);
      }
    }
  }

  pub fn cone(b:*Builder, base:V3, dir:V3, len:f32, r:f32, col:color.Rgba8, t:f32, part:vertex.Part) Allocator.Error!void {
    const side = m.norm(m.cross(dir, if (@abs(dir[1]) > 0.9) m.v3(1, 0, 0) else m.v3(0, 1, 0)));
    const up = m.cross(side, dir);
    const tip = base + dir * m.splat3(len);
    const sides = 4;
    for (0..sides) |i| {
      const a0 = m.f(i) / sides * m.tau;
      const a1 = m.f(i + 1) / sides * m.tau;
      const n0 = side * m.splat3(@cos(a0)) + up * m.splat3(@sin(a0));
      const n1 = side * m.splat3(@cos(a1)) + up * m.splat3(@sin(a1));
      try b.put(base + n0 * m.splat3(r), n0, col, t, 0, part);
      try b.put(base + n1 * m.splat3(r), n1, col, t, 0, part);
      try b.put(tip, dir, col, t, 1, part);
      // base cap so a cone never shows a hole when seen from below
      try b.put(base, -dir, col, t, 0, part);
      try b.put(base + n1 * m.splat3(r), -dir, col, t, 0, part);
      try b.put(base + n0 * m.splat3(r), -dir, col, t, 0, part);
    }
  }
};

/// the midrib of a drooping blade: out along `dir`, curving by `droop`.
pub fn bladeSpine(cs:*[BLADE_SEGS + 1]V3, base:V3, dir:V3, len:f32, droop:f32) void {
  for (cs, 0..) |*c, i| {
    const k = m.ratio(i, BLADE_SEGS);
    c.* = base + dir * m.splat3(len * k) + m.v3(0, len * (0.35 * k - droop * k * k), 0);
  }
}

/// a frame carried smoothly along a curve (parallel transport): for each
/// point a normal and binormal perpendicular to the local tangent, twisting
/// as little as possible, so rings built from it never shear or flip.
pub fn transport(spine:[]const V3, nrms:[]V3, bis:[]V3) void {
  const n = spine.len;
  const t0 = m.norm(spine[1] - spine[0]);
  var nrm = m.norm(m.cross(t0, if (@abs(t0[1]) > 0.9) m.v3(1, 0, 0) else m.v3(0, 1, 0)));
  for (0..n) |i| {
    // tangent: average of the neighbouring segments, so joints bisect the bend
    const tan = m.norm(spine[@min(i + 1, n - 1)] - spine[if (i == 0) 0 else i - 1]);
    // carry the normal along: remove its component along the new tangent
    nrm = m.norm(nrm - tan * m.splat3(m.dot(nrm, tan)));
    nrms[i] = nrm;
    bis[i] = m.cross(tan, nrm);
  }
}

/// how a vine grows: mostly along one direction, never quite straight.
pub const Growth = struct {
  start:V3,
  /// dominant growth direction (unit)
  direction:V3,
  length:f32,
  /// how much noise perturbs the path, relative to the control-point spacing
  wobble:f32 = 0.15,
  /// spiral around the growth axis: 0 none, 0.5 a tight tendril (two turns)
  curl:f32 = 0,
  /// tip radius relative to the base
  taper:f32 = 0.3,
  seed:u64 = 0,
};

/// perturb a control polyline the way a vine grows: wobble perpendicular to
/// `g.direction` and a curl around it, both easing off toward the tip. The
/// first point is the root and never moves. Deterministic in `g.seed`.
pub fn grow(pts:[]V3, g:Growth) void {
  const n = pts.len;
  const axis = g.direction;
  const up = m.norm(m.cross(axis, if (@abs(axis[1]) < 0.9) m.v3(0, 1, 0) else m.v3(1, 0, 0)));
  const side = m.norm(m.cross(axis, up));
  var rng = Rng.init(g.seed);
  const step = g.length / m.f(n - 1);
  for (pts[1..], 1..) |*p, i| {
    const t = m.ratio(i, n - 1);
    const w = g.wobble * step * (1 - 0.5 * t);
    p.* += side * m.splat3((rng.float() - 0.5) * w) + up * m.splat3((rng.float() - 0.5) * w);
    if (g.curl > 0) {
      const a = t * g.curl * 4 * m.tau;
      // the spiral widens out of the root and closes toward the tip
      const r = g.curl * 0.25 * g.length * m.smooth(@min(1, t * 4)) * (1 - t);
      p.* += side * m.splat3(@cos(a) * r) + up * m.splat3(@sin(a) * r);
    }
  }
}

/// control points for a grown vine, one per element of `out`.
pub fn growthPath(g:Growth, out:[]V3) void {
  for (out, 0..) |*p, i| p.* = g.start + g.direction * m.splat3(g.length * m.ratio(i, out.len - 1));
  grow(out, g);
}

/// radii tapering smoothly from `r0` at the base to `r0 * tip` at the end.
pub fn taperRadii(r0:f32, tip:f32, out:[]f32) void {
  for (out, 0..) |*r, i| r.* = r0 * (1 - m.ratio(i, out.len - 1) * (1 - tip));
}

/// a grown vine: `ctrl_n` control points from `g`, smoothed by Catmull-Rom
/// into `res` evenly spaced rings, tapering by `g.taper`, `t` from t0 to t1.
pub fn vine(b:*Builder, g:Growth, ctrl_n:usize, res:usize, r0:f32, col:color.Rgba8, part:vertex.Part, sides:u32, t0:f32, t1:f32) Allocator.Error!void {
  var ctrl:[MAX_SPINE]V3 = undefined;
  growthPath(g, ctrl[0..ctrl_n]);
  var path:[MAX_SPINE]V3 = undefined;
  m.splineResample(ctrl[0..ctrl_n], path[0..res]);
  var radii:[MAX_SPINE]f32 = undefined;
  taperRadii(r0, g.taper, radii[0..res]);
  var ts:[MAX_SPINE]f32 = undefined;
  for (ts[0..res], 0..) |*t, i| t.* = m.lerp(t0, t1, m.ratio(i, res - 1));
  try b.tubeR(path[0..res], ts[0..res], radii[0..res], col, part, sides);
}

/// a woven vine: a darker core along `spine` wrapped by `strands` helical
/// vines, `radii[i]` the bundle's radius at each point. `wobble` roughs the
/// strands' winding with smooth noise (0 = a perfect lathe-like helix).
pub fn braid(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, strands:u32, twist:f32, wobble:f32, seed:u64, core:color.Rgba8, strand:color.Rgba8) Allocator.Error!void {
  var turn:[MAX_SPINE]f32 = undefined;
  for (turn[0..spine.len], 0..) |*a, i| a.* = m.ratio(i, spine.len - 1) * twist;
  try braidTurned(b, spine, ts, radii, turn[0..spine.len], strands, wobble, seed, core, strand);
}

/// a braid whose strands have wound `turn[i]` radians around the core by
/// point i: winding fast spreads them into a loose diagonal weave, winding
/// slowly gathers them tight and nearly vertical.
pub fn braidTurned(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, turn:[]const f32, strands:u32, wobble:f32, seed:u64, core:color.Rgba8, strand:color.Rgba8) Allocator.Error!void {
  const n = spine.len;
  var fn_:[MAX_SPINE]V3 = undefined;
  var fb:[MAX_SPINE]V3 = undefined;
  transport(spine, fn_[0..n], fb[0..n]);
  var r:[MAX_SPINE]f32 = undefined;
  for (0..n) |i| r[i] = radii[i] * BRAID_CORE;
  try b.tubeR(spine, ts, r[0..n], core, .stem, 8);
  for (0..n) |i| r[i] = radii[i] * BRAID_STRAND;
  for (0..strands) |si| {
    const a0 = m.ratio(si, strands) * m.tau;
    const sd = seed +% si * STRAND_SALT;
    var path:[MAX_SPINE]V3 = undefined;
    for (0..n) |i| {
      const u = m.ratio(i, n - 1);
      // strands stay embedded in the core: the offset never leaves 0.8 +- 10%
      const a = a0 + turn[i] + strandTurn(sd, u, wobble);
      const off = radii[i] * BRAID_OFF * strandSwell(sd, u, wobble);
      path[i] = spine[i] + (fn_[i] * m.splat3(@cos(a)) + fb[i] * m.splat3(@sin(a))) * m.splat3(off);
    }
    try b.tubeR(path[0..n], ts, r[0..n], strand, .stem, 5);
  }
}

/// a tube along `spine` whose cross-section is `shape` (a closed curve over
/// 0..tau, roughly unit size, counter-clockwise when seen from the spine's
/// start) scaled by `widths`/`heights`, upright toward `up`. Rings are
/// shared and both ends capped, so it is watertight like `tubeR`.
pub fn loft(b:*Builder, spine:[]const V3, ts:[]const f32, widths:[]const f32, heights:[]const f32, up:V3, comptime shape:fn (f32) [2]f32, col:color.Rgba8, part:vertex.Part, full_sides:u32) Allocator.Error!void {
  assert(spine.len >= 2 and spine.len <= MAX_SPINE and full_sides <= MAX_LOFT);
  const sides = b.around(full_sides, 6);
  const n = spine.len;
  var rings:[MAX_SPINE][MAX_LOFT]V3 = undefined;
  var norms:[MAX_SPINE][MAX_LOFT]V3 = undefined;
  for (0..n) |i| {
    const tan = m.norm(spine[@min(i + 1, n - 1)] - spine[if (i == 0) 0 else i - 1]);
    const side = m.norm(m.cross(up, tan));
    const u = m.cross(tan, side);
    for (0..sides) |k| {
      const a = m.ratio(k, sides) * m.tau;
      const p = shape(a);
      // outward normal of the (scaled) section curve
      const e:f32 = 0.01;
      const p0 = shape(a - e);
      const p1 = shape(a + e);
      const dx = (p1[0] - p0[0]) * widths[i];
      const dy = (p1[1] - p0[1]) * heights[i];
      norms[i][k] = m.norm(side * m.splat3(dy) - u * m.splat3(dx));
      rings[i][k] = spine[i] + side * m.splat3(p[0] * widths[i]) + u * m.splat3(p[1] * heights[i]);
    }
  }
  var keep:[MAX_SPINE]usize = undefined;
  const kn = stride(n, b.step(), &keep);
  for (0..kn - 1) |j| for (0..sides) |k| {
    const k1 = (k + 1) % sides;
    const q = [4]usize{k, k1, k1, k};
    const r = [4]usize{keep[j], keep[j], keep[j + 1], keep[j + 1]};
    for ([_]usize{0, 1, 2, 0, 2, 3}) |c| try b.put(rings[r[c]][q[c]], norms[r[c]][q[c]], col, ts[r[c]], 0, part);
  };
  for ([_]usize{0, n - 1}) |i| {
    const out = if (i == 0) m.norm(spine[0] - spine[1]) else m.norm(spine[n - 1] - spine[n - 2]);
    for (0..sides) |k| {
      const k1 = (k + 1) % sides;
      try b.put(spine[i], out, col, ts[i], 0, part);
      try b.put(rings[i][k], out, col, ts[i], 0, part);
      try b.put(rings[i][k1], out, col, ts[i], 0, part);
    }
  }
}

/// a surface from a grid of `rows` x `cols` points (row-major), quads shared
/// between neighbours. Normals, colours and `us` (written to tu.y) are per point.
pub fn patch(b:*Builder, rows:usize, cols:usize, pts:[]const V3, nrms:[]const V3, cols_rgba:[]const color.Rgba8, us:[]const f32, t:f32, part:vertex.Part) Allocator.Error!void {
  assert(pts.len == rows * cols and nrms.len == pts.len and cols_rgba.len == pts.len and us.len == pts.len);
  // rows and columns kept at this level of detail
  var kr:[MAX_PATCH]usize = undefined;
  var kc:[MAX_PATCH]usize = undefined;
  const nr = stride(rows, b.step(), &kr);
  const nc = stride(cols, b.step(), &kc);
  for (0..nr - 1) |ri| for (0..nc - 1) |ci| {
    const r0 = kr[ri];
    const r1 = kr[ri + 1];
    const c0 = kc[ci];
    const c1 = kc[ci + 1];
    const q = [4]usize{r0 * cols + c0, r0 * cols + c1, r1 * cols + c1, r1 * cols + c0};
    for ([_]usize{0, 1, 2, 0, 2, 3}) |v| try b.put(pts[q[v]], nrms[q[v]], cols_rgba[q[v]], t, us[q[v]], part);
  };
}

pub const Petal = struct {
  base:V3,
  /// horizontal direction the petal faces out along (unit)
  out:V3,
  len:f32,
  /// widest half-width
  width:f32,
  /// angle above horizontal at the base, and how much it bends outward by
  /// the tip (a petal rises from the bloom's heart and flares open)
  rise:f32,
  flare:f32,
  /// how far its edges lift toward the bloom's heart (a cupped petal)
  cup:f32 = 0.4,
  col:color.Rgba8,
  tip:color.Rgba8,
  t:f32 = 1,
  part:vertex.Part = .bloom,
};

/// a flower petal: narrow at its claw, broadest past the middle and closing
/// in a rounded tip, cupped across its width, curving from upright at the
/// base to open at the tip. One shared-vertex sheet; tu.y runs base to tip.
pub fn petal(b:*Builder, p:Petal) Allocator.Error!void {
  const R = 7;
  const C = 5;
  const up = m.v3(0, 1, 0);
  const side = m.norm(m.cross(up, p.out));
  var spine:[R]V3 = undefined;
  var nrm:[R]V3 = undefined;
  spine[0] = p.base;
  for (0..R) |i| {
    const k = m.ratio(i, R - 1);
    const h = p.rise - p.flare * k * k;
    const dir = p.out * m.splat3(@cos(h)) + up * m.splat3(@sin(h));
    if (i > 0) spine[i] = spine[i - 1] + dir * m.splat3(p.len / (R - 1));
    // the face toward the bloom's heart and the sky
    nrm[i] = m.norm(m.cross(side, dir));
  }
  var pts:[R * C]V3 = undefined;
  var ns:[R * C]V3 = undefined;
  var cs:[R * C]color.Rgba8 = undefined;
  var us:[R * C]f32 = undefined;
  for (0..R) |i| {
    const k = m.ratio(i, R - 1);
    // obovate: zero at the claw, widest near two thirds, a rounded tip
    const w = p.width * @sqrt(@max(@sin(m.pi * m.pow(f32, k, 1.6)), 0));
    for (0..C) |j| {
      const u = m.ratio(j, C - 1) * 2 - 1;
      pts[i * C + j] = spine[i] + side * m.splat3(w * u) + nrm[i] * m.splat3(p.cup * w * u * u);
      cs[i * C + j] = color.mix(p.col, p.tip, k);
      us[i * C + j] = k;
    }
  }
  // normals from the sheet itself; where a row closes to a point (claw,
  // tip) the spine's face stands in
  for (0..R) |i| for (0..C) |j| {
    const dk = pts[@as(usize, @min(i + 1, R - 1)) * C + j] - pts[(if (i == 0) 0 else i - 1) * C + j];
    const du = pts[i * C + @min(j + 1, C - 1)] - pts[i * C + (if (j == 0) 0 else j - 1)];
    var n = m.cross(du, dk);
    if (m.len(n) < 1e-7) n = nrm[i];
    if (m.dot(n, nrm[i]) < 0) n = -n;
    ns[i * C + j] = m.norm(n);
  };
  try patch(b, R, C, &pts, &ns, &cs, &us, p.t, p.part);
}

/// grown vine bands wrapping over an ellipsoid (centre `at`, `radii`) along
/// its curvature: each band runs from (polar th0, azimuth ph0) to (th1, ph1).
/// `side` mirrors it in x, so left and right forms are built, not mirrored.
pub fn bands(b:*Builder, at:V3, radii:V3, arcs:[]const [4]f32, side:f32, r:f32, wobble:f32, seed:u64, col:color.Rgba8) Allocator.Error!void {
  for (arcs, 0..) |arc, i| {
    var ctrl:[6]V3 = undefined;
    for (&ctrl, 0..) |*c, j| {
      const k = m.ratio(j, ctrl.len - 1);
      const th = m.lerp(arc[0], arc[2], k);
      const ph = m.lerp(arc[1], arc[3], k);
      c.* = at + m.v3(@sin(th) * @cos(ph) * side, @cos(th), @sin(th) * @sin(ph)) * radii * m.splat3(1.03);
    }
    grow(&ctrl, .{
      .start = ctrl[0], .direction = m.norm(ctrl[ctrl.len - 1] - ctrl[0]), .length = m.len(ctrl[ctrl.len - 1] - ctrl[0]),
      .wobble = wobble, .curl = 0, .seed = seed +% i * 17,
    });
    var path:[16]V3 = undefined;
    m.splineResample(&ctrl, &path);
    var ts:[16]f32 = undefined;
    var rs:[16]f32 = undefined;
    for (&ts, &rs, 0..) |*t, *rr, j| {
      t.* = m.ratio(j, 15);
      // a grown vine: it tapers to a point at both ends, never cut off
      rr.* = @max(r * @sqrt(@sin(m.pi * t.*)), r * 0.05);
    }
    try b.tubeR(&path, &ts, &rs, col, .stem, 5);
  }
}

pub const Ellipsoid = struct {
  center:V3,
  radii:V3,
  col:color.Rgba8,
  part:vertex.Part = .stem,
  rings:u32 = 8,
  segs:u32 = 10,
  /// value written to tu.x (e.g. height along a body part)
  t:f32 = 0,
};

pub fn ellipsoid(b:*Builder, e:Ellipsoid) Allocator.Error!void {
  const R = b.around(e.rings, 3);
  const S = b.around(e.segs, 4);
  for (0..R) |ri| for (0..S) |si| {
    var q:[4]V3 = undefined;
    var n:[4]V3 = undefined;
    const corners = [4][2]u32{.{0, 0}, .{1, 0}, .{1, 1}, .{0, 1}};
    for (corners, 0..) |cn, k| {
      const th = m.ratio(ri + cn[0], R) * m.pi;
      const ph = m.ratio(si + cn[1], S) * m.tau;
      const u = m.v3(@sin(th) * @cos(ph), @cos(th), @sin(th) * @sin(ph));
      q[k] = e.center + u * e.radii;
      n[k] = u / e.radii;
    }
    for ([_]usize{0, 1, 2, 0, 2, 3}) |k| try b.put(q[k], n[k], e.col, e.t, 0, e.part);
  };
}

/// a woven bundle of vines along +Y from 0 to 1 (see `braid`).
/// `profile(k)` gives the bundle radius at height k.
pub fn bundle(b:*Builder, comptime profile:fn (f32) f32, strands:u32, twist:f32, wobble:f32, seed:u64, core:color.Rgba8, strand:color.Rgba8) Allocator.Error!void {
  const N = 18;
  var spine:[N + 1]V3 = undefined;
  var ts:[N + 1]f32 = undefined;
  var radii:[N + 1]f32 = undefined;
  for (0..N + 1) |i| {
    const k = m.f(i) / N;
    spine[i] = m.v3(0, k, 0);
    ts[i] = k;
    radii[i] = profile(k);
  }
  try braid(b, &spine, &ts, &radii, strands, twist, wobble, seed, core, strand);
}

/// grow one of a species' mesh variants from its genome. Deterministic per
/// (species, variant): the stem and tendrils are grown vines, so every
/// variant leans, wobbles and curls a little differently. A confluence's
/// variants are instead its growth keys (see `KEYS`).
pub fn plant(b:*Builder, id:species.Id, variant:u32) Allocator.Error!void {
  const def = species.get(id);
  const g = def.genome;
  const seed = @as(u64, @intFromEnum(id)) * 977 + 77;
  switch (g.form) {
    .herb => try herb(b, g, seed + @as(u64, variant) * 131, variant, !def.floating),
    .coil => try coil(b, g, seed + @as(u64, variant) * 131, variant),
    .drift => try drift(b, g, seed + @as(u64, variant) * 131, variant),
    .radiant => try radiant(b, g, seed + @as(u64, variant) * 131, variant),
    // a confluence's variants are its growth keys, all grown from one seed
    .confluence => try confluence(b, g, seed, m.ratio(variant, KEYS - 1)),
  }
}

fn herb(b:*Builder, g:species.Genome, seed:u64, variant:u32, rooted:bool) Allocator.Error!void {
  var rng = Rng.init(seed);
  const golden = 2.39996;

  // stem: a grown vine rising from the root, smoothed into evenly spaced
  // rings, flaring where it meets the ground so it grows out of the soil
  // rather than standing on it
  const RES = 32;
  const lean = m.v3(rng.range(-0.08, 0.08), 1, rng.range(-0.08, 0.08));
  const stem:Growth = .{
    .start = m.v3(0, 0, 0), .direction = m.norm(lean), .length = g.stem_h,
    .wobble = g.wobble, .curl = g.curl, .taper = 0.35, .seed = seed ^ 0x57E4,
  };
  var ctrl:[17]V3 = undefined;
  const cn = @as(usize, @max(@min(g.segments, 16), 3)) + 1;
  growthPath(stem, ctrl[0..cn]);
  var spine:[RES]V3 = undefined;
  m.splineResample(ctrl[0..cn], &spine);
  var ts:[RES]f32 = undefined;
  var radii:[RES]f32 = undefined;
  taperRadii(g.stem_r, stem.taper, &radii);
  for (&ts, &radii, 0..) |*t, *r, i| {
    const k = m.ratio(i, RES - 1);
    t.* = k;
    if (rooted) {
      const low = 1 - k;
      r.* *= 1 + 0.9 * low * low * low * low * low * low;
    }
  }
  try b.tubeR(&spine, &ts, &radii, g.stem_col.toRgba8(255), .stem, 6);

  // root flare: a few short roots splay from the foot into the soil
  if (rooted) for (0..3) |i| {
    const a = (m.f(i) + rng.float() * 0.6) / 3 * m.tau;
    const foot = m.v3(0, g.stem_h * 0.05, 0);
    const to = m.v3(@cos(a), 0, @sin(a)) * m.splat3(g.stem_r * 4.5) - m.v3(0, g.stem_r * 0.6, 0);
    try vine(b, .{
      .start = foot, .direction = m.norm(to - foot), .length = m.len(to - foot),
      .wobble = 0.2, .curl = 0, .taper = 0.2, .seed = seed +% i * 97,
    }, 4, 6, g.stem_r * 0.75, g.stem_col.toRgba8(255), .stem, 4, 0.02, 0);
  };

  // leaves in a phyllotactic spiral up the stem, all on one envelope: the
  // lowest longest and drooping most, rising and shortening toward the
  // crown, their bases tucked into the stem
  const from = g.leaf_from;
  for (0..g.leaves) |i| {
    const k = from + (0.92 - from) * m.ratio(i, @max(g.leaves, 1));
    const up = m.ratio(i, @max(g.leaves, 1));
    const at = m.alongPath(&spine, k);
    const ang = m.f(i) * golden + m.f(variant);
    const dir = m.norm(m.v3(@cos(ang), 0.15 + 0.45 * up, @sin(ang)));
    const len = g.leaf_len * m.lerp(1.25, 0.55, up) * rng.range(0.93, 1.07);
    const droop = g.leaf_droop * m.lerp(1.3, 0.6, up);
    const base = at - m.v3(@cos(ang), 0, @sin(ang)) * m.splat3(g.stem_r * 0.4);
    try b.blade(base, dir, len, g.leaf_w * m.lerp(1.1, 0.8, up), droop, color.shade(g.leaf_col, 0.6), g.leaf_col.toRgba8(255), k, .leaf);
  }

  // thorns: small, short, pressed to the stem
  for (0..g.thorns) |i| {
    const k = 0.15 + 0.7 * rng.float();
    const at = m.alongPath(&spine, k);
    const ang = m.f(i) * golden * 1.3;
    const dir = m.norm(m.v3(@cos(ang), 0.4, @sin(ang)));
    try b.cone(at, dir, 0.045, 0.01, color.shade(g.bloom_col, 0.7), k, .thorn);
  }

  // tendrils: rooted plants put down prop roots from low on the stem, close
  // around the foot; a floater trails them beneath it. Both grow small
  // leaves along their length, like any vine.
  const start = m.alongPath(&spine, if (rooted) 0.2 else 0.35);
  for (0..g.tendrils) |i| {
    const ang = m.ratio(i, g.tendrils) * m.tau + 0.4 + 0.3 * m.f(variant);
    const spread:f32 = if (rooted) g.stem_r * 3 + g.stem_h * 0.12 else 0.35;
    const reach = m.v3(@cos(ang) * spread, -start[1] * 0.98, @sin(ang) * spread);
    var tc:[7]V3 = undefined;
    growthPath(.{
      .start = start, .direction = m.norm(reach), .length = m.len(reach),
      .wobble = g.tendril_wobble, .curl = g.tendril_curl, .seed = seed +% i * 31,
    }, &tc);
    var tp:[20]V3 = undefined;
    m.splineResample(&tc, &tp);
    var tt:[20]f32 = undefined;
    var tr:[20]f32 = undefined;
    const t0:f32 = if (rooted) 0.2 else 0.35;
    const t1:f32 = if (rooted) 0.05 else 1;
    taperRadii(if (rooted) g.stem_r * 0.4 else 0.014, 0.3, &tr);
    for (&tt, 0..) |*t, j| t.* = m.lerp(t0, t1, m.ratio(j, 19));
    try b.tubeR(&tp, &tt, &tr, g.stem_col.toRgba8(255), .tendril, 4);
    try leavesAlong(b, &tp, 3, g.leaf_len * 0.4, g.leaf_w * 0.55, 0.12, 0.6, t0, t1, color.shade(g.leaf_col, 0.6), g.leaf_col.toRgba8(255), seed +% i * 13);
  }

  // offshoots: side stems leaving the main one between the leaves, each
  // curving up to the light and ending in a bud or a small bloom
  const shoot_r = g.stem_r * 0.5;
  // (below a tree's crown too: they branch from the trunk)
  const shoot_from = @max(from * 0.6, 0.3);
  var srng = Rng.init(seed ^ 0x0FF5);
  const shoots = shootCount(g, &srng);
  for (0..shoots) |i| {
    const k = m.lerp(shoot_from, 0.85, (m.f(i) + srng.range(0.2, 0.8)) / m.f(shoots));
    const ang = m.f(i) * golden * 1.7 + 1.1 + m.f(variant) * 0.9 + srng.range(-0.3, 0.3);
    const len = g.stem_h * srng.range(0.32, 0.46) * m.lerp(1.15, 0.75, k);
    const tip = try offshoot(b, &spine, k, k, ang, len, shoot_r, srng.range(0.3, 0.6), g.stem_col.toRgba8(255), .stem, seed +% i * 211);
    try leavesAlong(b, tip.path[0..], 2, g.leaf_len * 0.45, g.leaf_w * 0.6, 0.25, 0.7, tip.t0, tip.t1, color.shade(g.leaf_col, 0.6), g.leaf_col.toRgba8(255), seed +% i * 59);
    shootFoldAlong(b, tip.leaves, &tip.path);
    const s = b.mark();
    if (srng.float() < 0.5)
      try flower(b, g, tip.at, tip.axis, srng.range(0.55, 0.7), m.f(variant) + m.f(i), tip.t1)
    else
      try bud(b, g, tip.at, tip.axis, srng.range(0.65, 0.85), m.f(i) * 1.3, tip.t1);
    shootFold(b, s, 1);
  }

  // bloom: a calyx swelling at the tip with sepals folded back beneath it,
  // and the petals rising from it into a cup
  try flower(b, g, spine[RES - 1], m.norm(spine[RES - 1] - spine[RES - 4]), 1, m.f(variant), 1);
}

/// how many offshoots a variant grows, between the genome's two counts.
fn shootCount(g:species.Genome, rng:*Rng) u32 {
  const lo = g.shoots[0];
  const hi = @max(g.shoots[1], lo);
  return lo + rng.below(hi - lo + 1);
}

/// where an offshoot ends: its tip and heading, its smoothed path, its
/// tu.x at the stem and the tip, and the first vertex after its stem
/// (for whatever grows along it).
const Shoot = struct { at:V3, axis:V3, path:[16]V3, t0:f32, t1:f32, leaves:usize };

/// an offshoot: a side stem grown from `k` along `spine`, leaving it toward
/// bearing `ang` at elevation `rise` and curving up toward the light as it
/// goes, tapering but never to nothing (a bud or bloom sits on its tip).
/// Its root is inside the main stem, at that stem's tu.x there (`t0`), so the two bend
/// alike; each ring is marked for `shootFold` by how far out it is.
pub fn offshoot(b:*Builder, spine:[]const V3, k:f32, t0:f32, ang:f32, len:f32, r0:f32, rise:f32, col:color.Rgba8, part:vertex.Part, seed:u64) Allocator.Error!Shoot {
  const N = 8;
  const RES = 16;
  const root = m.alongPath(spine, k);
  const out = m.v3(@cos(ang), 0, @sin(ang));
  var ctrl:[N]V3 = undefined;
  ctrl[0] = root;
  for (1..N) |j| {
    const s = m.ratio(j, N - 1);
    // heading turns from `rise` toward upright, mostly in its outer half
    const h = m.lerp(rise, 1.35, s * s);
    ctrl[j] = ctrl[j - 1] + (out * m.splat3(@cos(h)) + m.v3(0, @sin(h), 0)) * m.splat3(len / (N - 1));
  }
  grow(&ctrl, .{.start = root, .direction = m.norm(ctrl[N - 1] - root), .length = len, .wobble = 0.12, .curl = 0.03, .seed = seed});
  var sh:Shoot = .{.at = undefined, .axis = undefined, .path = undefined, .t0 = t0, .t1 = @min(t0 + 0.15 + len * 0.2, 1), .leaves = 0};
  m.splineResample(&ctrl, &sh.path);
  var ts:[RES]f32 = undefined;
  var rs:[RES]f32 = undefined;
  var cs:[RES]color.Rgba8 = undefined;
  for (&ts, &rs, &cs, 0..) |*t, *r, *c, j| {
    const s = m.ratio(j, RES - 1);
    t.* = m.lerp(sh.t0, sh.t1, s);
    r.* = r0 * m.lerp(1, 0.55, s);
    c.* = col;
    c.a = m.unorm8(1 - s);
  }
  try b.tubeC(&sh.path, &ts, &rs, &cs, null, part, 5);
  sh.at = sh.path[RES - 1];
  sh.axis = m.norm(sh.path[RES - 1] - sh.path[RES - 4]);
  sh.leaves = b.mark();
  return sh;
}

/// mark every vertex since `start` as `w` of the way out along an offshoot
/// (colour alpha 1 - w; 1 everywhere else): until growth reaches it,
/// plant.vert folds an offshoot in against its stem by that much, so it
/// grows out of the stem, a bloom on it opening as it goes.
pub fn shootFold(b:*Builder, start:usize, w:f32) void {
  shootFoldRange(b, start, b.v.items.len, w);
}

/// `shootFold` for what grows along an offshoot (its leaves): each vertex
/// takes the weight of the point of `path` it grows from, so a leaf folds
/// in with the stem beneath it.
pub fn shootFoldAlong(b:*Builder, start:usize, path:[]const V3) void {
  var s = start;
  while (s < b.v.items.len) {
    // the vertices of one leaf share its tu.x; weigh them by its base (tu.y 0)
    var e = s;
    var base = b.v.items[s].pos;
    while (e < b.v.items.len and b.v.items[e].tu[0] == b.v.items[s].tu[0]) : (e += 1) {
      if (b.v.items[e].tu[1] < 1e-4) base = b.v.items[e].pos;
    }
    var best:usize = 0;
    for (path, 0..) |p, j| {
      if (m.len(p - base) < m.len(path[best] - base)) best = j;
    }
    shootFoldRange(b, s, e, m.ratio(best, path.len - 1));
    s = e;
  }
}

fn shootFoldRange(b:*Builder, start:usize, end:usize, w:f32) void {
  for (b.v.items[start..end]) |*v| v.col.a = m.unorm8(1 - w);
}

/// a bloom at `top` heading along `axis`, `sc` the size of the species'
/// own: a calyx swelling at the tip with sepals folded back beneath it, and
/// two overlapping whorls of petals rising from it into a cup.
fn flower(b:*Builder, g:species.Genome, top:V3, axis:V3, sc:f32, spin:f32, t:f32) Allocator.Error!void {
  const calyx = (g.bloom_r * 0.12 + g.stem_r * 0.6) * sc;
  try ellipsoid(b, .{
    .center = top + axis * m.splat3(calyx * 0.4), .radii = m.v3(calyx, calyx * 0.85, calyx),
    .col = g.stem_col.toRgba8(255), .part = .stem, .rings = 6, .segs = 8, .t = t,
  });
  for (0..4) |i| {
    const a = (m.f(i) + 0.5) / 4 * m.tau + spin;
    try b.blade(top, m.norm(m.v3(@cos(a), -0.1, @sin(a))), g.bloom_r * 0.55 * sc, g.bloom_r * 0.22 * sc, 0.5, color.shade(g.leaf_col, 0.55), g.leaf_col.toRgba8(255), t - 0.03, .leaf);
  }
  // broad outer petals opening out, a smaller inner ring standing more
  // upright between them
  const heart = top + axis * m.splat3(calyx * 0.5);
  const inner = @max(g.petals / 2, 3);
  for (0..g.petals + inner) |i| {
    const outer = i < g.petals;
    const ang = if (outer) m.ratio(i, g.petals) * m.tau else (m.f(i - g.petals) + 0.5) / m.f(inner) * m.tau;
    try petal(b, .{
      .base = heart, .out = m.v3(@cos(ang + spin * 0.37), 0, @sin(ang + spin * 0.37)),
      .len = g.bloom_r * sc * (if (outer) @as(f32, 1) else 0.72),
      .width = g.bloom_r * sc * (if (outer) @as(f32, 0.62) else 0.5),
      .rise = if (outer) 0.8 else 1.2, .flare = if (outer) 0.95 else 0.55, .cup = if (outer) 0.35 else 0.5,
      .col = color.shade(g.bloom_col, 0.8), .tip = g.bloom_col.toRgba8(255), .t = t,
    });
  }
}

/// a closed bud at `top`: a calyx, sepals clasping up around it, and the
/// petals folded over one another into a teardrop round a coloured heart.
fn bud(b:*Builder, g:species.Genome, top:V3, axis:V3, sc:f32, spin:f32, t:f32) Allocator.Error!void {
  const calyx = (g.bloom_r * 0.12 + g.stem_r * 0.6) * sc;
  const len = g.bloom_r * 0.6 * sc;
  try ellipsoid(b, .{
    .center = top + axis * m.splat3(calyx * 0.4), .radii = m.v3(calyx, calyx * 0.85, calyx),
    .col = g.stem_col.toRgba8(255), .part = .stem, .rings = 6, .segs = 8, .t = t,
  });
  const heart = top + axis * m.splat3(calyx * 0.5);
  try ellipsoid(b, .{
    .center = heart + axis * m.splat3(len * 0.42), .radii = m.v3(len * 0.22, len * 0.45, len * 0.22),
    .col = color.shade(g.bloom_col, 0.75), .part = .bloom, .rings = 6, .segs = 8, .t = t,
  });
  const n = @max(g.petals / 2 + 2, 4);
  for (0..n) |i| {
    const a = m.ratio(i, n) * m.tau + spin;
    try petal(b, .{
      .base = heart, .out = m.v3(@cos(a), 0, @sin(a)),
      .len = len, .width = len * 0.5,
      // past upright by the tip: the petals close over the heart
      .rise = 1.3, .flare = -0.55, .cup = 0.7,
      .col = color.shade(g.bloom_col, 0.7), .tip = g.bloom_col.toRgba8(255), .t = t,
    });
  }
  for (0..3) |i| {
    const a = (m.f(i) + 0.5) / 3 * m.tau + spin;
    try b.blade(top, m.norm(m.v3(@cos(a), 1.5, @sin(a))), len * 0.7, len * 0.22, 0.05, color.shade(g.leaf_col, 0.55), g.leaf_col.toRgba8(255), t - 0.03, .leaf);
  }
}

/// `n` small leaves grown along a vine between fractions `k0`..`k1` of
/// `path`: turning around it leaf by leaf, lifting toward the light, smaller
/// toward the tip. `t0`..`t1` is the vine's tu.x over its length.
pub fn leavesAlong(b:*Builder, path:[]const V3, n:u32, len:f32, width:f32, k0:f32, k1:f32, t0:f32, t1:f32, col:color.Rgba8, tip:color.Rgba8, seed:u64) Allocator.Error!void {
  var rng = Rng.init(seed);
  for (0..n) |i| {
    const k = m.lerp(k0, k1, (m.f(i) + 0.5) / m.f(n));
    const at = m.alongPath(path, k);
    const tan = m.norm(m.alongPath(path, @min(k + 0.03, 1)) - m.alongPath(path, @max(k - 0.03, 0)));
    const ref = if (@abs(tan[1]) > 0.9) m.v3(1, 0, 0) else m.v3(0, 1, 0);
    const s1 = m.norm(m.cross(tan, ref));
    const s2 = m.cross(tan, s1);
    const a = m.f(i) * 2.4 + rng.range(-0.3, 0.3) + m.f(seed % 7);
    var out = s1 * m.splat3(@cos(a)) + s2 * m.splat3(@sin(a)) + m.v3(0, 0.5, 0) + tan * m.splat3(0.3);
    // a blade needs some sideways lean to find its width
    out[1] = m.clamp(out[1], -0.6, 0.7);
    out = m.norm(out);
    const l = len * m.lerp(1, 0.6, k) * rng.range(0.85, 1.15);
    try b.blade(at, out, l, width * m.lerp(1, 0.7, k), 0.35, col, tip, m.lerp(t0, t1, k), .leaf);
  }
}

/// a parasite's body: alien rather than hostile. A ribbed, twisted stalk on
/// a bulbous foot half sunk in the soil, translucent bladders clinging up
/// it, and a crown of fronds that arc out and curl into spirals at their
/// tips around a bulb at its heart. No leaves, no spikes.
fn coil(b:*Builder, g:species.Genome, seed:u64, variant:u32) Allocator.Error!void {
  var rng = Rng.init(seed);
  const golden = 2.39996;
  const core = color.shade(g.stem_col, 0.7);
  const skin = g.stem_col.toRgba8(255);

  // the stalk: three strands wound tight, swelling into its foot
  const RES = 20;
  const lean = m.v3(rng.range(-0.1, 0.1), 1, rng.range(-0.1, 0.1));
  var ctrl:[8]V3 = undefined;
  growthPath(.{.start = m.v3(0, 0, 0), .direction = m.norm(lean), .length = g.stem_h, .wobble = g.wobble, .curl = g.curl, .seed = seed ^ 0x57E4}, &ctrl);
  var spine:[RES]V3 = undefined;
  m.splineResample(&ctrl, &spine);
  var ts:[RES]f32 = undefined;
  var radii:[RES]f32 = undefined;
  for (&ts, &radii, 0..) |*t, *r, i| {
    const k = m.ratio(i, RES - 1);
    t.* = k * 0.85;
    const low = 1 - k;
    r.* = g.stem_r * 1.2 * m.lerp(1, 0.6, k) * (1 + 0.9 * low * low * low * low * low);
  }
  try braid(b, &spine, &ts, &radii, 3, 4.5 + m.f(variant) * 0.3, 0.05, seed, core, skin);
  try ellipsoid(b, .{
    .center = m.v3(0, g.stem_r * 0.3, 0), .radii = m.v3(g.stem_r * 2.1, g.stem_r * 1.1, g.stem_r * 2.1),
    .col = skin, .part = .stem, .rings = 6, .segs = 10, .t = 0,
  });

  // bladders: translucent bulbs clinging up the stalk, smaller higher up
  for (0..g.thorns) |i| {
    const k = 0.45 + 0.38 * m.ratio(i, @max(g.thorns, 1));
    const at = m.alongPath(&spine, k);
    const ang = m.f(i) * golden + m.f(variant);
    const out = m.v3(@cos(ang), 0, @sin(ang));
    const r = g.stem_r * m.lerp(1.0, 0.65, k) * rng.range(0.85, 1.15);
    const ri = g.stem_r * 1.2 * m.lerp(1, 0.6, k);
    try ellipsoid(b, .{
      .center = at + out * m.splat3(ri + r * 0.5), .radii = m.v3(r, r * 1.3, r),
      .col = g.bloom_col.toRgba8(255), .part = .bloom, .rings = 4, .segs = 6, .t = k,
    });
  }

  // offshoots: thin stalks peeling off the main one, each holding
  // up a bladder, bare and clasped shut by curled fronds (a bud) or
  // crowned by a small ring of them opening (a bloom)
  var srng = Rng.init(seed ^ 0x0FF5);
  const shoots = shootCount(g, &srng);
  for (0..shoots) |i| {
    const k = m.lerp(0.3, 0.75, (m.f(i) + srng.range(0.2, 0.8)) / m.f(shoots));
    const ang = m.f(i) * golden * 1.7 + 0.6 + m.f(variant) * 1.3 + srng.range(-0.3, 0.3);
    const len = g.stem_h * srng.range(0.35, 0.55);
    const tip = try offshoot(b, &spine, k, k * 0.85, ang, len, g.stem_r * 0.55, srng.range(0.25, 0.6), skin, .stem, seed +% i * 211);
    const s = b.mark();
    const r = g.bloom_r * srng.range(0.55, 0.75);
    const open = srng.float() < 0.5;
    try ellipsoid(b, .{
      .center = tip.at + tip.axis * m.splat3(r * 0.9), .radii = m.v3(r * 0.8, r * 1.15, r * 0.8),
      .col = g.bloom_col.toRgba8(255), .part = .bloom, .rings = 6, .segs = 8, .t = tip.t1,
    });
    const fronds:u32 = if (open) 5 else 3;
    for (0..fronds) |j| {
      const a = m.ratio(j, fronds) * m.tau + srng.range(-0.3, 0.3);
      const out = m.v3(@cos(a), 0, @sin(a));
      if (open) {
        // a little crown, rising and curling out like the main one
        try frond(b, tip.at + tip.axis * m.splat3(r * 1.6), out, len * 0.5, g.stem_r * 0.45, 1.25, 5.2, tip.t1, g.leaf_col.toRgba8(255), seed +% i * 71 +% j * 13);
      } else {
        // clasping the bladder: up its flank, curling in over its crown
        try frond(b, tip.at + out * m.splat3(r * 0.55), out, r * 2.6, g.stem_r * 0.4, 1.15, -2.3, tip.t1, g.leaf_col.toRgba8(255), seed +% i * 71 +% j * 13);
      }
    }
    shootFold(b, s, 1);
  }

  // the crown: fronds whose heading turns ever faster toward the tip, so
  // they rise, arc out and curl inward like unfurling ferns
  const top = spine[RES - 1];
  for (0..g.tendrils) |i| {
    const ang = m.ratio(i, g.tendrils) * m.tau + rng.range(-0.3, 0.3);
    const len = g.stem_h * 0.6 * rng.range(0.85, 1.15);
    try frond(b, top, m.v3(@cos(ang), 0, @sin(ang)), len, g.stem_r * 0.85, 1.25, 5.2, 0.85, g.leaf_col.toRgba8(255), seed +% i * 31);
  }

  // a bulb at the heart of the crown
  try ellipsoid(b, .{
    .center = top + m.v3(0, g.bloom_r * 0.5, 0), .radii = m.v3(g.bloom_r, g.bloom_r * 1.25, g.bloom_r),
    .col = g.bloom_col.toRgba8(255), .part = .bloom, .rings = 7, .segs = 9, .t = 1,
  });
}

/// a parasite's frond from `from` out along `out`: its heading starts at
/// `rise` and turns ever faster (by `curl` at its tip), so it rises, arcs
/// out and curls inward like an unfurling fern; tu.x from `t0` to 1.
fn frond(b:*Builder, from:V3, out:V3, len:f32, r:f32, rise:f32, curl:f32, t0:f32, col:color.Rgba8, seed:u64) Allocator.Error!void {
  const N = 12;
  var pts:[N]V3 = undefined;
  pts[0] = from;
  for (1..N) |j| {
    const s = m.ratio(j, N - 1);
    const heading = rise - s * s * curl;
    const step = len / (N - 1) * (1 - 0.55 * s);
    pts[j] = pts[j - 1] + (out * m.splat3(@cos(heading)) + m.v3(0, @sin(heading), 0)) * m.splat3(step);
  }
  grow(&pts, .{.start = from, .direction = m.norm(pts[N - 1] - from), .length = len, .wobble = 0.08, .seed = seed});
  var path:[14]V3 = undefined;
  m.splineResample(&pts, &path);
  var pt:[14]f32 = undefined;
  var pr:[14]f32 = undefined;
  for (&pt, &pr, 0..) |*t, *rr, j| {
    const k = m.ratio(j, 13);
    t.* = m.lerp(t0, 1, k);
    rr.* = r * m.lerp(1, 0.35, k);
  }
  try b.tubeR(&path, &pt, &pr, col, .tendril, 4);
}

/// a floater: nothing reaches the ground. A translucent sap float holds it
/// up; above it a short neck lifts a wide catcher dish open to the sky (it
/// drinks starlight); beneath it long filaments trail down toward the
/// ground, swaying most at their tips, so it hangs in the air rather than
/// standing on it. The origin is the float's centre.
fn drift(b:*Builder, g:species.Genome, seed:u64, variant:u32) Allocator.Error!void {
  var rng = Rng.init(seed);
  const float_r = g.bloom_r * 0.62;

  // the float
  try ellipsoid(b, .{
    .center = m.v3(0, 0, 0), .radii = m.v3(float_r, float_r * 0.8, float_r),
    .col = color.shade(g.bloom_col, 0.85), .part = .bloom, .rings = 7, .segs = 10, .t = 0.5,
  });

  // the neck and the catcher dish: two whorls opening wide and shallow
  const neck = m.v3(rng.range(-0.02, 0.02), float_r * 0.7 + g.stem_h, rng.range(-0.02, 0.02));
  var nc:[4]V3 = undefined;
  growthPath(.{.start = m.v3(0, float_r * 0.5, 0), .direction = m.norm(neck - m.v3(0, float_r * 0.5, 0)), .length = m.len(neck - m.v3(0, float_r * 0.5, 0)), .wobble = g.wobble, .seed = seed ^ 0x57E4}, &nc);
  var np:[8]V3 = undefined;
  m.splineResample(&nc, &np);
  var nt:[8]f32 = undefined;
  var nr:[8]f32 = undefined;
  for (&nt, &nr, 0..) |*t, *r, i| {
    const k = m.ratio(i, 7);
    t.* = m.lerp(0.55, 0.9, k);
    r.* = g.stem_r * m.lerp(1.3, 0.8, k);
  }
  try b.tubeR(&np, &nt, &nr, g.stem_col.toRgba8(255), .stem, 6);
  const inner = @max(g.petals / 2, 3);
  for (0..g.petals + inner) |i| {
    const outer = i < g.petals;
    const ang = if (outer) m.ratio(i, g.petals) * m.tau + m.f(variant) else (m.f(i - g.petals) + 0.5) / m.f(inner) * m.tau;
    try petal(b, .{
      .base = np[7], .out = m.v3(@cos(ang), 0, @sin(ang)),
      .len = g.bloom_r * (if (outer) @as(f32, 1) else 0.6),
      .width = g.bloom_r * (if (outer) @as(f32, 0.5) else 0.42),
      .rise = if (outer) 0.55 else 1.0, .flare = if (outer) 0.35 else 0.4, .cup = 0.45,
      .col = color.shade(g.bloom_col, 0.8), .tip = g.bloom_col.toRgba8(255),
    });
  }

  // offshoots: slender stalks leaning out of the neck beneath the dish,
  // each lifting a bud or a small bloom of its own to the sky
  var srng = Rng.init(seed ^ 0x0FF5);
  const shoots = shootCount(g, &srng);
  for (0..shoots) |i| {
    const k = srng.range(0.05, 0.45);
    const ang = m.ratio(i, @max(shoots, 1)) * m.tau + 0.5 + m.f(variant) * 1.1 + srng.range(-0.4, 0.4);
    const len = g.bloom_r * srng.range(1.0, 1.5);
    const tip = try offshoot(b, &np, k, m.lerp(0.55, 0.9, k), ang, len, g.stem_r * 0.6, srng.range(0.15, 0.45), g.stem_col.toRgba8(255), .stem, seed +% i * 211);
    const s = b.mark();
    if (srng.float() < 0.5)
      try flower(b, g, tip.at, tip.axis, srng.range(0.35, 0.45), m.f(i) * 2.1, tip.t1)
    else
      try bud(b, g, tip.at, tip.axis, srng.range(0.4, 0.55), m.f(i) * 1.3, tip.t1);
    shootFold(b, s, 1);
  }

  // trailing filaments from the underside of the float
  for (0..g.tendrils) |i| {
    const a = m.ratio(i, g.tendrils) * m.tau + rng.range(-0.25, 0.25);
    const from = m.v3(@cos(a) * float_r * 0.55, -float_r * 0.5, @sin(a) * float_r * 0.55);
    const len = rng.range(0.55, 0.9);
    const to = from + m.v3(@cos(a) * 0.12, -len, @sin(a) * 0.12);
    var fc:[6]V3 = undefined;
    growthPath(.{.start = from, .direction = m.norm(to - from), .length = m.len(to - from), .wobble = g.tendril_wobble, .curl = g.tendril_curl, .seed = seed +% i * 31}, &fc);
    var fp:[16]V3 = undefined;
    m.splineResample(&fc, &fp);
    var ft:[16]f32 = undefined;
    var fr:[16]f32 = undefined;
    for (&ft, &fr, 0..) |*t, *r, j| {
      const k = m.ratio(j, 15);
      // tu.x rises toward the tips so they sway most, like a pendulum
      t.* = m.lerp(0.3, 1, k);
      r.* = g.stem_r * m.lerp(0.55, 0.12, k);
    }
    try b.tubeR(&fp, &ft, &fr, g.leaf_col.toRgba8(255), .tendril, 4);
  }
}

/// a celestial bloom: a flower whose petals are not joined to it. A small
/// luminous core with a crown of stamens holds three whorls of petals
/// floating free around it (an upright inner cup, a middle whorl, an outer
/// one opening wide), each bound to the core by a thread of light, and
/// motes of light spiralling in to it; a thin tilted halo rings it all.
/// Each fragment is rigid and carries, for plant.vert: tu.x its assembly
/// order (0 the core .. 1 the last to arrive), tu.y its ring (`Ring`; a
/// thread adds how far it is from its petal, so its core end stays put
/// while the rest follows the petal) and colour alpha its bearing around
/// the core. The origin is the core.
fn radiant(b:*Builder, g:species.Genome, seed:u64, variant:u32) Allocator.Error!void {
  var rng = Rng.init(seed);
  const body = g.stem_col.toRgba8(255);
  const lite = g.bloom_col.toRgba8(255);
  // petals pale toward their tips, where the light inside them gathers
  const pale = color.mix(lite, color.rgb(1, 1, 1).toRgba8(255), 0.6);
  const R = g.bloom_r;

  // the core and its nucleus, a little taller than wide, like a seed
  var s = b.mark();
  try ellipsoid(b, .{.center = m.v3(0, 0, 0), .radii = m.v3(R * 0.4, R * 0.48, R * 0.4), .col = body, .part = .bloom, .rings = 6, .segs = 8});
  try ellipsoid(b, .{.center = m.v3(0, R * 0.04, 0), .radii = m.splat3(R * 0.22), .col = lite, .part = .bloom, .rings = 4, .segs = 6});
  // a crown of stamens rising out of its top and arching out, each tipped
  // with a bead of light (their roots sunk in the core)
  const stamens = 7;
  for (0..stamens) |i| {
    const a = m.ratio(i, stamens) * m.tau + rng.range(-0.2, 0.2);
    const out = m.v3(@cos(a), 0, @sin(a));
    const from = out * m.splat3(R * 0.12) + m.v3(0, R * 0.3, 0);
    const len = R * rng.range(0.55, 0.8);
    const tip = try lightThread(b, .{.start = from, .direction = m.norm(out * m.splat3(0.55) + m.v3(0, 1, 0)), .length = len, .wobble = 0.3, .curl = 0.08, .seed = seed +% i * 13}, R * 0.03, lite);
    try ellipsoid(b, .{.center = tip, .radii = m.splat3(R * 0.06), .col = lite, .part = .bloom, .rings = 3, .segs = 5});
  }
  fragment(b, s, 0, @intFromEnum(Ring.core), 0);

  // the whorls, innermost first: each petal floats a gap off the core and
  // is held to it by a thread of light from the core's flank to its claw
  const whorls = [_]struct { n:u32, at:f32, y:f32, len:f32, w:f32, rise:f32, flare:f32, cup:f32, order:[2]f32, col:color.Rgba8, ring:Ring }{
    .{.n = 5, .at = 0.62, .y = -0.05, .len = 1.0, .w = 0.26, .rise = 1.3, .flare = 0.5, .cup = 0.7, .order = .{0.12, 0.3}, .col = lite, .ring = .inner},
    .{.n = 6 + variant % 2, .at = 1.1, .y = -0.2, .len = 1.25, .w = 0.3, .rise = 0.95, .flare = 0.6, .cup = 0.6, .order = .{0.3, 0.55}, .col = body, .ring = .middle},
    .{.n = 8 + variant % 2, .at = 1.6, .y = -0.4, .len = 1.4, .w = 0.28, .rise = 0.6, .flare = 0.7, .cup = 0.5, .order = .{0.5, 0.8}, .col = body, .ring = .outer},
  };
  for (whorls, 0..) |wh, k| {
    const off = if (k % 2 == 1) m.pi / m.f(wh.n) else 0;
    for (0..wh.n) |i| {
      const a = m.ratio(i, wh.n) * m.tau + off + rng.range(-0.12, 0.12);
      const out = m.v3(@cos(a), 0, @sin(a));
      const base = out * m.splat3(R * wh.at) + m.v3(0, R * (wh.y + rng.range(-0.05, 0.05)), 0);
      const order = m.lerp(wh.order[0], wh.order[1], m.ratio(i, wh.n));
      s = b.mark();
      try petal(b, .{
        .base = base, .out = out,
        .len = R * wh.len * rng.range(0.9, 1.1), .width = R * wh.w,
        .rise = wh.rise + rng.range(-0.1, 0.1), .flare = wh.flare, .cup = wh.cup,
        .col = wh.col, .tip = pale, .part = .leaf,
      });
      fragment(b, s, order, @intFromEnum(wh.ring), a);
      // the thread: from just inside the core's skin to just short of the claw
      s = b.mark();
      const from = out * m.splat3(R * 0.3) + m.v3(0, -R * 0.05, 0);
      const to = base - out * m.splat3(R * 0.04);
      _ = try lightThread(b, .{.start = from, .direction = m.norm(to - from), .length = m.len(to - from), .wobble = 0.25, .curl = 0.1, .seed = seed +% k * 97 +% i * 7}, R * 0.022, lite);
      fragment(b, s, order, @intFromEnum(wh.ring), a);
      for (b.v.items[s..]) |*v| {
        const along = m.clamp01(m.dot(v.pos - from, to - from) / m.dot(to - from, to - from));
        v.tu[1] += (1 - along) * THREAD;
      }
    }
  }

  // motes of light, each on its own bearing, spiralling in to the core
  // (plant.vert carries them in and fades them as they are taken up)
  const motes = 9;
  for (0..motes) |i| {
    const a = m.ratio(i, motes) * m.tau + rng.range(-0.3, 0.3);
    s = b.mark();
    try ellipsoid(b, .{.center = m.v3(@cos(a), 0, @sin(a)) * m.splat3(R * 0.5), .radii = m.splat3(R * rng.range(0.04, 0.07)), .col = lite, .part = .bloom, .rings = 3, .segs = 4});
    fragment(b, s, m.ratio(i, motes), @intFromEnum(Ring.motes), a);
  }

  // the halo: a thin ring of light at a tilt, the last to close
  s = b.mark();
  var ring:[25]V3 = undefined;
  var ts:[25]f32 = undefined;
  const tilt:f32 = 0.35;
  for (&ring, &ts, 0..) |*p, *t, j| {
    const a = m.ratio(j, 24) * m.tau;
    const q = m.v3(@cos(a) * R * 1.55, 0, @sin(a) * R * 1.55);
    p.* = m.v3(q[0], q[1] * @cos(tilt) - q[2] * @sin(tilt), q[1] * @sin(tilt) + q[2] * @cos(tilt));
    t.* = 1;
  }
  try b.tube(&ring, &ts, R * 0.025, R * 0.025, lite, .bloom, 4);
  fragment(b, s, 0.95, @intFromEnum(Ring.halo), 0);
}

/// what each fragment of a celestial bloom belongs to (tu.y; plant.vert
/// moves each its own way)
const Ring = enum(u8) { core, inner, middle, outer, motes, halo };
/// tu.y a bloom's thread adds at its core end (0 at its petal)
const THREAD = 0.9;

/// mark every vertex since `start` as one fragment of a radiant bloom
fn fragment(b:*Builder, start:usize, order:f32, ring:u8, bearing:f32) void {
  const a:u8 = @intFromFloat(@mod(bearing, m.tau) / m.tau * 255);
  for (b.v.items[start..]) |*v| {
    v.tu = .{order, m.f(ring)};
    v.col.a = a;
  }
}

/// a thread of light along a grown path, tapering to a point at both ends;
/// returns its far end
fn lightThread(b:*Builder, g:Growth, r:f32, col:color.Rgba8) Allocator.Error!V3 {
  var ctrl:[6]V3 = undefined;
  growthPath(g, &ctrl);
  var path:[14]V3 = undefined;
  m.splineResample(&ctrl, &path);
  var ts:[14]f32 = undefined;
  var radii:[14]f32 = undefined;
  for (&ts, &radii, 0..) |*t, *rr, j| {
    const k = m.ratio(j, 13);
    t.* = k;
    rr.* = r * @sqrt(@sin(m.pi * k)) + r * 0.05;
  }
  try b.tubeR(&path, &ts, &radii, col, .bloom, 4);
  return path[13];
}

/// tu.x where the confluence's braid gives way to its vines.
const FRAY = 0.55;
/// control points over which a vine peels off the line of its strand.
const PEEL = 4;
/// growth keys a confluence is built at, evenly from sprout (0) to bloom (1).
/// Every key has the same vertices in the same order, so the plant shader
/// blends between the two around a plant's growth: it grows, never jumps.
pub const KEYS = 8;

/// how each part of a confluence has come along at `growth` (0..1)
const Grown = struct {
  /// the braid's height and girth
  rise:f32,
  /// the vines' length
  reach:f32,
  /// the canopy's petals
  bloom:f32,

  fn at(growth:f32) Grown {
    return .{
      .rise = m.lerp(0.3, 1, m.smooth(m.clamp01(growth / 0.5))),
      .reach = m.smooth(m.clamp01((growth - 0.15) / 0.6)),
      .bloom = m.smooth(m.clamp01((growth - 0.72) / 0.28)),
    };
  }
};

/// the confluence at `growth` (0..1): a symbiotic braid below whose strands
/// gather at its crown and carry on, each as one unbroken tube, into a
/// parasitic vine reaching up and out, green blending to red along it. The
/// leader returns to the axis and opens into a canopy of sap petals.
/// Nothing appears or vanishes with growth (a part not yet grown is folded
/// to nothing), so every growth gives the same vertex layout.
fn confluence(b:*Builder, g:species.Genome, seed:u64, growth:f32) Allocator.Error!void {
  const gr = Grown.at(growth);
  var rng = Rng.init(seed);
  const core = color.shade(g.stem_col, 0.55);
  const strand = color.shade(g.stem_col, 1.3);
  const orange = color.rgb(g.leaf_col.r * 1.2, g.leaf_col.g * 1.9, g.leaf_col.b * 1.1).toRgba8(255);
  const red = g.leaf_col.toRgba8(255);

  // the braid: dense symbiotic weave, flaring into the ground and gathering
  // at its crown, where the strands leave it
  const RES = 24;
  const STRANDS = 7;
  const TWIST:f32 = 3;
  const WOBBLE:f32 = 0.04;
  const trunk_h = g.stem_h * FRAY;
  const lean = m.norm(m.v3(rng.range(-0.05, 0.05), 1, rng.range(-0.05, 0.05)));
  var ctrl:[8]V3 = undefined;
  growthPath(.{.start = m.v3(0, 0, 0), .direction = lean, .length = trunk_h * gr.rise, .wobble = g.wobble, .curl = g.curl, .seed = seed ^ 0x57E4}, &ctrl);
  var spine:[RES]V3 = undefined;
  m.splineResample(&ctrl, &spine);
  var ts:[RES]f32 = undefined;
  var radii:[RES]f32 = undefined;
  var core_r:[RES]f32 = undefined;
  for (&ts, &radii, &core_r, 0..) |*t, *r, *cr, i| {
    const k = m.ratio(i, RES - 1);
    t.* = k * FRAY * gr.rise;
    const flare = 1 - k;
    const crown = m.smooth(m.clamp01((k - 0.8) / 0.2));
    r.* = g.stem_r * (0.7 + 0.3 * gr.rise) * m.lerp(1, 0.75, k) * (1 + 0.6 * flare * flare * flare * flare) * m.lerp(1, 0.55, crown);
    // the core closes over at the crown instead of ending in a flat cut
    cr.* = r.* * BRAID_CORE * (1 - 0.85 * m.smooth(m.clamp01((k - 0.85) / 0.15)));
  }
  try b.tubeR(&spine, &ts, &core_r, core, .stem, 8);

  // buttress roots splay toward the corners of the footprint
  for (0..4) |i| {
    const a = (m.f(i) + 0.5) / 4 * m.tau + rng.range(-0.2, 0.2);
    const from = m.v3(0, trunk_h * gr.rise * 0.18, 0);
    const spread = 0.75 * (0.6 + 0.4 * gr.rise);
    const to = m.v3(@cos(a) * spread, -0.02, @sin(a) * spread);
    var rc:[6]V3 = undefined;
    growthPath(.{.start = from, .direction = m.norm(to - from), .length = m.len(to - from), .wobble = 0.15, .seed = seed +% i * 53}, &rc);
    var rs:[12]V3 = undefined;
    m.splineResample(&rc, &rs);
    var rt:[12]f32 = undefined;
    var rr:[12]f32 = undefined;
    for (&rt, &rr, 0..) |*t, *r, j| {
      const k = m.ratio(j, 11);
      t.* = 0.05 * (1 - k);
      r.* = g.stem_r * 0.42 * m.lerp(1, 0.45, k);
    }
    try braid(b, &rs, &rt, &rr, 3, 2, 0.05, seed +% i * 7, core, strand);
  }

  // each strand: wound around the core up the braid (as `braidTurned` winds
  // them), then on past the crown as its vine, one tube from root to tip
  var fn_:[RES]V3 = undefined;
  var fb:[RES]V3 = undefined;
  transport(&spine, &fn_, &fb);
  const top = spine[RES - 1];
  const VC = 10;
  const VR = 28;
  const N = RES + VR - 1;
  var leader_tip = top;
  for (0..STRANDS) |si| {
    var path:[N]V3 = undefined;
    var pt:[N]f32 = undefined;
    var pu:[N]f32 = undefined;
    var pr:[N]f32 = undefined;
    var cols:[N]color.Rgba8 = undefined;
    const a0 = m.ratio(si, STRANDS) * m.tau;
    const sd = seed +% si * STRAND_SALT;
    for (0..RES) |i| {
      const u = m.ratio(i, RES - 1);
      const a = a0 + u * TWIST + strandTurn(sd, u, WOBBLE);
      const off = radii[i] * BRAID_OFF * strandSwell(sd, u, WOBBLE);
      path[i] = spine[i] + (fn_[i] * m.splat3(@cos(a)) + fb[i] * m.splat3(@sin(a))) * m.splat3(off);
      pt[i] = ts[i];
      pu[i] = 0;
      pr[i] = radii[i] * BRAID_STRAND;
      cols[i] = strand;
    }
    const root = path[RES - 1];
    const along = m.norm(root - path[RES - 2]);
    // the leader climbs back over the axis; the rest reach up and out
    const leader = si == 0;
    const e = rng.range(0.5, 1.0);
    const span = (g.stem_h - trunk_h) * rng.range(0.8, 1.05);
    const target = if (leader)
      top + m.v3(0, (g.stem_h - trunk_h) * gr.reach, 0)
    else blk: {
      const out = m.norm(m.v3(root[0] - top[0], 0, root[2] - top[2]));
      break :blk root + (out * m.splat3(@cos(e)) + m.v3(0, @sin(e), 0)) * m.splat3(span * gr.reach);
    };
    // a vine not yet grown is a bud at the strand's end, never nothing
    const to = target - root;
    const len = @max(m.len(to), 0.004);
    const dir = if (m.len(to) > 1e-4) m.norm(to) else along;
    var vc:[VC]V3 = undefined;
    growthPath(.{
      .start = root, .direction = dir, .length = len,
      .wobble = g.tendril_wobble, .curl = g.tendril_curl, .seed = seed +% si * 31,
    }, &vc);
    // over the first PEEL control points the vine leaves the line the
    // strand was on for its own path
    for (vc[1..], 1..) |*p, j| {
      const w = m.smooth(@min(1, m.ratio(j, PEEL)));
      const hug = root + along * m.splat3(m.len(p.* - root));
      p.* = hug + (p.* - hug) * m.splat3(w);
    }
    var vp:[VR]V3 = undefined;
    m.splineResample(&vc, &vp);
    const body = g.stem_r * (if (leader) @as(f32, 0.36) else 0.28) * m.lerp(0.3, 1, gr.reach);
    const t0 = ts[RES - 1];
    const t1 = m.lerp(t0, if (leader) @as(f32, 1) else 0.92, gr.reach);
    // vp[0] is the strand's last point: the vine starts one ring on
    for (1..VR) |j| {
      const k = m.ratio(j, VR - 1);
      const at = RES - 1 + j;
      path[at] = vp[j];
      pt[at] = m.lerp(t0, t1, k);
      pu[at] = k;
      // the strand swells into the vine, then tapers to its tip
      pr[at] = @max(m.lerp(pr[RES - 1], body, m.smooth(@min(1, k / 0.15))) * m.lerp(1, 0.25, k), 1e-3);
      // the transition zone: a gradient, never a line
      const warm = color.mix(strand, orange, m.smooth(m.clamp01((k - 0.12) / 0.4)));
      cols[at] = color.mix(warm, red, m.smooth(m.clamp01((k - 0.45) / 0.45)));
    }
    try b.tubeC(&path, &pt, &pr, &cols, &pu, .tendril, 6);
    // the green, braid-side length of each vine grows leaves like any vine
    // (sized by growth, never absent, so every key keeps one layout)
    try leavesAlong(b, path[RES - 1 ..], 3, @max(g.stem_r * 1.5 * gr.reach, 0.01), g.stem_r * 0.5 * @max(gr.reach, 0.2), 0.06, 0.38, pt[RES - 1], pt[N - 1], color.shade(g.stem_col, 0.9), color.shade(g.stem_col, 1.4), seed +% si * 17);
    if (leader) leader_tip = path[N - 1];
  }

  const heart = color.shade(g.bloom_col, 0.8);
  const rim = color.rgb(0.82, 0.6, 1.0).toRgba8(255);

  // offshoots: woven side stems reaching out of the braid as it rises, each
  // ending in a sap bud, some of which open into small canopies with the
  // crown's (grown in the keys like everything else: a stem not yet grown
  // is a nub on the braid, a bud not yet opened stays closed)
  var srng = Rng.init(seed ^ 0x0FF5);
  const shoots = shootCount(g, &srng);
  for (0..shoots) |i| {
    const k = m.lerp(0.35, 0.85, (m.f(i) + srng.range(0.2, 0.8)) / m.f(shoots));
    const ang = m.f(i) * 2.39996 * 1.7 + 0.8 + srng.range(-0.3, 0.3);
    const len = g.stem_h * srng.range(0.22, 0.32) * m.lerp(0.05, 1, gr.reach);
    const tip = try offshoot(b, &spine, k, ts[0] + (ts[RES - 1] - ts[0]) * k, ang, len, g.stem_r * 0.16 * m.lerp(0.4, 1, gr.reach), srng.range(0.3, 0.6), strand, .stem, seed +% i * 211);
    try leavesAlong(b, tip.path[0..], 2, @max(g.stem_r * 1.1 * gr.reach, 0.01), g.stem_r * 0.4 * @max(gr.reach, 0.2), 0.3, 0.7, tip.t0, tip.t1, color.shade(g.stem_col, 0.9), color.shade(g.stem_col, 1.4), seed +% i * 59);
    const opens = srng.float() < 0.5;
    const op = if (opens) gr.bloom else 0;
    const sc = srng.range(0.35, 0.45) * m.lerp(0.3, 1, gr.reach);
    for (0..6) |j| {
      const a = m.ratio(j, 6) * m.tau + m.f(i);
      try petal(b, .{
        .base = tip.at, .out = m.v3(@cos(a), 0, @sin(a)),
        .len = g.bloom_r * sc * m.lerp(0.55, 1, op),
        .width = g.bloom_r * sc * m.lerp(0.3, 0.5, op),
        .rise = m.lerp(1.35, 0.55, op), .flare = m.lerp(-0.45, 0.7, op),
        .cup = m.lerp(0.7, 0.4, op), .col = heart, .tip = rim, .t = tip.t1,
      });
    }
  }

  // the canopy: translucent sap petals, violet at the heart, amber at the
  // rim
  // a closed upright bud that opens with growth: the petals lengthen, lean
  // out and flare, an outer whorl and a smaller inner one
  const op = gr.bloom;
  for (0..g.petals + 6) |i| {
    const outer = i < g.petals;
    const a = if (outer) m.ratio(i, g.petals) * m.tau else (m.f(i - g.petals) + 0.5) / 6 * m.tau;
    try petal(b, .{
      .base = leader_tip, .out = m.v3(@cos(a), 0, @sin(a)),
      .len = g.bloom_r * m.lerp(0.3, if (outer) @as(f32, 1) else 0.65, op),
      .width = g.bloom_r * m.lerp(0.12, if (outer) @as(f32, 0.5) else 0.38, op),
      .rise = m.lerp(1.45, if (outer) @as(f32, 0.5) else 1.05, op),
      .flare = m.lerp(0.0, if (outer) @as(f32, 0.75) else 0.45, op),
      .cup = 0.4, .col = heart, .tip = rim,
    });
  }
}

/// how many meshes a species is built as: shapes picked by tile, or for a
/// confluence its growth keys.
pub fn variants(id:species.Id) u32 {
  return switch (species.get(id).genome.form) {
    .herb, .coil, .drift, .radiant => VARIANTS,
    .confluence => KEYS,
  };
}

/// for a species grown through keys, the key below `growth` and how far
/// toward the next one it is; null for a species of fixed shapes.
pub const Key = struct { v:u32, f:f32 };
pub fn growthKey(id:species.Id, growth:f32) ?Key {
  switch (species.get(id).genome.form) {
    .herb, .coil, .drift, .radiant => return null,
    .confluence => {
      const x = m.clamp01(growth) * (KEYS - 1);
      const v = @min(m.floorTo(u32, x), KEYS - 2);
      return .{.v = v, .f = x - m.f(v)};
    },
  }
}

/// slots per species in per-variant tables (the most any species uses).
pub const MAX_VARIANTS = @max(VARIANTS, KEYS);

/// where a (species, variant, level of detail) mesh sits in per-variant tables.
pub fn plantSlot(id:species.Id, variant:u32, lod:u32) usize { return (@as(usize, @intFromEnum(id)) * MAX_VARIANTS + variant) * LODS + lod; }

test "grown vines keep their root and regrow identically" {
  const g:Growth = .{.start = m.v3(1, 0, 2), .direction = m.v3(0, 1, 0), .length = 1, .wobble = 0.2, .curl = 0.4, .seed = 9};
  var a:[8]V3 = undefined;
  var b:[8]V3 = undefined;
  growthPath(g, &a);
  growthPath(g, &b);
  try std.testing.expectEqual(g.start, a[0]);
  for (a, b) |x, y| try std.testing.expectEqual(x, y);
  // it still grows along its direction, roughly its length
  try std.testing.expect(@abs(a[7][1] - 1) < 0.1);
}

test "a confluence's growth keys share one vertex layout and grow taller" {
  var b:Builder = .{.gpa = std.testing.allocator};
  defer b.deinit();
  var counts:[KEYS]usize = undefined;
  var tops:[KEYS]f32 = undefined;
  for (0..KEYS) |v| {
    b.v.clearRetainingCapacity();
    try plant(&b, .confluence, @intCast(v));
    counts[v] = b.v.items.len;
    var hi:f32 = 0;
    for (b.v.items) |x| hi = @max(hi, x.pos[1]);
    tops[v] = hi;
  }
  for (counts[1..]) |c| try std.testing.expectEqual(counts[0], c);
  for (tops[1..], tops[0 .. KEYS - 1]) |t, prev| try std.testing.expect(t >= prev);
  // keys cover growth end to end; between keys the blend is the fraction
  try std.testing.expectEqual(Key{.v = 0, .f = 0}, growthKey(.confluence, 0).?);
  const end = growthKey(.confluence, 1).?;
  try std.testing.expect(end.v == KEYS - 2 and end.f == 1);
  try std.testing.expect(growthKey(.lumenroot, 0.5) == null);
}
