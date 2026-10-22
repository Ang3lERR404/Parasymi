//! the one place for numeric helpers: scalars, angles, tile/world
//! coordinates, SIMD vectors and column-major 4x4 matrices (Vulkan clip
//! space: y down, depth 0..1). World: x east, y up, z south; 1 tile = 1 unit.
//! Game code uses this instead of reaching into std.math directly.
const std = @import("std");
const math = std.math;
const testing = std.testing;
const assert = std.debug.assert;

pub const V2 = @Vector(2, f32);
pub const V3 = @Vector(3, f32);
pub const V4 = @Vector(4, f32);
pub const M4 = [4]V4;

// ---- scalars ----

pub const pi = math.pi;
pub const tau = math.tau;
pub const clamp = math.clamp;
pub const pow = math.pow;
pub const maxInt = math.maxInt;

/// integer (or comptime number) to f32: the cast written everywhere else.
pub inline fn f(x:anytype) f32 { return @floatFromInt(x); }
pub inline fn lerp(a:f32, b:f32, t:f32) f32 { return a + (b - a) * t; }
pub inline fn clamp01(x:f32) f32 { return math.clamp(x, 0, 1); }
pub inline fn smooth(t:f32) f32 { return t * t * (3 - 2 * t); }
/// whole units of a non-negative float (e.g. ripe seeds) as integer type T.
pub inline fn floorTo(comptime T:type, x:f32) T { return @intFromFloat(@floor(x)); }
/// fraction of `a` over `b` as f32 (e.g. progress counters).
pub inline fn ratio(a:anytype, b:anytype) f32 { return f(a) / f(b); }

// ---- angles ----

pub inline fn atan2(y:f32, x:f32) f32 { return math.atan2(y, x); }
/// shortest signed difference `to - from`, wrapped into -pi..pi.
pub inline fn angleDiff(from:f32, to:f32) f32 { return atan2(@sin(to - from), @cos(to - from)); }

// ---- tiles ----

/// the tile containing a world coordinate.
pub inline fn tileOf(x:f32) i32 { return @intFromFloat(@floor(x)); }
/// the tile (x, z) under a world position.
pub inline fn tileAt(p:V3) [2]i32 { return .{tileOf(p[0]), tileOf(p[2])}; }
/// world-space centre of a size x size footprint anchored at tile (x, z).
pub inline fn footprintCentre(x:i32, z:i32, size:u8, y:f32) V3 {
  const half = f(size) / 2;
  return .{f(x) + half, y, f(z) + half};
}
/// world-space centre of tile (x, z) at height y.
pub inline fn tileCentre(x:i32, z:i32, y:f32) V3 { return footprintCentre(x, z, 1, y); }

/// one of four facings: +x (east), +z (south), -x (west), -z (north).
pub const Dir = u2;
pub fn dirVec(d:Dir) [2]i32 {
  return switch (d) { 0 => .{1, 0}, 1 => .{0, 1}, 2 => .{-1, 0}, 3 => .{0, -1} };
}
/// yaw that turns a +x-facing model to face `d`.
pub inline fn dirYaw(d:Dir) f32 { return -f(d) * pi / 2.0; }

// ---- vectors ----

pub inline fn v3(x:f32, y:f32, z:f32) V3 { return .{x, y, z}; }
pub inline fn splat(s:f32) V3 { return @splat(s); }
pub inline fn dot(a:V3, b:V3) f32 { return @reduce(.Add, a * b); }
pub inline fn len(a:V3) f32 { return @sqrt(dot(a, a)); }
pub inline fn norm(a:V3) V3 {
  const l = len(a);
  return if (l > 1e-8) a / splat(l) else a;
}
pub inline fn cross(a:V3, b:V3) V3 {
  return .{a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0]};
}
pub inline fn lerpV(a:V3, b:V3, t:f32) V3 { return a + (b - a) * splat(t); }
/// a point at fraction `k` (0..1) along a polyline.
pub fn alongPath(path:[]const V3, k:f32) V3 {
  const pos = k * f(path.len - 1);
  const i:usize = @min(@as(usize, @intFromFloat(pos)), path.len - 2);
  return lerpV(path[i], path[i + 1], pos - f(i));
}

// ---- splines ----

