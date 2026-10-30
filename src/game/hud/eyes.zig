//! looking out of the wolf's eyes: a small lit seed at the middle of the
//! screen, in a soft glow, marking what a click lands on.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the game itself: whether it looks out of the eyes
const play=lib.play;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the aiming seed's radius (pixels)
const seedR:f32=4;
/// the radius of its soft glow (pixels)
const glowR:f32=14;
/// shown while looking out of the wolf's eyes.
pub fn visible(g:*const play.Game)bool{return g.looking;}
/// draws the lit seed and its glow at the middle of the screen.
pub fn draw(_:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  try d.glow(w/2,h/2,glowR,s.aimGlow);
  try d.pod(w/2,h/2,seedR,s.aim,1,0.3);
}
