//! the one place for numeric helpers: scalars, angles, tile/world
//! coordinates, SIMD vectors and column-major 4x4 matrices (Vulkan clip
//! space: y down, depth 0..1). World: x east, y up, z south; 1 tile = 1 unit.
//! Game code uses this instead of reaching into std.math directly.
const std = @import("std");
const math = std.math;
const testing = std.testing;

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

test "inverse roundtrip" {
  const p = mul(perspective(0.8, 1.5, 0.1, 100), lookAt(v3(3, 10, 8), v3(0, 0, 0), v3(0, 1, 0)));
  const i = mul(inverse(p), p);
  inline for (0..4) |c| inline for (0..4) |r| {
    try testing.expectApproxEqAbs(identity[c][r], i[c][r], 1e-3);
  };
}
