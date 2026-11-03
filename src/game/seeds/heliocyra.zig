//! HELIOCYRA seed: a heliotrope on a neck of light from the seed, a cut
//! crystal at its heart, its head turning slowly side to side, a strip of
//! light running level out of the crystal the way it faces (it casts and
//! bends light in strips).
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
pub const item:items.Item=.seedHeliocyra;
/// draws the neck, the turning head of ray petals round its crystal, its
/// strip of light, and the coat in `col` beneath.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // which way the head faces now, -1 left .. 1 right, and where it hangs
  const face=@sin(ic.t*turnRate+ic.phase*6);
  const head:iconKit.P=.{0.08*face,0.62};
  try ic.stem(.{.{0,iconKit.topAt},.{0.04,0.25},.{-0.04,0.45},.{head[0],head[1]-0.06}},0.035,neck);
  // the strip, level out of the crystal the way it faces
  try ic.stem(.{head,.{head[0]+0.25*face,head[1]},.{head[0]+0.5*face,head[1]},.{head[0]+0.8*face,head[1]}},0.05,strip);
  try ic.glow(head,0.24,glowCol);
  for(0..rays)|i|{
    // this ray's bearing round the head
    const a=m.tau*m.ratio(i,rays)+0.2*face;
    try ic.leaf(.{head[0]+0.05*@cos(a),head[1]+0.05*@sin(a)},a,0.15,0.045,petal,1);
  }
  try ic.gem(head,0.07,crystal);
  try ic.coat(col);
}
/// how many ray petals ring the head
const rays=12;
/// how fast the head turns side to side (radians a second)
const turnRate:f32=0.7;
/// its neck of light: amber, half see-through
const neck:Color=.{250,200,130,170};
/// the strip of light it casts
const strip:Color=.{255,225,150,170};
/// its ray petals: warm amber
const petal:Color=.{250,185,95,255};
/// its crystal heart
const crystal:Color=.{255,240,215,255};
/// the light round its head
const glowCol:Color=.{255,205,130,80};