/// the Catmull-Rom curve between `p1` (t=0) and `p2` (t=1); `p0` and `p3`
/// shape the tangents at either end.
pub fn catmullRom(p0:V3, p1:V3, p2:V3, p3:V3, t:f32) V3 {
  const t2 = t * t;
  const t3 = t2 * t;
  return (p1 * splat(2) + (p2 - p0) * splat(t) +
    (p0 * splat(2) - p1 * splat(5) + p2 * splat(4) - p3) * splat(t2) +
    (p1 * splat(3) - p0 - p2 * splat(3) + p3) * splat(t3)) * splat(0.5);
}

pub const MAX_SPLINE = 64;
const DENSE = 8;

/// resample the Catmull-Rom spline through every point of `pts` into `out`,
/// evenly spaced by arc length. The end points repeat as their own outer
/// control points, so the curve starts and ends exactly on them.
pub fn splineResample(pts:[]const V3, out:[]V3) void {
  assert(pts.len >= 2 and pts.len <= MAX_SPLINE and out.len >= 2);
  const n = pts.len;
  // dense samples along the curve, with cumulative length
  var dense:[(MAX_SPLINE - 1) * DENSE + 1]V3 = undefined;
  var at:[(MAX_SPLINE - 1) * DENSE + 1]f32 = undefined;
  var k:usize = 0;
  for (0..n - 1) |seg| {
    const p0 = pts[if (seg == 0) 0 else seg - 1];
    const p3 = pts[@min(seg + 2, n - 1)];
    for (0..DENSE) |j| {
      dense[k] = catmullRom(p0, pts[seg], pts[seg + 1], p3, ratio(j, DENSE));
      k += 1;
    }
  }
  dense[k] = pts[n - 1];
  at[0] = 0;
  for (1..k + 1) |i| at[i] = at[i - 1] + len(dense[i] - dense[i - 1]);
  const total = at[k];
  // walk the dense polyline, emitting a point every total/(out.len-1)
  var i:usize = 0;
  for (out, 0..) |*o, j| {
    const want = total * ratio(j, out.len - 1);
    while (i + 1 < k and at[i + 1] < want) i += 1;
    const span = at[i + 1] - at[i];
    o.* = lerpV(dense[i], dense[i + 1], if (span > 1e-8) clamp01((want - at[i]) / span) else 0);
  }
}

pub const identity:M4 = .{
  .{1, 0, 0, 0}, .{0, 1, 0, 0}, .{0, 0, 1, 0}, .{0, 0, 0, 1},
};

pub fn mul(a:M4, b:M4) M4 {
  var r:M4 = undefined;
  inline for (0..4) |c| {
    r[c] = a[0] * @as(V4, @splat(b[c][0])) + a[1] * @as(V4, @splat(b[c][1])) +
      a[2] * @as(V4, @splat(b[c][2])) + a[3] * @as(V4, @splat(b[c][3]));
  }
  return r;
}

pub fn mulV(m:M4, v:V4) V4 {
  return m[0] * @as(V4, @splat(v[0])) + m[1] * @as(V4, @splat(v[1])) +
    m[2] * @as(V4, @splat(v[2])) + m[3] * @as(V4, @splat(v[3]));
}

/// right-handed perspective for Vulkan (y flipped, depth 0..1).
pub fn perspective(fovy:f32, aspect:f32, near:f32, far:f32) M4 {
  const k = 1 / @tan(fovy * 0.5);
  return .{
    .{k / aspect, 0, 0, 0},
    .{0, -k, 0, 0},
    .{0, 0, far / (near - far), -1},
    .{0, 0, near * far / (near - far), 0},
  };
}

pub fn lookAt(eye:V3, at:V3, up:V3) M4 {
  const fw = norm(at - eye);
  const s = norm(cross(fw, up));
  const u = cross(s, fw);
  return .{
    .{s[0], u[0], -fw[0], 0},
    .{s[1], u[1], -fw[1], 0},
    .{s[2], u[2], -fw[2], 0},
    .{-dot(s, eye), -dot(u, eye), dot(fw, eye), 1},
  };
}

