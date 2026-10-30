//! mesh: BELLY LUMP. unit sphere: one of the heavier things the wolf carries,
//! a dark shape seen faintly through the sap belly. Listed before the belly
//! so it is drawn first and the translucent sac blends over it.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// the plant-piece mesher: ellipsoids, tubes, the builder this mesh is put into
const mg=lib.meshgen;
/// colour conversions, for the lump's dark amber
const color=engine.core.color;
/// builds the lump: one coarse unit sphere, dark amber, drawn as a `.bloom` part
/// so it glows faintly; scaled to size where it is placed
pub fn build(b:*mg.Builder)Allocator.Error!void{
  try mg.ellipsoid(b,.{.center=m.v3(0,0,0),.radii=m.v3(1,1,1),.col=color.rgb(0.2,0.09,0.03).toRgba8(255),.part=.bloom,.rings=6,.segs=9,.t=0.4});
}
