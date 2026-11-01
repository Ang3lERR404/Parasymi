//! mesh: STRANGE SEED. the seed the unforming gathers out of the shattered
//! radiant light (radiant_kit `cut`): a long cut crystal, a seed's shape,
//! deep violet at its foot and near white above, a soft light held inside
//! it. It gathers in the sky and falls (game/unforming.zig), then lies on
//! the ground as a structure of its own (game/structures/strange_seed.zig).
const lib=@import("../../lib.zig");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=lib.engine.core.math;
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
/// makes a vector from three numbers
const v3=lib.engine.core.math.v3;
/// the seed's rows, foot to tip: height, radius, twist
const rows=[_]m.Vice(f32,3){.{0,0,0},.{0.03,0.04,0},.{0.08,0.058,0.5},.{0.13,0.052,0},.{0.17,0.032,0.5},.{0.2,0,0}};
/// builds the seed, lying as it stands: its foot at the origin
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // its own random stream, the same every build
  var rng=pal.rngFor("strangeSeed");
  try rk.cut(b,.{.rows=&rows,.deepRows=2,.deep=color.rgb(0.42,0.3,0.7).toRgba8(255),.lite=color.rgb(0.94,0.95,1).toRgba8(255)},&rng);
  try mg.ellipsoid(b,.{.center=v3(0,0.095,0),.radii=v3(0.03,0.06,0.03),.col=color.rgb(0.85,0.8,1).toRgba8(255),.part=.energy,.rings=6,.segs=8});
}
