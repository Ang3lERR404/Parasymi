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

pub const Builder = struct {
  gpa:Allocator,
  v:std.ArrayList(PV) = .empty,

  pub fn deinit(b:*Builder) void { b.v.deinit(b.gpa); }

  fn put(b:*Builder, p:V3, n:V3, col:[4]u8, t:f32, u:f32, part:vertex.Part) Allocator.Error!void {
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
  pub fn tube(b:*Builder, spine:[]const V3, ts:[]const f32, r0:f32, r1:f32, col:[4]u8, part:vertex.Part, sides:u32) Allocator.Error!void {
    var radii:[MAX_SPINE]f32 = undefined;
    const last = m.f(spine.len - 1);
    for (0..spine.len) |i| radii[i] = m.lerp(r0, r1, m.f(i) / last);
    try b.tubeR(spine, ts, radii[0..spine.len], col, part, sides);
  }

  /// watertight tube: one ring per spine point, oriented by a frame carried
  /// smoothly along the curve (parallel transport) so consecutive segments
  /// share their rings exactly, with both ends capped.
  pub fn tubeR(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, col:[4]u8, part:vertex.Part, sides:u32) Allocator.Error!void {
    var cols:[MAX_SPINE][4]u8 = undefined;
    @memset(cols[0..spine.len], col);
    try b.tubeC(spine, ts, radii, cols[0..spine.len], null, part, sides);
  }

  /// `tubeR` with a colour per ring (a gradient along the tube, shared rings
  /// so it never steps), and optionally `us[i]` written to tu.y.
  pub fn tubeC(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, cols:[]const [4]u8, us:?[]const f32, part:vertex.Part, sides:u32) Allocator.Error!void {
    assert(spine.len >= 2 and spine.len <= MAX_SPINE and sides <= MAX_SIDES and cols.len == spine.len);
    var rings:[MAX_SPINE][MAX_SIDES]V3 = undefined;
    var norms:[MAX_SPINE][MAX_SIDES]V3 = undefined;
    const n = spine.len;
    var fn_:[MAX_SPINE]V3 = undefined;
    var fb:[MAX_SPINE]V3 = undefined;
    transport(spine, fn_[0..n], fb[0..n]);
    for (0..n) |i| {
      for (0..sides) |k| {
        const a = m.ratio(k, sides) * m.tau;
        const dir = fn_[i] * m.splat(@cos(a)) + fb[i] * m.splat(@sin(a));
        norms[i][k] = dir;
        rings[i][k] = spine[i] + dir * m.splat(radii[i]);
      }
    }
    for (0..n - 1) |i| for (0..sides) |k| {
      const k1 = (k + 1) % sides;
      const q = [4]usize{k, k1, k1, k};
      const r = [4]usize{i, i, i + 1, i + 1};
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
  pub fn blade(b:*Builder, base:V3, dir:V3, len:f32, width:f32, droop:f32, col:[4]u8, tip:[4]u8, t:f32, part:vertex.Part) Allocator.Error!void {
    var cs:[BLADE_SEGS + 1]V3 = undefined;
    bladeSpine(&cs, base, dir, len, droop);
    try b.sheet(&cs, m.norm(m.cross(dir, m.v3(0, 1, 0))), width, col, tip, t, part);
  }

  /// a blade whose midrib follows the smooth spline through `path`, its
  /// width lying along `side`.
  pub fn bladeAlong(b:*Builder, path:[]const V3, side:V3, width:f32, col:[4]u8, tip:[4]u8, t:f32, part:vertex.Part) Allocator.Error!void {
    var cs:[BLADE_SEGS + 1]V3 = undefined;
    m.splineResample(path, &cs);
    try b.sheet(&cs, side, width, col, tip, t, part);
  }

  /// the leaf surface along a midrib: rows of (left, centre, right) shared
  /// between neighbouring quads, with one smooth normal per row so the leaf
  /// bends without seams or light breaks.
  fn sheet(b:*Builder, cs:*const [BLADE_SEGS + 1]V3, side:V3, width:f32, col:[4]u8, tip:[4]u8, t:f32, part:vertex.Part) Allocator.Error!void {
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
    for (0..segs) |i| {
      const k0 = m.f(i) / segs;
      const k1 = m.f(i + 1) / segs;
      // a slight raised midrib keeps the blade from reading as a flat card
      const rib0 = cs[i] + ns[i] * m.splat(ws[i] * 0.25);
      const rib1 = cs[i + 1] + ns[i + 1] * m.splat(ws[i + 1] * 0.25);
      const quads = [2][4]V3{
        .{cs[i] + side * m.splat(ws[i]), rib0, rib1, cs[i + 1] + side * m.splat(ws[i + 1])},
        .{rib0, cs[i] - side * m.splat(ws[i]), cs[i + 1] - side * m.splat(ws[i + 1]), rib1},
      };
      const c0 = color.mix(col, tip, k0);
      const c1 = color.mix(col, tip, k1);
      for (quads) |q| {
        const cols = [4][4]u8{c0, c0, c1, c1};
        const kk = [4]f32{k0, k0, k1, k1};
        const nn = [4]V3{ns[i], ns[i], ns[i + 1], ns[i + 1]};
        for ([_]usize{0, 1, 2, 0, 2, 3}) |v| try b.put(q[v], nn[v], cols[v], t, kk[v], part);
      }
    }
  }

  pub fn cone(b:*Builder, base:V3, dir:V3, len:f32, r:f32, col:[4]u8, t:f32, part:vertex.Part) Allocator.Error!void {
    const side = m.norm(m.cross(dir, if (@abs(dir[1]) > 0.9) m.v3(1, 0, 0) else m.v3(0, 1, 0)));
    const up = m.cross(side, dir);
    const tip = base + dir * m.splat(len);
    const sides = 4;
    for (0..sides) |i| {
      const a0 = m.f(i) / sides * m.tau;
      const a1 = m.f(i + 1) / sides * m.tau;
      const n0 = side * m.splat(@cos(a0)) + up * m.splat(@sin(a0));
      const n1 = side * m.splat(@cos(a1)) + up * m.splat(@sin(a1));
      try b.put(base + n0 * m.splat(r), n0, col, t, 0, part);
      try b.put(base + n1 * m.splat(r), n1, col, t, 0, part);
      try b.put(tip, dir, col, t, 1, part);
      // base cap so a cone never shows a hole when seen from below
      try b.put(base, -dir, col, t, 0, part);
      try b.put(base + n1 * m.splat(r), -dir, col, t, 0, part);
      try b.put(base + n0 * m.splat(r), -dir, col, t, 0, part);
    }
  }
};

/// the midrib of a drooping blade: out along `dir`, curving by `droop`.
pub fn bladeSpine(cs:*[BLADE_SEGS + 1]V3, base:V3, dir:V3, len:f32, droop:f32) void {
  for (cs, 0..) |*c, i| {
    const k = m.ratio(i, BLADE_SEGS);
    c.* = base + dir * m.splat(len * k) + m.v3(0, len * (0.35 * k - droop * k * k), 0);
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
    nrm = m.norm(nrm - tan * m.splat(m.dot(nrm, tan)));
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
    p.* += side * m.splat((rng.float() - 0.5) * w) + up * m.splat((rng.float() - 0.5) * w);
    if (g.curl > 0) {
      const a = t * g.curl * 4 * m.tau;
      // the spiral widens out of the root and closes toward the tip
      const r = g.curl * 0.25 * g.length * m.smooth(@min(1, t * 4)) * (1 - t);
      p.* += side * m.splat(@cos(a) * r) + up * m.splat(@sin(a) * r);
    }
  }
}

/// control points for a grown vine, one per element of `out`.
pub fn growthPath(g:Growth, out:[]V3) void {
  for (out, 0..) |*p, i| p.* = g.start + g.direction * m.splat(g.length * m.ratio(i, out.len - 1));
  grow(out, g);
}

/// radii tapering smoothly from `r0` at the base to `r0 * tip` at the end.
pub fn taperRadii(r0:f32, tip:f32, out:[]f32) void {
  for (out, 0..) |*r, i| r.* = r0 * (1 - m.ratio(i, out.len - 1) * (1 - tip));
}

/// a grown vine: `ctrl_n` control points from `g`, smoothed by Catmull-Rom
/// into `res` evenly spaced rings, tapering by `g.taper`, `t` from t0 to t1.
pub fn vine(b:*Builder, g:Growth, ctrl_n:usize, res:usize, r0:f32, col:[4]u8, part:vertex.Part, sides:u32, t0:f32, t1:f32) Allocator.Error!void {
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
pub fn braid(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, strands:u32, twist:f32, wobble:f32, seed:u64, core:[4]u8, strand:[4]u8) Allocator.Error!void {
  var turn:[MAX_SPINE]f32 = undefined;
  for (turn[0..spine.len], 0..) |*a, i| a.* = m.ratio(i, spine.len - 1) * twist;
  try braidTurned(b, spine, ts, radii, turn[0..spine.len], strands, wobble, seed, core, strand);
}

/// a braid whose strands have wound `turn[i]` radians around the core by
/// point i: winding fast spreads them into a loose diagonal weave, winding
/// slowly gathers them tight and nearly vertical.
pub fn braidTurned(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, turn:[]const f32, strands:u32, wobble:f32, seed:u64, core:[4]u8, strand:[4]u8) Allocator.Error!void {
  const n = spine.len;
  var fn_:[MAX_SPINE]V3 = undefined;
  var fb:[MAX_SPINE]V3 = undefined;
  transport(spine, fn_[0..n], fb[0..n]);
  var r:[MAX_SPINE]f32 = undefined;
  for (0..n) |i| r[i] = radii[i] * 0.72;
  try b.tubeR(spine, ts, r[0..n], core, .stem, 8);
  for (0..n) |i| r[i] = radii[i] * 0.26;
  for (0..strands) |si| {
    const a0 = m.ratio(si, strands) * m.tau;
    const sd = seed +% si * 7919;
    var path:[MAX_SPINE]V3 = undefined;
    for (0..n) |i| {
      const u = m.ratio(i, n - 1);
      // strands stay embedded in the core: the offset never leaves 0.8 +- 10%
      const a = a0 + turn[i] + wobble * 4 * noise.grad(sd, u * 3, 0.5);
      const off = radii[i] * 0.8 * (1 + wobble * 3 * noise.grad(sd, u * 3, 7.5));
      path[i] = spine[i] + (fn_[i] * m.splat(@cos(a)) + fb[i] * m.splat(@sin(a))) * m.splat(off);
    }
    try b.tubeR(path[0..n], ts, r[0..n], strand, .stem, 5);
  }
}

/// a tube along `spine` whose cross-section is `shape` (a closed curve over
/// 0..tau, roughly unit size, counter-clockwise when seen from the spine's
/// start) scaled by `widths`/`heights`, upright toward `up`. Rings are
/// shared and both ends capped, so it is watertight like `tubeR`.
pub fn loft(b:*Builder, spine:[]const V3, ts:[]const f32, widths:[]const f32, heights:[]const f32, up:V3, comptime shape:fn (f32) [2]f32, col:[4]u8, part:vertex.Part, sides:u32) Allocator.Error!void {
  assert(spine.len >= 2 and spine.len <= MAX_SPINE and sides <= MAX_LOFT);
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
      norms[i][k] = m.norm(side * m.splat(dy) - u * m.splat(dx));
      rings[i][k] = spine[i] + side * m.splat(p[0] * widths[i]) + u * m.splat(p[1] * heights[i]);
    }
  }
  for (0..n - 1) |i| for (0..sides) |k| {
    const k1 = (k + 1) % sides;
    const q = [4]usize{k, k1, k1, k};
    const r = [4]usize{i, i, i + 1, i + 1};
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
pub fn patch(b:*Builder, rows:usize, cols:usize, pts:[]const V3, nrms:[]const V3, cols_rgba:[]const [4]u8, us:[]const f32, t:f32, part:vertex.Part) Allocator.Error!void {
  assert(pts.len == rows * cols and nrms.len == pts.len and cols_rgba.len == pts.len and us.len == pts.len);
  for (0..rows - 1) |r| for (0..cols - 1) |c| {
    const q = [4]usize{r * cols + c, r * cols + c + 1, (r + 1) * cols + c + 1, (r + 1) * cols + c};
    for ([_]usize{0, 1, 2, 0, 2, 3}) |v| try b.put(pts[q[v]], nrms[q[v]], cols_rgba[q[v]], t, us[q[v]], part);
  };
}

/// grown vine bands wrapping over an ellipsoid (centre `at`, `radii`) along
/// its curvature: each band runs from (polar th0, azimuth ph0) to (th1, ph1).
/// `side` mirrors it in x, so left and right forms are built, not mirrored.
pub fn bands(b:*Builder, at:V3, radii:V3, arcs:[]const [4]f32, side:f32, r:f32, wobble:f32, seed:u64, col:[4]u8) Allocator.Error!void {
  for (arcs, 0..) |arc, i| {
    var ctrl:[6]V3 = undefined;
    for (&ctrl, 0..) |*c, j| {
      const k = m.ratio(j, ctrl.len - 1);
      const th = m.lerp(arc[0], arc[2], k);
      const ph = m.lerp(arc[1], arc[3], k);
      c.* = at + m.v3(@sin(th) * @cos(ph) * side, @cos(th), @sin(th) * @sin(ph)) * radii * m.splat(1.03);
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
      rr.* = r;
    }
    try b.tubeR(&path, &ts, &rs, col, .stem, 5);
  }
}

pub const Ellipsoid = struct {
  center:V3,
  radii:V3,
  col:[4]u8,
  part:vertex.Part = .stem,
  rings:u32 = 8,
  segs:u32 = 10,
  /// value written to tu.x (e.g. height along a body part)
  t:f32 = 0,
};

pub fn ellipsoid(b:*Builder, e:Ellipsoid) Allocator.Error!void {
  const R = e.rings;
  const S = e.segs;
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
pub fn bundle(b:*Builder, comptime profile:fn (f32) f32, strands:u32, twist:f32, wobble:f32, seed:u64, core:[4]u8, strand:[4]u8) Allocator.Error!void {
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
/// variant leans, wobbles and curls a little differently.
pub fn plant(b:*Builder, id:species.Id, variant:u32) Allocator.Error!void {
  const g = species.get(id).genome;
  const seed = @as(u64, @intFromEnum(id)) * 977 + 77;
  switch (g.form) {
    .herb => try herb(b, g, seed + @as(u64, variant) * 131, variant),
    // a confluence's variants are its growth stages, all grown from one seed
    .confluence => try confluence(b, g, seed, variant),
  }
}

fn herb(b:*Builder, g:species.Genome, seed:u64, variant:u32) Allocator.Error!void {
  var rng = Rng.init(seed);
  const golden = 2.39996;

  // stem: a grown vine rising from the root, smoothed into evenly spaced rings
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
  for (&ts, 0..) |*t, i| t.* = m.ratio(i, RES - 1);
  taperRadii(g.stem_r, stem.taper, &radii);
  try b.tubeR(&spine, &ts, &radii, color.rgb(g.stem_col, 255), .stem, 6);

  // leaves in a phyllotactic spiral up the stem.
  for (0..g.leaves) |i| {
    const k = 0.2 + 0.7 * m.ratio(i, @max(g.leaves, 1));
    const at = m.alongPath(&spine, k);
    const ang = m.f(i) * golden + m.f(variant);
    const dir = m.v3(@cos(ang), 0, @sin(ang));
    const len = g.leaf_len * (1.1 - 0.5 * k) * rng.range(0.85, 1.15);
    try b.blade(at, dir, len, g.leaf_w, g.leaf_droop, color.shade(g.leaf_col, 0.6), color.rgb(g.leaf_col, 255), k, .leaf);
  }

  // thorns: short cones pointing outward and slightly down.
  for (0..g.thorns) |i| {
    const k = 0.1 + 0.8 * rng.float();
    const at = m.alongPath(&spine, k);
    const ang = m.f(i) * golden * 1.3;
    const dir = m.norm(m.v3(@cos(ang), -0.3, @sin(ang)));
    try b.cone(at, dir, 0.07, 0.012, color.shade(g.bloom_col, 0.7), k, .thorn);
  }

  // tendrils: grown vines that leave the stem and coil down to the ground.
  const start = m.alongPath(&spine, 0.35);
  for (0..g.tendrils) |i| {
    const ang = m.ratio(i, g.tendrils) * m.tau + 0.4 + 0.3 * m.f(variant);
    const reach = m.v3(@cos(ang) * 0.35, -start[1] * 0.95, @sin(ang) * 0.35);
    try vine(b, .{
      .start = start, .direction = m.norm(reach), .length = m.len(reach),
      .wobble = g.tendril_wobble, .curl = g.tendril_curl, .taper = 0.3, .seed = seed +% i * 31,
    }, 7, 24, 0.014, color.rgb(g.stem_col, 255), .tendril, 4, 0.35, 1);
  }

  // bloom: a fan of petals around the tip.
  const top = spine[RES - 1];
  for (0..g.petals) |i| {
    const ang = m.ratio(i, g.petals) * m.tau;
    const dir = m.v3(@cos(ang), 0, @sin(ang));
    try b.blade(top, dir, g.bloom_r, g.bloom_r * 0.45, -0.6, color.shade(g.bloom_col, 0.8), color.rgb(g.bloom_col, 255), 1, .bloom);
  }
}

/// tu.x where the confluence's braid gives way to its vines.
const FRAY = 0.55;
/// control points over which a vine peels off its braid strand.
const PEEL = 4;

/// the confluence at growth `stage` (0..3): a symbiotic braid below whose
/// strands peel away, over `PEEL` control points, into parasitic vines that
/// reach up and out, green blending to red along them. The leader returns to
/// the axis and, at the last stage, opens into a canopy of sap petals.
fn confluence(b:*Builder, g:species.Genome, seed:u64, stage:u32) Allocator.Error!void {
  comptime assert(VARIANTS == 4);
  const rise = ([4]f32{0.4, 0.7, 1, 1})[stage];
  const reach = ([4]f32{0, 0.45, 1, 1})[stage];
  var rng = Rng.init(seed);
  const core = color.shade(g.stem_col, 0.55);
  const strand = color.shade(g.stem_col, 1.3);
  const orange = color.rgb(.{g.leaf_col[0] * 1.2, g.leaf_col[1] * 1.9, g.leaf_col[2] * 1.1}, 255);
  const red = color.rgb(g.leaf_col, 255);

  // the braid: dense symbiotic weave, flaring into the ground
  const RES = 24;
  const STRANDS = 7;
  const TWIST:f32 = 3;
  const trunk_h = g.stem_h * FRAY;
  const lean = m.norm(m.v3(rng.range(-0.05, 0.05), 1, rng.range(-0.05, 0.05)));
  var ctrl:[8]V3 = undefined;
  growthPath(.{.start = m.v3(0, 0, 0), .direction = lean, .length = trunk_h * rise, .wobble = g.wobble, .curl = g.curl, .seed = seed ^ 0x57E4}, &ctrl);
  var spine:[RES]V3 = undefined;
  m.splineResample(&ctrl, &spine);
  var ts:[RES]f32 = undefined;
  var radii:[RES]f32 = undefined;
  for (&ts, &radii, 0..) |*t, *r, i| {
    const k = m.ratio(i, RES - 1);
    t.* = k * FRAY * rise;
    const flare = 1 - k;
    r.* = g.stem_r * (0.7 + 0.3 * rise) * m.lerp(1, 0.75, k) * (1 + 0.6 * flare * flare * flare * flare);
  }
  try braid(b, &spine, &ts, &radii, STRANDS, TWIST, 0.04, seed, core, strand);

  // buttress roots splay toward the corners of the footprint
  for (0..4) |i| {
    const a = (m.f(i) + 0.5) / 4 * m.tau + rng.range(-0.2, 0.2);
    const from = m.v3(0, trunk_h * rise * 0.18, 0);
    const to = m.v3(@cos(a) * 0.75 * (0.6 + 0.4 * rise), -0.02, @sin(a) * 0.75 * (0.6 + 0.4 * rise));
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

  if (stage == 0) return;

  // vines: each strand's path along the top of the braid, then free
  var fn_:[RES]V3 = undefined;
  var fb:[RES]V3 = undefined;
  transport(&spine, &fn_, &fb);
  const top = spine[RES - 1];
  const up = m.norm(spine[RES - 1] - spine[RES - 2]);
  const VC = 12;
  const VR = 28;
  var leader_tip = top;
  for (0..STRANDS) |si| {
    const a0 = m.ratio(si, STRANDS) * m.tau;
    var vc:[VC]V3 = undefined;
    for (vc[0..PEEL], 0..) |*p, j| p.* = strandAt(&spine, &fn_, &fb, &radii, a0, TWIST, m.lerp(0.5, 1, m.ratio(j, PEEL - 1)));
    const root = vc[PEEL - 1];
    // the leader climbs back over the axis; the rest reach up and out
    const leader = si == 0;
    const target = if (leader)
      top + m.v3(0, (g.stem_h - trunk_h) * reach, 0)
    else blk: {
      const out = m.norm(m.v3(root[0] - top[0], 0, root[2] - top[2]));
      const e = rng.range(0.5, 1.0);
      const len = (g.stem_h - trunk_h) * rng.range(0.8, 1.05) * reach;
      break :blk root + (out * m.splat(@cos(e)) + m.v3(0, @sin(e), 0)) * m.splat(len);
    };
    var free:[VC - PEEL + 1]V3 = undefined;
    growthPath(.{
      .start = root, .direction = m.norm(target - root), .length = m.len(target - root),
      .wobble = g.tendril_wobble, .curl = g.tendril_curl, .seed = seed +% si * 31,
    }, &free);
    // over the next PEEL control points the vine leaves the braid's axis
    // for its own path
    for (free[1..], PEEL..) |p, j| {
      const w = m.smooth(@min(1, m.ratio(j - PEEL + 1, PEEL)));
      const hug = root + up * m.splat(m.len(p - root));
      vc[j] = hug + (p - hug) * m.splat(w);
    }
    var path:[VR]V3 = undefined;
    m.splineResample(&vc, &path);
    var vt:[VR]f32 = undefined;
    var vu:[VR]f32 = undefined;
    var vr:[VR]f32 = undefined;
    var cols:[VR][4]u8 = undefined;
    const r0 = g.stem_r * (if (leader) @as(f32, 0.36) else 0.28);
    for (0..VR) |i| {
      const k = m.ratio(i, VR - 1);
      vt[i] = m.lerp(FRAY * rise * 0.9, if (leader) 1 else 0.92, k);
      vu[i] = k;
      vr[i] = r0 * m.lerp(1, 0.25, k);
      // the transition zone: a gradient, never a line
      const warm = color.mix(strand, orange, m.smooth(m.clamp01((k - 0.12) / 0.4)));
      cols[i] = color.mix(warm, red, m.smooth(m.clamp01((k - 0.45) / 0.45)));
    }
    try b.tubeC(&path, &vt, &vr, &cols, &vu, .tendril, 6);
    if (leader) leader_tip = path[VR - 1];
  }

  if (stage < 3) return;

  // the canopy: translucent sap petals, violet at the heart, amber at the rim
  const heart = color.shade(g.bloom_col, 0.8);
  const rim = color.rgb(.{0.82, 0.6, 1.0}, 255);
  for (0..g.petals) |i| {
    const a = m.ratio(i, g.petals) * m.tau;
    try b.blade(leader_tip, m.v3(@cos(a), 0, @sin(a)), g.bloom_r, g.bloom_r * 0.42, -0.35, heart, rim, 1, .bloom);
  }
  for (0..6) |i| {
    const a = (m.f(i) + 0.5) / 6 * m.tau;
    try b.blade(leader_tip, m.norm(m.v3(@cos(a), 0.9, @sin(a))), g.bloom_r * 0.6, g.bloom_r * 0.3, -0.2, heart, rim, 1, .bloom);
  }
}

/// where braid strand `a0` (see `braidTurned`, ignoring its noise) lies at
/// fraction `k` up `spine`.
fn strandAt(spine:[]const V3, fn_:[]const V3, fb:[]const V3, radii:[]const f32, a0:f32, twist:f32, k:f32) V3 {
  const n = spine.len;
  const fi = k * m.f(n - 1);
  const lo:usize = @min(n - 2, @as(usize, @intFromFloat(fi)));
  const t = fi - m.f(lo);
  const at = struct {
    fn v(xs:[]const V3, i:usize, w:f32) V3 { return xs[i] + (xs[i + 1] - xs[i]) * m.splat(w); }
  };
  const a = a0 + k * twist;
  const off = m.lerp(radii[lo], radii[lo + 1], t) * 0.8;
  return at.v(spine, lo, t) + (at.v(fn_, lo, t) * m.splat(@cos(a)) + at.v(fb, lo, t) * m.splat(@sin(a))) * m.splat(off);
}

/// where a (species, variant) mesh sits in per-variant tables.
pub fn plantSlot(id:species.Id, variant:u32) usize { return @as(usize, @intFromEnum(id)) * VARIANTS + variant; }

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
