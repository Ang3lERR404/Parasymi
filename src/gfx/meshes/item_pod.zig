//! mesh: ITEM POD. a generic carried item, tinted per item
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const mg=lib.meshgen;
const color=engine.core.color;
const v3=m.v3;
pub fn build(b:*mg.Builder)Allocator.Error!void{
  try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(0.09,0.08,0.09),.col=color.rgb(0.9,0.9,0.9).toRgba8(255),.part=.bloom,.rings=5,.segs=7,.t=1});
}
