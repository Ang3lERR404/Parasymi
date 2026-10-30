//! what the cursor carries: the lifted stack (or hotbar item) hangs just
//! off the pointer, glowing, until a click puts it down.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const play=lib.play;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const icon=lib.icon;
const offset:f32=16;
const r:f32=24;
const glowR:f32=38;
const glowAlpha:u8=90;
/// it sways out of step with the slots
const phase:f32=0.71;
pub fn visible(g:*const play.Game)bool{return g.mode.live() and g.carried()!=null;}
pub fn draw(g:*play.Game,d:*Draw,_:f32,_:f32)Allocator.Error!void{
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
