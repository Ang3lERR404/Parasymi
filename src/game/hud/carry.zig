//! what the cursor carries: the lifted stack (or hotbar item) hangs just
//! off the pointer, glowing, until a click puts it down.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the game itself: the mouse, what is held
const play=lib.play;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the tools an item's icon is drawn with
const icon=lib.icon;
/// how far (pixels) down and right of the pointer the carried thing hangs
const offset:f32=16;
/// the carried icon's radius (pixels)
const r:f32=24;
/// the radius of the glow round it (pixels)
const glowR:f32=38;
/// how strong that glow is, 0..255
const glowAlpha:u8=90;
/// it sways out of step with the slots
const phase:f32=0.71;
/// shown while playing and something is carried.
pub fn visible(g:*const play.Game)bool{return g.mode.live() and g.carried()!=null;}
/// draws the carried thing beside the pointer in a glow of its own colour,
/// with its count when it came from a stack.
pub fn draw(g:*play.Game,d:*Draw,_:f32,_:f32)Allocator.Error!void{
  // what is carried, where it hangs, and its colour
  const item=g.carried().?;
  const c=[2]f32{g.mouse[0]+offset,g.mouse[1]+offset};
  const col=item.info().col;
  try d.glow(c[0],c[1],glowR,.{col[0],col[1],col[2],glowAlpha});
  try icon.draw(d,item,c,r,g.uiT(),phase,1,255);
  switch(g.held.?){
    .slot=>|i|try icon.count(d,c,r,g.player.inv.slot[i].?.n),
    .store=>|i|try icon.count(d,c,r,g.storeSlot(i).?.n),
    .bar=>{},
  }
}
