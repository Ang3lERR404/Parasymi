//! colour helpers. Colours are authored as 0..1 floats (Rgb) and travel
//! to the GPU as 8-bit RGBA (Rgba8); the shaders linearise them.
/// the engine's maths: lerp, byte packing, float casts
const m=@import("math.zig");
/// the standard library
const std=@import("std");
/// the test helpers
const testing=std.testing;
/// a colour as it is authored: red, green and blue, each 0..1 (more for
/// light brighter than white)
pub const Rgb=extern struct{
  /// how red, 0..1
  r:f32,
  /// how green, 0..1
  g:f32,
  /// how blue, 0..1
  b:f32,
  /// the same hue, every channel multiplied by `k` (darker under 1)
  pub fn scale(self:Rgb,k:f32)Rgb{
    return.{.r=self.r*k,.g=self.g*k,.b=self.b*k};
  }
  /// the colour `t` of the way from `a` to `b` (0: a, 1: b), channel by channel
  pub fn lerp(a:Rgb,b:Rgb,t:f32)Rgb{
    return.{
      .r=m.lerp(a.r,b.r,t),
      .g=m.lerp(a.g,b.g,t),
      .b=m.lerp(a.b,b.b,t),
    };
  }
  /// packed for the GPU: each 0..1 channel to a byte, with the given alpha byte
  pub fn toRgba8(self:Rgb,a:u8)Rgba8{
    return.{.r=m.unorm8(self.r),.g=m.unorm8(self.g),.b=m.unorm8(self.b),.a=a};
  }
};
/// a colour as the GPU takes it: four bytes, red, green, blue and alpha.
/// Extern so it can sit in vertex layouts (as r8g8b8a8_unorm).
pub const Rgba8=extern struct{
  /// red, 0..255
  r:u8,
  /// green, 0..255
  g:u8,
  /// blue, 0..255
  b:u8,
  /// alpha, 0..255 (255: opaque)
  a:u8,
  /// from the UI's plain [4]u8 colours (ui/draw.zig, item infos), byte for byte
  pub fn of(c:m.Vice(u8,4))Rgba8{return.{.r=c[0],.g=c[1],.b=c[2],.a=c[3]};}
  /// back to 0..1 floats for blending: red, green and blue (alpha discarded)
  pub fn toRgb(self:Rgba8)Rgb{
    return.{.r=m.f(self.r)*inv255,.g=m.f(self.g)*inv255,.b=m.f(self.b)*inv255};
  }
  /// all four bytes as 0..1 floats: red, green, blue, then alpha
  pub fn toF4(self:Rgba8)m.Vice(f32,4){
    return.{m.f(self.r)*inv255,m.f(self.g)*inv255,m.f(self.b)*inv255,m.f(self.a)*inv255};
  }
};
/// one byte's step as a 0..1 float, to unpack bytes by multiplying
const inv255:f32=1.0/255.0;
/// a colour from its three 0..1 channels, red, green, blue
pub fn rgb(r:f32,g:f32,b:f32)Rgb{return.{.r=r,.g=g,.b=b};}
// ---- common colours ----
/// full light on every channel
pub const white:Rgb=.{.r=1,.g=1,.b=1};
/// no light at all
pub const black:Rgb=.{.r=0,.g=0,.b=0};
// ---- module-level helpers (for places that don't have an Rgb yet) ----
/// `c` darkened (or brightened) by `k` and packed, fully opaque
pub fn shade(c:Rgb,k:f32)Rgba8{return c.scale(k).toRgba8(255);}
/// a blend between two packed colours, `t` of the way from `a` to `b`: done
/// in floats (alpha too) and quantised to bytes once at the end
pub fn mix(a:Rgba8,b:Rgba8,t:f32)Rgba8{
  return Rgb.lerp(a.toRgb(),b.toRgb(),t).toRgba8(@intFromFloat(m.lerp(m.f(a.a),m.f(b.a),t)));
}
// ---- tests ----
test"lerp is linear and symmetric"{
  // two colours, one rising where the other falls
  const a:Rgb=.{.r=0,.g=0.5,.b=1};
  const b:Rgb=.{.r=1,.g=0,.b=0};
  // the halfway colour
  const mid=Rgb.lerp(a,b,0.5);
  try testing.expectApproxEqAbs(@as(f32,0.5),mid.r,1e-6);
  try testing.expectApproxEqAbs(@as(f32,0.25),mid.g,1e-6);
  try testing.expectApproxEqAbs(@as(f32,0.5),mid.b,1e-6);
  // the halfway colour from the other side, which must agree
  const back=Rgb.lerp(b,a,0.5);
  try testing.expectApproxEqAbs(mid.r,back.r,1e-6);
}
test"roundtrip rgb -> rgba8 -> rgb"{
  // a colour off the byte grid
  const c:Rgb=.{.r=0.4,.g=0.7,.b=0.9};
  // packed into bytes
  const r8=c.toRgba8(255);
  // and unpacked again, within one byte step of where it began
  const back=r8.toRgb();
  try testing.expectApproxEqAbs(c.r,back.r,1.0/255.0);
  try testing.expectApproxEqAbs(c.g,back.g,1.0/255.0);
  try testing.expectApproxEqAbs(c.b,back.b,1.0/255.0);
}
test"mix keeps its endpoints and lerps every channel"{
  // two packed colours differing on every channel, alpha too
  const a:Rgba8=.{.r=0,.g=100,.b=255,.a=0};
  const b:Rgba8=.{.r=255,.g=200,.b=55,.a=255};
  try testing.expectEqual(a,mix(a,b,0));
  try testing.expectEqual(b,mix(a,b,1));
  // the halfway blend
  const mid=mix(a,b,0.5);
  // quantised once, so each channel is within one step of the exact midpoint
  try testing.expect(@abs(@as(i32,mid.r)-127)<=1);
  try testing.expect(@abs(@as(i32,mid.g)-150)<=1);
  try testing.expect(@abs(@as(i32,mid.b)-155)<=1);
  try testing.expect(@abs(@as(i32,mid.a)-127)<=1);
}
