//! a text field, the third of the HUD's components: what is typed into a
//! text input (ui/text_input.zig) grows along a young stem across its box,
//! a bud blinking where the next letter goes. The text and the bud keep to
//! the input's side of the box: its left-hand side, its centre or its
//! right-hand side.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: angles
const m=lib.engine.core.math;
/// a screen rectangle
const Box=lib.hud.Box;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// how far below the box's top the stem runs (pixels)
const stemY:f32=22;
/// how far the stem sways either way (pixels)
const swayPx:f32=1.5;
/// how far (pixels) the text stands in from the side it keeps to
const pad:f32=12;
/// how far after the text the bud sits (pixels)
const budGap:f32=6;
/// the bud where the next letter goes blinks this often (1/s)
const blink:f32=2.2;
/// draws the text of `t` (a `TextInput` of type `T`) on its stem across
/// `b`, its bud blinking after it, at UI time `time`
pub fn draw(comptime T:type,t:*const T,d:*Draw,b:Box,time:f32)Allocator.Error!void{
  // how far the stem sways now (pixels), and its height
  const sway=swayPx*@sin(time*1.3);
  const y=b.y+stemY;
  try d.limb(.{b.x,y+sway},.{b.x+b.w,y-sway},2.5,1.5,s.barkYoung,0);
  // the text, its width, and where it starts on its side of the box
  const text=t.slice();
  const tw=Draw.width(text,s.textHeading);
  _=try d.text(t.textX(b,tw,pad),b.y,s.textHeading,s.white,text);
  // how far the bud is open now, blinking 0..1
  const open=0.5+0.5*@sin(time*blink*m.tau);
  try d.leaf(.{t.caretX(b,tw,pad)+budGap,y-2},-m.halfPi,18,8,s.leaf,open,0.2);
}
