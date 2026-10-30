//! gathering progress grows a tendril above the wolf's focus.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const play=lib.play;
const actions=lib.actions;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const m=lib.engine.core.math;
const tendrilW:f32=120;
const tendrilH=s.barHBold;
const aboveHead:f32=120;
pub fn visible(g:*const play.Game)bool{return g.gatherT>0 and g.hover!=null;}
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  const t=m.clamp01(g.gatherT/actions.gatherTime);
  try d.tendril(w/2-tendrilW/2,h/2-aboveHead,tendrilW,tendrilH,s.gold,t,0.9);
}
