//! mesh: STRANGE SEED. the seed the unforming gathers out of the shattered
//! radiant light (radiant_kit `cut`): a long cut crystal, a seed's shape,
//! its husk clear glass (part `husk`), faintly violet at its foot and near
//! white above, cracks glowing over it, and inside it a small constellate
//! web turning slowly, the light it holds. It gathers in the sky and falls
//! (game/unforming.zig), then lies on the ground as a structure of its own
//! (game/structures/strange_seed.zig); planted, its fragments slip out
//! through its cracks.
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
/// the constellate web: the light inside the husk
const constellate=lib.constellate;
/// the seed's rows, foot to tip: height, radius, twist (part.vert
/// `PLEXUS_HUSK_*` follows its middle and reach)
const rows=[_]m.Vice(f32,3){.{0,0,0},.{0.045,0.06,0},.{0.12,0.087,0.5},.{0.195,0.078,0},.{0.255,0.048,0.5},.{0.3,0,0}};
/// builds the seed, lying as it stands: its foot at the origin
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // its own random stream, the same every build
  var rng=pal.rngFor("strangeSeed");
  try rk.cut(b,.{.rows=&rows,.deepRows=2,.deep=color.rgb(0.42,0.3,0.7).toRgba8(255),.lite=color.rgb(0.94,0.95,1).toRgba8(255),.part=.husk},&rng);
  try constellate.seedHeartWeb(b);
}
