//! SOLCYRIPHON seed: the light grid's maker hung high over the seed on a
//! thread of light: a flat lens of facets round a gold heart, pearl petals
//! rising round it open to the sky, threads trailing beneath; now and then
//! it folds and pours a beam straight down into the seed (day and night).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: angles, easing
const m=lib.engine.core.math;
/// what can be held: item kinds
const items=lib.items;
/// the tools a seed icon is drawn with
const iconKit=lib.icon;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the seed this module draws
pub const item:items.Item=.seedSolcyriphon;
/// draws the lens hung high, its petals opening and folding with a slow
/// day and night of its own, threads trailing, a beam falling at night,
/// and the coat in `col` beneath.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // how far into its own night it is, 0 day .. 1 night, and where the lens hangs
  const night=m.smooth(0.5+0.5*@sin(ic.t*dayRate+ic.phase*6));
  const lens:iconKit.P=.{0,0.7+bobAmount*@sin(ic.t*1.1+ic.phase*4)};
  // its threads, loose by day, drawn in by night
  for(0..threads)|i|{
    // where this thread hangs from under the lens
    const x=lens[0]+m.lerp(0.14,0.03,night)*(m.ratio(i,threads-1)*2-1);
    try ic.thread(.{x,lens[1]-0.05},m.lerp(0.22,0.14,night),2,0.03,0.025,m.f(i),thread);
  }
  // the beam, by night, straight down into the seed
  if(night>0.5)try ic.stem(.{.{lens[0],lens[1]-0.06},.{lens[0],0.5},.{lens[0],0.3},.{0,iconKit.topAt}},0.06*(night-0.5)*2,beam);
  try ic.glow(lens,m.lerp(0.34,0.22,night),glowCol);
  // the petals round the lens: wide by day, folded up by night
  for(0..petals)|i|{
    // this petal's place round the rim, -1..1, and how far it leans out
    const k=m.ratio(i,petals-1)*2-1;
    const a=m.halfPi-k*m.lerp(1.1,0.35,night);
    try ic.leaf(.{lens[0]+0.08*k,lens[1]+0.02},a,m.lerp(0.24,0.2,night),0.07,petal,1);
  }
  // the lens: a ring of facets round the heart
  for(0..facets)|i|{
    // this facet's bearing round the rim
    const a=m.tau*m.ratio(i,facets)+ic.t*0.2;
    try ic.gem(.{lens[0]+0.11*@cos(a),lens[1]+0.035*@sin(a)},0.025,facet);
  }
  try ic.bud(lens,m.lerp(0.06,0.045,night),heart,1);
  try ic.coat(col);
}
/// how many petals rise round the lens
const petals=7;
/// how many facets ring the lens
const facets=8;
/// how many threads trail beneath it
const threads=5;
/// how fast its own day and night turn (radians a second)
const dayRate:f32=0.5;
/// how far the lens bobs (icon units)
const bobAmount:f32=0.025;
/// its petals: pearl
const petal:Color=.{225,215,245,255};
/// its facets: clear, catching the light
const facet:Color=.{235,240,255,255};
/// its heart: warm gold
const heart:Color=.{255,220,140,255};
/// its threads: pale gold, half see-through
const thread:Color=.{255,225,170,150};
/// the night beam: bright gold
const beam:Color=.{255,225,150,220};
/// the light round it
const glowCol:Color=.{255,215,150,90};
