//! the options panel (pause menu, OPTIONS): the world stays frozen behind
//! the veil. Each setting is a row, its value held between two leaves; a
//! click turns it on, the other button turns it back. BACK (or Esc) returns
//! to the pause menu.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// a struct's fields, to count the settings
const fields=std.meta.fields;
/// all the maths: conversions, angles
const m=lib.engine.core.math;
/// the game itself: its mode and options
const play=lib.play;
/// the settings: their values, steps and names
const opt=lib.options;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the HUD: picks, presses, rows and bullets
const hud=lib.hud;
/// every player-facing string
const txt=lib.txt;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// the panel's width (pixels)
const pw:f32=620;
/// the height (pixels) of its title band, above the first setting
const headerH:f32=104;
/// the height (pixels) of one setting's row
const rowH:f32=50;
/// the height (pixels) of BACK's row
const backH:f32=56;
/// the height (pixels) of the hint along the bottom
const hintH:f32=40;
/// how far (pixels) a setting's label stands in from the panel's left
const padX:f32=64;
/// the value's centre, from the panel's right edge
const valueX:f32=150;
/// the leaves either side of the value: how far from its centre (pixels)
const leafOff:f32=84;
/// a leaf's length (pixels)
const leafLen:f32=20;
/// a leaf's width (pixels)
const leafW:f32=12;
/// how many settings there are, one row each
const settings=fields(opt.Setting).len;
/// shown while the options are open.
pub fn visible(g:*const play.Game)bool{return g.mode==.options;}
/// a setting's row, or BACK
pub const Pick=union(enum){
  /// the row of this setting
  setting:opt.Setting,
  /// BACK, to the pause menu
  back
};
/// a click turns a setting on, the other button turns it back; BACK
/// returns to the pause menu
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  // which way to step the setting: on (+1), back (-1); a throw does nothing
  const dir:i32=switch(press){.use=>1,.remove=>-1,.discard=>return};
  switch(p){
    .setting=>|set|opt.step(&g.opts,set,dir,g.mostSamples),
    .back=>if(dir>0){g.mode=.paused;},
  }
}
/// draws the veil and the panel: the title, each setting's row (its label,
/// its value between two swaying leaves that open under the mouse), BACK,
/// and the hint; each row registered to be clicked.
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  try d.glow(w/2,h/2,@max(w,h)*s.veilReach,s.veil);
  // the settings' labels, the panel's height, and its top-left corner
  const labels=txt.s.hud.optionLabels;
  const ph=headerH+rowH*m.f(settings)+backH+hintH;
  const px=(w-pw)/2;
  const py=(h-ph)/2;
  // the clock, for the leaves' sway
  const t=g.uiT();
  try d.trellis(px,py,pw,ph,s.pausePanel,0.71);
  g.rows.add(.{.x=px,.y=py,.w=pw,.h=ph},.panel);
  // the title, centred over the panel
  const title=txt.s.hud.optionsTitle;
  _=try d.text(w/2-Draw.width(title,s.textBanner)/2,py+s.titleY,s.textBanner,s.gold,title);
  for(0..settings)|i|{
    // this row's setting, its line's top, and the leaves' middle height
    const set:opt.Setting=@enumFromInt(i);
    const y=py+headerH+rowH*m.f(i);
    const mid=y+8;
    // whether the mouse is over this row
    const over=g.points(hud.row(.options,.{.setting=set}));
    if(over)try d.glow(px+pw/2,mid,pw*0.45,s.menuHover);
    _=try d.text(px+padX,y,s.textLabel,if(over)s.gold else s.white,txt.nth(labels,i));
    // the setting's value as shown, and where its centre sits
    const val=opt.shown(&g.opts,set);
    const vx=px+pw-valueX;
    _=try d.text(vx-Draw.width(val,s.textLabel)/2,y,s.textLabel,s.gold,val);
    // leaves pointing either way, swaying a little, opening under the mouse
    // how open the leaves are, and how far they sway now
    const open:f32=if(over)1 else 0.6;
    const sway=0.08*@sin(t*2+m.f(i));
    try d.leaf(.{vx-leafOff,mid},m.pi+sway,leafLen,leafW,s.leaf,open,m.f(i)*0.3);
    try d.leaf(.{vx+leafOff,mid},-sway,leafLen,leafW,s.leaf,open,m.f(i)*0.3+0.5);
    g.rows.add(.{.x=px+padX/2,.y=y-rowH/2+8,.w=pw-padX,.h=rowH},hud.row(.options,.{.setting=set}));
  }
  // BACK's line, its label, and whether the mouse is over it
  const by=py+headerH+rowH*m.f(settings)+14;
  const back=txt.s.hud.optionsBack;
  const over=g.points(hud.row(.options,.back));
  if(over)try d.glow(w/2,by+8,pw*0.25,s.menuHover);
  try hud.bullet(d,w/2-Draw.width(back,s.textLabel)/2-26,by+8,9,s.gold,if(over)1 else 0.15,0.2);
  _=try d.text(w/2-Draw.width(back,s.textLabel)/2,by,s.textLabel,if(over)s.gold else s.white,back);
  g.rows.add(.{.x=w/2-pw/4,.y=by-backH/2+8,.w=pw/2,.h=backH},hud.row(.options,.back));
  // the hint, centred along the bottom
  const hint=txt.s.hud.optionsHint;
  _=try d.text(w/2-Draw.width(hint,s.textFine)/2,py+ph-hintH+4,s.textFine,s.dim,hint);
}
