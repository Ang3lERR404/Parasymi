//! mesh: NODE LEY. ley shards: a cluster of crystals grown out of a ley
//! line, faceted prisms with pointed terminations fanning up and out from
//! a common root, the tallest at the heart, smaller ones leaning out at
//! its feet. Violet, paling to light at the points, glowing from within
//! (the instance's glow). Tile space, centred on the tile.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, angles, ratios
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// the shared swatches, and the per-mesh random stream
const pal=lib.palette;
/// colour conversions, for the violet body and pale tips
const color=engine.core.color;
/// the mineral kit: crystals and stones
const kit=lib.mineralKit;
/// makes a vector from three numbers
const v3=m.v3;
/// how much larger than its sketch the whole cluster is drawn
const scale:f32=1.8;
/// builds the cluster: three tall crystals at the heart, a ring of seven
/// smaller ones leaning out round them, all rising from a dark stone root.
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the cluster's own random stream, the same every build
  var rng=pal.rngFor("node_ley");
  // the crystals' violet body, and the pale light at their points
  const body=color.rgb(0.42,0.26,0.78).toRgba8(255);
  const tip=color.rgb(0.86,0.74,1.0).toRgba8(255);
  // the heart: a few tall crystals, nearly upright
  for(0..3)|_|{
    try kit.crystal(b,.{
      .base=v3(rng.range(-0.05,0.05),-0.03,rng.range(-0.05,0.05)),
      .dir=m.norm(v3(rng.range(-0.25,0.25),1,rng.range(-0.25,0.25))),
      .len=rng.range(0.38,0.55)*scale,.r=rng.range(0.04,0.055)*scale,.col=body,.tip=tip,
    },&rng);
  }
  // a ring of smaller ones leaning out around it
  for(0..7)|i|{
    // this one's bearing round the heart, and how far out it stands
    const a=m.ratio(i,7)*m.tau+rng.range(-0.3,0.3);
    const d=rng.range(0.07,0.16);
    try kit.crystal(b,.{
      .base=v3(@cos(a)*d,-0.02,@sin(a)*d),
      .dir=m.norm(v3(@cos(a)*rng.range(0.5,1.0),1,@sin(a)*rng.range(0.5,1.0))),
      .len=rng.range(0.12,0.26)*scale,.r=rng.range(0.022,0.035)*scale,.col=body,.tip=tip,
    },&rng);
  }
  // a root of dark stone the cluster grows out of
  try kit.stone(b,v3(0,-0.02,0),0.13*scale,0.4,color.rgb(0.2,0.17,0.26).toRgba8(255),color.rgb(0.3,0.26,0.4).toRgba8(255),&rng);
}
