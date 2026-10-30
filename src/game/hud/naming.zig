//! the name prompt: the garden being saved is given a name (saving a fresh
//! one from the saved gardens, or the save key before it has one). The
//! name grows along a young stem as it is typed, a bud blinking where the
//! next letter goes; OK saves (over a garden of that name only when clicked
//! twice), CANCEL (or Esc) returns to where it was asked.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the game itself: its mode and the name being typed
const play=lib.play;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// every player-facing string
const txt=lib.txt;
/// the HUD: picks and rows
const hud=lib.hud;
/// the saved gardens panel, whose buttons and picks the prompt shares
const gardens=hud.panels.gardens;
/// saving: what a typed name may be
const save=lib.save;
/// the HUD's text field component, the name grows along
const field=lib.hudField;
/// the panel's width (pixels)
const pw:f32=560;
/// the panel's height (pixels)
const ph:f32=260;
/// where the name's stem sits, from the panel's top (pixels)
const fieldY:f32=112;
/// how far (pixels) the stem stands in from either side
const fieldPad:f32=56;
/// where OK and CANCEL sit, from the panel's top (pixels)
const actsY:f32=190;
/// shown while a garden is being named.
pub fn visible(g:*const play.Game)bool{return g.mode==.naming;}
/// draws the veil and the panel: the title, the typed name on its swaying
/// stem with a blinking bud after it, OK (pulsing when it would save over a
/// garden of that name) and CANCEL, and the hint under them.
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  try d.glow(w/2,h/2,@max(w,h)*s.veilReach,s.veil);
  // the panel's top-left corner, and the clock for sway and blink
  const px=(w-pw)/2;
  const py=(h-ph)/2;
  const t=g.uiT();
  try d.trellis(px,py,pw,ph,s.pausePanel,0.61);
  g.rows.add(.{.x=px,.y=py,.w=pw,.h=ph},.panel);
  // the title, centred over the panel
  const title=txt.s.hud.namingTitle;
  _=try d.text(w/2-Draw.width(title,s.textTitle)/2,py+s.titleY,s.textTitle,s.gold,title);
  // the name on its stem, the bud after its last letter
  try field.draw(save.Typed,&g.typed,d,.{.x=px+fieldPad,.y=py+fieldY-8,.w=pw-2*fieldPad,.h=36},t);
  // OK only for a name that can be one; asking first over a taken one
  // the buttons' row, whether the name can be one, and OK's label
  const by=py+actsY;
  const ok=save.named(&g.typed)!=null;
  const okLabel=if(g.overwrite)txt.s.hud.gardensOverwrite else txt.s.hud.namingOk;
  try gardens.button(g,d,px+pw*0.32,by,okLabel,hud.row(.gardens,.{.act=.ok}),ok,if(g.overwrite)0.5+0.5*@sin(t*6)else 0);
  try gardens.button(g,d,px+pw*0.7,by,txt.s.hud.namingCancel,hud.row(.gardens,.{.act=.cancel}),true,0);
  // the hint, centred along the bottom
  const hint=txt.s.hud.namingHint;
  _=try d.text(w/2-Draw.width(hint,s.textFine)/2,py+ph-36,s.textFine,s.dim,hint);
}
