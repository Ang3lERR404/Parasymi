//! a button, the second of the HUD's components: a bud and its label in a
//! box the mouse lands on. The engine says which state it is in (idle,
//! hovering, pressed, held, released: ui/button.zig); this is only how
//! each looks: a closed bud at rest, opening and glowing under the mouse
//! (or the keys), pressed a little shut and in while mouse1 is down on it.
//! Dim when it would do nothing; `call` pulses its glow (asking first).
//! What a click does is its panel's `click` hook, as for any row.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: clamps
const m=lib.engine.core.math;
/// the game itself: what the mouse points at and the pointer
const play=lib.play;
/// the HUD: picks, rows and bullets
const hud=lib.hud;
/// a screen rectangle the mouse can land in
const Box=hud.Box;
/// the engine's button: its states, and which one a box is in
const ui=lib.engine.ui.button;
/// the four states a button can be in
pub const State=ui.State;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the HUD's shared sizes and colours
const s=lib.style;
/// how far a pressed button's label sinks (pixels)
const sink:f32=1;
/// how much of its glow a pressed button keeps (its radius, a share)
const pressedReach:f32=0.82;
/// how open its bud is pressed (a hovered one is fully open)
const pressedOpen:f32=0.7;
/// how open its bud is at rest
const restOpen:f32=0.15;
/// a button's size: a label's (the menus' buttons) or a note's (small ones
/// beside a row)
pub const Size=enum{
  /// a menu's button, at label size
  label,
  /// a small button beside a row, at note size
  note,
  /// its text's scale
  fn text(z:Size)f32{return switch(z){.label=>s.textLabel,.note=>s.textNote};}
  /// its bud's radius (pixels)
  fn bud(z:Size)f32{return switch(z){.label=>9,.note=>5.4};}
  /// how far its bud sits left of its label (pixels)
  fn budGap(z:Size)f32{return switch(z){.label=>22,.note=>12};}
  /// how far its box reaches left of its label, over the bud (pixels)
  fn left(z:Size)f32{return switch(z){.label=>40,.note=>22};}
  /// how far its box reaches right of its label (pixels)
  fn right(z:Size)f32{return switch(z){.label=>20,.note=>8};}
  /// how far above its middle its label's top sits (pixels)
  fn rise(z:Size)f32{return switch(z){.label=>8,.note=>6};}
  /// its glow's radius for a label `w` pixels wide
  fn reach(z:Size,w:f32)f32{return switch(z){.label=>w*0.8+30,.note=>w*0.7+16};}
  /// its bud's colour at rest
  fn budCol(z:Size)Color{return switch(z){.label=>s.gold,.note=>s.bud};}
  /// its label's colour at rest
  fn restCol(z:Size)Color{return switch(z){.label=>s.white,.note=>s.dim};}
};
/// the state of the button picking `p` laid out in `b`: idle unless the
/// mouse points at it (the topmost row under the cursor), else as the
/// pointer says; the keys on it, it is hovered
pub fn stateOf(g:*const play.Game,p:hud.Pick,b:Box)State{
  if(!g.points(p))return.idle;
  if(g.keyFocus!=null)return.hovering;
  return ui.state(b,g.pointer);
}
/// `c` with its alpha scaled by `a`
fn faded(c:Color,a:f32)Color{
  return.{c[0],c[1],c[2],@intFromFloat(m.f(c[3])*m.clamp01(a))};
}
/// one button as a panel lays it out
pub const Button=struct{
  /// the middle of its label's line (pixels)
  center:[2]f32,
  /// what it says
  label:[]const u8,
  /// what a click on it picks
  pick:hud.Pick,
  /// how tall its box is (pixels)
  h:f32,
  /// a menu's button or a small one
  size:Size=.label,
  /// whether it would do anything (dim when not)
  live:bool=true,
  /// how strongly its glow pulses, asking (0 not at all)
  call:f32=0,
  /// its box's width, when wider than its label and bud (pixels)
  wide:?f32=null,
  /// its glow's radius, when not its label's (pixels)
  reach:?f32=null,
  /// its label's width (pixels)
  fn labelW(b:Button)f32{return Draw.width(b.label,b.size.text());}
  /// the box the mouse lands on
  pub fn box(b:Button)Box{
    // its label's width, and its middle
    const w=b.labelW();
    const c=b.center;
    if(b.wide)|ww|return.{.x=c[0]-ww/2,.y=c[1]-b.h/2,.w=ww,.h=b.h};
    return.{.x=c[0]-w/2-b.size.left(),.y=c[1]-b.h/2,.w=w+b.size.left()+b.size.right(),.h=b.h};
  }
  /// the state it is in this frame (always idle when it would do nothing)
  pub fn state(b:Button,g:*const play.Game)State{
    return if(b.live)stateOf(g,b.pick,b.box())else.idle;
  }
  /// registers its box and draws it as its state looks
  pub fn draw(b:Button,g:*play.Game,d:*Draw)Allocator.Error!void{
    // its state, label width, middle, and how far it sinks pressed
    const st=b.state(g);
    const w=b.labelW();
    const c=b.center;
    const down:f32=if(st.down())sink else 0;
    // its glow's radius: smaller pressed, as if pushed in
    const r=(b.reach orelse b.size.reach(w))*(if(st.down())pressedReach else 1);
    if(st.over() or b.call>0)try d.glow(c[0],c[1]+down,r,faded(s.menuHover,if(st.over())1 else b.call*2));
    // its label's colour: dim when it would do nothing
    const col=if(!b.live)s.unknown else if(st.over() or b.call>0)s.gold else b.size.restCol();
    // how open its bud is: closed at rest, open under the mouse, half shut pressed
    const open:f32=switch(st){.idle=>restOpen,.hovering,.released=>1,.pressed,.held=>pressedOpen};
    try hud.bullet(d,c[0]-w/2-b.size.budGap(),c[1]+down,b.size.bud(),if(b.live)b.size.budCol()else s.unknown,open,c[0]*0.01);
    _=try d.text(c[0]-w/2,c[1]-b.size.rise()+down,b.size.text(),col,b.label);
    try g.rows.add(b.box(),b.pick);
  }
};
