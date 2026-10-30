//! the free camera's reminder: a small glowing tendril by the top-left with
//! how to get back.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the game itself: its mode
const play=lib.play;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// every player-facing string
const txt=lib.txt;
/// where the reminder starts (pixels from the left)
const ox:f32=344;
/// where the reminder starts (pixels from the top)
const oy:f32=46;
/// the tendril's length (pixels)
const tendrilW:f32=300;
/// its thickness (pixels)
const tendrilH=s.barHBold;
/// the radius of the glow at its root (pixels)
const glowR:f32=22;
/// shown while the free camera is out.
pub fn visible(g:*const play.Game)bool{return g.mode==.inspect;}
/// draws the glowing tendril with the free camera's name and how to leave it.
pub fn draw(_:*play.Game,d:*Draw,_:f32,_:f32)Allocator.Error!void{
  try d.glow(ox+8,oy+8,glowR,s.freecamGlow);
  try d.tendril(ox,oy,tendrilW,tendrilH,s.freecam,1,0.7);
  _=try d.text(ox+14,oy+24,s.textBody,s.white,txt.s.hud.freeCam);
  _=try d.text(ox+14,oy+44,s.textTiny,s.dim,txt.s.hud.freeCamHint);
}
