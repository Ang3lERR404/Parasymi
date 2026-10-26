//! procedural mesh construction, the generic half: a `Builder` holding a
//! mesh's vertices (with skin weights and growth records beside them, and
//! the level of detail it is built at) and the primitives every mesh is
//! composed of: watertight tubes along a spline (parallel-transported
//! frames, shared rings, capped ends), lofts of any cross-section, cones,
//! ellipsoids, grid patches, grown vines (Catmull-Rom, tapering) and woven
//! braids. A vertex's role is the game's own enum (`Mesher(Part, stem)`):
//! its shaders key motion and shading off it.
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const m = @import("../core/math.zig");
const Rng = @import("../core/rng.zig").Rng;
const color = @import("../core/color.zig");
const noise = @import("../core/noise.zig");
const vertex = @import("vertex.zig");

const V3 = m.V3;
const MAX_SPINE = m.MAX_SPLINE;
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
  const up = m.norm(m.cross(axis, if (@abs(axis[1]) < m.NEAR_PARALLEL) m.v3(0, 1, 0) else m.v3(1, 0, 0)));
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

/// the builder and the primitives that write a role: `Part` is the game's
/// enum(u32) of vertex roles, `stem` the role a plain woody surface takes
/// (braids, bands, an ellipsoid left unset)
pub fn Mesher(comptime Role:type, comptime stem:Role) type {
  return struct {
    pub const Part = Role;
    const P = Role;
  pub const Builder = struct {
    gpa:Allocator,
    v:std.ArrayList(vertex.Mesh) = .empty,
    /// skin weights beside `v`, as far as the last skinned vertex (see `skinOf`)
    skin:std.ArrayList(vertex.Skin) = .empty,
    /// growth records beside `v`, as far as the last vertex grown along a
    /// growth spline (see `growOf`, gfx/growth.zig)
    grow:std.ArrayList(vertex.Grow) = .empty,
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
      b.grow.deinit(b.gpa);
    }

    /// the skin weights of every vertex since `start`, to be filled in
    /// (vertices before it without any are left unskinned)
    pub fn skinOf(b:*Builder, start:usize) Allocator.Error![]vertex.Skin {
      try b.skin.appendNTimes(b.gpa, .{}, b.v.items.len -| b.skin.items.len);
      return b.skin.items[start..b.v.items.len];
    }

    /// the growth records of every vertex since `start`, to be filled in
    /// (vertices before it without any grow as their structure does)
    pub fn growOf(b:*Builder, start:usize) Allocator.Error![]vertex.Grow {
      try b.grow.appendNTimes(b.gpa, .{}, b.v.items.len -| b.grow.items.len);
      return b.grow.items[start..b.v.items.len];
    }

    pub fn put(b:*Builder, p:V3, n:V3, col:color.Rgba8, t:f32, u:f32, part:Part) Allocator.Error!void {
      try b.v.append(b.gpa, .{.pos = p, .nrm = m.norm(n), .col = col, .tu = .{t, u}, .part = @intFromEnum(part)});
    }

    /// apply a transform to every vertex added since `start` (build in a unit
    /// space, then place/scale into the final part space).
    pub fn xform(b:*Builder, start:usize, mat:m.M4) void {
      const nm = m.inverse(mat); // normals use the inverse-transpose
      for (b.v.items[start..]) |*v| {
        v.pos = m.mulPoint(mat, v.pos);
        v.nrm = m.norm(m.mulCovector(nm, v.nrm));
      }
      // where a vertex grows out of moves with it
      if (start < b.grow.items.len) for (b.grow.items[start..]) |*g| {
        g.from = m.mulPoint(mat, g.from);
      };
      // a weight's gradient is a covector too: it goes as the normals do
      if (start >= b.skin.items.len) return;
      for (b.skin.items[start..]) |*k| for (0..4) |i| {
        const g = m.mulCovector(nm, .{k.gx[i], k.gy[i], k.gz[i]});
        k.gx[i] = g[0];
        k.gy[i] = g[1];
        k.gz[i] = g[2];
      };
    }

    pub fn mark(b:*const Builder) usize { return b.v.items.len; }

    /// tube along a spine, `sides` facets, radius tapering from r0 to r1.
    pub fn tube(b:*Builder, spine:[]const V3, ts:[]const f32, r0:f32, r1:f32, col:color.Rgba8, part:Part, sides:u32) Allocator.Error!void {
      var radii:[MAX_SPINE]f32 = undefined;
      const last = m.f(spine.len - 1);
      for (0..spine.len) |i| radii[i] = m.lerp(r0, r1, m.f(i) / last);
      try b.tubeR(spine, ts, radii[0..spine.len], col, part, sides);
    }

    /// watertight tube: one ring per spine point, oriented by a frame carried
    /// smoothly along the curve (parallel transport) so consecutive segments
    /// share their rings exactly, with both ends capped.
    pub fn tubeR(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, col:color.Rgba8, part:Part, sides:u32) Allocator.Error!void {
      var cols:[MAX_SPINE]color.Rgba8 = undefined;
      @memset(cols[0..spine.len], col);
      try b.tubeC(spine, ts, radii, cols[0..spine.len], null, part, sides);
    }

    /// `tubeR` with a colour per ring (a gradient along the tube, shared rings
    /// so it never steps), and optionally `us[i]` written to tu.y.
    pub fn tubeC(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, cols:[]const color.Rgba8, us:?[]const f32, part:Part, full_sides:u32) Allocator.Error!void {
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

    pub fn cone(b:*Builder, base:V3, dir:V3, len:f32, r:f32, col:color.Rgba8, t:f32, part:Part) Allocator.Error!void {
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

  /// a grown vine: `ctrl_n` control points from `g`, smoothed by Catmull-Rom
  /// into `res` evenly spaced rings, tapering by `g.taper`, `t` from t0 to t1.
  pub fn vine(b:*Builder, g:Growth, ctrl_n:usize, res:usize, r0:f32, col:color.Rgba8, part:Part, sides:u32, t0:f32, t1:f32) Allocator.Error!void {
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
    try braidAround(b, spine, ts, radii, turn, strands, wobble, seed, core, strand, stem);
  }

  /// `braidTurned` round a core of role `core_part` (an arsthraxia's nerve
  /// showing between its strands)
  pub fn braidAround(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, turn:[]const f32, strands:u32, wobble:f32, seed:u64, core:color.Rgba8, strand:color.Rgba8, core_part:Part) Allocator.Error!void {
    const n = spine.len;
    var fn_:[MAX_SPINE]V3 = undefined;
    var fb:[MAX_SPINE]V3 = undefined;
    transport(spine, fn_[0..n], fb[0..n]);
    var r:[MAX_SPINE]f32 = undefined;
    for (0..n) |i| r[i] = radii[i] * BRAID_CORE;
    try b.tubeR(spine, ts, r[0..n], core, core_part, 8);
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
      try b.tubeR(path[0..n], ts, r[0..n], strand, stem, 5);
    }
  }

  /// a tube along `spine` whose cross-section is `shape` (a closed curve over
  /// 0..tau, roughly unit size, counter-clockwise when seen from the spine's
  /// start) scaled by `widths`/`heights`, upright toward `up`. Rings are
  /// shared and both ends capped, so it is watertight like `tubeR`.
  pub fn loft(b:*Builder, spine:[]const V3, ts:[]const f32, widths:[]const f32, heights:[]const f32, up:V3, comptime shape:fn (f32) [2]f32, col:color.Rgba8, part:Part, full_sides:u32) Allocator.Error!void {
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
  pub fn patch(b:*Builder, rows:usize, cols:usize, pts:[]const V3, nrms:[]const V3, cols_rgba:[]const color.Rgba8, us:[]const f32, t:f32, part:Part) Allocator.Error!void {
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
      try b.tubeR(&path, &ts, &rs, col, stem, 5);
    }
  }

  pub const Ellipsoid = struct {
    center:V3,
    radii:V3,
    col:color.Rgba8,
    part:Part = stem,
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
  };
}

test "grown vines keep their root and regrow identically" {
  const g:Growth = .{.start = m.v3(1, 0, 2), .direction = m.v3(0, 1, 0), .length = 1, .wobble = 0.2, .curl = 0.4, .seed = 9};
  var a:[8]V3 = undefined;
  var b:[8]V3 = undefined;
  growthPath(g, &a);
  growthPath(g, &b);
  try testing.expectEqual(g.start, a[0]);
  for (a, b) |x, y| try testing.expectEqual(x, y);
  // it still grows along its direction, roughly its length
  try testing.expect(@abs(a[7][1] - 1) < 0.1);
}

test "a tube keeps fewer rings and sides at a coarser level of detail, its caps closed" {
  const Role = enum(u32) { stem, leaf };
  const M = Mesher(Role, .stem);
  const spine = [_]V3{m.v3(0, 0, 0), m.v3(0, 0.3, 0), m.v3(0.1, 0.6, 0), m.v3(0.1, 0.9, 0.1), m.v3(0, 1.2, 0.1)};
  const ts = [_]f32{0, 0.25, 0.5, 0.75, 1};
  var counts:[2]usize = undefined;
  for (&counts, 0..) |*c, l| {
    var b:M.Builder = .{.gpa = testing.allocator, .lod = @intCast(l)};
    defer b.deinit();
    try b.tube(&spine, &ts, 0.1, 0.05, color.rgb(0.4, 0.3, 0.2).toRgba8(255), .stem, 8);
    // two triangles a side between kept rings, a fan a side at each cap
    const sides:usize = b.around(8, 3);
    var keep:[8]usize = undefined;
    const rings = stride(spine.len, b.step(), &keep);
    try testing.expectEqual((rings - 1) * sides * 6 + 2 * sides * 3, b.v.items.len);
    c.* = b.v.items.len;
  }
  try testing.expect(counts[1] < counts[0]);
}
