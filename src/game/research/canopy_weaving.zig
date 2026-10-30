//! CANOPY WEAVING: Hollowhearts, the first plants larger than a tile.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// the species registry, naming the plants this study touches
const species=lib.species;
/// what it costs: essence, fibre and grit, twenty-five units of six
/// seconds, after root communion; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.fibre,.n=2},
    .{.item=.grit,.n=1},
  },
  .units=25,
  .unitTime=6,
  .prereq=&.{.rootCommunion},
  .branch=true,
};
/// the species it lets the gardener plant: the hollowheart
pub const unlocks=[_]species.Id{.hollowheart};