pub fn translate(t:V3) M4 {
  return .{.{1, 0, 0, 0}, .{0, 1, 0, 0}, .{0, 0, 1, 0}, .{t[0], t[1], t[2], 1}};
}
pub fn scale3(s:V3) M4 {
  return .{.{s[0], 0, 0, 0}, .{0, s[1], 0, 0}, .{0, 0, s[2], 0}, .{0, 0, 0, 1}};
}
pub fn rotX(a:f32) M4 {
  const c = @cos(a); const s = @sin(a);
  return .{.{1, 0, 0, 0}, .{0, c, s, 0}, .{0, -s, c, 0}, .{0, 0, 0, 1}};
}
pub fn rotY(a:f32) M4 {
  const c = @cos(a); const s = @sin(a);
  return .{.{c, 0, -s, 0}, .{0, 1, 0, 0}, .{s, 0, c, 0}, .{0, 0, 0, 1}};
}
pub fn rotZ(a:f32) M4 {
  const c = @cos(a); const s = @sin(a);
  return .{.{c, s, 0, 0}, .{-s, c, 0, 0}, .{0, 0, 1, 0}, .{0, 0, 0, 1}};
}
/// chain transforms parent-first: chain(.{a, b, c}) == a * b * c.
pub fn chain(ms:anytype) M4 {
  var r:M4 = identity;
  inline for (ms) |x| r = mul(r, x);
  return r;
}
pub fn origin(a:M4) V3 { return .{a[3][0], a[3][1], a[3][2]}; }

/// a rotation taking +Y onto `dir` (a unit vector); the roll around it is arbitrary.
pub fn alignY(dir:V3) M4 {
  const ref = if (@abs(dir[2]) < 0.9) v3(0, 0, 1) else v3(1, 0, 0);
  const x = norm(cross(dir, ref));
  const z = cross(x, dir);
  return .{.{x[0], x[1], x[2], 0}, .{dir[0], dir[1], dir[2], 0}, .{z[0], z[1], z[2], 0}, .{0, 0, 0, 1}};
}

/// critically damped spring step (for procedural secondary motion).
/// Uses the exact closed-form solution, so it is stable for any `dt`: a long
/// frame can never make it overshoot or blow up.
pub fn spring(pos:*f32, vel:*f32, target:f32, freq:f32, dt:f32) void {
  const x = pos.* - target;
  const j = vel.* + freq * x;
  const e = @exp(-freq * dt);
  pos.* = target + (x + j * dt) * e;
  vel.* = (vel.* - freq * j * dt) * e;
}

/// a damped spring-mass pulling `pos` toward `rest` under an extra `force`:
/// `m a = -k (pos - rest) - c v + force`. Substepped so stiff springs stay
/// stable over long frames.
pub fn springDamper(pos:*V3, vel:*V3, rest:V3, k:f32, c:f32, mass:f32, force:V3, dt:f32) void {
  const n = @max(@as(u32, @intFromFloat(@ceil(dt * 240))), 1);
  const h = dt / f(n);
  for (0..n) |_| {
    const acc = (force - (pos.* - rest) * splat(k) - vel.* * splat(c)) / splat(mass);
    vel.* += acc * splat(h);
    pos.* += vel.* * splat(h);
  }
}

test "spring-damper settles where its force balances" {
  var p = v3(0, 0, 0);
  var v = v3(1, 0, 0);
  for (0..120) |_| springDamper(&p, &v, v3(0, 1, 0), 60, 6, 0.8, v3(0, 0, 3), 1.0 / 30.0);
  try testing.expect(len(p - v3(0, 1, 0.05)) < 1e-3);
  try testing.expect(len(v) < 1e-3);
}

test "spring is stable for huge steps" {
  var p:f32 = 0;
  var v:f32 = 50;
  for (0..20) |_| spring(&p, &v, 1, 7, 0.75);
  try testing.expectApproxEqAbs(@as(f32, 1), p, 1e-3);
  try testing.expect(@abs(v) < 1e-2);
}

