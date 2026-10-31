//! a slider, as far as the mouse goes: where along its track the pointer
//! lies, and so which of its stops it is set to. A slider of `n` stops sets
//! one of `n` values, its first at the track's left end, its last at the
//! right. How it looks stays the game's.
/// the standard library
const std=@import("std");
/// the engine's maths: clamps, rounding, conversions
const m=@import("../core/math.zig");
/// a box in screen pixels: the slider's track
const Box=@import("box.zig").Box;
/// where along the track `b` (drawn in `pad` at either end) the cursor's
/// `x` lies: 0 its left end, 1 its right
pub fn share(b:Box,x:f32,pad:f32)f32{
  // how long the track runs between its ends
  const len=b.w-2*pad;
  return if(len>0)m.clamp01((x-b.x-pad)/len)else 0;
}
/// the stop of `n` nearest `s` along the track (0 the leftmost)
pub fn stop(s:f32,n:usize)usize{
  if(n<2)return 0;
  return@intFromFloat(@round(m.clamp01(s)*m.f(n-1)));
}
/// where along the track stop `i` of `n` sits (0 its left end, 1 its right)
pub fn at(i:usize,n:usize)f32{return if(n<2)0 else m.f(i)/m.f(n-1);}
/// the test helpers
const testing=std.testing;
test"a slider's stops lie evenly along its track, the pointer setting the nearest"{
  // a 120 wide track from x 40, its ends 10 in
  const b:Box=.{.x=40,.y=0,.w=120,.h=20};
  try testing.expectEqual(@as(f32,0),share(b,0,10));
  try testing.expectEqual(@as(f32,0.5),share(b,100,10));
  try testing.expectEqual(@as(f32,1),share(b,500,10));
  try testing.expectEqual(@as(usize,2),stop(0.5,5));
  try testing.expectEqual(@as(usize,1),stop(0.3,5));
  try testing.expectEqual(@as(usize,4),stop(1,5));
  try testing.expectEqual(@as(usize,0),stop(0.9,1));
  try testing.expectEqual(@as(f32,0.75),at(3,5));
}
