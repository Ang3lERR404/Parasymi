//! colour helpers. Colours are authored as 0..1 floats (Rgb) and travel
//! to the GPU as 8-bit RGBA (Rgba8); the shaders linearise them.
const m=@import("math.zig");
const std=@import("std");
const testing=std.testing;
pub const Rgb=extern struct{
  r:f32,g:f32,b:f32,
  pub fn scale(self:Rgb,k:f32)Rgb{
    return.{.r=self.r*k,.g=self.g*k,.b=self.b*k};
  }
  pub fn lerp(a:Rgb,b:Rgb,t:f32)Rgb{
    return.{
      .r=m.lerp(a.r,b.r,t),
      .g=m.lerp(a.g,b.g,t),
      .b=m.lerp(a.b,b.b,t),
    };
  }
  /// 0..1 rgb -> 8-bit RGBA with the given alpha byte.
  pub fn toRgba8(self:Rgb,a:u8)Rgba8{
    return.{.r=m.unorm8(self.r),.g=m.unorm8(self.g),.b=m.unorm8(self.b),.a=a};
  }
};
/// extern so it can sit in GPU vertex layouts (as r8g8b8a8_unorm).
pub const Rgba8=extern struct{
  r:u8,g:u8,b:u8,a:u8,
  /// from the UI's plain [4]u8 colours (ui/draw.zig, item infos).
  pub fn of(c:[4]u8)Rgba8{return.{.r=c[0],.g=c[1],.b=c[2],.a=c[3]};}
  /// 8-bit RGBA -> 0..1 f32 rgb (alpha discarded).
  pub fn toRgb(self:Rgba8)Rgb{
    return.{.r=m.f(self.r)*inv255,.g=m.f(self.g)*inv255,.b=m.f(self.b)*inv255};
  }
  /// 8-bit RGBA -> 4-component f32 (rgb 0..1, alpha 0..1).
  pub fn toF4(self:Rgba8)[4]f32{
    return.{m.f(self.r)*inv255,m.f(self.g)*inv255,m.f(self.b)*inv255,m.f(self.a)*inv255};
  }
};
const inv255:f32=1.0/255.0;
pub fn rgb(r:f32,g:f32,b:f32)Rgb{return.{.r=r,.g=g,.b=b};}
// ---- common colours ----
pub const white:Rgb=.{.r=1,.g=1,.b=1};
pub const black:Rgb=.{.r=0,.g=0,.b=0};
// ---- module-level helpers (for places that don't have an Rgb yet) ----
/// rgb scaled by k, opaque.
pub fn shade(c:Rgb,k:f32)Rgba8{return c.scale(k).toRgba8(255);}
/// f32-space lerp between two 8-bit colours, quantized once at the end.
pub fn mix(a:Rgba8,b:Rgba8,t:f32)Rgba8{
  return Rgb.lerp(a.toRgb(),b.toRgb(),t).toRgba8(@intFromFloat(m.lerp(m.f(a.a),m.f(b.a),t)));
}
// ---- tests ----
test"lerp is linear and symmetric"{
  const a:Rgb=.{.r=0,.g=0.5,.b=1};
  const b:Rgb=.{.r=1,.g=0,.b=0};
  const mid=Rgb.lerp(a,b,0.5);
  try testing.expectApproxEqAbs(@as(f32,0.5),mid.r,1e-6);
  try testing.expectApproxEqAbs(@as(f32,0.25),mid.g,1e-6);
  try testing.expectApproxEqAbs(@as(f32,0.5),mid.b,1e-6);
  const back=Rgb.lerp(b,a,0.5);
  try testing.expectApproxEqAbs(mid.r,back.r,1e-6);
}
test"roundtrip rgb -> rgba8 -> rgb"{
  const c:Rgb=.{.r=0.4,.g=0.7,.b=0.9};
  const r8=c.toRgba8(255);
  const back=r8.toRgb();
  try testing.expectApproxEqAbs(c.r,back.r,1.0/255.0);
  try testing.expectApproxEqAbs(c.g,back.g,1.0/255.0);
  try testing.expectApproxEqAbs(c.b,back.b,1.0/255.0);
}
test"mix keeps its endpoints and lerps every channel"{
  const a:Rgba8=.{.r=0,.g=100,.b=255,.a=0};
  const b:Rgba8=.{.r=255,.g=200,.b=55,.a=255};
  try testing.expectEqual(a,mix(a,b,0));
  try testing.expectEqual(b,mix(a,b,1));
  const mid=mix(a,b,0.5);
  // quantised once, so each channel is within one step of the exact midpoint
  try testing.expect(@abs(@as(i32,mid.r)-127)<=1);
  try testing.expect(@abs(@as(i32,mid.g)-150)<=1);
  try testing.expect(@abs(@as(i32,mid.b)-155)<=1);
  try testing.expect(@abs(@as(i32,mid.a)-127)<=1);
}
