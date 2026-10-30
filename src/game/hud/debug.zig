//! F3: frame/sim timings and world counts.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const play=lib.play;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const txt=lib.txt;
const m=lib.engine.core.math;
const margin=s.edge;
const bw:f32=364;
const lineH:f32=22;
pub fn visible(g:*const play.Game)bool{return g.debug;}
pub fn draw(g:*play.Game,d:*Draw,w:f32,_:f32)Allocator.Error!void{
  const rs=g.renderStats;
  const bx=w-bw-margin;
  const lines=7;
  const bh=lineH*m.f(lines)+28;
  try d.trellis(bx,14,bw,bh,s.card,0.85);
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
