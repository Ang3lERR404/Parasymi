//! DRIFT SPORES: the first floaters, Driftwisps, which condense starlight.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// the species registry, naming the plants this study touches
const species=lib.species;
/// what it costs: starlight and essence, fifteen units of four seconds,
/// after ley sight; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.starlight,.n=2},
    .{.item=.essence,.n=1},
  },
  .units=15,
  .unitTime=4,
  .prereq=&.{.leySight},
  .branch=true,
};
/// the species it lets the gardener plant: the driftwisp
pub const unlocks=[_]species.Id{.driftwisp};
