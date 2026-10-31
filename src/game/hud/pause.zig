//! the pause menu (Esc): the world holds its breath behind a soft veil.
//! Each row is clicked (or its key pressed, or the keys moved onto it and
//! confirm pressed) to do what it says.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// a struct's fields, to count the rows
const fields=std.meta.fields;
/// all the maths: conversions
const m=lib.engine.core.math;
/// the game itself: its mode and what each row does
const play=lib.play;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// laying the rows out down the panel
const Column=lib.engine.ui.layout.Column;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the HUD: picks, presses, rows and bullets
const hud=lib.hud;
/// every player-facing string
const txt=lib.txt;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// a button's state, for each row
const buttonState=lib.hudButton.stateOf;
/// the HUD's panel component
const Panel=lib.hudPanel.Panel;
/// the panel's width (pixels)
const pw:f32=480;
/// the height (pixels) of its title band, above the first row
const headerH:f32=100;
/// the height (pixels) of one row
const optionH:f32=44;
/// the room (pixels) under the last row
const padBottom:f32=30;
/// where a row's bullet bud sits, from the panel's left (pixels)
const podX:f32=90;
/// where a row's key sits, from the panel's left (pixels)
const keyX:f32=112;
/// where a row's label sits, from the panel's left (pixels)
const labelX:f32=190;
/// a row's clickable band, from this far left of its pod
const rowInset:f32=50;
/// how far a row's line of text sits below its box's top (pixels)
const lineY:f32=optionH/2-8;
/// how many rows the menu has
const rows=fields(play.PauseRow).len;
/// shown while paused.
pub fn visible(g:*const play.Game)bool{return g.mode==.paused;}
/// a row of the menu
pub const Pick=union(enum){
  /// the menu row, which says what it does
  row:play.PauseRow
};
/// a row clicks as mouse1 is let go over it
pub fn fire(_:Pick)hud.Fire{return.release;}
/// a click does what the row says
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(press==.use)switch(p){.row=>|r|g.choose(r)};
}
/// draws the veil and the panel: the title and each row's bud, key and
/// label, lit under the mouse (or the keys) and registered to be clicked.
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  // the rows' keys and labels (one of each per row: the strings test checks)
  const keys=txt.s.hud.pauseKeys;
  const labels=txt.s.hud.pauseLabels;
  // the panel, centred
  const pn=Panel.menu(.{w,h},pw,headerH+optionH*m.f(rows)+padBottom,0.55,txt.s.hud.paused);
  try pn.draw(g,d,.{w,h});
  const px=pn.box.x;
  // the rows, down the panel under its title band
  var col=Column.in(.{.x=px+podX-rowInset,.y=pn.box.y+headerH-lineY,.w=pw-2*(podX-rowInset),.h=optionH*m.f(rows)},0);
  for(0..rows)|i|{
    // which row it is, its box, its line of text, its state and whether
    // the mouse is over it
    const row:play.PauseRow=@enumFromInt(i);
    const box=col.next(optionH);
    const y=box.y+lineY;
    const st=buttonState(g,hud.row(.pause,.{.row=row}),box);
    const over=st.over();
    if(over)try d.glow(px+pw/2,y+8,pw*@as(f32,if(st.down())0.36 else 0.42),s.menuHover);
    try hud.bullet(d,px+podX,y+8,9,s.gold,switch(st){.idle=>0.15,.hovering,.released=>1,.pressed,.held=>0.7},m.f(i)*0.4);
    _=try d.text(px+keyX,y,s.textLabel,s.dim,txt.nth(keys,i));
    _=try d.text(px+labelX,y,s.textLabel,if(over)s.gold else s.white,txt.nth(labels,i));
    try g.rows.add(box,hud.row(.pause,.{.row=row}));
  }
}
