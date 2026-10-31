//! the name prompt: the garden being saved is given a name (saving a fresh
//! one from the saved gardens, or the save key before it has one). The
//! name grows along a young stem as it is typed in at its caret, a bud
//! blinking where the next letter goes, a selection lit along the stem; a
//! click on it puts the caret there. OK saves (over a garden of that name
//! only when clicked twice), CANCEL (or Esc) returns to where it was asked.
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
/// a screen rectangle
const Box=hud.Box;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// the saved gardens panel, whose buttons and picks the prompt shares
const gardens=hud.panels.gardens;
/// saving: what a typed name may be
const save=lib.save;
/// the HUD's text field component, the name grows along
const field=lib.hudField;
/// the HUD's panel component
const Panel=lib.hudPanel.Panel;
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
/// the name's field
pub const Pick=union(enum){
  /// the field the name is typed into
  field
};
/// a click on the field types into it, its caret put where it lands
pub fn click(g:*play.Game,p:Pick,press:hud.Press,in:*const Input)void{
  if(press!=.use)return;
  switch(p){.field=>{
    g.typing=hud.row(.naming,.field);
    if(g.rows.find(hud.row(.naming,.field)))|b|g.typed.place(field.caretAt(save.Typed,&g.typed,b,in.mouse[0]));
  }}
}
/// the name typed into, while the prompt is open
pub fn edit(g:*play.Game,p:Pick)?hud.Edit{
  if(g.mode!=.naming)return null;
  return switch(p){.field=>g.typed.edit()};
}
/// the name changed: asking again before saving over a taken one; handed
/// on (enter): OK
pub fn typed(g:*play.Game,p:Pick,fed:hud.Fed)void{
  switch(p){.field=>switch(fed){
    .same=>{},
    .changed=>g.overwrite=false,
    .submitted=>g.nameChosen(),
  }}
}
/// the field's box in the panel `pn`
fn fieldBox(pn:Panel)Box{return.{.x=pn.box.x+fieldPad,.y=pn.box.y+fieldY-8,.w=pw-2*fieldPad,.h=36};}
/// draws the veil and the panel: the title, the typed name on its swaying
/// stem with a blinking bud at its caret, OK (pulsing when it would save
/// over a garden of that name) and CANCEL, and the hint under them.
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  // the panel, centred, and the clock for sway and blink
  var pn=Panel.menu(.{w,h},pw,ph,0.61,txt.s.hud.namingTitle);
  pn.titleSize=s.textTitle;
  try pn.draw(g,d,.{w,h});
  const px=pn.box.x;
  const py=pn.box.y;
  const t=g.uiT();
  // the name on its stem, the bud at its caret, lit while typed into
  const fb=fieldBox(pn);
  const pick=hud.row(.naming,.field);
  try field.draw(save.Typed,&g.typed,d,fb,t,g.points(pick));
  try g.rows.add(fb,pick);
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
