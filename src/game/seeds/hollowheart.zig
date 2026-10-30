//! HOLLOWHEART seed: a stout trunk carrying a broad crown, an amber heart
//! glowing in its hollow and pulsing (a deep reservoir that feeds around it).
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
pub const item:items.Item=.seedHollowheart;
/// draws a stout trunk rising from the seed into a fan of leaves, an amber
/// heart pulsing in its hollow, and the coat in `col` beneath.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // where the crown spreads, and where the heart glows in the trunk
  const crown:iconKit.P=.{0,0.62};
  const heart:iconKit.P=.{0,0.36};
  try ic.stem(.{.{0,iconKit.topAt},.{-0.04,0.25},.{0.04,0.45},crown},0.22,trunk);
  for(0..leaves)|i|{
    // this leaf's bearing, fanned across the top of the crown
    const a=0.25+(m.pi-0.5)*m.ratio(i,leaves-1);
    try ic.leaf(crown,a,0.38,0.2,if(i%2==0)leaf else leafYoung,0.9);
  }
  // the heartbeat now, 0..1
  const beat=0.5+0.5*@sin(ic.t*beatRate+ic.phase*6);
  try ic.glow(heart,0.2+0.08*beat,heartGlow);
  try ic.bud(heart,0.07,amber,beat);
  try ic.coat(col);
}
/// how many leaves make the crown
const leaves=6;
/// how fast the heart beats (radians a second)
const beatRate:f32=2.2;
/// the trunk: a warm brown bark
const trunk:Color=.{105,80,58,255};
/// the older leaves: deep green
const leaf:Color=.{70,160,100,255};
/// the younger leaves between them: a lighter green
const leafYoung:Color=.{100,190,115,255};
/// the heart: glowing amber
const amber:Color=.{255,200,120,255};
/// the heart's halo, soft amber
const heartGlow:Color=.{255,200,120,100};
