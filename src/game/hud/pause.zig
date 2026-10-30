//! the pause menu (Esc): the world holds its breath behind a soft veil.
//! Each row is clicked (or its key pressed) to do what it says.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const fields=std.meta.fields;
const m=lib.engine.core.math;
const play=lib.play;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const hud=lib.hud;
const txt=lib.txt;
const Input=lib.engine.platform.input.Input;
const pw:f32=480;
const headerH:f32=100;
const optionH:f32=44;
const padBottom:f32=30;
const podX:f32=90;
const keyX:f32=112;
const labelX:f32=190;
/// a row's clickable band, from this far left of its pod
const rowInset:f32=50;
const rows=fields(play.PauseRow).len;
pub fn visible(g:*const play.Game)bool{return g.mode==.paused;}
/// a row of the menu
pub const Pick=union(enum){row:play.PauseRow};
/// a click does what the row says
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(press==.use)switch(p){.row=>|r|g.choose(r)};
}
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  try d.glow(w/2,h/2,@max(w,h)*s.veilReach,s.veil);
  const keys=txt.s.hud.pauseKeys;
  const labels=txt.s.hud.pauseLabels;
  // one label and key per row (the strings test checks the counts)
  const n=rows;
  const ph=headerH+optionH*m.f(n)+padBottom;
  const px=(w-pw)/2;
  const py=(h-ph)/2;
  try d.trellis(px,py,pw,ph,s.pausePanel,0.55);
  g.rows.add(.{.x=px,.y=py,.w=pw,.h=ph},.panel);
  const title=txt.s.hud.paused;
  _=try d.text(w/2-Draw.width(title,s.textBanner)/2,py+s.titleY,s.textBanner,s.gold,title);
  for(0..n)|i|{
    const y=py+headerH+optionH*m.f(i);
    const row:play.PauseRow=@enumFromInt(i);
    const over=g.points(hud.row(.pause,.{.row=row}));
    if(over)try d.glow(px+pw/2,y+8,pw*0.42,s.menuHover);
    try hud.bullet(d,px+podX,y+8,9,s.gold,if(over)1 else 0.15,m.f(i)*0.4);
    _=try d.text(px+keyX,y,s.textLabel,s.dim,txt.nth(keys,i));
    _=try d.text(px+labelX,y,s.textLabel,if(over)s.gold else s.white,txt.nth(labels,i));
    g.rows.add(.{.x=px+podX-rowInset,.y=y-optionH/2+8,.w=pw-2*(podX-rowInset),.h=optionH},hud.row(.pause,.{.row=row}));
  }
}
