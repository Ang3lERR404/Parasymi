//! HOLLOWHEART seed: a stout trunk carrying a broad crown, an amber heart
//! glowing in its hollow and pulsing (a deep reservoir that feeds around it).
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const m=lib.engine.core.math;
const items=lib.items;
const iconKit=lib.icon;
const Color=lib.engine.ui.draw.Color;
pub const item:items.Item=.seedHollowheart;
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  const crown:iconKit.P=.{0,0.62};
  const heart:iconKit.P=.{0,0.36};
  try ic.stem(.{.{0,iconKit.topAt},.{-0.04,0.25},.{0.04,0.45},crown},0.22,trunk);
  for(0..leaves)|i|{
    const a=0.25+(m.pi-0.5)*m.ratio(i,leaves-1);
    try ic.leaf(crown,a,0.38,0.2,if(i%2==0)leaf else leafYoung,0.9);
  }
  const beat=0.5+0.5*@sin(ic.t*beatRate+ic.phase*6);
  try ic.glow(heart,0.2+0.08*beat,heartGlow);
  try ic.bud(heart,0.07,amber,beat);
  try ic.coat(col);
}
const leaves=6;
/// heartbeats (radians a second)
const beatRate:f32=2.2;
const trunk:Color=.{105,80,58,255};
const leaf:Color=.{70,160,100,255};
const leafYoung:Color=.{100,190,115,255};
const amber:Color=.{255,200,120,255};
const heartGlow:Color=.{255,200,120,100};
