//! a text field, the third of the HUD's components: what is typed into a
//! text input (ui/text_input.zig) grows along a young stem across its box,
//! a bud blinking at its caret, where the next letter goes; a selection is
//! a sheath of sap lit behind its letters. The text keeps to the input's
//! side of the box: its left-hand side, its centre or its right-hand side.
//! A click on it puts the caret between the letters it lands nearest.
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
/// how far after the caret the bud sits (pixels)
const budGap:f32=2;
/// the bud where the next letter goes blinks this often (1/s)
const blink:f32=2.2;
/// the selection's sheath: how far down the letters its middle runs, and
/// its radius (pixels)
const sheathY:f32=8;
/// the selection's sheath's radius (pixels)
const sheathR:f32=11;
/// how wide one character of the field's text is (pixels)
fn charW()f32{return Draw.width(" ",s.textHeading);}
/// which byte of `t` (a `TextInput` of type `T`) laid out in `b` a click
/// at `x` puts the caret before
pub fn caretAt(comptime T:type,t:*const T,b:Box,x:f32)usize{
  return t.at(b,Draw.width(t.slice(),s.textHeading),pad,x,charW());
}
/// draws the text of `t` (a `TextInput` of type `T`) on its stem across
/// `b`, its selection lit behind it and its bud blinking at the caret, at
/// UI time `time`; `over` lights it under the mouse (or the keys)
pub fn draw(comptime T:type,t:*const T,d:*Draw,b:Box,time:f32,over:bool)Allocator.Error!void{
  // how far the stem sways now (pixels), and its height
  const sway=swayPx*@sin(time*1.3);
  const y=b.y+stemY;
  if(over)try d.glow(b.x+b.w/2,y-6,b.w*0.35,s.menuHover);
  try d.limb(.{b.x,y+sway},.{b.x+b.w,y-sway},2.5,1.5,s.barkYoung,0);
  // the text, its width, and where it starts on its side of the box
  const text=t.slice();
  const tw=Draw.width(text,s.textHeading);
  const x0=t.textX(b,tw,pad);
  // the selection's ends, lit behind its letters
  const sel=t.selection();
  if(sel[1]>sel[0]){
    // where it starts and ends across the text
    const xa=x0+Draw.width(text[0..sel[0]],s.textHeading);
    const xb=x0+Draw.width(text[0..sel[1]],s.textHeading);
    try d.limb(.{xa,b.y+sheathY},.{xb,b.y+sheathY},sheathR,sheathR,s.selection,time*3);
  }
  _=try d.text(x0,b.y,s.textHeading,s.white,text);
  // how far the bud is open now, blinking 0..1, and where the caret is
  const open=0.5+0.5*@sin(time*blink*m.tau);
  const cx=x0+Draw.width(text[0..t.caret],s.textHeading);
  try d.leaf(.{cx+budGap,y-2},-m.halfPi,18,8,s.leaf,open,0.2);
}
