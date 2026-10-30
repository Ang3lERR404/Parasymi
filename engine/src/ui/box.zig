//! a box in screen pixels (y down): where a UI component sits, how big it
//! is, and so what the mouse can land on. Every component is laid out by
//! one; its look is drawn inside it, its hit test is the box itself.
/// the standard library
const std=@import("std");
/// a rectangle on screen, in pixels from the top left (y down)
pub const Box=struct{
  /// its left edge (pixels)
  x:f32,
  /// its top edge (pixels)
  y:f32,
  /// how wide it is (pixels)
  w:f32,
  /// how tall it is (pixels)
  h:f32,
  /// a `w` by `h` box centred on `c`
  pub fn around(c:[2]f32,w:f32,h:f32)Box{return.{.x=c[0]-w/2,.y=c[1]-h/2,.w=w,.h=h};}
  /// its centre, as .{x, y}
  pub fn center(b:Box)[2]f32{return.{b.x+b.w/2,b.y+b.h/2};}
  /// the smaller of its sides
  pub fn side(b:Box)f32{return@min(b.w,b.h);}
  /// whether `p` is over it (its left and top edges in, right and bottom out,
  /// so boxes laid edge to edge never both hold a point)
  pub fn contains(b:Box,p:[2]f32)bool{
    return p[0]>=b.x and p[0]<b.x+b.w and p[1]>=b.y and p[1]<b.y+b.h;
  }
  /// where `p` lies across it, (0, 0) at its top left and (1, 1) at its
  /// bottom right
  pub fn local(b:Box,p:[2]f32)[2]f32{return.{(p[0]-b.x)/b.w,(p[1]-b.y)/b.h};}
};
/// the test helpers
const testing=std.testing;
test"a box holds what is over it, and of two edge to edge only one holds their seam"{
  // a 20 by 10 box round (100, 50)
  const a=Box.around(.{100,50},20,10);
  try testing.expect(a.contains(.{100,50}));
  try testing.expect(a.contains(.{90,45}));
  try testing.expect(!a.contains(.{110,50}));
  try testing.expect(!a.contains(.{100,55}));
  // a box laid edge to edge on its right
  const b:Box=.{.x=110,.y=45,.w=20,.h=10};
  try testing.expect(b.contains(.{110,50}));
  try testing.expectEqual([2]f32{100,50},a.center());
  try testing.expectEqual([2]f32{0.5,0.5},a.local(a.center()));
  try testing.expectEqual(@as(f32,10),a.side());
}
