//! recent messages (newest first, fading) and the control hint line.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const m=lib.engine.core.math;
const play=lib.play;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const txt=lib.txt;
const lineH:f32=22;
const startY:f32=160;
const fadeDur:f32=8;
const maxAge:f32=12;
pub fn draw(g:*play.Game,d:*Draw,_:f32,h:f32)Allocator.Error!void{
  for(g.prog.log,0..)|msg,i|{
    if(msg.len==0 or msg.age>maxAge)continue;
    const a=m.unorm8(1.5-msg.age/fadeDur);
    _=try d.text(24,h-startY-m.f(i)*lineH,s.textLabel,.{220,210,255,a},msg.buf[0..msg.len]);
  }
  _=try d.text(24,h-22,s.textSmall,s.dim,txt.s.hud.controls);
}