/// general 4x4 inverse (cofactor expansion), used for mouse picking.
pub fn inverse(m:M4) M4 {
  var a:[16]f32 = undefined;
  inline for (0..4) |c| inline for (0..4) |r| { a[c*4 + r] = m[c][r]; };
  var inv:[16]f32 = undefined;
  inv[0] = a[5]*a[10]*a[15] - a[5]*a[11]*a[14] - a[9]*a[6]*a[15] + a[9]*a[7]*a[14] + a[13]*a[6]*a[11] - a[13]*a[7]*a[10];
  inv[4] = -a[4]*a[10]*a[15] + a[4]*a[11]*a[14] + a[8]*a[6]*a[15] - a[8]*a[7]*a[14] - a[12]*a[6]*a[11] + a[12]*a[7]*a[10];
  inv[8] = a[4]*a[9]*a[15] - a[4]*a[11]*a[13] - a[8]*a[5]*a[15] + a[8]*a[7]*a[13] + a[12]*a[5]*a[11] - a[12]*a[7]*a[9];
  inv[12] = -a[4]*a[9]*a[14] + a[4]*a[10]*a[13] + a[8]*a[5]*a[14] - a[8]*a[6]*a[13] - a[12]*a[5]*a[10] + a[12]*a[6]*a[9];
  inv[1] = -a[1]*a[10]*a[15] + a[1]*a[11]*a[14] + a[9]*a[2]*a[15] - a[9]*a[3]*a[14] - a[13]*a[2]*a[11] + a[13]*a[3]*a[10];
  inv[5] = a[0]*a[10]*a[15] - a[0]*a[11]*a[14] - a[8]*a[2]*a[15] + a[8]*a[3]*a[14] + a[12]*a[2]*a[11] - a[12]*a[3]*a[10];
  inv[9] = -a[0]*a[9]*a[15] + a[0]*a[11]*a[13] + a[8]*a[1]*a[15] - a[8]*a[3]*a[13] - a[12]*a[1]*a[11] + a[12]*a[3]*a[9];
  inv[13] = a[0]*a[9]*a[14] - a[0]*a[10]*a[13] - a[8]*a[1]*a[14] + a[8]*a[2]*a[13] + a[12]*a[1]*a[10] - a[12]*a[2]*a[9];
  inv[2] = a[1]*a[6]*a[15] - a[1]*a[7]*a[14] - a[5]*a[2]*a[15] + a[5]*a[3]*a[14] + a[13]*a[2]*a[7] - a[13]*a[3]*a[6];
  inv[6] = -a[0]*a[6]*a[15] + a[0]*a[7]*a[14] + a[4]*a[2]*a[15] - a[4]*a[3]*a[14] - a[12]*a[2]*a[7] + a[12]*a[3]*a[6];
  inv[10] = a[0]*a[5]*a[15] - a[0]*a[7]*a[13] - a[4]*a[1]*a[15] + a[4]*a[3]*a[13] + a[12]*a[1]*a[7] - a[12]*a[3]*a[5];
  inv[14] = -a[0]*a[5]*a[14] + a[0]*a[6]*a[13] + a[4]*a[1]*a[14] - a[4]*a[2]*a[13] - a[12]*a[1]*a[6] + a[12]*a[2]*a[5];
  inv[3] = -a[1]*a[6]*a[11] + a[1]*a[7]*a[10] + a[5]*a[2]*a[11] - a[5]*a[3]*a[10] - a[9]*a[2]*a[7] + a[9]*a[3]*a[6];
  inv[7] = a[0]*a[6]*a[11] - a[0]*a[7]*a[10] - a[4]*a[2]*a[11] + a[4]*a[3]*a[10] + a[8]*a[2]*a[7] - a[8]*a[3]*a[6];
  inv[11] = -a[0]*a[5]*a[11] + a[0]*a[7]*a[9] + a[4]*a[1]*a[11] - a[4]*a[3]*a[9] - a[8]*a[1]*a[7] + a[8]*a[3]*a[5];
  inv[15] = a[0]*a[5]*a[10] - a[0]*a[6]*a[9] - a[4]*a[1]*a[10] + a[4]*a[2]*a[9] + a[8]*a[1]*a[6] - a[8]*a[2]*a[5];
  const det = a[0]*inv[0] + a[1]*inv[4] + a[2]*inv[8] + a[3]*inv[12];
  const id = if (det != 0) 1 / det else 0;
  var r:M4 = undefined;
  inline for (0..4) |c| inline for (0..4) |rr| { r[c][rr] = inv[c*4 + rr] * id; };
  return r;
}

/// a matrix whose upper 3x3 has rows `r0..r2` (inverse of the linear part)
/// and translation `-R * t`, undoing a translation `t`.
fn fromRows(r0:V3, r1:V3, r2:V3, t:V3) M4 {
  return .{
    .{r0[0], r1[0], r2[0], 0},
    .{r0[1], r1[1], r2[1], 0},
    .{r0[2], r1[2], r2[2], 0},
    .{-dot(r0, t), -dot(r1, t), -dot(r2, t), 1},
  };
}

