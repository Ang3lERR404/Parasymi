//! ASTROCYME seed: a spiral bouquet winding up a thread of light from the
//! seed, its flowers filling one at a time from the bottom up, each
//! gathering its loose petals and opening, then all letting go again (it
//! stores light and gives it back).
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
pub const item:items.Item=.seedAstrocyme;
/// draws the thread of light winding up, its flowers filling and opening
/// in turn from the bottom, and the coat in `col` beneath.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // how full it is now, filling and emptying slowly, 0..1
  const full=0.5+0.5*@sin(ic.t*fillRate+ic.phase*6);
  try ic.stem(.{.{0,iconKit.topAt},.{0.14,0.32},.{-0.14,0.56},.{0.04,0.86}},0.03,thread);
  for(0..flowers)|i|{
    // where this flower sits up the spiral, and how far it has opened
    const k=m.ratio(i,flowers-1);
    const at=iconKit.curve(.{.{0,iconKit.topAt},.{0.14,0.32},.{-0.14,0.56},.{0.04,0.86}},0.2+0.75*k);
    const open=m.smooth(m.clamp01(full*m.f(flowers)-m.f(i)));
    try ic.glow(at,0.1*open,glowCol);
    for(0..5)|j|{
      // this petal's bearing, and how far it drifts loose while the flower is empty
      const a=m.tau*m.ratio(j,5)+ic.t*0.3+m.f(i);
      const loose=(1-open)*0.07;
      try ic.leaf(.{at[0]+loose*@cos(a),at[1]+loose*@sin(a)},a,0.09*m.lerp(0.6,1,open),0.04,petal,open);
    }
    try ic.bud(at,0.025,heart,open);
  }
  try ic.coat(col);
}
/// how many flowers wind up the thread
const flowers=4;
/// how fast it fills and empties (radians a second)
const fillRate:f32=0.6;
/// the thread of light
const thread:Color=.{230,205,255,170};
/// its petals: soft violet
const petal:Color=.{205,180,250,255};
/// each flower's heart: gold
const heart:Color=.{255,220,160,255};
/// the light of a full flower
const glowCol:Color=.{240,210,255,90};
