//! DRIFTWISP spore: the sprout has let go of its seed and floats above
//! it, a comb-jelly lantern of clear sap (its comb rows splitting the light
//! into colours, a golden spore inside) under a catcher dish, hair-thin
//! filaments waving beneath, a mote of starlight falling into the dish (it
//! drinks the sky into starlight).
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
/// the spore this module draws
pub const item:items.Item=.seedDriftwisp;
/// draws the floating lantern over its seed: filaments waving under it, a
/// catcher dish of petals above, clear sap with a spore and coloured comb
/// rows, a mote of starlight falling in, and the coat in `col` beneath.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // how far the lantern bobs now, and where it floats
  const bob=bobAmount*@sin(ic.t*bobRate+ic.phase*6);
  const float:iconKit.P=.{0,0.46+bob};
  // top, mouth: the lantern's crown and its open underside
  const top=float[1]+lanternH;
  const mouth=float[1]-lanternH;
  // the dish, sitting just above the lantern's crown
  const dish:iconKit.P=.{0,top+0.03};
  // filaments out of the lantern's mouth, two lengths, waving
  for(0..filaments)|i|{
    // where along the mouth this filament hangs (-0.5..0.5), and its length
    const k=m.ratio(i,filaments-1)-0.5;
    const len:f32=if(i%2==0)0.4 else 0.28;
    try ic.thread(.{k*lanternW*0.9,mouth+0.02},len,1.6,0.05,0.03,m.f(i)*1.9+ic.phase*4,filament);
  }
  // the catcher dish: a cup of petals opening upward
  for(0..petals)|i|{
    // this petal's bearing: fanned round straight up
    const a=m.halfPi+(m.ratio(i,petals-1)-0.5)*2.2;
    try ic.leaf(dish,a,0.3,0.12,petal,0.8);
  }
  try ic.stamens(dish,m.halfPi,0.6,4,0.2,filamentLite);
  // the lantern: clear sap, the spore inside, comb rows over it in colours
  try ic.glow(float,0.26,floatGlow);
  try ic.bud(float,lanternW,sap,0.6);
  try ic.bud(.{0,float[1]-0.01},0.05,spore,1);
  for(0..rowCount)|i|{
    // this row's place across the lantern (-1..1), and its reach out
    const k=m.ratio(i,rowCount-1)*2-1;
    const x=k*lanternW*0.95;
    try ic.stem(.{.{0,mouth},.{x*1.3,float[1]-lanternH*0.6},.{x*1.3,float[1]+lanternH*0.6},.{0,top}},0.025,rows[i]);
  }
  // starlight falling into the dish
  // how far the falling mote has come, 0..1
  const f=@mod(ic.t*fallTime+ic.phase,1);
  try ic.bud(.{0.04,m.lerp(0.98,dish[1]+0.1,f)},0.045,star,@sin(f*m.pi));
  try ic.coat(col);
}
/// how many filaments wave under the lantern
const filaments=5;
/// how many petals make the catcher dish
const petals=5;
/// the lantern's half width (icon units)
const lanternW:f32=0.15;
/// the lantern's half height (icon units)
const lanternH:f32=0.16;
/// how many comb rows are seen over the lantern
const rowCount=5;
/// how far it bobs (icon units)
const bobAmount:f32=0.05;
/// how fast it bobs (radians a second)
const bobRate:f32=1.6;
/// how many motes fall a second
const fallTime:f32=0.5;
/// the filaments: a dusky blue thread
const filament:Color=.{170,185,230,210};
/// the dish's petals: pale blue
const petal:Color=.{200,215,255,230};
/// the dish's stamens: near white
const filamentLite:Color=.{230,238,255,240};
/// the clear sap of the lantern, mostly see-through
const sap:Color=.{215,230,255,120};
/// the golden spore inside
const spore:Color=.{255,235,160,255};
/// the soft blue glow round the lantern
const floatGlow:Color=.{200,225,255,80};
/// the falling mote of starlight
const star:Color=.{255,245,190,255};
/// the comb rows, each splitting the light its own colour, left to right
/// the comb rows, each splitting the light a different colour
const rows=[rowCount]Color{
  .{255,190,220,230},.{255,235,170,230},.{190,255,210,230},.{170,220,255,230},.{210,185,255,230},
};
