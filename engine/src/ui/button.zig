//! a button, as far as the mouse goes: its box and the pointer decide which
//! of five states it is in (idle, hovering, pressed, held, released), so
//! each button worries only about how it looks in each. A click is mouse1
//! let go over the button it went down on (`clicked`), so sliding off before
//! letting go takes it back. What a click does stays the game's.
/// the standard library
const std=@import("std");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=@import("../core/math.zig");
/// deep equality, to tell the button let go over from the one pressed
const eqlDeep=std.meta.eql;
/// a box in screen pixels: where the button sits and what the mouse lands on
const Box=@import("box.zig").Box;
/// what the main mouse button (mouse1, the left) and the cursor are doing
/// this frame, as the game reads them from its own bindings
pub const Pointer=struct{
  /// the cursor (screen pixels)
  at:m.Vice(f32,2)=.{0,0},
  /// mouse1 is held down this frame
  down:bool=false,
  /// mouse1 went down this very frame
  went:bool=false,
  /// mouse1 was let go this very frame
  up:bool=false,
};
/// the five states a button can be in
pub const State=enum{
  /// the mouse is elsewhere
  idle,
  /// the mouse is over it, mouse1 up
  hovering,
  /// mouse1 went down over it this frame
  pressed,
  /// mouse1 is held down over it (after the frame it was pressed)
  held,
  /// mouse1 was let go over it this frame (a click, if it went down on it)
  released,
  /// whether the mouse is over it at all
  pub fn over(st:State)bool{return st!=.idle;}
  /// whether mouse1 is down on it (pressed or held)
  pub fn down(st:State)bool{return st==.pressed or st==.held;}
};
/// the state of a button laid out in `b`, under the pointer `p`
pub fn state(b:Box,p:Pointer)State{
  if(!b.contains(p.at))return.idle;
  if(p.went)return.pressed;
  if(p.up)return.released;
  return if(p.down).held else.hovering;
}
/// what a press and its release make of a button, followed frame by frame:
/// which button (by the game's own `Id` for it) mouse1 went down on, so a
/// release over that same one is a click and over any other is none
pub fn Press(comptime Id:type)type{
  return struct{
    /// this press's own type
    const Self=@This();
    /// the button mouse1 went down on, while it is held
    on:?Id=null,
    /// a frame of the pointer `p` over the button `over` (null: none):
    /// the button clicked this frame, if any
    pub fn track(s:*Self,p:Pointer,over:?Id)?Id{
      if(p.went){
        s.on=over;
        return null;
      }
      if(!p.up)return null;
      // the button it went down on, let go of now
      const was=s.on;
      s.on=null;
      const a=was orelse return null;
      const b=over orelse return null;
      return if(eqlDeep(a,b))a else null;
    }
  };
}
/// the test helpers
const testing=std.testing;
test"a button is idle away from the mouse, hovered under it, pressed the frame mouse1 goes down, held after and released when let go"{
  // a 40 by 20 button round (100, 100)
  const b=Box.around(.{100,100},40,20);
  try testing.expectEqual(State.idle,state(b,.{.at=.{10,10}}));
  try testing.expectEqual(State.idle,state(b,.{.at=.{10,10},.down=true,.went=true}));
  try testing.expectEqual(State.hovering,state(b,.{.at=.{100,100}}));
  try testing.expectEqual(State.pressed,state(b,.{.at=.{100,100},.down=true,.went=true}));
  try testing.expectEqual(State.held,state(b,.{.at=.{100,100},.down=true}));
  try testing.expectEqual(State.released,state(b,.{.at=.{100,100},.up=true}));
  try testing.expect(State.held.down() and State.pressed.over() and !State.hovering.down() and !State.idle.over() and !State.released.down());
}
test"a click is a release over the button pressed; sliding off takes it back"{
  // a press over buttons numbered by u8
  var p=Press(u8){};
  try testing.expectEqual(null,p.track(.{.went=true,.down=true},3));
  try testing.expectEqual(null,p.track(.{.down=true},3));
  try testing.expectEqual(@as(?u8,3),p.track(.{.up=true},3));
  // pressed on 3, let go over 4: nothing
  _=p.track(.{.went=true,.down=true},3);
  try testing.expectEqual(null,p.track(.{.up=true},4));
  // pressed on nothing, let go over 3: nothing
  _=p.track(.{.went=true,.down=true},null);
  try testing.expectEqual(null,p.track(.{.up=true},3));
}
