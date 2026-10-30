//! VESPER seed: an evening star come down over the seed, held up on a
//! thread of light: a gold core in a star of five dusk-violet rays, two
//! dusky leaves floating free beneath it, and starlight falling to it from
//! the star that feeds it (it needs radiance).
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const m=lib.engine.core.math;
const items=lib.items;
const iconKit=lib.icon;
const Color=lib.engine.ui.draw.Color;
pub const item:items.Item=.seedVesper;
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  const bob=bobAmount*@sin(ic.t*bobRate+ic.phase*6);
  const core:iconKit.P=.{-0.04,0.58+bob};
  const star:iconKit.P=.{0.42,0.88};
  try ic.stem(.{.{0,iconKit.topAt},.{0.03,0.24},.{-0.06,0.38},.{core[0],core[1]-0.1}},0.035,thread);
  // its leaves, floating apart under it
  for(leaves,0..)|a,i|{
    const at:iconKit.P=.{core[0]+0.1*@cos(a),core[1]-0.15+0.02*m.f(i)};
    try ic.leaf(at,a-0.35,0.2,0.08,leaf,0.9);
  }
  // starlight falling from the star to the flower
  const k=@mod(ic.t*fallTime+ic.phase,1);
  try ic.bud(.{m.lerp(star[0],core[0],k),m.lerp(star[1],core[1],k)},0.04,ray,@sin(k*m.pi));
  try ic.glow(core,0.3,bloomGlow);
  // the star of rays, turning slowly round the core, a gap off it
  const turn=ic.t*turnRate+ic.phase;
  for(0..rays)|i|{
    const a=turn+m.halfPi+m.tau*m.ratio(i,rays);
    try ic.leaf(.{core[0]+gap*@cos(a),core[1]+gap*@sin(a)},a,0.22,0.06,petal,1);
  }
  try ic.stamens(core,m.halfPi,0.7,5,0.12,filament);
  try ic.bud(core,0.06,coreCol,1);
  const twinkle=0.75+0.25*@sin(ic.t*3+ic.phase*4);
  try ic.glow(star,0.22*twinkle,starGlow);
  try ic.gem(star,0.09*twinkle,starCol);
  try ic.coat(col);
}
const rays=5;
/// the leaves' bearings (radians: one each way, below the core)
const leaves=[_]f32{-2.6,-0.55};
/// the rays float this far from the core, turning this fast (radians/s)
const gap:f32=0.05;
const turnRate:f32=0.25;
const bobAmount:f32=0.03;
const bobRate:f32=1.1;
/// motes from the star a second
const fallTime:f32=0.6;
const thread:Color=.{255,225,170,140};
const leaf:Color=.{95,125,160,255};
const petal:Color=.{150,115,225,255};
const coreCol:Color=.{255,235,190,255};
const filament:Color=.{255,235,200,255};
const bloomGlow:Color=.{255,215,160,80};
const ray:Color=.{255,245,200,255};
const starCol:Color=.{255,245,210,255};
const starGlow:Color=.{255,240,200,110};
