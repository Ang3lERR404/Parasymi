//! mesh: NODE FIBRE. a clump of fibre plant: long fibrous stalks rising
//! from a tuft of roots in a loose vase, arching out under their own weight,
//! green at the root and drying to straw at their tapering tips, small
//! leaves along a few of them. It sways like any plant (the instance's
//! sway). Tile space, centred on the tile.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, splines, easing
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// the shared swatches, and the per-mesh random stream
const pal=lib.palette;
/// colour conversions, for the green-to-straw stalks
const color=engine.core.color;
/// the structure kit, for the root mat at the clump's foot
const kit=lib.structureKit;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// how much larger than its sketch the whole clump is drawn
const scale:f32=1.8;
/// builds the clump: a root mat, then sixteen stalks fanning round it,
/// each arching out and over, fading green to straw, every third leafed.
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the clump's own random stream, the same every build
  var rng=pal.rngFor("node_fibre");
  try kit.rootMat(b,5,0.22*scale,0.025*scale,0x1F1B,null);
  // the dry straw of the tips, and the living green at the root
  const straw=color.rgb(0.62,0.52,0.3).toRgba8(255);
  const green=color.rgb(0.32,0.5,0.24).toRgba8(255);
  for(0..16)|i|{
    // this stalk's bearing, and the flat direction out along it
    const a=m.ratio(i,16)*m.tau+rng.range(-0.2,0.2);
    const out=v3(@cos(a),0,@sin(a));
    // how long it grows, and how far it leans out (0 upright .. 1 sideways)
    const len=rng.range(0.28,0.5)*scale;
    const lean=rng.range(0.25,0.7);
    // the stalk's control points
    var c:[6]V3=undefined;
    mg.growthPath(.{.start=out*m.splat3(0.02),.direction=m.norm(out*m.splat3(lean)+v3(0,1,0)),.length=len,.wobble=0.2,.curl=0.05,.seed=0xF1B0+%i},&c);
    // they arch out and over as they go (the root stays put)
    for(c[1..],1..)|*p,j|{
      // how far up the stalk this point lies, 0..1
      const k=m.ratio(j,5);
      p.*+=out*m.splat3(0.12*k*k*lean*scale)-v3(0,0.08*k*k*k*lean*scale,0);
    }
    // the stalk resampled smooth along its spline
    var p:[14]V3=undefined;
    m.splineResample(&c,&p);
    // each point's growth stamp, radius and colour
    var ts:[14]f32=undefined;
    var rs:[14]f32=undefined;
    var cs:[14]color.Rgba8=undefined;
    for(&ts,&rs,&cs,0..)|*t,*r,*cc,j|{
      // how far along the stalk, 0 root .. 1 tip
      const k=m.ratio(j,13);
      t.*=k;
      r.*=@max(0.011*(1-k*0.9),0.0007);
      cc.*=color.mix(green,straw,m.smooth(k));
    }
    try b.tubeC(&p,&ts,&rs,&cs,null,.stem,4);
    if(i%3==0)try mg.leavesAlong(b,&p,3,0.09,0.025,0.2,0.7,0.2,0.7,pal.leafDark,pal.leafLite,0xF1C0+%i);
  }
}
