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

const V3 = m.V3;
const PV = vertex.Mesh;
const MAX_SPINE = 64;
const MAX_SIDES = 16;

pub const Builder = struct {
  gpa:Allocator,
  v:std.ArrayList(PV) = .empty,

  pub fn deinit(b:*Builder) void { b.v.deinit(b.gpa); }

  fn put(b:*Builder, p:V3, n:V3, col:[4]u8, t:f32, u:f32, part:vertex.Part) !void {
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
  pub fn tube(b:*Builder, spine:[]const V3, ts:[]const f32, r0:f32, r1:f32, col:[4]u8, part:vertex.Part, sides:u32) !void {
    var radii:[MAX_SPINE]f32 = undefined;
    const last = m.f(spine.len - 1);
    for (0..spine.len) |i| radii[i] = m.lerp(r0, r1, m.f(i) / last);
    try b.tubeR(spine, ts, radii[0..spine.len], col, part, sides);
  }

  /// watertight tube: one ring per spine point, oriented by a frame carried
  /// smoothly along the curve (parallel transport) so consecutive segments
  /// share their rings exactly, with both ends capped.
  pub fn tubeR(b:*Builder, spine:[]const V3, ts:[]const f32, radii:[]const f32, col:[4]u8, part:vertex.Part, sides:u32) !void {
    assert(spine.len >= 2 and spine.len <= MAX_SPINE and sides <= MAX_SIDES);
    var rings:[MAX_SPINE][MAX_SIDES]V3 = undefined;
    var norms:[MAX_SPINE][MAX_SIDES]V3 = undefined;
    const n = spine.len;
    var tan = m.norm(spine[1] - spine[0]);
    var nrm = m.norm(m.cross(tan, if (@abs(tan[1]) > 0.9) m.v3(1, 0, 0) else m.v3(0, 1, 0)));
    for (0..n) |i| {
      // tangent: average of the neighbouring segments, so joints bisect the bend
      const prev = spine[if (i == 0) 0 else i - 1];
      const next = spine[@min(i + 1, n - 1)];
      const t_new = m.norm(next - prev);
      // carry the normal along: remove its component along the new tangent
      nrm = m.norm(nrm - t_new * m.splat(m.dot(nrm, t_new)));
      tan = t_new;
      const bi = m.cross(tan, nrm);
      for (0..sides) |k| {
        const a = m.ratio(k, sides) * m.tau;
        const dir = nrm * m.splat(@cos(a)) + bi * m.splat(@sin(a));
        norms[i][k] = dir;
        rings[i][k] = spine[i] + dir * m.splat(radii[i]);
      }
    }
    for (0..n - 1) |i| for (0..sides) |k| {
      const k1 = (k + 1) % sides;
      const q = [4]usize{k, k1, k1, k};
      const r = [4]usize{i, i, i + 1, i + 1};
      for ([_]usize{0, 1, 2, 0, 2, 3}) |c| try b.put(rings[r[c]][q[c]], norms[r[c]][q[c]], col, ts[r[c]], 0, part);
    };
    // caps (skipped where the tube tapers to a point anyway)
    for ([_]usize{0, n - 1}) |i| {
      if (radii[i] < 1e-4) continue;
      const out = if (i == 0) m.norm(spine[0] - spine[1]) else m.norm(spine[n - 1] - spine[n - 2]);
      for (0..sides) |k| {
        const k1 = (k + 1) % sides;
        try b.put(spine[i], out, col, ts[i], 0, part);
        try b.put(rings[i][k], out, col, ts[i], 0, part);
        try b.put(rings[i][k1], out, col, ts[i], 0, part);
      }
    }
  }

  /// curved blade (leaf/petal). `dir` horizontal outward, droops along its length.
  pub fn blade(b:*Builder, base:V3, dir:V3, len:f32, width:f32, droop:f32, col:[4]u8, tip:[4]u8, t:f32, part:vertex.Part) !void {
    const segs = 8;
    const side = m.norm(m.cross(dir, m.v3(0, 1, 0)));
    // rows of (left, centre, right) shared between neighbouring quads, with one
    // smooth normal per row so the leaf bends without seams or light breaks
    var cs:[segs + 1]V3 = undefined;
    var ws:[segs + 1]f32 = undefined;
    for (0..segs + 1) |i| {
      const k = m.f(i) / segs;
      ws[i] = width * @sin(k * m.pi) * (1 - 0.3 * k);
      cs[i] = base + dir * m.splat(len * k) + m.v3(0, len * (0.35 * k - droop * k * k), 0);
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

  pub fn cone(b:*Builder, base:V3, dir:V3, len:f32, r:f32, col:[4]u8, t:f32, part:vertex.Part) !void {
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

pub fn ellipsoid(b:*Builder, e:Ellipsoid) !void {
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

/// a woven bundle of vines along +Y from 0 to 1: a darker core wrapped by
/// `strands` helical vines. `profile(k)` gives the bundle radius at height k.
pub fn bundle(b:*Builder, comptime profile:fn (f32) f32, strands:u32, twist:f32, core:[4]u8, vine:[4]u8) !void {
  const N = 18;
  var spine:[N + 1]V3 = undefined;
  var ts:[N + 1]f32 = undefined;
  var radii:[N + 1]f32 = undefined;
  for (0..N + 1) |i| {
    const k = m.f(i) / N;
    spine[i] = m.v3(0, k, 0);
    ts[i] = k;
    radii[i] = profile(k) * 0.72;
  }
  // core: one continuous tube whose radius follows the profile
  try b.tubeR(&spine, &ts, &radii, core, .stem, 8);
  // strands wind around it, each a single unbroken vine
  for (0..N + 1) |i| radii[i] = profile(ts[i]) * 0.26;
  for (0..strands) |s| {
    const a0 = m.ratio(s, strands) * m.tau;
    var path:[N + 1]V3 = undefined;
    for (0..N + 1) |i| {
      const k = ts[i];
      const a = a0 + k * twist;
      const r = profile(k) * 0.8;
      path[i] = m.v3(@cos(a) * r, k, @sin(a) * r);
    }
    try b.tubeR(&path, &ts, &radii, vine, .stem, 5);
  }
}

/// grow a species' mesh from its genome. Deterministic per species.
pub fn plant(b:*Builder, id:species.Id) !void {
  const g = species.get(id).genome;
  var rng = Rng.init(@as(u64, @intFromEnum(id)) + 77);
  const golden = 2.39996;

  // spine: a gentle helix whose amplitude grows with height (curl).
  var spine:[17]V3 = undefined;
  var ts:[17]f32 = undefined;
  const n = @min(g.segments, 16);
  for (0..n + 1) |i| {
    const k = m.ratio(i, n);
    const amp = g.curl * 0.12 * k * k;
    spine[i] = m.v3(amp * @sin(k * 7), g.stem_h * k, amp * @cos(k * 5));
    ts[i] = k;
  }
  try b.tube(spine[0 .. n + 1], ts[0 .. n + 1], g.stem_r, g.stem_r * 0.35, color.rgb(g.stem_col, 255), .stem, 6);

  // leaves in a phyllotactic spiral up the stem.
  for (0..g.leaves) |i| {
    const k = 0.2 + 0.7 * m.ratio(i, @max(g.leaves, 1));
    const at = m.alongPath(spine[0 .. n + 1], k);
    const ang = m.f(i) * golden;
    const dir = m.v3(@cos(ang), 0, @sin(ang));
    const len = g.leaf_len * (1.1 - 0.5 * k) * rng.range(0.85, 1.15);
    try b.blade(at, dir, len, g.leaf_w, g.leaf_droop, color.shade(g.leaf_col, 0.6), color.rgb(g.leaf_col, 255), k, .leaf);
  }

  // thorns: short cones pointing outward and slightly down.
  for (0..g.thorns) |i| {
    const k = 0.1 + 0.8 * rng.float();
    const at = m.alongPath(spine[0 .. n + 1], k);
    const ang = m.f(i) * golden * 1.3;
    const dir = m.norm(m.v3(@cos(ang), -0.3, @sin(ang)));
    try b.cone(at, dir, 0.07, 0.012, color.shade(g.bloom_col, 0.7), k, .thorn);
  }

  // tendrils: thin tubes that leave the stem and coil down toward the ground.
  for (0..g.tendrils) |i| {
    const ang = m.ratio(i, g.tendrils) * m.tau + 0.4;
    var tp:[9]V3 = undefined;
    var tt:[9]f32 = undefined;
    const start = m.alongPath(spine[0 .. n + 1], 0.35);
    for (0..9) |j| {
      const k = m.f(j) / 8;
      const rad = 0.05 + 0.3 * k;
      const a = ang + k * 2.5;
      tp[j] = start + m.v3(@cos(a) * rad, -start[1] * k * 0.95 + 0.06 * @sin(k * 9), @sin(a) * rad);
      tt[j] = 0.35 * (1 - k) + k;
    }
    try b.tube(&tp, &tt, 0.014, 0.004, color.rgb(g.stem_col, 255), .tendril, 4);
  }

  // bloom: a fan of petals around the tip.
  const top = spine[n];
  for (0..g.petals) |i| {
    const ang = m.ratio(i, g.petals) * m.tau;
    const dir = m.v3(@cos(ang), 0, @sin(ang));
    try b.blade(top, dir, g.bloom_r, g.bloom_r * 0.45, -0.6, color.shade(g.bloom_col, 0.8), color.rgb(g.bloom_col, 255), 1, .bloom);
  }
}

