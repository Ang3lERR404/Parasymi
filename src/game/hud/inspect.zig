//! the free camera's reminder: a small glowing tendril by the top-left with
//! how to get back.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const play=lib.play;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const txt=lib.txt;
const ox:f32=344;
const oy:f32=46;
const tendrilW:f32=300;
const tendrilH=s.barHBold;
const glowR:f32=22;
pub fn visible(g:*const play.Game)bool{return g.mode==.inspect;}
pub fn draw(_:*play.Game,d:*Draw,_:f32,_:f32)Allocator.Error!void{
  try d.glow(ox+8,oy+8,glowR,s.freecamGlow);
  try d.tendril(ox,oy,tendrilW,tendrilH,s.freecam,1,0.7);
  _=try d.text(ox+14,oy+24,s.textBody,s.white,txt.s.hud.freeCam);
  _=try d.text(ox+14,oy+44,s.textTiny,s.dim,txt.s.hud.freeCamHint);
}
