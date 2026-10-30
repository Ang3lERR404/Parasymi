//! the saved gardens (pause menu): the world stays frozen behind the veil.
//! A fresh garden heads the list, then every saved one, the most recent
//! first; the list scrolls (wheel, or drag its stem) past what fits. A
//! click chooses one; SAVE writes the garden as it (a fresh one asks its
//! name, a saved one is saved over only when clicked twice), LOAD returns
//! to it, the chosen one's small DELETE lets it go (clicked twice). BACK
//! (or Esc) returns to the pause menu.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: conversions, clamps, angles
const m=lib.engine.core.math;
/// the game itself: the gardens list, the chosen one, the scroll
const play=lib.play;
/// saving, for the name of the automatic save
const save=lib.save;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the HUD: picks, presses, rows and bullets
const hud=lib.hud;
/// every player-facing string
const txt=lib.txt;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// the panel's width (pixels)
const pw:f32=680;
/// the height (pixels) of its title band, above the list
const headerH:f32=104;
/// the height (pixels) of one garden's row
const rowH:f32=46;
/// the height (pixels) of the list: as many rows as are shown at once
const listH:f32=rowH*play.gardensShown;
/// the height (pixels) of the buttons' band
const actsH:f32=64;
/// the height (pixels) of the hint along the bottom
const hintH:f32=40;
/// how far (pixels) the list stands in from the panel's left
const padX:f32=64;
/// a row's pod radius (pixels)
const podR:f32=9;
/// the radius (pixels) of the chosen row's glow
const chosenGlow:f32=34;
/// a row's text, from its pod
const textX:f32=26;
/// the scroll stem: how far (pixels) in from the panel's right edge
const stemX:f32=34;
/// the scroll stem's clickable width (pixels)
const stemW:f32=28;
/// rows fade out over this much of a row past the list's ends
const fadeRows:f32=0.5;
/// the seconds in a minute, an hour and a day, for how long ago a save was
const secondsPer=[_]i64{60,3600,86400};
/// shown while the saved gardens are open.
pub fn visible(g:*const play.Game)bool{return g.mode==.gardens;}
/// a garden's row (0: a fresh one), a button (the name prompt's too), BACK,
/// the scroll stem
pub const Pick=union(enum){
  /// a garden's row: 0 a fresh one, then the saved ones, newest first
  garden:usize,
  /// a button: SAVE, LOAD, DELETE, or the name prompt's OK and CANCEL
  act:play.GardenAct,
  /// BACK, to the pause menu
  back,
  /// the scroll stem, dragged while held
  scroll
};
/// a click chooses a garden, presses a button, returns to the pause menu,
/// or takes hold of the stem (dragged while held)
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(press!=.use)return;
  switch(p){
    .garden=>|i|if(i!=g.garden){
      g.garden=i;
      g.overwrite=false;
      g.deleting=false;
    },
    .act=>|a|g.gardenAct(a),
    .back=>g.mode=.paused,
    .scroll=>g.scrolling=true,
  }
}
/// `c` with its alpha scaled by `a`
pub fn faded(c:Color,a:f32)Color{
  return.{c[0],c[1],c[2],@intFromFloat(m.f(c[3])*m.clamp01(a))};
}
/// draws the veil and the panel: the title, the list of gardens (scrolled,
/// fading at its ends, each row registered to be clicked), the scroll stem,
/// SAVE, LOAD and BACK, and the hint.
pub fn draw(g:*play.Game,d:*Draw,screenW:f32,screenH:f32)Allocator.Error!void{
  try d.glow(screenW/2,screenH/2,@max(screenW,screenH)*s.veilReach,s.veil);
  // the panel's height, and its top-left corner
  const ph=headerH+listH+actsH+hintH;
  const px=(screenW-pw)/2;
  const py=(screenH-ph)/2;
  // the clock, for pulses and sway
  const t=g.uiT();
  try d.trellis(px,py,pw,ph,s.pausePanel,0.83);
  g.rows.add(.{.x=px,.y=py,.w=pw,.h=ph},.panel);
  // the title, centred over the panel
  const title=txt.s.hud.gardensTitle;
  _=try d.text(screenW/2-Draw.width(title,s.textBanner)/2,py+s.titleY,s.textBanner,s.gold,title);
  // the list, scrolled to `gardenAt`; rows fade in and out at its ends
  // the list's top, how many rows it has (a fresh one first), and the last shown
  const top=py+headerH-12;
  const n=g.gardens.items.len+1;
  const last=m.f(play.gardensShown-1);
  for(0..n)|i|{
    // this row's place in the scrolled list (0: at the top), and its opacity
    const pos=m.f(i)-g.gardenAt;
    const a=1-@max(-pos,pos-last,0)/fadeRows;
    if(a<=0)continue;
    // the row's middle height
    const mid=top+rowH*(pos+0.5);
    // (under the chosen row's DELETE, added as it is drawn)
    if(a>0.5){
      // the row's clickable band, clipped to the list
      const y0=@max(mid-rowH/2,top);
      const y1=@min(mid+rowH/2,top+listH);
      g.rows.add(.{.x=px+padX/2,.y=y0,.w=pw-padX-stemW,.h=y1-y0},hud.row(.gardens,.{.garden=i}));
    }
    try row(g,d,i,px,mid,a,t);
  }
  try stem(g,d,px+pw-stemX,top,t);
  // the buttons: SAVE (asking first before saving over a garden), LOAD, BACK
  // the buttons' middle height, and whether a saved garden is chosen (LOAD)
  const by=top+listH+actsH/2;
  const saved=g.garden>0;
  // SAVE's label: asking first before saving over
  const saveLabel=if(g.overwrite)txt.s.hud.gardensOverwrite else txt.s.hud.gardensSave;
  try button(g,d,px+pw*0.22,by,saveLabel,hud.row(.gardens,.{.act=.save}),true,if(g.overwrite)0.5+0.5*@sin(t*6)else 0);
  try button(g,d,px+pw*0.55,by,txt.s.hud.gardensLoad,hud.row(.gardens,.{.act=.load}),saved,0);
  try button(g,d,px+pw*0.82,by,txt.s.hud.optionsBack,hud.row(.gardens,.back),true,0);
  // the hint, centred along the bottom
  const hint=txt.s.hud.gardensHint;
  _=try d.text(screenW/2-Draw.width(hint,s.textFine)/2,py+ph-hintH+4,s.textFine,s.dim,hint);
}
/// row `i` (0: a fresh garden) centred at `mid`, at opacity `a`
fn row(g:*play.Game,d:*Draw,i:usize,px:f32,mid:f32,a:f32,t:f32)Allocator.Error!void{
  // whether it is chosen, whether the mouse is over it, and its pod's x
  const chosen=g.garden==i;
  const over=g.points(hud.row(.gardens,.{.garden=i}));
  const x=px+padX;
  if(over)try d.glow(px+pw/2,mid,pw*0.3,faded(s.menuHover,a));
  // the chosen one: its pod glows and a tendril runs under it
  if(chosen){
    try d.glow(x,mid,chosenGlow,faded(s.researchActive,a));
    try d.limb(.{x+textX-4,mid+14},.{px+pw-stemW-padX/2,mid+14+2*@sin(t)},2,0.8,faded(s.leaf,a),0);
  }
  // how lit its pod is, and its label's colour
  const lit:f32=if(chosen)1 else if(over)0.8 else 0.4;
  const labelCol=faded(if(chosen or over)s.gold else s.white,a);
  if(i==0){
    // a fresh garden: a sprout from its pod
    try d.pod(x,mid,podR,faded(s.leaf,a),lit,0.1);
    try d.leaf(.{x,mid-podR*0.5},-m.halfPi+0.15*@sin(t*2),16,9,faded(s.leaf,a),if(chosen or over)1 else 0.6,0.3);
    _=try d.text(x+textX,mid-8,s.textLabel,labelCol,txt.s.hud.gardensFresh);
    return;
  }
  // the saved garden it shows
  const e=&g.gardens.items[i-1];
  try d.grain(x,mid,podR*1.5,podR*2.1,faded(s.gold,a),lit,m.f(i)*0.4);
  // its name (the automatic save by its own name), and where that ends
  const name=if(e.name.is(save.auto))txt.s.hud.gardensAuto else e.name.slice();
  const end=try d.text(x+textX,mid-8,s.textLabel,labelCol,name);
  if(g.slot)|sl|if(sl.is(e.name.slice())){
    _=try d.text(end+14,mid-6,s.textNote,faded(s.growth,a),txt.s.hud.gardensPlaying);
  };
  // how long ago, right-aligned before the scroll stem (the chosen one's
  // DELETE before it)
  // room to write the age in, the age, and where it is right-aligned to
  var ageBuf:[64]u8=undefined;
  const age=ago(&ageBuf,e.age+@as(i64,@intFromFloat(g.uiTime-g.listedAt)));
  const ax=px+pw-stemW-padX/2-Draw.width(age,s.textNote)-12;
  _=try d.text(ax,mid-6,s.textNote,faded(s.dim,a),age);
  if(chosen and a>0.5){
    // DELETE's label: asking first when already pressed once
    const label=if(g.deleting)txt.s.hud.gardensDeleteSure else txt.s.hud.gardensDelete;
    try small(g,d,ax-24-Draw.width(label,s.textNote)/2,mid,label,if(g.deleting)0.5+0.5*@sin(t*6)else 0);
  }
}
/// the chosen garden's DELETE: a small button centred on (cx, mid), its
/// glow pulsing with `call` (asking)
fn small(g:*play.Game,d:*Draw,cx:f32,mid:f32,label:[]const u8,call:f32)Allocator.Error!void{
  // what the button picks, whether the mouse is over it, and its label's width
  const p:hud.Pick=hud.row(.gardens,.{.act=.delete});
  const over=g.points(p);
  const w=Draw.width(label,s.textNote);
  if(over or call>0)try d.glow(cx,mid,w*0.7+16,faded(s.menuHover,if(over)1 else call*2));
  try hud.bullet(d,cx-w/2-12,mid,podR*0.6,s.bud,if(over)1 else 0.15,cx*0.01);
  _=try d.text(cx-w/2,mid-6,s.textNote,if(over or call>0)s.gold else s.dim,label);
  g.rows.add(.{.x=cx-w/2-22,.y=mid-rowH/2+6,.w=w+30,.h=rowH-12},p);
}
/// `secs` as shown: just now, minutes, hours or days ago
fn ago(buf:[]u8,secs:i64)[]const u8{
  // the age words: just now, then minutes, hours, days
  const list=txt.s.hud.gardensAge;
  if(secs<secondsPer[0])return txt.nth(list,0);
  // the largest unit the age fills
  var k:usize=secondsPer.len-1;
  while(secs<secondsPer[k])k-=1;
  return txt.bufRender(buf,txt.nth(list,k+1),.{@divFloor(secs,secondsPer[k])});
}
/// the list's scroll stem down the right side, a bud riding it where the
/// list is; only there while the list runs past what fits
fn stem(g:*play.Game,d:*Draw,x:f32,top:f32,t:f32)Allocator.Error!void{
  // how far the list can scroll (rows past what fits)
  const most=m.f((g.gardens.items.len+1)-|play.gardensShown);
  if(most<=0)return;
  // whether the stem is pointed at or held
  const over=g.points(hud.row(.gardens,.scroll)) or g.scrolling;
  // how far the stem sways now (pixels)
  const sway=1.5*@sin(t*1.3);
  try d.limb(.{x+sway,top+4},.{x-sway,top+listH-4},3,2,s.barkYoung,0);
  // where the bud rides on the stem
  const y=top+12+(listH-24)*m.clamp01(g.gardenAt/most);
  try d.grain(x,y,14,22,if(over)s.gold else s.bud,if(over)0.4 else 0.1,t*0.2);
  g.rows.add(.{.x=x-stemW/2,.y=top,.w=stemW,.h=listH},hud.row(.gardens,.scroll));
}
/// a button: a pod and its label centred on (cx, mid); dim when it would
/// do nothing; `call` pulses its glow (asking)
pub fn button(g:*play.Game,d:*Draw,cx:f32,mid:f32,label:[]const u8,p:hud.Pick,live:bool,call:f32)Allocator.Error!void{
  // whether it is live under the mouse, and its label's width
  const over=live and g.points(p);
  const w=Draw.width(label,s.textLabel);
  if(over or call>0)try d.glow(cx,mid,w*0.8+30,faded(s.menuHover,if(over)1 else call*2));
  // its label's colour: dim when it would do nothing
  const col=if(!live)s.unknown else if(over or call>0)s.gold else s.white;
  try hud.bullet(d,cx-w/2-22,mid,podR,if(live)s.gold else s.unknown,if(over)1 else 0.15,cx*0.01);
  _=try d.text(cx-w/2,mid-8,s.textLabel,col,label);
  g.rows.add(.{.x=cx-w/2-40,.y=mid-actsH/2+6,.w=w+60,.h=actsH-12},p);
}
