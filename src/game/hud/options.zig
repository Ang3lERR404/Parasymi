//! the options panel (pause menu, OPTIONS): the world stays frozen behind
//! the veil. Each setting is a row, its value shown as it is set: a toggle's
//! bud opening when on, a picker's mode between two leaves (each turning it
//! its way), a slider's seed riding a stem of stops, dragged along it. A
//! click on a row turns it on, the other button turns it back; the keys
//! turn it with left and right. BACK (or Esc) returns to the pause menu.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: conversions
const m=lib.engine.core.math;
/// the game itself: its mode and options
const play=lib.play;
/// the settings: their values, kinds, steps and names
const opt=lib.options;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// laying the rows out down the panel
const Column=lib.engine.ui.layout.Column;
/// where along a slider's track its stops lie
const track=lib.engine.ui.slider;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the HUD: picks, presses, rows and bullets
const hud=lib.hud;
/// a screen rectangle
const Box=hud.Box;
/// every player-facing string
const txt=lib.txt;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// the HUD's button component
const Button=lib.hudButton.Button;
/// a button's state, for each setting's row
const buttonState=lib.hudButton.stateOf;
/// the HUD's panel component
const Panel=lib.hudPanel.Panel;
/// the HUD's toggle component
const Toggle=lib.hudToggle.Toggle;
/// the HUD's picker component
const Picker=lib.hudPicker.Picker;
/// the HUD's slider component, and the stop a cursor sets
const slider=lib.hudSlider;
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
/// how far a row's line of text sits below its box's top (pixels)
const lineY:f32=17;
/// a slider's track: how far it reaches either side of the value's middle
const trackHalf:f32=96;
/// a slider's track: how far below the row's line of text its stem runs
const trackY:f32=21;
/// a slider's track's height, its clickable band (pixels)
const trackH:f32=18;
/// how fast a shown setting eases to its value (share a second)
const ease:f32=12;
/// how many settings there are, one row each
const settings=opt.settingCount;
/// drawn at the main menu too (`hud.build`)
pub const atTitle=true;
/// shown while the options are open.
pub fn visible(g:*const play.Game)bool{return g.mode==.options;}
/// a setting's row, a picker's leaves, or BACK
pub const Pick=union(enum){
  /// the row of this setting
  setting:opt.Setting,
  /// a picker's left leaf: turns it back
  less:opt.Setting,
  /// a picker's right leaf: turns it on
  more:opt.Setting,
  /// BACK, to the pause menu
  back
};
/// a slider's row fires as mouse1 goes down (and is dragged after); every
/// other row as it is let go
pub fn fire(p:Pick)hud.Fire{
  return switch(p){
    .setting=>|set|if(opt.kind(set)==.slider).press else.release,
    .less,.more,.back=>.release,
  };
}
/// a picker's leaves are the mouse's; the keys turn it from its row
pub fn focusable(p:Pick)bool{return switch(p){.setting,.back=>true,.less,.more=>false};}
/// turns `set` one way (`dir` +1) or back (-1): a slider a stop along
/// (stopping at its ends), anything else round its values
fn turn(g:*play.Game,set:opt.Setting,dir:i32)void{
  if(opt.kind(set)==.slider){
    // the stop it is at, moved along
    const i:i32=@intCast(opt.stopOf(&g.opts,set));
    opt.setStop(&g.opts,set,@intCast(@max(i+dir,0)));
    return;
  }
  opt.step(&g.opts,set,dir,g.mostSamples);
}
/// a click turns a setting on, the other button turns it back (a slider
/// is set where it is clicked, by `drag`); a leaf turns it its way; BACK
/// returns to the pause menu
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  // which way to turn: on (+1), back (-1); a throw does nothing
  const dir:i32=switch(press){.use=>1,.remove=>-1,.discard=>return};
  switch(p){
    .setting=>|set|if(!(opt.kind(set)==.slider and dir>0))turn(g,set,dir),
    .less=>|set|if(dir>0)turn(g,set,-1),
    .more=>|set|if(dir>0)turn(g,set,1),
    .back=>if(dir>0){g.mode=g.menuHome;},
  }
}
/// a slider held: set to the stop under the cursor
pub fn drag(g:*play.Game,p:Pick,b:Box,at:m.Vice(f32,2))void{
  switch(p){
    .setting=>|set|if(opt.kind(set)==.slider)opt.setStop(&g.opts,set,slider.stopAt(trackOf(b),at[0],opt.stops(set))),
    .less,.more,.back=>{},
  }
}
/// left and right on a setting turn it back and on
pub fn nudge(g:*play.Game,p:Pick,dir:i32)bool{
  switch(p){
    .setting=>|set|{
      turn(g,set,dir);
      return true;
    },
    .less,.more,.back=>return false,
  }
}
/// the value's middle across the row laid out in `b` (pixels)
fn valueAt(b:Box)f32{return b.x+b.w+padX/2-valueX;}
/// a slider's track in the row laid out in `b`
fn trackOf(b:Box)Box{
  return.{.x=valueAt(b)-trackHalf,.y=b.y+lineY+trackY-trackH/2,.w=2*trackHalf,.h=trackH};
}
/// each setting as shown eases toward its value: a toggle's bud open or
/// shut, a slider's seed along its stem (where it is, the first frame)
pub fn tick(g:*play.Game,dt:f32)void{
  for(0..settings)|i|{
    // this row's setting, and where its value is
    const set:opt.Setting=@enumFromInt(i);
    const want:f32=switch(opt.kind(set)){
      .toggle=>if(opt.isOn(&g.opts,set))1 else 0,
      .slider=>track.at(opt.stopOf(&g.opts,set),opt.stops(set)),
      .picker=>0,
    };
    // as shown now
    const v=&g.settingShown[i];
    v.*=if(v.*<0)want else m.damp(v.*,want,ease,dt);
  }
}
/// draws the veil and the panel: the title, each setting's row (its label,
/// its value set as it is), BACK, and the hint; each row registered to be
/// clicked.
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  // the panel, centred, and the clock for sway
  const ph=headerH+rowH*m.f(settings)+backH+hintH;
  const pn=Panel.menu(.{w,h},pw,ph,0.71,txt.s.hud.optionsTitle);
  try pn.draw(g,d,.{w,h});
  const t=g.uiT();
  // the rows, down the panel under its title band
  const px=pn.box.x;
  var col=Column.in(.{.x=px+padX/2,.y=pn.box.y+headerH-lineY,.w=pw-padX,.h=rowH*m.f(settings)},0);
  for(0..settings)|i|try row(g,d,@enumFromInt(i),col.next(rowH),t);
  // BACK's line
  const by=pn.box.y+headerH+rowH*m.f(settings)+14;
  try(Button{.center=.{w/2,by+8},.label=txt.s.hud.optionsBack,.pick=hud.row(.options,.back),.h=backH,.wide=pw/2,.reach=pw*0.25}).draw(g,d);
  // the hint, centred along the bottom
  const hint=txt.s.hud.optionsHint;
  _=try d.text(w/2-Draw.width(hint,s.textFine)/2,pn.box.y+ph-hintH+4,s.textFine,s.dim,hint);
}
/// the row of setting `set` laid out in `b`: its label, lit under the
/// mouse, and its value set as it is, at UI time `t`
fn row(g:*play.Game,d:*Draw,set:opt.Setting,b:Box,t:f32)Allocator.Error!void{
  // its index, line of text, the value's middle, and its pick
  const i=@intFromEnum(set);
  const y=b.y+lineY;
  const vx=valueAt(b);
  const pick=hud.row(.options,.{.setting=set});
  // its state, and whether the mouse (or the keys) are on it
  const st=buttonState(g,pick,b);
  const over=st.over() or g.grips(pick);
  if(over)try d.glow(b.x+b.w/2,y+8,pw*0.45,s.menuHover);
  try g.rows.add(b,pick);
  _=try d.text(b.x+padX/2,y,s.textLabel,if(over)s.gold else s.white,txt.nth(txt.s.hud.optionLabels,i));
  // the value as shown, and how far it has eased
  const val=opt.shown(&g.opts,set);
  const shown=@max(g.settingShown[i],0);
  switch(opt.kind(set)){
    .picker=>try(Picker{.center=.{vx,y},.value=val,.less=hud.row(.options,.{.less=set}),.more=hud.row(.options,.{.more=set}),.over=over,.phase=m.f(i)*0.3}).draw(g,d,t),
    .toggle=>{
      _=try d.text(vx-Draw.width(val,s.textLabel)/2,y,s.textLabel,s.gold,val);
      try(Toggle{.at=.{vx+lib.hudPicker.leafOff,y+6},.on=shown,.over=over,.phase=m.f(i)*0.3}).draw(d,t);
    },
    .slider=>{
      _=try d.text(vx-Draw.width(val,s.textNote)/2,y-2,s.textNote,s.gold,val);
      try(slider.Slider{.box=trackOf(b),.stops=opt.stops(set),.at=shown,.over=over,.phase=m.f(i)*0.3}).draw(d,t);
    },
  }
}
