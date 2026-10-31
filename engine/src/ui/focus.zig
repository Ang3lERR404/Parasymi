//! keyboard and gamepad focus: which of a panel's boxes is reached next
//! without the mouse, by the arrows (the nearest box that way) or by
//! stepping through them in the order they were drawn. What the focused box
//! is, and what choosing it does, stays the game's.
/// the standard library
const std=@import("std");
/// a box in screen pixels: what can be focused
const Box=@import("box.zig").Box;
/// which way focus is moved
pub const Dir=enum{
  /// toward the top of the screen
  up,
  /// toward the bottom
  down,
  /// toward the left
  left,
  /// toward the right
  right,
};
/// a box off the line focus moves along counts this much worse for each
/// pixel it is off, so the box straight ahead wins over one nearer but aside
const aside:f32=2;
/// the box of `boxes` focus moves to from box `from` going `dir`: the
/// nearest whose middle lies beyond `from`'s that way, boxes straight ahead
/// first; null when there is none that way
pub fn toward(boxes:[]const Box,from:usize,dir:Dir)?usize{
  // where focus moves from
  const a=boxes[from].center();
  // the best box so far, and how far it is
  var best:?usize=null;
  var bestD:f32=0;
  for(boxes,0..)|b,i|{
    if(i==from)continue;
    // the run to its middle, along the way focus moves and across it
    const c=b.center();
    const dx=c[0]-a[0];
    const dy=c[1]-a[1];
    const along=switch(dir){.up=>-dy,.down=>dy,.left=>-dx,.right=>dx};
    const across=@abs(switch(dir){.up,.down=>dx,.left,.right=>dy});
    if(along<1)continue;
    // how far it is, the run aside counting more
    const d=along+aside*across;
    if(best==null or d<bestD){
      best=i;
      bestD=d;
    }
  }
  return best;
}
/// stepping through `n` boxes in order from `from` (none yet: the first
/// going on, the last going back), round past either end
pub fn step(n:usize,from:?usize,on:Way)?usize{
  if(n==0)return null;
  // the box stepped from
  const i=from orelse return switch(on){.on=>0,.back=>n-1};
  return switch(on){.on=>(i+1)%n,.back=>(i+n-1)%n};
}
/// which way `step` goes through the boxes
pub const Way=enum{
  /// to the next drawn
  on,
  /// to the one drawn before
  back,
};
/// the test helpers
const testing=std.testing;
test"the arrows move focus to the nearest box that way, straight ahead first"{
  // a column of three rows, a button to the right of the middle one
  const boxes=[_]Box{
    .{.x=0,.y=0,.w=100,.h=20},
    .{.x=0,.y=40,.w=100,.h=20},
    .{.x=0,.y=80,.w=100,.h=20},
    .{.x=200,.y=30,.w=40,.h=20},
  };
  try testing.expectEqual(@as(?usize,1),toward(&boxes,0,.down));
  try testing.expectEqual(@as(?usize,2),toward(&boxes,1,.down));
  try testing.expectEqual(@as(?usize,0),toward(&boxes,1,.up));
  try testing.expectEqual(@as(?usize,3),toward(&boxes,1,.right));
  try testing.expectEqual(@as(?usize,1),toward(&boxes,3,.left));
  try testing.expectEqual(null,toward(&boxes,0,.up));
  try testing.expectEqual(null,toward(&boxes,3,.right));
}
test"stepping goes through the boxes in order, round past the ends"{
  try testing.expectEqual(@as(?usize,0),step(3,null,.on));
  try testing.expectEqual(@as(?usize,2),step(3,null,.back));
  try testing.expectEqual(@as(?usize,0),step(3,2,.on));
  try testing.expectEqual(@as(?usize,2),step(3,0,.back));
  try testing.expectEqual(null,step(0,null,.on));
}
