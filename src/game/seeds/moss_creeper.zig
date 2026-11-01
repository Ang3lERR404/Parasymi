//! MOSS CREEPER seed: a cushion of moss with runners creeping out from it
//! along the ground, small leaves at their ends, and the soil under them
//! greening as they go.
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
pub const item:items.Item=.seedMossCreeper;
/// draws runners creeping out to either side along the ground, reaching
/// further and back, small leaves at their tips, and a cushion of moss at
/// their heart, then the coat in `col` beneath.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // how far the runners have crept now (0.6..1)
  const reach=0.8+0.2*@sin(ic.t*creepRate+ic.phase*4);
  const heart:iconKit.P=.{0,iconKit.topAt+0.1};
  for(sides)|s|{
    // where this runner's tip lies
    const tip:iconKit.P=.{heart[0]+s*0.42*reach,heart[1]+0.02};
    try ic.stem(.{heart,.{heart[0]+s*0.15,heart[1]+0.06},.{heart[0]+s*0.3*reach,heart[1]-0.02},tip},0.025,runner);
    try ic.leaf(tip,m.halfPi-s*0.5,0.1,0.05,leaf,1);
    try ic.leaf(tip,m.halfPi+s*0.2,0.08,0.04,leaf,1);
  }
  // the cushion: lumps of moss heaped at the heart
  for(lumps)|l|try ic.bud(.{heart[0]+l[0],heart[1]+l[1]},l[2],moss,1);
  try ic.coat(col);
}
/// the two ways the runners creep
const sides=[_]f32{-1,1};
/// the cushion's lumps: across, up, radius (icon units)
const lumps=[_]m.Vec(f32,3){.{-0.08,0.04,0.07},.{0.08,0.04,0.07},.{0,0.09,0.08},.{0,0.02,0.07}};
/// how fast the runners creep out and back (radians a second)
const creepRate:f32=0.8;
/// its runners: violet-tinged
const runner:Color=.{107,92,102,255};
/// its leaves: fresh green
const leaf:Color=.{110,170,70,255};
/// its moss: deep green
const moss:Color=.{82,140,51,255};
