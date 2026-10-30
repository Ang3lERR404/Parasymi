//! a slot, the first of the HUD's components: a husk hanging in its box. The
//! box is both its size (everything it draws scales with the box's smaller
//! side) and what the mouse lands on, registered in `hud.Rows` with its pick.
//! A halo behind it when it is lit (the selected, the chosen), a glow when
//! the mouse is over it; what it holds the caller draws at `center` once
//! `draw` says it has grown.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const m=lib.engine.core.math;
const play=lib.play;
const hud=lib.hud;
const Box=hud.Box;
const Draw=lib.engine.ui.draw.Draw;
const Color=lib.engine.ui.draw.Color;
const s=lib.style;
// decision: the glows scale with the box (shares of its side) instead of
// each panel's own pixel radii, so a resized slot keeps its look.
/// the glow under the mouse, and the halo of a lit slot, as shares of the
/// box's side (their radii)
const hoverShare:f32=0.55;
const haloShare:f32=0.62;
pub const Slot=struct{
  box:Box,
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
  pub fn around(c:[2]f32,w:f32,h:f32,pick:hud.Pick,husk:f32)Slot{
    return.{.box=Box.around(c,w,h),.pick=pick,.husk=husk};
  }
  pub fn center(sl:Slot)[2]f32{return sl.box.center();}
  /// its husk's radius at full growth
  pub fn radius(sl:Slot)f32{return sl.husk*sl.box.side();}
  /// registers its box and draws it; true once it has grown enough to show
  /// what it holds.
  pub fn draw(sl:Slot,g:*play.Game,d:*Draw)Allocator.Error!bool{
    g.rows.add(sl.box,sl.pick);
    if(sl.grown<=0)return false;
    const c=sl.center();
    const side=sl.box.side();
    if(sl.halo)|col|try d.glow(c[0],c[1],haloShare*side,col);
    if(g.points(sl.pick))try d.glow(c[0],c[1],hoverShare*side,if(sl.takes and g.held!=null)s.dropTarget else s.slotHover);
    try d.husk(c[0],c[1],sl.radius()*m.smooth(sl.grown),s.podEmpty,sl.lit,sl.phase);
    return sl.grown>=1;
  }
};
