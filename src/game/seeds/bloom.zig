//! CELESTIAL BLOOM seed: a luminous core floating free of the seed on a
//! thread of light, its petals hanging apart from it and turning slowly,
//! each held by a thread (it radiates a field of celestial energy).
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const m=lib.engine.core.math;
const items=lib.items;
const iconKit=lib.icon;
const Color=lib.engine.ui.draw.Color;
pub const item:items.Item=.seedBloom;
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  const bob=bobAmount*@sin(ic.t*bobRate+ic.phase*6);
  const core:iconKit.P=.{0,0.56+bob};
  try ic.stem(.{.{0,iconKit.topAt},.{0.04,0.22},.{-0.04,0.36},.{0,core[1]-0.08}},0.04,thread);
  const pulse=0.85+0.15*@sin(ic.t*2.4+ic.phase*3);
  try ic.glow(core,0.42*pulse,field);
  const turn=ic.t*turnRate+ic.phase;
  for(0..petals)|i|{
    const a=turn+m.tau*m.ratio(i,petals);
    const dir:iconKit.P=.{@cos(a),@sin(a)};
    const at:iconKit.P=.{core[0]+gap*dir[0],core[1]+gap*dir[1]*squash};
    const from:iconKit.P=.{core[0]+0.06*dir[0],core[1]+0.06*dir[1]*squash};
    try ic.stem(.{from,from,at,at},0.025,thread);
    try ic.leaf(at,a,0.18,0.1,petal,0.8);
  }
  // its crown of stamens
  try ic.stamens(core,m.halfPi,0.7,5,0.15,thread);
  try ic.bud(core,0.09,coreCol,1);
  try ic.coat(col);
}
const petals=6;
/// petals float this far from the core, their ring tilted (squashed in y)
const gap:f32=0.2;
const squash:f32=0.75;
/// radians a second the petals turn
const turnRate:f32=0.45;
const bobAmount:f32=0.04;
const bobRate:f32=1.3;
const thread:Color=.{220,255,245,150};
const petal:Color=.{235,245,255,235};
const coreCol:Color=.{240,255,250,255};
const field:Color=.{140,255,215,90};
