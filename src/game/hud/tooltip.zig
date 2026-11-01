//! an item's full name, on a small trellis beside the cursor, while the
//! mouse rests on a row showing one (a slot holding one, a recipe).
const lib=@import("../../lib.zig");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=lib.engine.core.math;
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the game itself: the mouse and what it points at
const play=lib.play;
/// what can be held: item kinds
const items=lib.items;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// every player-facing string
const txt=lib.txt;
/// the HUD, to ask a panel what its row shows
const hud=lib.hud;
/// how far (pixels) the card stands off the cursor, right and up
const offset=m.Vice(f32,2){20,10};
/// the card's inner margin (pixels)
const margin:f32=12;
/// the height of one line (pixels)
const lineH:f32=22;
/// how close (pixels) the card may come to the screen's edge
const edge:f32=8;
/// the item on the row under the mouse, as its panel shows it.
fn pointed(g:*const play.Game)?items.Item{
  return hud.shows(g,g.pointed orelse return null);
}
/// shown while playing (not in the free camera) and the mouse rests on a
/// row showing an item.
pub fn visible(g:*const play.Game)bool{
  return g.mode.live() and g.mode!=.inspect and pointed(g)!=null;
}
/// draws a small card beside the cursor, kept on screen, with the item's
/// name in its colour, and "not understood" under it when it is not yet known.
pub fn draw(g:*play.Game,d:*Draw,screenW:f32,screenH:f32)Allocator.Error!void{
  // the item, its name, and whether the gardener understands it yet
  const item=pointed(g).?;
  const name=txt.item(item).name;
  const known=play.known(g,item);
  // the card's width and height, fitting its lines
  const w=@max(Draw.width(name,s.textSub),if(known)0 else Draw.width(txt.s.hud.notUnderstood,s.textFine))+2*margin;
  const h=lineH*@as(f32,if(known)1 else 2)+margin;
  // beside the cursor, kept on screen
  const x=@min(g.mouse[0]+offset[0],screenW-w-edge);
  const y=@max(@min(g.mouse[1]-h-offset[1],screenH-h-edge),edge);
  try d.trellis(x,y,w,h,s.card,0.8);
  _=try d.text(x+margin,y+margin*0.75,s.textSub,item.info().col,name);
  if(!known)_=try d.text(x+margin,y+margin*0.75+lineH,s.textFine,s.dim,txt.s.hud.notUnderstood);
}
