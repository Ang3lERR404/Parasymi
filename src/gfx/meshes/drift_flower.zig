//! mesh: DRIFT FLOWER. a flower of both lineages with no stem, as the
//! confluence bears and a polyp lets drift on the air (convergence_kit
//! `bloom`): a sac bead of both saps, a calyx of five pale frondlets
//! tipped with pearls holding warm living petals and stamens, open and
//! facing up. The polyp places and sizes it as it rises out of its crown
//! (game/structures/polyp.zig).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the mesh builder
const mg=lib.meshgen;
/// the convergence kit: its flower of both lineages
const kit=lib.convergenceKit;
/// makes a vector from three numbers
const v3=lib.engine.core.math.v3;
/// builds the flower at the origin, open and facing up
pub fn build(b:*mg.Builder)Allocator.Error!void{
  try kit.bloom(b,.{.heart=v3(0,0,0),.len=0.09,.petals=6,.seed=0x9B01});
}
