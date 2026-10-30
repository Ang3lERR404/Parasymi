//! F3: frame/sim timings and world counts.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the game itself: its timings and counts
const play=lib.play;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// every player-facing string
const txt=lib.txt;
/// all the maths: conversions, easing
const m=lib.engine.core.math;
/// how far (pixels) the card stands in from the screen's right edge
const margin=s.edge;
/// the card's width (pixels)
const bw:f32=364;
/// the height of one line (pixels)
const lineH:f32=22;
/// shown while the debug key has it toggled on.
pub fn visible(g:*const play.Game)bool{return g.debug;}
/// draws a card at the top right: frame, GPU and sim times, world counts,
/// draw counts, the wolf's place and the hour, and motes in flight.
pub fn draw(g:*play.Game,d:*Draw,w:f32,_:f32)Allocator.Error!void{
  // the renderer's numbers from last frame, and the card's left edge
  const rs=g.renderStats;
  const bx=w-bw-margin;
  // how many lines it holds, and so the card's height
  const lines=7;
  const bh=lineH*m.f(lines)+28;
  try d.trellis(bx,14,bw,bh,s.card,0.85);
  // where the next line's top sits (pixels), moving down a line each print
  var y:f32=28;
  _=try d.print(bx+18,y,s.textLabel,s.white,txt.s.hud.fps,.{m.msPerS/@max(g.frameMs,0.01),g.frameMs});
  y+=lineH;
  _=try d.print(bx+18,y,s.textLabel,s.white,txt.s.hud.gpu,.{rs.gpuMs});
  y+=lineH;
  _=try d.print(bx+18,y,s.textLabel,s.white,txt.s.hud.sim,.{g.simMs,g.ticks});
  y+=lineH;
  _=try d.print(bx+18,y,s.textLabel,s.white,txt.s.hud.counts,.{g.world.map.count(),g.plants.len(),g.structs.list.items.len});
  y+=lineH;
  _=try d.print(bx+18,y,s.textLabel,s.white,txt.s.hud.draws,.{rs.instances,rs.parts,rs.draws});
  y+=lineH;
  _=try d.print(bx+18,y,s.textLabel,s.white,txt.s.hud.pos,.{g.player.pos[0],g.player.pos[2],g.sky.tod});
  y+=lineH;
  _=try d.print(bx+18,y,s.textLabel,s.dim,txt.s.hud.motes,.{g.stars.motes.items.len,rs.meshed});
}
