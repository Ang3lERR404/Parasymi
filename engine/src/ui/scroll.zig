//! a scrolled list, as far as where it is goes: how many rows down it is
//! wanted (the wheel, a dragged stem, a row brought into view), how far it
//! has eased there, and so where each row sits in view and how much of it
//! shows as it slides past the list's ends. How the rows and the stem look
//! stays the game's.
/// the standard library
const std=@import("std");
/// the engine's maths: clamps, conversions
const m=@import("../core/math.zig");
/// a list `shown` rows tall scrolled over rows of its own
pub const Scroll=struct{
  /// how many rows show at once
  shown:usize,
  /// rows above the first in view, as wanted
  top:f32=0,
  /// rows above the first in view, as shown now (easing toward `top`)
  at:f32=0,
  /// back at its first row at once
  pub fn reset(s:*Scroll)void{
    s.top=0;
    s.at=0;
  }
  /// how far a list of `total` rows can scroll (rows past what fits)
  pub fn most(s:*const Scroll,total:usize)f32{return m.f(total-|s.shown);}
  /// the wheel turned `notches` (away is positive, scrolling up), `per`
  /// rows a notch
  pub fn wheel(s:*Scroll,notches:f32,per:f32)void{s.top-=notches*per;}
  /// its stem dragged to `along` its length (0 top, 1 bottom) over a
  /// list of `total` rows
  pub fn drag(s:*Scroll,along:f32,total:usize)void{s.top=m.clamp01(along)*s.most(total);}
  /// scrolled no further than needed for row `i` to be in view
  pub fn keep(s:*Scroll,i:usize)void{
    // the topmost it may be with row `i` still in view at its bottom
    const first=@max(m.f(i)-m.f(s.shown-|1),0);
    s.top=m.clamp(s.top,first,m.f(i));
  }
  /// a frame `dt` long over a list of `total` rows: what is wanted kept in
  /// range, what is shown easing toward it (`ease` of the way a second)
  pub fn tick(s:*Scroll,total:usize,dt:f32,ease:f32)void{
    s.top=m.clamp(s.top,0,s.most(total));
    s.at+=(s.top-s.at)*@min(1,dt*ease);
  }
  /// where row `i` sits in view now (0 the top row's place; fractions while
  /// easing, negative above the list, `shown` or more below it)
  pub fn place(s:*const Scroll,i:usize)f32{return m.f(i)-s.at;}
  /// how much of row `i` shows (0..1): all inside the list, fading out over
  /// `fadeRows` of a row past either end
  pub fn shows(s:*const Scroll,i:usize,fadeRows:f32)f32{
    // its place, and how far past the list's ends it is
    const p=s.place(i);
    const past=@max(-p,p-m.f(s.shown-|1),0);
    return m.clamp01(1-past/fadeRows);
  }
  /// where along its stem the list is now (0 top, 1 bottom) over `total` rows
  pub fn share(s:*const Scroll,total:usize)f32{
    // how far it can scroll at all
    const room=s.most(total);
    return if(room>0)m.clamp01(s.at/room)else 0;
  }
};
/// the test helpers
const testing=std.testing;
test"a list scrolls by wheel and stem, keeps in range, and eases there"{
  // three rows in view over ten
  var s:Scroll=.{.shown=3};
  try testing.expectEqual(@as(f32,7),s.most(10));
  s.wheel(-2,1.5);
  s.tick(10,1,1);
  try testing.expectEqual(@as(f32,3),s.top);
  try testing.expectEqual(@as(f32,3),s.at);
  // too far up stays at the first row; easing goes part of the way
  s.wheel(20,1);
  s.tick(10,0.25,2);
  try testing.expectEqual(@as(f32,0),s.top);
  try testing.expectApproxEqAbs(@as(f32,1.5),s.at,1e-6);
  s.drag(1,10);
  try testing.expectEqual(@as(f32,7),s.top);
  // a list that fits never scrolls
  s.tick(2,1,1);
  try testing.expectEqual(@as(f32,0),s.top);
  try testing.expectEqual(@as(f32,0),s.share(2));
}
test"a row is brought into view, and fades past the list's ends"{
  // three rows in view, scrolled two down
  var s:Scroll=.{.shown=3,.top=2,.at=2};
  s.keep(6);
  try testing.expectEqual(@as(f32,4),s.top);
  s.keep(1);
  try testing.expectEqual(@as(f32,1),s.top);
  // shown from row 2: rows 2..4 show wholly, row 1 half a row above is gone
  try testing.expectEqual(@as(f32,1),s.shows(3,0.5));
  try testing.expectEqual(@as(f32,0),s.shows(1,0.5));
  s.at=1.25;
  try testing.expectApproxEqAbs(@as(f32,0.5),s.shows(1,0.5),1e-6);
  try testing.expectApproxEqAbs(@as(f32,-0.25),s.place(1),1e-6);
}
