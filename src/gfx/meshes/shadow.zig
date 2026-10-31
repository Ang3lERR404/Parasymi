//! mesh: SHADOW. a flat unit disc on the ground (y = 0), part `.shadow`,
//! tu.x its radial fraction so the shader can soften its edge. Laid under
//! things that float, so they read as hanging in the air.
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
/// colour conversions, for the disc's black
const color=engine.core.color;
/// how many rings the disc is cut into from its centre out
const rings=4;
/// how many steps round each ring
const stepCount=16;
/// builds the disc: a patch of rings round the origin, all facing up, black,
/// each vertex carrying how far out it lies (0 centre .. 1 rim) in tu.x.
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the grid's rows (rings plus the centre) and columns (steps plus the seam)
  const r=rings+1;
  const c=stepCount+1;
  // each vertex's position, normal, colour and radial fraction
  var pts:[r*c]m.V3=undefined;
  var ns:[r*c]m.V3=undefined;
  var cs:[r*c]color.Rgba8=undefined;
  // (and the radial fraction, which the patch writes into tu.y)
  var us:[r*c]f32=undefined;
  for(0..r)|i|for(0..c)|j|{
    // how far out this ring lies, and the bearing round it
    const k=m.ratio(i,rings);
    const a=m.ratio(j,stepCount)*m.tau;
    pts[i*c+j]=m.v3(@cos(a)*k,0,@sin(a)*k);
    ns[i*c+j]=m.v3(0,1,0);
    cs[i*c+j]=color.black.toRgba8(255);
    us[i*c+j]=k;
  };
  // tu.x carries the radial fraction (patch writes `us` to tu.y): move it over
  const start=b.mark();
  try mg.patch(b,r,c,&pts,&ns,&cs,&us,0,.shadow);
  for(b.v.items[start..])|*v|v.tu=.{v.tu[1],0,0};
}
