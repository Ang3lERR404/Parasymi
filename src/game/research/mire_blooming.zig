//! MIRE BLOOMING: once the first rain has fallen, germinators weave mire
//! lily seeds, a breed of both lineages that roots in soaked ground.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// the species registry, naming the plants this study touches
const species=lib.species;
/// what it costs: convergence essence and a ley crystal, twenty units of
/// eight seconds, after the unforming and the first rain; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.convergenceEssence,.n=2},
    .{.item=.leyCrystal,.n=1},
  },
  .units=20,.unitTime=8,
  .prereq=&.{.unforming},
  .needs=.firstRain,
  .branch=true,
};
/// the species it lets the gardener plant: the mire lily
pub const unlocks=[_]species.Id{.mireLily};
