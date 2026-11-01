//! a slot, the first of the HUD's components: a husk hanging in its box. The
//! box is both its size (everything it draws scales with the box's smaller
//! side) and what the mouse lands on, registered in `hud.Rows` with its pick.
//! A halo behind it when it is lit (the selected, the chosen), a glow when
//! the mouse is over it; what it holds the caller draws at `center` once
//! `draw` says it has grown.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: easing
const m=lib.engine.core.math;
/// the game itself: the clickable rows, what is held and pointed at
const play=lib.play;
/// the HUD: picks and rows
const hud=lib.hud;
/// a screen rectangle the mouse can land in
const Box=hud.Box;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the HUD's shared sizes and colours
const s=lib.style;
// decision: the glows scale with the box (shares of its side) instead of
// each panel's own pixel radii, so a resized slot keeps its look.
/// the glow under the mouse, as a share of the box's side (its radius)
const hoverShare:f32=0.55;
/// the halo of a lit slot, as a share of the box's side (its radius)
const haloShare:f32=0.62;
/// one slot as a panel lays it out: its box, what it picks, and how it looks now
pub const Slot=struct{
  /// its box on screen: its size, and what the mouse lands on
  box:Box,
  /// what a click on it picks
  pick:hud.Pick,
  /// the husk's radius at full growth, as a share of the box's side
  husk:f32,
  /// how far what it hangs from has reached it: 0 not yet there, 1 grown
  grown:f32=1,
  /// how much sap light fills the husk
  lit:f32=0,
  /// the halo behind it, if it is the selected or chosen one
  halo:?Color=null,
  /// whether what the gardener carries can be put down on it (the glow
  /// under the mouse says so)
  takes:bool=true,
  /// its sway's phase
  phase:f32=0,
  /// a slot `w` by `h` centred on `c`
  pub fn around(c:m.Vice(f32,2),w:f32,h:f32,pick:hud.Pick,husk:f32)Slot{
    return.{.box=Box.around(c,w,h),.pick=pick,.husk=husk};
  }
  /// the middle of its box (pixels)
  pub fn center(sl:Slot)m.Vice(f32,2){return sl.box.center();}
  /// its husk's radius at full growth
  pub fn radius(sl:Slot)f32{return sl.husk*sl.box.side();}
  /// registers its box and draws it; true once it has grown enough to show
  /// what it holds.
  pub fn draw(sl:Slot,g:*play.Game,d:*Draw)Allocator.Error!bool{
    try g.rows.add(sl.box,sl.pick);
    if(sl.grown<=0)return false;
    // the box's middle, and its smaller side
    const c=sl.center();
    const side=sl.box.side();
    if(sl.halo)|col|try d.glow(c[0],c[1],haloShare*side,col);
    if(g.points(sl.pick))try d.glow(c[0],c[1],hoverShare*side,if(sl.takes and g.held!=null)s.dropTarget else s.slotHover);
    try d.husk(c[0],c[1],sl.radius()*m.smooth(sl.grown),s.podEmpty,sl.lit,sl.phase);
    return sl.grown>=1;
  }
};
