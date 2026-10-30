//! looking out of the wolf's eyes: a small lit seed at the middle of the
//! screen, in a soft glow, marking what a click lands on.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const play=lib.play;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const seedR:f32=4;
const glowR:f32=14;
pub fn visible(g:*const play.Game)bool{return g.looking;}
pub fn draw(_:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  try d.glow(w/2,h/2,glowR,s.aimGlow);
  try d.pod(w/2,h/2,seedR,s.aim,1,0.3);
}
