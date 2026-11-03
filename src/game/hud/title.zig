//! the main menu, at the start: beside the wolf asleep on its dark stage, a
//! column of the menu's rows down the right of the screen under the game's
//! name, on a trellis of its own (no veil: the stage is the backdrop). Each
//! row is clicked (or the keys moved onto it and confirm pressed) to do
//! what it says; continue, with no garden saved, is not offered.
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
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// a screen rectangle
const Box=lib.hud.Box;
/// laying the rows out down the column
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
/// the column's width (pixels)
const cw:f32=400;
/// where the column's middle sits across the screen (a share of its width)
const across:f32=0.76;
/// the height (pixels) of the band the game's name fills, above the rows
const headerH:f32=130;
/// the height (pixels) of one row
const rowH:f32=52;
/// the room (pixels) under the last row
const padBottom:f32=36;
/// where a row's bullet bud sits, from the column's left (pixels)
const podX:f32=70;
/// where a row's label sits, from the column's left (pixels)
const labelX:f32=104;
/// a row's clickable band, from this far left of its pod
const rowInset:f32=40;
/// how far a row's line of text sits below its box's top (pixels)
const lineY:f32=rowH/2-10;
/// how far under its label continue's garden name sits (pixels)
const nameDown:f32=22;
/// how many rows the menu has
const rows=fields(play.TitleRow).len;
/// a row not offered (continue, nothing saved) is drawn this faint
const absent:f32=0.35;
/// drawn at the main menu too (`hud.build`)
pub const atTitle=true;
/// shown at the start, until a garden is entered
pub fn visible(g:*const play.Game)bool{return g.mode==.title;}
/// a row of the menu
pub const Pick=union(enum){
  /// the menu row, which says what it does
  row:play.TitleRow
};
/// a row clicks as mouse1 is let go over it
pub fn fire(_:Pick)hud.Fire{return.release;}
/// a click does what the row says
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(press==.use)switch(p){.row=>|r|g.chooseTitle(r)};
}
/// whether row `r` is offered: continue only with a garden saved
fn offered(g:*const play.Game,r:play.TitleRow)bool{return r!=.@"continue" or g.gardens.items.len>0;}
/// draws the trellis down the right, the game's name over it, and each
/// row's bud and label, lit under the mouse (or the keys) and registered
/// to be clicked; continue names the garden it wakes into
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  // the rows' labels (one per row: the strings test checks)
  const labels=txt.s.hud.titleLabels;
  // the column's box, its middle `across` the screen, centred up and down
  const ch=headerH+rowH*m.f(rows)+padBottom;
  const box=Box{.x=w*across-cw/2,.y=(h-ch)/2,.w=cw,.h=ch};
  const pn=Panel{.box=box,.col=s.pausePanel,.seed=0.9};
  try pn.draw(g,d,.{w,h});
  // the game's name, large, centred along its top band
  const name=txt.s.window.title;
  _=try d.text(box.x+(cw-Draw.width(name,s.textBanner))/2,box.y+headerH/2-s.textBanner*6,s.textBanner,s.gold,name);
  // the rows, down the column under the name
  var col=Column.in(.{.x=box.x+podX-rowInset,.y=box.y+headerH-lineY,.w=cw-2*(podX-rowInset),.h=rowH*m.f(rows)},0);
  for(0..rows)|i|{
    // which row it is, its box, its line of text, its state and whether
    // the mouse is over it
    const row:play.TitleRow=@enumFromInt(i);
    const rb=col.next(rowH);
    const y=rb.y+lineY;
    const on=offered(g,row);
    const st=buttonState(g,hud.row(.title,.{.row=row}),rb);
    const over=on and st.over();
    if(over)try d.glow(box.x+cw/2,y+8,cw*@as(f32,if(st.down())0.36 else 0.42),s.menuHover);
    try hud.bullet(d,box.x+podX,y+8,9,s.gold,if(!on)0 else switch(st){.idle=>0.15,.hovering,.released=>1,.pressed,.held=>0.7},m.f(i)*0.4);
    // its label: lit under the mouse, faint when not offered
    const lc=if(over)s.gold else if(on)s.white else fade(s.white,absent);
    _=try d.text(box.x+labelX,y,s.textLabel,lc,txt.nth(labels,i));
    if(row==.@"continue" and on){
      // the garden continue wakes into: the newest saved
      var buf:[64]u8=undefined;
      const said=txt.bufRender(&buf,txt.s.hud.titleContinue,.{g.gardens.items[0].name.slice()});
      _=try d.text(box.x+labelX,y+nameDown,s.textSmall,s.dim,said);
    }
    if(on)try g.rows.add(rb,hud.row(.title,.{.row=row}));
  }
}
/// `c` with its alpha scaled by `a`
fn fade(c:Color,a:f32)Color{return.{c[0],c[1],c[2],m.unorm8(m.f(c[3])/255*a)};}
