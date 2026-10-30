//! the options panel (pause menu, OPTIONS): the world stays frozen behind
//! the veil. Each setting is a row, its value held between two leaves; a
//! click turns it on, the other button turns it back. BACK (or Esc) returns
//! to the pause menu.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const fields=std.meta.fields;
const m=lib.engine.core.math;
const play=lib.play;
const opt=lib.options;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const hud=lib.hud;
const txt=lib.txt;
const Input=lib.engine.platform.input.Input;
const pw:f32=620;
const headerH:f32=104;
const rowH:f32=50;
const backH:f32=56;
const hintH:f32=40;
const padX:f32=64;
/// the value's centre, from the panel's right edge
const valueX:f32=150;
/// the leaves either side of the value: from its centre, length and width
const leafOff:f32=84;
const leafLen:f32=20;
const leafW:f32=12;
const settings=fields(opt.Setting).len;
pub fn visible(g:*const play.Game)bool{return g.mode==.options;}
/// a setting's row, or BACK
pub const Pick=union(enum){setting:opt.Setting,back};
/// a click turns a setting on, the other button turns it back; BACK
/// returns to the pause menu
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  const dir:i32=switch(press){.use=>1,.remove=>-1,.discard=>return};
  switch(p){
    .setting=>|set|opt.step(&g.opts,set,dir,g.mostSamples),
    .back=>if(dir>0){g.mode=.paused;},
  }
}
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  try d.glow(w/2,h/2,@max(w,h)*s.veilReach,s.veil);
  const labels=txt.s.hud.optionLabels;
  const ph=headerH+rowH*m.f(settings)+backH+hintH;
  const px=(w-pw)/2;
  const py=(h-ph)/2;
  const t=g.uiT();
  try d.trellis(px,py,pw,ph,s.pausePanel,0.71);
  g.rows.add(.{.x=px,.y=py,.w=pw,.h=ph},.panel);
  const title=txt.s.hud.optionsTitle;
  _=try d.text(w/2-Draw.width(title,s.textBanner)/2,py+s.titleY,s.textBanner,s.gold,title);
  for(0..settings)|i|{
    const set:opt.Setting=@enumFromInt(i);
    const y=py+headerH+rowH*m.f(i);
    const mid=y+8;
    const over=g.points(hud.row(.options,.{.setting=set}));
    if(over)try d.glow(px+pw/2,mid,pw*0.45,s.menuHover);
    _=try d.text(px+padX,y,s.textLabel,if(over)s.gold else s.white,txt.nth(labels,i));
    const val=opt.shown(&g.opts,set);
    const vx=px+pw-valueX;
    _=try d.text(vx-Draw.width(val,s.textLabel)/2,y,s.textLabel,s.gold,val);
    // leaves pointing either way, swaying a little, opening under the mouse
    const open:f32=if(over)1 else 0.6;
    const sway=0.08*@sin(t*2+m.f(i));
    try d.leaf(.{vx-leafOff,mid},m.pi+sway,leafLen,leafW,s.leaf,open,m.f(i)*0.3);
    try d.leaf(.{vx+leafOff,mid},-sway,leafLen,leafW,s.leaf,open,m.f(i)*0.3+0.5);
    g.rows.add(.{.x=px+padX/2,.y=y-rowH/2+8,.w=pw-padX,.h=rowH},hud.row(.options,.{.setting=set}));
  }
  const by=py+headerH+rowH*m.f(settings)+14;
  const back=txt.s.hud.optionsBack;
  const over=g.points(hud.row(.options,.back));
  if(over)try d.glow(w/2,by+8,pw*0.25,s.menuHover);
  try hud.bullet(d,w/2-Draw.width(back,s.textLabel)/2-26,by+8,9,s.gold,if(over)1 else 0.15,0.2);
  _=try d.text(w/2-Draw.width(back,s.textLabel)/2,by,s.textLabel,if(over)s.gold else s.white,back);
  g.rows.add(.{.x=w/2-pw/4,.y=by-backH/2+8,.w=pw/2,.h=backH},hud.row(.options,.back));
  const hint=txt.s.hud.optionsHint;
  _=try d.text(w/2-Draw.width(hint,s.textFine)/2,py+ph-hintH+4,s.textFine,s.dim,hint);
}
