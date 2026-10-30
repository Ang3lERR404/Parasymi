//! the pause menu (Esc): the world holds its breath behind a soft veil.
//! Each row is clicked (or its key pressed) to do what it says.
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
/// how many rows the menu has
const rows=fields(play.PauseRow).len;
/// shown while paused.
pub fn visible(g:*const play.Game)bool{return g.mode==.paused;}
/// a row of the menu
pub const Pick=union(enum){
  /// the menu row, which says what it does
  row:play.PauseRow
};
/// a click does what the row says
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(press==.use)switch(p){.row=>|r|g.choose(r)};
}
/// draws the veil and the panel: the title and each row's bud, key and
/// label, lit under the mouse and registered to be clicked.
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  try d.glow(w/2,h/2,@max(w,h)*s.veilReach,s.veil);
  // the rows' keys and labels
  const keys=txt.s.hud.pauseKeys;
  const labels=txt.s.hud.pauseLabels;
  // one label and key per row (the strings test checks the counts)
  const n=rows;
  // the panel's height, and its top-left corner
  const ph=headerH+optionH*m.f(n)+padBottom;
  const px=(w-pw)/2;
  const py=(h-ph)/2;
  try d.trellis(px,py,pw,ph,s.pausePanel,0.55);
  g.rows.add(.{.x=px,.y=py,.w=pw,.h=ph},.panel);
  // the title, centred over the panel
  const title=txt.s.hud.paused;
  _=try d.text(w/2-Draw.width(title,s.textBanner)/2,py+s.titleY,s.textBanner,s.gold,title);
  for(0..n)|i|{
    // this row's line top, which row it is, its box, its state and
    // whether the mouse is over it
    const y=py+headerH+optionH*m.f(i);
    const row:play.PauseRow=@enumFromInt(i);
    const box:hud.Box=.{.x=px+podX-rowInset,.y=y-optionH/2+8,.w=pw-2*(podX-rowInset),.h=optionH};
    const st=buttonState(g,hud.row(.pause,.{.row=row}),box);
    const over=st.over();
    if(over)try d.glow(px+pw/2,y+8,pw*@as(f32,if(st.down())0.36 else 0.42),s.menuHover);
    try hud.bullet(d,px+podX,y+8,9,s.gold,switch(st){.idle=>0.15,.hovering=>1,.pressed,.held=>0.7},m.f(i)*0.4);
    _=try d.text(px+keyX,y,s.textLabel,s.dim,txt.nth(keys,i));
    _=try d.text(px+labelX,y,s.textLabel,if(over)s.gold else s.white,txt.nth(labels,i));
    g.rows.add(box,hud.row(.pause,.{.row=row}));
  }
}
