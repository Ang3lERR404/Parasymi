//! mesh: NODE GRIT. mineral grit breaking out of the ground: a cluster of
//! faceted stones half sunk in the soil, grit and pebbles heaped around
//! them, and pale quartz chips glinting out of the cracks. Tile space,
//! centred on the tile.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, angles
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// the shared swatches, and the per-mesh random stream
const pal=lib.palette;
/// colour conversions, for the greys of the stone and the quartz
const color=engine.core.color;
/// the mineral kit: crystals and stones
const kit=lib.mineralKit;
/// makes a vector from three numbers
const v3=m.v3;
/// how much larger than its sketch the whole cluster is drawn
const scale:f32=1.8;
/// builds the node: four big stones near the middle and nine pebbles
/// scattered round them, each a warm grey, then five quartz chips between.
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the node's own random stream, the same every build
  var rng=pal.rngFor("node_grit");
  // the big stones, then a scatter of grit around them
  for(0..13)|i|{
    // whether this is one of the four big stones
    const big=i<4;
    // its bearing, its distance out, and its size
    const a=rng.range(0,m.tau);
    const d=if(big)rng.range(0.0,0.2)*scale else rng.range(0.18,0.38)*scale;
    const r=if(big)rng.range(0.09,0.15)*scale else rng.range(0.025,0.05)*scale;
    // its grey, and the warm grey body and paler facets made from it
    const g=rng.range(0.42,0.56);
    const col=color.rgb(g+0.04,g,g-0.03).toRgba8(255);
    const lite=color.rgb(g+0.16,g+0.13,g+0.1).toRgba8(255);
    try kit.stone(b,v3(@cos(a)*d,-0.01,@sin(a)*d),r,if(big)rng.range(0.7,1.0)else 0.6,col,lite,&rng);
  }
  // quartz chips in the cracks between the stones
  for(0..5)|_|{
    // the chip's bearing and how far out it pokes up
    const a=rng.range(0,m.tau);
    const d=rng.range(0.06,0.22)*scale;
    try kit.crystal(b,.{
      .base=v3(@cos(a)*d,0.0,@sin(a)*d),.dir=m.norm(v3(@cos(a)*0.5,1,@sin(a)*0.5)),
      .len=rng.range(0.06,0.12)*scale,.r=rng.range(0.012,0.02)*scale,.sides=5,
      .col=color.rgb(0.78,0.76,0.72).toRgba8(255),.tip=color.rgb(0.95,0.94,0.9).toRgba8(255),.part=.thorn,
    },&rng);
  }
}
