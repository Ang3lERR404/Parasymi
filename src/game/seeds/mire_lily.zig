//! MIRE LILY seed: a pale cupped lily on a short teal stem, broad pads
//! lying round its foot, and rain falling into its cup (it lives on
//! soaked ground).
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
pub const item:items.Item=.seedMireLily;
/// draws its pads lying out round its foot, a short stem, the lily's
/// petals cupped upward round its stamens, raindrops falling into it, and
/// the coat in `col` beneath.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // where the lily's cup sits, nodding a little on the wind
  const sway=swayAmount*@sin(ic.t*swayRate+ic.phase*5);
  const cup:iconKit.P=.{0.02+sway,0.52};
  // its pads, lying flat out to either side of its foot
  for(pads)|a|try ic.leaf(.{0,iconKit.topAt+0.04},a,0.3,0.13,pad,1);
  try ic.stem(.{.{0,iconKit.topAt},.{0.03,0.2},.{-0.02,0.36},.{cup[0],cup[1]-0.06}},0.035,stemCol);
  // rain falling into the cup, one drop at a time
  // how far the falling drop has come, 0..1
  const k=@mod(ic.t*fallRate+ic.phase,1);
  try ic.bud(.{cup[0]+0.05,m.lerp(0.95,cup[1]+0.08,k)},0.025,drop,@sin(k*m.pi));
  // the petals, cupped upward, the back ones first
  for(petals)|a|try ic.leaf(cup,m.halfPi+a,0.2,0.08,petal,1);
  try ic.stamens(cup,m.halfPi,0.6,5,0.1,filament);
  try ic.glow(cup,0.22,lilyGlow);
  try ic.coat(col);
}
/// its pads' bearings (radians: low to either side)
const pads=[_]f32{-0.15,m.pi+0.15,-0.6,m.pi+0.6};
/// its petals' lean off upright (radians), cupped
const petals=[_]f32{-0.7,0.7,-0.35,0.35,0};
/// how far the lily nods (icon units)
const swayAmount:f32=0.02;
/// how fast it nods (radians a second)
const swayRate:f32=0.9;
/// how many drops fall into it a second
const fallRate:f32=0.7;
/// its stem: mire teal
const stemCol:Color=.{64,115,107,255};
/// its pads: deep wet green
const pad:Color=.{51,107,77,255};
/// its petals: pale lilac blue
const petal:Color=.{199,209,255,255};
/// its stamens: pale gold
const filament:Color=.{255,235,200,255};
/// a falling raindrop: pale blue
const drop:Color=.{190,220,255,255};
/// the soft light in its cup
const lilyGlow:Color=.{200,215,255,70};
