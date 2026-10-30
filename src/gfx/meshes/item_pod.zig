//! mesh: ITEM POD. a generic carried item, tinted per item
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
/// colour conversions, for the pod's pale base
const color=engine.core.color;
/// a point in space, made from three numbers
const v3=m.v3;
/// builds the pod: a small near-white seed shape, a touch squat, about 0.09
/// across, drawn as a `.bloom` part so each item's tint colours it
pub fn build(b:*mg.Builder)Allocator.Error!void{
  try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(0.09,0.08,0.09),.col=color.rgb(0.9,0.9,0.9).toRgba8(255),.part=.bloom,.rings=5,.segs=7,.t=1});
}