fn column(m:M4, c:usize) V3 { return .{m[c][0], m[c][1], m[c][2]}; }

/// inverse of an affine transform (any rotation/scale/shear + translation;
/// bottom row 0 0 0 1). The 3x3 inverts by cofactors: its rows are the
/// cross products of the columns over the determinant.
pub fn inverseAffine(m:M4) M4 {
  const c0 = column(m, 0);
  const c1 = column(m, 1);
  const c2 = column(m, 2);
  const x12 = cross(c1, c2);
  const det = dot(c0, x12);
  const id = splat(if (det != 0) 1 / det else 0);
  return fromRows(x12 * id, cross(c2, c0) * id, cross(c0, c1) * id, column(m, 3));
}

/// inverse of a rigid transform (rotation + translation only): the rotation
/// transposes.
pub fn inverseRigid(m:M4) M4 {
  return fromRows(column(m, 0), column(m, 1), column(m, 2), column(m, 3));
}

test "inverse roundtrip" {
  const p = mul(perspective(0.8, 1.5, 0.1, 100), lookAt(v3(3, 10, 8), v3(0, 0, 0), v3(0, 1, 0)));
  const i = mul(inverse(p), p);
  inline for (0..4) |c| inline for (0..4) |r| {
    try testing.expectApproxEqAbs(identity[c][r], i[c][r], 1e-3);
  };
}

test "affine and rigid inverses" {
  const aff = chain(.{translate(v3(3, -2, 5)), rotY(0.7), rotX(-0.4), scale3(v3(2, 0.5, 1.5))});
  const rig = chain(.{translate(v3(-1, 4, 2)), rotY(1.9), rotZ(0.3)});
  for ([_]M4{mul(inverseAffine(aff), aff), mul(aff, inverseAffine(aff)), mul(inverseRigid(rig), rig)}) |i| {
    inline for (0..4) |c| inline for (0..4) |r| {
      try testing.expectApproxEqAbs(identity[c][r], i[c][r], 1e-4);
    };
  }
  const ia = inverseAffine(aff);
  const ig = inverse(aff);
  inline for (0..4) |c| inline for (0..4) |r| {
    try testing.expectApproxEqAbs(ig[c][r], ia[c][r], 1e-4);
  };
}

test "catmull-rom passes through its inner points" {
  const a = v3(0, 0, 0);
  const b = v3(1, 2, 0);
  const c = v3(3, 2, 1);
  const d = v3(4, 0, 1);
  try testing.expectEqual(b, catmullRom(a, b, c, d, 0));
  const e = catmullRom(a, b, c, d, 1);
  try testing.expect(len(e - c) < 1e-5);
  // evenly spaced collinear points give a straight, uniformly paced line
  const mid = catmullRom(v3(0, 0, 0), v3(1, 0, 0), v3(2, 0, 0), v3(3, 0, 0), 0.5);
  try testing.expect(len(mid - v3(1.5, 0, 0)) < 1e-5);
}

test "spline resampling keeps the ends and evens the spacing" {
  const pts = [_]V3{v3(0, 0, 0), v3(0, 1, 0), v3(0.2, 3, 0), v3(1, 3.5, 0.5)};
  var out:[16]V3 = undefined;
  splineResample(&pts, &out);
  try testing.expect(len(out[0] - pts[0]) < 1e-5);
  try testing.expect(len(out[15] - pts[3]) < 1e-4);
  const step = len(out[1] - out[0]);
  for (1..out.len) |i| try testing.expectApproxEqAbs(step, len(out[i] - out[i - 1]), step * 0.1);
}

test "alignY maps +Y onto the direction, orthonormally" {
  for ([_]V3{v3(0, 1, 0), v3(0, 0, 1), norm(v3(1, -2, 0.5))}) |d| {
    const r = alignY(d);
    const y = mulV(r, .{0, 1, 0, 0});
    try testing.expect(len(v3(y[0], y[1], y[2]) - d) < 1e-5);
    const x = v3(r[0][0], r[0][1], r[0][2]);
    const z = v3(r[2][0], r[2][1], r[2][2]);
    try testing.expectApproxEqAbs(@as(f32, 1), dot(cross(x, d), z), 1e-5);
  }
}
