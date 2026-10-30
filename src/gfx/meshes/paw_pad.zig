//! mesh: PAW PAD. the central (metacarpal) bean under the foot: a rounded
//! triangle of three merged lobes, unit size; instances flatten it onto the
//! sole. Sap, made denser and browner by the instance.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// the shared swatches: the pad is amber sap
const pal=lib.palette;
/// makes a vector from three numbers
const v3=m.v3;
/// builds the pad: three glowing sap lobes, two behind and one ahead,
/// melting into one rounded triangle about a unit across.
pub fn build(b:*mg.Builder)Allocator.Error!void{
  for([_][2]f32{.{-0.38,-0.2},.{0.38,-0.2},.{0,0.32}})|c|{
    try mg.ellipsoid(b,.{.center=v3(c[0],0,c[1]),.radii=v3(0.62,1,0.56),.col=pal.sap,.part=.bloom,.rings=6,.segs=9,.t=0.5});
  }
}
/// mesh: PAW BEAN. a small rounded oval of sap, unit size: the toe pads
/// under each foot, and the wolf's nose pad.
pub const bean=struct{
  /// builds the bean: one glowing sap sphere of unit radius at the origin,
  /// which each instance squashes into its oval.
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(1,1,1),.col=pal.sap,.part=.bloom,.rings=6,.segs=9,.t=0.5});
  }
};
