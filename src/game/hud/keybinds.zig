//! the keybinds (pause menu, KEYBINDS): the world stays frozen behind the
//! veil. Every action is a row, its name and the keys and buttons it is
//! bound to; the list scrolls (wheel, or drag its stem) past what fits. A
//! click on a row listens for the next key, mouse or pad button pressed
//! and binds the action to it (in place of its first of that kind); back
//! cancels the listening. The other button sets the row back as the game
//! ships it, ALL DEFAULTS every row; a row bound otherwise than shipped is
//! marked. BACK (or Esc) returns to the pause menu.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// a text writer, for each row's keys
const Writer=std.Io.Writer;
/// all the maths: conversions
const m=lib.engine.core.math;
/// the game itself: its mode, the action listened for, the list's scroll
const play=lib.play;
/// the bindings: each action's keys, rebinding and resetting them
const ctl=lib.controls;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the HUD: picks, presses, rows and bullets
const hud=lib.hud;
/// every player-facing string, and how a key is shown
const txt=lib.txt;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// the HUD's panel component
const Panel=lib.hudPanel.Panel;
/// the HUD's scrolled list component
const scroll=lib.hudScroll;
/// the HUD's button component
const Button=lib.hudButton.Button;
/// a colour faded by how much of its row shows
const faded=lib.hud.panels.gardens.faded;
/// every action, one row each, in `ctl.Action` order
const actions=std.enums.values(ctl.Action);
/// the panel's width (pixels)
const pw:f32=760;
/// the height (pixels) of its title band, above the list
const headerH:f32=104;
/// the height (pixels) of one action's row
const rowH:f32=play.bindRowH;
/// the height (pixels) of the list: as many rows as are shown at once
const listH:f32=rowH*play.bindsShown;
/// the height (pixels) of the buttons' band
const actsH:f32=64;
/// the height (pixels) of the hint along the bottom
const hintH:f32=40;
/// how far (pixels) the list stands in from the panel's left
const padX:f32=64;
/// the scroll stem: how far (pixels) in from the panel's right edge
const stemX:f32=34;
/// a row's text, from its bud
const textX:f32=22;
/// a row's bud's radius (pixels)
const budR:f32=7;
/// how far (pixels) a row's keys end before the stem
const keysEnd:f32=20;
/// rows fade out over this much of a row past the list's ends
const fadeRows:f32=0.5;
/// how fast a listening row's glow pulses (radians a second)
const pulse:f32=6;
/// the longest a row's keys run as shown (bytes)
const maxKeys=96;
/// drawn at the main menu too (`hud.build`)
pub const atTitle=true;
/// shown while the keybinds are open.
pub fn visible(g:*const play.Game)bool{return g.mode==.keybinds;}
/// an action's row, ALL DEFAULTS, BACK, the scroll stem
pub const Pick=union(enum){
  /// the row of this action
  action:ctl.Action,
  /// ALL DEFAULTS: every action bound as the game ships it
  reset,
  /// BACK, to the pause menu
  back,
  /// the scroll stem, dragged while held
  scroll
};
/// a click on a row listens for its new key (the other button sets it
/// back as shipped); ALL DEFAULTS sets every row back; BACK returns to the
/// pause menu (the stem is dragged, by `drag`)
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  switch(press){
    .use=>switch(p){
      .action=>|a|g.rebinding=a,
      .reset=>{
        ctl.resetAll();
        g.request=.bindings;
      },
      .back=>g.mode=g.menuHome,
      .scroll=>{},
    },
    .remove=>switch(p){
      .action=>|a|if(ctl.changed(a)){
        ctl.reset(a);
        g.request=.bindings;
      },
      .reset,.back,.scroll=>{},
    },
    .discard=>{},
  }
}
/// the stem takes hold as mouse1 goes down; every other row clicks as it
/// is let go over it
pub fn fire(p:Pick)hud.Fire{return switch(p){.scroll=>.press,.action,.reset,.back=>.release};}
/// the stem is the mouse's; the keys scroll by moving down the rows
pub fn focusable(p:Pick)bool{return p!=.scroll;}
/// the stem held: the list dragged to where the cursor is along it
pub fn drag(g:*play.Game,p:Pick,b:hud.Box,at:m.Vice(f32,2))void{
  if(p==.scroll)scroll.dragged(&g.bindList,actions.len,b,at);
}
/// the list of actions as it is laid out in the panel `pn`
fn listOf(g:*const play.Game,pn:Panel)scroll.List{
  // the list's box: under the title band, from the rows' left to the stem
  const b=pn.box;
  return.{.box=.{.x=b.x+padX/2,.y=b.y+headerH-12,.w=b.w-padX/2-stemX+scroll.stemW/2,.h=listH},.rowH=rowH,.total=actions.len,.at=&g.bindList,.fade=fadeRows};
}
/// draws the veil and the panel: the title, the list of actions (scrolled,
/// fading at its ends and cut to them, each row registered to be clicked),
/// the scroll stem, ALL DEFAULTS and BACK, and the hint.
pub fn draw(g:*play.Game,d:*Draw,screenW:f32,screenH:f32)Allocator.Error!void{
  // the panel, centred, and the clock for pulses and sway
  const ph=headerH+listH+actsH+hintH;
  const pn=Panel.menu(.{screenW,screenH},pw,ph,0.37,txt.s.hud.keybindsTitle);
  try pn.draw(g,d,.{screenW,screenH});
  const px=pn.box.x;
  const t=g.uiT();
  // the list: the glows under the rows first (soft, so never cut), then the
  // rows cut to the list (and the half row either end they fade over)
  const li=listOf(g,pn);
  for(actions,0..)|a,i|{
    // how much of this row shows, and whether it is listening
    const al=li.shows(i);
    if(g.rebinding==a){
      try d.glow(px+pw/2,li.mid(i),pw*0.36,faded(s.researchActive,al*(0.6+0.4*@sin(t*pulse))));
    }else if(g.points(hud.row(.keybinds,.{.action=a})))try d.glow(px+pw/2,li.mid(i),pw*0.3,faded(s.menuHover,al));
  }
  const was=d.clipTo(lib.engine.ui.layout.inset(li.box,0,-rowH*fadeRows));
  for(actions,0..)|a,i|{
    // how much of this row shows
    const al=li.shows(i);
    if(al<=0)continue;
    if(al>0.5)if(li.row(i,li.box.x,li.box.w-scroll.stemW))|rb|try g.rows.add(rb,hud.row(.keybinds,.{.action=a}));
    try row(g,d,a,px,li.mid(i),al,t);
  }
  d.unclip(was);
  try li.stem(g,d,hud.row(.keybinds,.scroll),t);
  // the buttons: ALL DEFAULTS and BACK
  const by=li.box.y+listH+actsH/2;
  try(Button{.center=.{px+pw*0.3,by},.label=txt.s.hud.keybindsReset,.pick=hud.row(.keybinds,.reset),.h=actsH-12}).draw(g,d);
  try(Button{.center=.{px+pw*0.72,by},.label=txt.s.hud.optionsBack,.pick=hud.row(.keybinds,.back),.h=actsH-12}).draw(g,d);
  // the hint, centred along the bottom
  const hint=txt.s.hud.keybindsHint;
  _=try d.text(screenW/2-Draw.width(hint,s.textFine)/2,pn.box.y+ph-hintH+4,s.textFine,s.dim,hint);
}
/// action `a`'s row centred at `mid`, at opacity `al`: its bud (open when
/// bound otherwise than shipped), its name, and its keys right-aligned
/// before the stem (asking for a key while listening)
fn row(g:*play.Game,d:*Draw,a:ctl.Action,px:f32,mid:f32,al:f32,t:f32)Allocator.Error!void{
  // whether the mouse (or the keys) are on it, whether it is listening or
  // changed, and its bud's x
  const over=g.points(hud.row(.keybinds,.{.action=a}));
  const listening=g.rebinding==a;
  const changed=ctl.changed(a);
  const x=px+padX;
  // its index, for the bud's sway
  const i=@intFromEnum(a);
  try hud.bullet(d,x,mid,budR,faded(if(changed)s.growth else s.gold,al),if(over or listening)1 else if(changed)0.7 else 0.15,m.f(i)*0.4);
  _=try d.text(x+textX,mid-8,s.textLabel,faded(if(over or listening)s.gold else s.white,al),txt.s.action.get(a));
  // where the keys end: before the stem
  const right=px+pw-stemX-scroll.stemW/2-keysEnd;
  if(listening){
    // the call for a key, pulsing
    const call=txt.s.hud.keybindsListen;
    _=try d.text(right-Draw.width(call,s.textNote),mid-6,s.textNote,faded(s.gold,al*(0.6+0.4*@sin(t*pulse))),call);
    return;
  }
  // the keys as shown, joined, and in what colour
  var buf:[maxKeys]u8=undefined;
  const keys=shown(&buf,a);
  const none=keys.len==0;
  const label=if(none)txt.s.hud.keybindsNone else keys;
  const end=right-Draw.width(label,s.textLabel);
  _=try d.text(end,mid-8,s.textLabel,faded(if(none)s.dim else if(changed)s.growth else s.gold,al),label);
  if(changed){
    // the mark of a row changed from the game's own
    const mark=txt.s.hud.keybindsChanged;
    _=try d.text(end-Draw.width(mark,s.textLabel)-10,mid-8,s.textLabel,faded(s.growth,al),mark);
  }
}
/// action `a`'s keys and buttons as shown, joined by ` / ` into `buf`
/// (cut short when they would run past it)
fn shown(buf:*[maxKeys]u8,a:ctl.Action)[]const u8{
  // the writer filling the buffer
  var w:Writer=.fixed(buf);
  for(ctl.map.getPtrConst(a).items(),0..)|b,i|{
    if(i>0)w.writeAll(" / ") catch break;
    txt.bindName(&w,b) catch break;
  }
  return w.buffered();
}
