//! the name prompt: the garden being saved is given a name (saving a fresh
//! one from the saved gardens, or the save key before it has one). The
//! name grows along a young stem as it is typed, a bud blinking where the
//! next letter goes; OK saves (over a garden of that name only when clicked
//! twice), CANCEL (or Esc) returns to where it was asked.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const m=lib.engine.core.math;
const play=lib.play;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const txt=lib.txt;
const hud=lib.hud;
const gardens=hud.panels.gardens;
const pw:f32=560;
const ph:f32=260;
const fieldY:f32=112;
const fieldPad:f32=56;
const actsY:f32=190;
/// the bud where the next letter goes blinks this often (1/s)
const blink:f32=2.2;
pub fn visible(g:*const play.Game)bool{return g.mode==.naming;}
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  try d.glow(w/2,h/2,@max(w,h)*s.veilReach,s.veil);
  const px=(w-pw)/2;
  const py=(h-ph)/2;
  const t=g.uiT();
  try d.trellis(px,py,pw,ph,s.pausePanel,0.61);
  g.rows.add(.{.x=px,.y=py,.w=pw,.h=ph},.panel);
  const title=txt.s.hud.namingTitle;
  _=try d.text(w/2-Draw.width(title,s.textTitle)/2,py+s.titleY,s.textTitle,s.gold,title);
  // the name on its stem, the bud after its last letter
  const name=g.typed.slice();
  const fy=py+fieldY;
  const x0=px+fieldPad;
  const x1=px+pw-fieldPad;
  const sway=1.5*@sin(t*1.3);
  try d.limb(.{x0,fy+14+sway},.{x1,fy+14-sway},2.5,1.5,s.barkYoung,0);
  const nx=w/2-Draw.width(name,s.textHeading)/2;
  const end=try d.text(nx,fy-8,s.textHeading,s.white,name);
  const open=0.5+0.5*@sin(t*blink*m.tau);
  try d.leaf(.{end+6,fy+12},-m.halfPi,18,8,s.leaf,open,0.2);
  // OK only for a name that can be one; asking first over a taken one
  const by=py+actsY;
  const ok=g.typed.typed()!=null;
  const okLabel=if(g.overwrite)txt.s.hud.gardensOverwrite else txt.s.hud.namingOk;
  try gardens.button(g,d,px+pw*0.32,by,okLabel,hud.row(.gardens,.{.act=.ok}),ok,if(g.overwrite)0.5+0.5*@sin(t*6)else 0);
  try gardens.button(g,d,px+pw*0.7,by,txt.s.hud.namingCancel,hud.row(.gardens,.{.act=.cancel}),true,0);
  const hint=txt.s.hud.namingHint;
  _=try d.text(w/2-Draw.width(hint,s.textFine)/2,py+ph-36,s.textFine,s.dim,hint);
}
