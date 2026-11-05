//! F3: frame/sim timings, world counts, where the wolf stands (tile and
//! chunk), which way the view looks and what the cursor points at; the
//! ground draws its tile, fan and chunk grid meanwhile (terrain.frag).
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
/// how far the card hangs below the screen's top (pixels)
const cardTop:f32=14;
/// how far the card reaches past its lines, top and bottom together (pixels)
const cardPad:f32=28;
/// how far the lines stand in from the card's left edge (pixels)
const inset:f32=18;
/// how opaque the card's trellis is
const cardAlpha:f32=0.85;
/// the shortest frame time the frame rate is worked out from (ms), so a
/// first frame of none never divides by nothing
const minFrameMs:f32=0.01;
/// the chunks: their size, and a tile's chunk
const ck=lib.ck;
/// the name of what stands on tile `hv`: a structure, else a plant, else nothing
fn aimedName(g:*const play.Game,hv:m.Vice(i32,2))[]const u8{
  if(g.structs.touched(&g.world,hv[0],hv[1]))|j|return txt.item(g.structs.list.items[j.idx()].def().item).name;
  if(g.plantAt(hv))|p|return txt.plant(g.plants.list.items(.sp)[p.idx()]).name;
  return txt.s.describe.nothing;
}
/// shown while the debug key has it toggled on.
pub fn visible(g:*const play.Game)bool{return g.debug;}
/// draws a card at the top right: frame, GPU and sim times, world counts,
/// draw counts, the wolf's place and the hour, and motes in flight.
pub fn draw(g:*play.Game,d:*Draw,w:f32,_:f32)Allocator.Error!void{
  // the renderer's numbers from last frame, and the card's left edge
  const rs=g.renderStats;
  const bx=w-bw-margin;
  // how many lines it holds, and so the card's height
  const lines=10;
  const bh=lineH*m.f(lines)+cardPad;
  try d.trellis(bx,cardTop,bw,bh,s.card,cardAlpha);
  // where the next line's top sits (pixels), moving down a line each print
  var y:f32=cardPad;
  _=try d.print(bx+inset,y,s.textLabel,s.white,txt.s.hud.fps,.{m.msPerS/@max(g.frameMs,minFrameMs),g.frameMs});
  y+=lineH;
  _=try d.print(bx+inset,y,s.textLabel,s.white,txt.s.hud.gpu,.{rs.gpuMs});
  y+=lineH;
  _=try d.print(bx+inset,y,s.textLabel,s.white,txt.s.hud.sim,.{g.simMs,g.ticks});
  y+=lineH;
  _=try d.print(bx+inset,y,s.textLabel,s.white,txt.s.hud.counts,.{g.world.map.count(),g.plants.len(),g.structs.list.items.len});
  y+=lineH;
  _=try d.print(bx+inset,y,s.textLabel,s.white,txt.s.hud.draws,.{rs.instances,rs.parts,rs.draws});
  y+=lineH;
  _=try d.print(bx+inset,y,s.textLabel,s.white,txt.s.hud.pos,.{g.player.pos[0],g.player.pos[1],g.player.pos[2],g.sky.tod});
  y+=lineH;
  // the wolf's tile, the chunk it lies in, and where in that chunk
  const t=m.tileAt(g.player.pos);
  const cc=ck.Coord.ofTile(t[0],t[1]);
  _=try d.print(bx+inset,y,s.textLabel,s.white,txt.s.hud.place,.{t[0],t[1],cc.x,cc.y,@mod(t[0],ck.sizeTiles),@mod(t[1],ck.sizeTiles)});
  y+=lineH;
  // which way the view looks, and its heading round the compass
  const gz=g.cam.looking();
  const hd=m.heading(gz);
  _=try d.print(bx+inset,y,s.textLabel,s.white,txt.s.hud.looking,.{gz[0],gz[1],gz[2],txt.nth(txt.s.hud.facing,m.dirOfHeading(hd)),hd,m.deg(m.atan2(gz[1],m.len(m.v3(gz[0],0,gz[2]))))});
  y+=lineH;
  // the hovered tile and what stands on it
  if(g.hover)|hv|{
    _=try d.print(bx+inset,y,s.textLabel,s.white,txt.s.hud.aimed,.{hv[0],hv[1],aimedName(g,hv)});
  }else _=try d.print(bx+inset,y,s.textLabel,s.dim,txt.s.hud.aimed,.{0,0,txt.s.describe.nothing});
  y+=lineH;
  _=try d.print(bx+inset,y,s.textLabel,s.dim,txt.s.hud.motes,.{g.starlight.near.n,rs.meshed});
}
