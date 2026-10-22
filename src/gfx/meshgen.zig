//! procedural mesh construction. No asset files: every plant is grown from its
//! species genome by composing a few primitives (tube, blade, cone).
const std = @import("std");
const m = @import("../core/math.zig");
const Rng = @import("../core/rng.zig").Rng;
const vertex = @import("vertex.zig");
const species = @import("../sim/species.zig");

const V3 = m.V3;
const PV = vertex.Mesh;

pub const Builder = struct {
  gpa:std.mem.Allocator,
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
    const nseg = spine.len - 1;
    for (0..nseg) |s| {
      const a0 = spine[s];
      const a1 = spine[s + 1];
      const dir = m.norm(a1 - a0);
      const side = m.norm(m.cross(dir, if (@abs(dir[1]) > 0.9) m.v3(1, 0, 0) else m.v3(0, 1, 0)));
      const up = m.cross(side, dir);
      const k0 = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(nseg));
      const k1 = @as(f32, @floatFromInt(s + 1)) / @as(f32, @floatFromInt(nseg));
      const ra = m.lerp(r0, r1, k0);
      const rb = m.lerp(r0, r1, k1);
      for (0..sides) |i| {
        const ang0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sides)) * std.math.tau;
        const ang1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(sides)) * std.math.tau;
        const n0 = side * m.splat(@cos(ang0)) + up * m.splat(@sin(ang0));
        const n1 = side * m.splat(@cos(ang1)) + up * m.splat(@sin(ang1));
        const p00 = a0 + n0 * m.splat(ra);
        const p01 = a0 + n1 * m.splat(ra);
        const p10 = a1 + n0 * m.splat(rb);
        const p11 = a1 + n1 * m.splat(rb);
        try b.put(p00, n0, col, ts[s], 0, part);
        try b.put(p01, n1, col, ts[s], 0, part);
        try b.put(p11, n1, col, ts[s + 1], 0, part);
        try b.put(p00, n0, col, ts[s], 0, part);
        try b.put(p11, n1, col, ts[s + 1], 0, part);
        try b.put(p10, n0, col, ts[s + 1], 0, part);
      }
    }
  }

  /// curved blade (leaf/petal). `dir` horizontal outward, droops along its length.
  pub fn blade(b:*Builder, base:V3, dir:V3, len:f32, width:f32, droop:f32, col:[4]u8, tip:[4]u8, t:f32, part:vertex.Part) !void {
    const segs = 5;
    const side = m.norm(m.cross(dir, m.v3(0, 1, 0)));
    var prev_l:V3 = base;
    var prev_r:V3 = base;
    var prev_c:V3 = base;
    for (1..segs + 1) |i| {
      const k = @as(f32, @floatFromInt(i)) / segs;
      const k0 = @as(f32, @floatFromInt(i - 1)) / segs;
      const w = width * @sin(k * std.math.pi) * (1 - 0.3 * k);
      const c = base + dir * m.splat(len * k) + m.v3(0, len * (0.35 * k - droop * k * k), 0);
      const l = c + side * m.splat(w);
      const r = c - side * m.splat(w);
      const n = m.norm(m.cross(c - prev_c, side));
      const cl = mixCol(col, tip, k);
      const cl0 = mixCol(col, tip, k0);
      try b.put(prev_l, n, cl0, t, k0, part);
      try b.put(prev_r, n, cl0, t, k0, part);
      try b.put(r, n, cl, t, k, part);
      try b.put(prev_l, n, cl0, t, k0, part);
      try b.put(r, n, cl, t, k, part);
      try b.put(l, n, cl, t, k, part);
      prev_l = l; prev_r = r; prev_c = c;
    }
  }

  pub fn cone(b:*Builder, base:V3, dir:V3, len:f32, r:f32, col:[4]u8, t:f32, part:vertex.Part) !void {
    const side = m.norm(m.cross(dir, if (@abs(dir[1]) > 0.9) m.v3(1, 0, 0) else m.v3(0, 1, 0)));
    const up = m.cross(side, dir);
    const tip = base + dir * m.splat(len);
    const sides = 4;
    for (0..sides) |i| {
      const a0 = @as(f32, @floatFromInt(i)) / sides * std.math.tau;
      const a1 = @as(f32, @floatFromInt(i + 1)) / sides * std.math.tau;
      const n0 = side * m.splat(@cos(a0)) + up * m.splat(@sin(a0));
      const n1 = side * m.splat(@cos(a1)) + up * m.splat(@sin(a1));
      try b.put(base + n0 * m.splat(r), n0, col, t, 0, part);
      try b.put(base + n1 * m.splat(r), n1, col, t, 0, part);
      try b.put(tip, dir, col, t, 1, part);
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
      const th = @as(f32, @floatFromInt(ri + cn[0])) / @as(f32, @floatFromInt(R)) * std.math.pi;
      const ph = @as(f32, @floatFromInt(si + cn[1])) / @as(f32, @floatFromInt(S)) * std.math.tau;
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
  const N = 10;
  var spine:[N + 1]V3 = undefined;
  var ts:[N + 1]f32 = undefined;
  for (0..N + 1) |i| {
    const k = @as(f32, @floatFromInt(i)) / N;
    spine[i] = m.v3(0, k, 0);
    ts[i] = k;
  }
  // core: a tube whose radius follows the profile (built ring by ring)
  for (0..N) |i| {
    const k0 = ts[i];
    const k1 = ts[i + 1];
    try b.tube(spine[i .. i + 2], ts[i .. i + 2], profile(k0) * 0.72, profile(k1) * 0.72, core, .stem, 8);
  }
  for (0..strands) |s| {
    const a0 = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(strands)) * std.math.tau;
    var path:[N + 1]V3 = undefined;
    for (0..N + 1) |i| {
      const k = ts[i];
      const a = a0 + k * twist;
      const r = profile(k) * 0.8;
      path[i] = m.v3(@cos(a) * r, k, @sin(a) * r);
    }
    for (0..N) |i| try b.tube(path[i .. i + 2], ts[i .. i + 2], profile(ts[i]) * 0.26, profile(ts[i + 1]) * 0.26, vine, .stem, 5);
  }
}

