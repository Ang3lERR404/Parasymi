//! colour helpers. Colours travel to the GPU as 8-bit RGBA (sRGB-ish, the
//! shaders linearise them) and are authored as 0..1 floats.
const m = @import("math.zig");

pub const Rgba8 = [4]u8;
pub const Rgb = [3]f32;

inline fn byte(x:f32) u8 { return @intFromFloat(m.clamp01(x) * 255); }

/// 0..1 rgb plus an alpha byte -> RGBA8.
pub fn rgb(c:Rgb, a:u8) Rgba8 { return .{byte(c[0]), byte(c[1]), byte(c[2]), a}; }

/// rgb scaled by k, opaque.
pub fn shade(c:Rgb, k:f32) Rgba8 { return rgb(scale(c, k), 255); }

pub fn scale(c:Rgb, k:f32) Rgb { return .{c[0] * k, c[1] * k, c[2] * k}; }

pub fn mix(a:Rgba8, b:Rgba8, t:f32) Rgba8 {
  var o:Rgba8 = undefined;
  inline for (0..4) |i| o[i] = @intFromFloat(m.lerp(m.f(a[i]), m.f(b[i]), t));
  return o;
}

/// RGBA8 -> 0..1 rgb with an explicit 4th component (e.g. a tint weight).
pub fn toF(c:Rgba8, w:f32) [4]f32 { return .{m.f(c[0]) / 255, m.f(c[1]) / 255, m.f(c[2]) / 255, w}; }
