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
/// the HUD's panel component
const Panel=lib.hudPanel.Panel;
/// the HUD's scrolled list component
const scroll=lib.hudScroll;
/// the scroll stem's clickable width (pixels)
const stemW=scroll.stemW;
/// the HUD's button component
const Button=lib.hudButton.Button;
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
/// a click chooses a garden, presses a button or returns to the pause menu
/// (the stem is dragged, by `drag`)
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
    .scroll=>{},
  }
}
/// the stem takes hold as mouse1 goes down; every other row clicks as it
/// is let go over it
pub fn fire(p:Pick)hud.Fire{return switch(p){.scroll=>.press,.garden,.act,.back=>.release};}
/// the stem is the mouse's; the keys scroll by moving down the rows
pub fn focusable(p:Pick)bool{return p!=.scroll;}
/// the stem held: the list dragged to where the cursor is along it
pub fn drag(g:*play.Game,p:Pick,b:hud.Box,at:[2]f32)void{
  if(p==.scroll)scroll.dragged(&g.gardenList,g.gardens.items.len+1,b,at);
}
/// `c` with its alpha scaled by `a`
pub fn faded(c:Color,a:f32)Color{
  return.{c[0],c[1],c[2],@intFromFloat(m.f(c[3])*m.clamp01(a))};
}
/// the list of gardens as it is laid out in the panel `pn`
fn listOf(g:*const play.Game,pn:Panel)scroll.List{
  // the list's box: under the title band, from the rows' left to the stem
  const b=pn.box;
  return.{.box=.{.x=b.x+padX/2,.y=b.y+headerH-12,.w=b.w-padX/2-stemX+scroll.stemW/2,.h=listH},.rowH=rowH,.total=g.gardens.items.len+1,.at=&g.gardenList,.fade=fadeRows};
}
/// draws the veil and the panel: the title, the list of gardens (scrolled,
/// fading at its ends and cut to them, each row registered to be clicked),
/// the scroll stem, SAVE, LOAD and BACK, and the hint.
pub fn draw(g:*play.Game,d:*Draw,screenW:f32,screenH:f32)Allocator.Error!void{
  // the panel, centred, and the clock for pulses and sway
  const ph=headerH+listH+actsH+hintH;
  const pn=Panel.menu(.{screenW,screenH},pw,ph,0.83,txt.s.hud.gardensTitle);
  try pn.draw(g,d,.{screenW,screenH});
  const px=pn.box.x;
  const t=g.uiT();
  // the list: the glows under the rows first (soft, so never cut), then the
  // rows cut to the list (and the half row either end they fade over)
  const li=listOf(g,pn);
  for(0..li.total)|i|if(g.points(hud.row(.gardens,.{.garden=i})))try d.glow(px+pw/2,li.mid(i),pw*0.3,faded(s.menuHover,li.shows(i)));
  const was=d.clipTo(lib.engine.ui.layout.inset(li.box,0,-rowH*fadeRows));
  for(0..li.total)|i|{
    // how much of this row shows
    const a=li.shows(i);
    if(a<=0)continue;
    // (under the chosen row's DELETE, added as it is drawn)
    if(a>0.5)if(li.row(i,li.box.x,li.box.w-scroll.stemW))|rb|try g.rows.add(rb,hud.row(.gardens,.{.garden=i}));
    try row(g,d,i,px,li.mid(i),a,t);
  }
  d.unclip(was);
  try li.stem(g,d,hud.row(.gardens,.scroll),t);
  // the buttons: SAVE (asking first before saving over a garden), LOAD, BACK
  // the buttons' middle height, and whether a saved garden is chosen (LOAD)
  const by=li.box.y+listH+actsH/2;
  const saved=g.garden>0;
  // SAVE's label: asking first before saving over
  const saveLabel=if(g.overwrite)txt.s.hud.gardensOverwrite else txt.s.hud.gardensSave;
  try button(g,d,px+pw*0.22,by,saveLabel,hud.row(.gardens,.{.act=.save}),true,if(g.overwrite)0.5+0.5*@sin(t*6)else 0);
  try button(g,d,px+pw*0.55,by,txt.s.hud.gardensLoad,hud.row(.gardens,.{.act=.load}),saved,0);
  try button(g,d,px+pw*0.82,by,txt.s.hud.optionsBack,hud.row(.gardens,.back),true,0);
  // the hint, centred along the bottom
  const hint=txt.s.hud.gardensHint;
  _=try d.text(screenW/2-Draw.width(hint,s.textFine)/2,pn.box.y+ph-hintH+4,s.textFine,s.dim,hint);
}
/// row `i` (0: a fresh garden) centred at `mid`, at opacity `a`
fn row(g:*play.Game,d:*Draw,i:usize,px:f32,mid:f32,a:f32,t:f32)Allocator.Error!void{
  // whether it is chosen, whether the mouse is over it, and its pod's x
  const chosen=g.garden==i;
  const over=g.points(hud.row(.gardens,.{.garden=i}));
  const x=px+padX;
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
  try(Button{.center=.{cx,mid},.label=label,.pick=hud.row(.gardens,.{.act=.delete}),.h=rowH-12,.size=.note,.call=call}).draw(g,d);
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
/// a button: a pod and its label centred on (cx, mid); dim when it would
/// do nothing; `call` pulses its glow (asking)
pub fn button(g:*play.Game,d:*Draw,cx:f32,mid:f32,label:[]const u8,p:hud.Pick,live:bool,call:f32)Allocator.Error!void{
  try(Button{.center=.{cx,mid},.label=label,.pick=p,.h=actsH-12,.live=live,.call=call}).draw(g,d);
}
