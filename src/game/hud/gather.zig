//! gathering progress grows a tendril above the wolf's focus.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the game itself: how long the wolf has gathered
const play=lib.play;
/// the gardener's actions, for how long a gathering takes
const actions=lib.actions;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// all the maths: clamps, easing
const m=lib.engine.core.math;
/// the tendril's full length (pixels)
const tendrilW:f32=120;
/// its thickness (pixels)
const tendrilH=s.barHBold;
/// how far (pixels) above the screen's middle it grows
const aboveHead:f32=120;
/// shown while a gathering is under way on something pointed at.
pub fn visible(g:*const play.Game)bool{return g.gatherT>0 and g.hover!=null;}
/// draws the gold tendril above the middle, grown as far as the gathering is.
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  // how far the gathering has come, 0..1
  const t=m.clamp01(g.gatherT/actions.gatherTime);
  try d.tendril(w/2-tendrilW/2,h/2-aboveHead,tendrilW,tendrilH,s.gold,t,0.9);
}
