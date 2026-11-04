//! mesh: SPARK. a starlit patch's star spark: a flat four-pointed star of
//! light, its points long and needle thin, a sliver thick so it is whole
//! from either side. part.vert turns it to face the eye and lifts it off
//! the patch by day or lets it drift down the night's column; the instance
//! tints it its patch's colour and makes it glow.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, angles
const m=engine.core.math;
/// the mesh builder
const mg=lib.meshgen;
/// colour conversions
const color=engine.core.color;
/// the mineral kit, for its flat-shaded facets
const kit=lib.mineralKit;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// how far its four points reach (mesh space)
const point:f32=0.12;
/// how far in its waist lies between two points
const waist:f32=0.022;
/// how thick it is through its middle
const thick:f32=0.004;
/// builds the spark: its outline of four points and four waists, fanned to
/// a front and a back middle, so it is closed
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // its bright heart and its paler points (the instance tints both)
  const heart=color.rgb(1,1,1).toRgba8(255);
  const tip=color.rgb(0.8,0.85,1).toRgba8(255);
  // the outline, round from the first point
  var rim:[8]V3=undefined;
  for(&rim,0..)|*q,i|{
    // its bearing, and how far out it lies: a point, or a waist between two
    const a=m.tau*m.ratio(i,8);
    const r=if(i%2==0)point else waist;
    q.*=v3(@cos(a)*r,@sin(a)*r,0);
  }
  // its front and back middles
  const front=v3(0,0,thick);
  const back=v3(0,0,-thick);
  for(0..8)|i|{
    // this edge of the outline
    const p0=rim[i];
    const p1=rim[(i+1)%8];
    // the colours along it: pale at a point, bright at a waist
    const c0=if(i%2==0)tip else heart;
    const c1=if(i%2==0)heart else tip;
    try kit.facet(b,.{p0,p1,front},v3(0,0,0),.{c0,c1,heart},1,.bloom);
    try kit.facet(b,.{p1,p0,back},v3(0,0,0),.{c1,c0,heart},1,.bloom);
  }
}
