//! matter's icons in the belly, the hotbar and on the cursor: what is not a
//! seed or a bulb drawn as what it is, with the icon kit, in its own colour
//! (grit a few rough grains, fibre a twist of strands, essence a drop,
//! starlight a shimmering mote, a ley shard a cut crystal...). Sunlit matter
//! is its own, lit warmer by its colour.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: angles, conversions
const m=lib.engine.core.math;
/// what can be held
const items=lib.items;
/// the icon kit: an icon's slot and the pieces it is drawn with
const iconKit=lib.icon;
/// one icon being drawn
const Icon=iconKit.Icon;
/// an icon point (icon units: the slot's radius, +y up)
const P=iconKit.P;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the grains of grit: where each lies and how big it is
const gritGrains=[_]m.Vice(f32,3){.{-0.32,-0.3,0.2},.{0.12,-0.36,0.24},.{0.38,-0.12,0.16},.{-0.08,0.02,0.2},.{-0.42,0.1,0.13},.{0.22,0.2,0.14}};
/// fibre's strands: how far apart they start, and how far each twists round
const fibreStrands=3;
/// how far a strand of fibre sways across as it twists (icon units)
const fibreTwist:f32=0.22;
/// a drop's height (icon units; essence), its width two thirds of it
const dropH:f32=1.15;
/// how fast starlight shimmers (radians a second), and how far its glow swells
const shimmerRate:f32=3.1;
/// (see `shimmerRate`)
const shimmerSwell:f32=0.12;
/// the pale of a glint on glass and of light's own heart, never white-hot
const glint:Color=.{236,238,255,255};
/// the gold of a constellate fragment's light
const fragmentGold:Color=.{230,206,140,255};
/// draws `item` as matter, if it is matter (true); else draws nothing
pub fn icon(item:items.Item,ic:Icon,col:Color)Allocator.Error!bool{
  switch(item){
    .grit=>for(gritGrains,0..)|g,k|try ic.kernel(.{g[0],g[1]},g[2]*1.9,mix(col,.{0,0,0,255},0.08*m.f(k%3))),
    .fibre=>try strands(ic,col),
    .essence,.sunlitEssence=>try drop(ic,col,item==.sunlitEssence),
    .convergenceEssence,.sunlitConvergenceEssence=>{
      // two drops grown into one: the paler second inside the first
      try drop(ic,col,item==.sunlitConvergenceEssence);
      try ic.kernel(.{0.02,-0.2},0.42,mix(col,glint,0.45));
    },
    .starlight=>try mote(ic,col),
    .leyShard=>try ic.gem(.{0,-0.05},0.62,col),
    .leyCrystal=>{
      try ic.gem(.{-0.3,-0.2},0.38,col);
      try ic.gem(.{0.28,-0.25},0.32,col);
      try ic.gem(.{0,0.12},0.46,col);
    },
    .starglass=>{
      try ic.gem(.{0,-0.05},0.6,col);
      try ic.glow(.{-0.12,0.1},0.3,glint);
    },
    .fragment=>{
      try ic.gem(.{0,-0.05},0.5,col);
      try ic.glow(.{0,-0.05},0.7,mix(col,fragmentGold,0.3));
    },
    .eveningSilk=>for(0..3)|k|{
      // threads of light hanging, each its own wave
      try ic.thread(.{-0.3+m.f(k)*0.3,0.55},1.05,1.5,0.12,0.06,m.f(k)*1.7,col);
    },
    .driftFlower=>{
      // a flower adrift: its petals round its stamens, a breath of glow
      try ic.glow(.{0,0},0.7,col);
      for(0..5)|k|{
        const a=m.f(k)*m.tau/5+0.3;
        try ic.leaf(.{0,0},a,0.5,0.32,col,1);
      }
      try ic.stamens(.{0,0},m.halfPi,1.2,5,0.28,mix(col,glint,0.5));
    },
    .strangeSeed=>{
      // a crystal husk with a web of light inside
      try ic.gem(.{0,-0.05},0.66,col);
      try ic.glow(.{0,-0.05},0.34,glint);
    },
    .constellateCore,.constellateHeart=>{
      try ic.glow(.{0,0},0.75,col);
      try ic.gem(.{0,0},0.42,col);
      for(0..4)|k|try ic.bud(.{0.55*@cos(m.f(k)*m.halfPi+0.4),0.55*@sin(m.f(k)*m.halfPi+0.4)},0.09,fragmentGold,1);
    },
    .constellatePetal=>try ic.leaf(.{0,-0.6},m.halfPi,1.1,0.5,col,1),
    .constellateLeaf=>try ic.leaf(.{-0.35,-0.55},m.halfPi-0.4,1.15,0.42,col,0.9),
    .constellateBud=>{
      try ic.glow(.{0,0},0.55,col);
      try ic.bud(.{0,0},0.4,col,1);
    },
    .constellateStem=>try ic.stem(.{.{-0.1,-0.8},.{-0.3,-0.2},.{0.3,0.2},.{0.05,0.8}},0.22,col),
    else=>return false,
  }
  return true;
}
/// three strands of fibre twisted round each other, rising up the slot
fn strands(ic:Icon,col:Color)Allocator.Error!void{
  for(0..fibreStrands)|k|{
    // this strand's start across, and which way it first leans
    const x=(m.f(k)-1)*0.16;
    const s:f32=if(k%2==0)1 else-1;
    try ic.stem(.{.{x,-0.7},.{x+s*fibreTwist,-0.25},.{x-s*fibreTwist,0.25},.{x,0.7}},0.2,mix(col,.{0,0,0,255},0.12*m.f(k)));
  }
}
/// a drop: its body a grain stood on its round end, a soft glow round it
/// and a glint of light near its top; a sunlit one glows warmer
fn drop(ic:Icon,col:Color,sunlit:bool)Allocator.Error!void{
  try ic.glow(.{0,-0.1},if(sunlit)0.95 else 0.75,col);
  try ic.kernel(.{0,-0.1},dropH,col);
  try ic.bud(.{-0.14,0.12},0.08,glint,1);
}
/// starlight: a small mote of its own colour, its glow swelling and its
/// heart pale, shimmering, never still
fn mote(ic:Icon,col:Color)Allocator.Error!void{
  // how far the shimmer has swollen it now
  const sw=1+shimmerSwell*@sin(ic.t*shimmerRate+ic.phase*m.tau);
  try ic.glow(.{0,0},0.62*sw,col);
  try ic.glow(.{0,0},0.36*sw,col);
  try ic.glow(.{0,0},0.16*sw,mix(col,glint,0.4));
}
/// colour `a` moved `k` (0..1) of the way to `b`, keeping `a`'s alpha
fn mix(a:Color,b:Color,k:f32)Color{
  return.{
    @intFromFloat(m.lerp(m.f(a[0]),m.f(b[0]),k)),
    @intFromFloat(m.lerp(m.f(a[1]),m.f(b[1]),k)),
    @intFromFloat(m.lerp(m.f(a[2]),m.f(b[2]),k)),
    a[3],
  };
}
test"every item has an icon of its own: a bulb, a seed or matter"{
  // the test helpers
  const testing=std.testing;
  // whether `item` is matter drawn here (the switch above, its cases)
  const drawnHere=struct{
    fn is(item:items.Item)bool{
      return switch(item){
        .grit,.fibre,.essence,.sunlitEssence,.convergenceEssence,.sunlitConvergenceEssence,.starlight,.leyShard,.leyCrystal,.starglass,.fragment,.eveningSilk,.driftFlower,.strangeSeed,.constellateCore,.constellateHeart,.constellatePetal,.constellateLeaf,.constellateBud,.constellateStem=>true,
        else=>false,
      };
    }
  }.is;
  for(std.enums.values(items.Item))|item|{
    const has=lib.structures.kindOf(item)!=null or lib.seeds.draws(item) or drawnHere(item);
    if(!has)std.debug.print("{t} has no icon\n",.{item});
    try testing.expect(has);
  }
}
