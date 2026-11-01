//! MOSS CREEPING: once the first rain has fallen, germinators weave moss
//! creeper seeds, a breed of both lineages that turns soaked soil to moss.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// the species registry, naming the plants this study touches
const species=lib.species;
/// what it costs: convergence essence and grit, twenty units of eight
/// seconds, after the unforming and the first rain; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.convergenceEssence,.n=2},
    .{.item=.grit,.n=2},
  },
  .units=20,.unitTime=8,
  .prereq=&.{.unforming},
  .needs=.firstRain,
  .branch=true,
};
/// the species it lets the gardener plant: the moss creeper
pub const unlocks=[_]species.Id{.mossCreeper};
