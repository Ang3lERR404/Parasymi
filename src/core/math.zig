//! SIMD-friendly vector/matrix helpers. Column-major 4x4, Vulkan clip space
//! (y down, depth 0..1). World: x east, y up, z south; 1 tile = 1 unit.
const std = @import("std");

pub const V2 = @Vector(2, f32);
pub const V3 = @Vector(3, f32);
pub const V4 = @Vector(4, f32);
pub const M4 = [4]V4;

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
pub inline fn lerp(a:f32, b:f32, t:f32) f32 { return a + (b - a) * t; }
pub inline fn clamp01(x:f32) f32 { return std.math.clamp(x, 0, 1); }
pub inline fn smooth(t:f32) f32 { return t * t * (3 - 2 * t); }

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
  const f = 1 / @tan(fovy * 0.5);
  return .{
    .{f / aspect, 0, 0, 0},
    .{0, -f, 0, 0},
    .{0, 0, far / (near - far), -1},
    .{0, 0, near * far / (near - far), 0},
  };
}

pub fn lookAt(eye:V3, at:V3, up:V3) M4 {
  const f = norm(at - eye);
  const s = norm(cross(f, up));
  const u = cross(s, f);
  return .{
    .{s[0], u[0], -f[0], 0},
    .{s[1], u[1], -f[1], 0},
    .{s[2], u[2], -f[2], 0},
    .{-dot(s, eye), -dot(u, eye), dot(f, eye), 1},
  };
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
    try std.testing.expectApproxEqAbs(identity[c][r], i[c][r], 1e-3);
  };
}
