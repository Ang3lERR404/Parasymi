//! CELESTIAL BLOOM seed: a luminous core floating free of the seed on a
//! thread of light, its petals hanging apart from it and turning slowly,
//! each held by a thread (it radiates a field of celestial energy).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, easing, angles
const m=lib.engine.core.math;
/// what can be held: item kinds
const items=lib.items;
/// the tools a seed icon is drawn with
const iconKit=lib.icon;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the seed this module draws
pub const item:items.Item=.seedBloom;
/// draws the seed with its bloom loose above it: a glowing core bobbing on
/// its thread, six petals turning round it on threads, its stamens, and the
/// seed's coat in `col` beneath.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // how far the core bobs now, and where it floats
  const bob=bobAmount*@sin(ic.t*bobRate+ic.phase*6);
  const core:iconKit.P=.{0,0.56+bob};
  try ic.stem(.{.{0,iconKit.topAt},.{0.04,0.22},.{-0.04,0.36},.{0,core[1]-0.08}},0.04,thread);
  // how bright the field glows now, breathing round 0.85..1
  const pulse=0.85+0.15*@sin(ic.t*2.4+ic.phase*3);
  try ic.glow(core,0.42*pulse,field);
  // how far round the petal ring has turned
  const turn=ic.t*turnRate+ic.phase;
  for(0..petals)|i|{
    // this petal's bearing, and which way it lies from the core
    const a=turn+m.tau*m.ratio(i,petals);
    const dir:iconKit.P=.{@cos(a),@sin(a)};
    // where the petal hangs, and where its thread leaves the core
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
/// how many petals float round the core
const petals=6;
/// petals float this far from the core, their ring tilted (squashed in y)
const gap:f32=0.2;
/// how much the petal ring is squashed in height, 0..1 (1: a full circle)
const squash:f32=0.75;
/// radians a second the petals turn
const turnRate:f32=0.45;
/// how far the core bobs (icon units)
const bobAmount:f32=0.04;
/// how fast it bobs (radians a second)
const bobRate:f32=1.3;
/// the threads of light holding core and petals: pale, half see-through
const thread:Color=.{220,255,245,150};
/// the petals: near white with a cool blush
const petal:Color=.{235,245,255,235};
/// the core: a bright pale bud
const coreCol:Color=.{240,255,250,255};
/// the field of celestial energy round the core: a soft green glow
const field:Color=.{140,255,215,90};
