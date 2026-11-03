//! HALCYRA seed: a small flower under a see-through veil leaning over a
//! green sprout beside the seed, crystal petals at the veil's rim, a thread
//! of light wound round the sprout, sparkles scattering off the veil (it
//! guards a plant from the beam).
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
pub const item:items.Item=.seedHalcyra;
/// draws the sprout it guards, the thread wound round it, the veiled
/// flower leaning over it, sparkles off the veil, and the coat in `col`.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // the sprout it guards, and its leaves
  try ic.stem(.{.{0.08,iconKit.topAt},.{0.1,0.2},.{0.14,0.32},.{0.16,0.44}},0.035,iconKit.stemCol);
  try ic.leaf(.{0.14,0.32},0.5,0.14,0.06,iconKit.sprout,1);
  try ic.leaf(.{0.12,0.26},2.4,0.12,0.05,iconKit.sprout,1);
  // the thread wound round it, a few turns of light
  for(0..turns)|i|{
    // how far up the sprout this turn sits, and how it swings round
    const y=0.12+0.08*m.f(i);
    const a=ic.t*1.5+m.f(i)*1.7;
    try ic.bud(.{0.11+0.05*@cos(a),y},0.016,thread,1);
  }
  // the veiled flower leaning over it from the seed's other side
  const at:iconKit.P=.{0.02,0.62};
  try ic.stem(.{.{-0.06,iconKit.topAt},.{-0.14,0.3},.{-0.08,0.52},at},0.03,neck);
  try ic.glow(at,0.2,glowCol);
  // the veil, a hood of see-through petals leaning toward the sprout
  for(0..veil)|i|{
    // this veil petal's bearing, a fan opening down over the sprout
    const a=-0.2-m.pi*0.75*m.ratio(i,veil-1);
    try ic.leaf(at,a,0.2,0.09,hood,1);
    try ic.gem(.{at[0]+0.2*@cos(a),at[1]+0.2*@sin(a)},0.025,crystal);
  }
  try ic.bud(at,0.045,heart,1);
  // a sparkle scattering off the veil now and then
  const k=@mod(ic.t*0.8+ic.phase,1);
  try ic.gem(.{at[0]+0.3*k,at[1]+0.15*k},0.02*(1-k),crystal);
  try ic.coat(col);
}
/// how many turns of thread wind round the sprout
const turns=4;
/// how many petals make the veil
const veil=5;
/// the veil: pale blue, see-through
const hood:Color=.{200,230,255,120};
/// the crystal petals at its rim
const crystal:Color=.{235,248,255,255};
/// its flower's heart
const heart:Color=.{240,250,255,255};
/// its neck of light
const neck:Color=.{200,225,250,170};
/// the thread wound round what it guards
const thread:Color=.{230,245,255,220};
/// the calm light round it
const glowCol:Color=.{200,230,255,80};
