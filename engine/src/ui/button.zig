//! a button, as far as the mouse goes: its box and the pointer decide which
//! of four states it is in (idle, hovering, pressed, held), so each button
//! worries only about how it looks in each. What a click does stays the
//! game's.
/// the standard library
const std=@import("std");
/// a box in screen pixels: where the button sits and what the mouse lands on
const Box=@import("box.zig").Box;
/// what the main mouse button (mouse1, the left) and the cursor are doing
/// this frame, as the game reads them from its own bindings
pub const Pointer=struct{
  /// the cursor (screen pixels)
  at:[2]f32=.{0,0},
  /// mouse1 is held down this frame
  down:bool=false,
  /// mouse1 went down this very frame
  went:bool=false,
};
/// the four states a button can be in
pub const State=enum{
  /// the mouse is elsewhere
  idle,
  /// the mouse is over it, mouse1 up
  hovering,
  /// mouse1 went down over it this frame
  pressed,
  /// mouse1 is held down over it (after the frame it was pressed)
  held,
  /// whether the mouse is over it at all (hovering, pressed or held)
  pub fn over(st:State)bool{return st!=.idle;}
  /// whether mouse1 is down on it (pressed or held)
  pub fn down(st:State)bool{return st==.pressed or st==.held;}
};
/// the state of a button laid out in `b`, under the pointer `p`
pub fn state(b:Box,p:Pointer)State{
  if(!b.contains(p.at))return.idle;
  if(p.went)return.pressed;
  return if(p.down).held else.hovering;
}
/// the test helpers
const testing=std.testing;
test"a button is idle away from the mouse, hovered under it, pressed the frame mouse1 goes down and held after"{
  // a 40 by 20 button round (100, 100)
  const b=Box.around(.{100,100},40,20);
  try testing.expectEqual(State.idle,state(b,.{.at=.{10,10}}));
  try testing.expectEqual(State.idle,state(b,.{.at=.{10,10},.down=true,.went=true}));
  try testing.expectEqual(State.hovering,state(b,.{.at=.{100,100}}));
  try testing.expectEqual(State.pressed,state(b,.{.at=.{100,100},.down=true,.went=true}));
  try testing.expectEqual(State.held,state(b,.{.at=.{100,100},.down=true}));
  try testing.expect(State.held.down() and State.pressed.over() and !State.hovering.down() and !State.idle.over());
}