pub fn rgb(c:[3]f32, a:u8) [4]u8 {
  return .{@intFromFloat(m.clamp01(c[0]) * 255), @intFromFloat(m.clamp01(c[1]) * 255), @intFromFloat(m.clamp01(c[2]) * 255), a};
}
fn mixCol(a:[4]u8, b:[4]u8, t:f32) [4]u8 {
  var o:[4]u8 = undefined;
  inline for (0..4) |i| o[i] = @intFromFloat(m.lerp(@floatFromInt(a[i]), @floatFromInt(b[i]), t));
  return o;
}
fn scale(c:[3]f32, k:f32) [3]f32 { return .{c[0] * k, c[1] * k, c[2] * k}; }

/// grow a species' mesh from its genome. Deterministic per species.
pub fn plant(b:*Builder, id:species.Id) !void {
  const g = species.get(id).genome;
  var rng = Rng.init(@intFromEnum(id) + 77);
  const golden = 2.39996;

  // spine: a gentle helix whose amplitude grows with height (curl).
  var spine:[17]V3 = undefined;
  var ts:[17]f32 = undefined;
  const n = @min(g.segments, 16);
  for (0..n + 1) |i| {
    const k = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
    const amp = g.curl * 0.12 * k * k;
    spine[i] = m.v3(amp * @sin(k * 7), g.stem_h * k, amp * @cos(k * 5));
    ts[i] = k;
  }
  try b.tube(spine[0 .. n + 1], ts[0 .. n + 1], g.stem_r, g.stem_r * 0.35, rgb(g.stem_col, 255), .stem, 6);

  // leaves in a phyllotactic spiral up the stem.
  for (0..g.leaves) |i| {
    const k = 0.2 + 0.7 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(@max(g.leaves, 1)));
    const at = spineAt(spine[0 .. n + 1], k);
    const ang = @as(f32, @floatFromInt(i)) * golden;
    const dir = m.v3(@cos(ang), 0, @sin(ang));
    const len = g.leaf_len * (1.1 - 0.5 * k) * rng.range(0.85, 1.15);
    try b.blade(at, dir, len, g.leaf_w, g.leaf_droop, rgb(scale(g.leaf_col, 0.6), 255), rgb(g.leaf_col, 255), k, .leaf);
  }

  // thorns: short cones pointing outward and slightly down.
  for (0..g.thorns) |i| {
    const k = 0.1 + 0.8 * rng.float();
    const at = spineAt(spine[0 .. n + 1], k);
    const ang = @as(f32, @floatFromInt(i)) * golden * 1.3;
    const dir = m.norm(m.v3(@cos(ang), -0.3, @sin(ang)));
    try b.cone(at, dir, 0.07, 0.012, rgb(scale(g.bloom_col, 0.7), 255), k, .thorn);
  }

  // tendrils: thin tubes that leave the stem and coil down toward the ground.
  for (0..g.tendrils) |i| {
    const ang = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(g.tendrils)) * std.math.tau + 0.4;
    var tp:[9]V3 = undefined;
    var tt:[9]f32 = undefined;
    const start = spineAt(spine[0 .. n + 1], 0.35);
    for (0..9) |j| {
      const k = @as(f32, @floatFromInt(j)) / 8;
      const rad = 0.05 + 0.3 * k;
      const a = ang + k * 2.5;
      tp[j] = start + m.v3(@cos(a) * rad, -start[1] * k * 0.95 + 0.06 * @sin(k * 9), @sin(a) * rad);
      tt[j] = 0.35 * (1 - k) + k;
    }
    try b.tube(&tp, &tt, 0.014, 0.004, rgb(g.stem_col, 255), .tendril, 4);
  }

  // bloom: a fan of petals around the tip.
  const top = spine[n];
  for (0..g.petals) |i| {
    const ang = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(g.petals)) * std.math.tau;
    const dir = m.v3(@cos(ang), 0, @sin(ang));
    try b.blade(top, dir, g.bloom_r, g.bloom_r * 0.45, -0.6, rgb(scale(g.bloom_col, 0.8), 255), rgb(g.bloom_col, 255), 1, .bloom);
  }
}

fn spineAt(spine:[]const V3, k:f32) V3 {
  const f = k * @as(f32, @floatFromInt(spine.len - 1));
  const i:usize = @min(@as(usize, @intFromFloat(f)), spine.len - 2);
  const t = f - @as(f32, @floatFromInt(i));
  return spine[i] + (spine[i + 1] - spine[i]) * m.splat(t);
}
