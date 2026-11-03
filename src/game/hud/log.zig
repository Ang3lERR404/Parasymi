//! recent messages (newest first, fading) and the control hint line.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: conversions to bytes and floats
const m=lib.engine.core.math;
/// the game itself: its message log
const play=lib.play;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// every player-facing string
const txt=lib.txt;
/// the height of one message line (pixels)
const lineH:f32=22;
/// how far (pixels) above the bottom the newest message sits
const startY:f32=160;
/// how long (s) a message takes to fade, after a short hold at full
const fadeDur:f32=8;
/// how old (s) a message may be before it is no longer drawn
const maxAge:f32=12;
/// shown everywhere but over the research tree, which fills the screen
/// with its own hint and cards
pub fn visible(g:*const play.Game)bool{return g.mode!=.research;}
/// draws the recent messages upward from the bottom left, newest lowest,
/// each fading with age, and the control hint along the very bottom.
pub fn draw(g:*play.Game,d:*Draw,_:f32,h:f32)Allocator.Error!void{
  for(g.prog.log,0..)|msg,i|{
    if(msg.len==0 or msg.age>maxAge)continue;
    // how opaque this message is now, 0..255
    const a=m.unorm8(1.5-msg.age/fadeDur);
    _=try d.text(24,h-startY-m.f(i)*lineH,s.textLabel,.{220,210,255,a},msg.buf[0..msg.len]);
  }
  _=try d.text(24,h-22,s.textSmall,s.dim,txt.s.hud.controls);
}
