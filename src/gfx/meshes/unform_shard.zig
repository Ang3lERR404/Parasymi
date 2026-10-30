//! mesh: UNFORM SHARD. a shard of a radiant plant as it shatters, flying up
//! to where the unforming gathers its seed (radiant_kit `cut`): a small
//! sliver of cut crystal, faintly violet. The event places, spins and
//! shrinks it as it flies (game/unforming.zig).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the mesh builder
const mg=lib.meshgen;
/// the radiant kit: its cut crystals
const rk=lib.radiantKit;
/// the shared swatches, and the per-mesh random stream
const pal=lib.palette;
/// colour conversions
const color=lib.engine.core.color;
/// the shard's rows, foot to tip: height, radius, twist
const rows=[_][3]f32{.{-0.03,0,0},.{-0.005,0.018,0},.{0.03,0,0.5}};
/// builds the shard about the origin
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // its own random stream, the same every build
  var rng=pal.rngFor("unformShard");
  try rk.cut(b,.{.rows=&rows,.deepRows=1,.deep=color.rgb(0.6,0.5,0.9).toRgba8(255),.lite=color.rgb(0.95,0.96,1).toRgba8(255)},&rng);
}
