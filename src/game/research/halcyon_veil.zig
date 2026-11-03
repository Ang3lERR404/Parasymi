//! HALCYON VEIL: the first evening silk, steeped in a vesper under a night
//! beam, is woven into a veil the beam cannot burn through: germinators
//! weave the halcyra's seed, which keeps what it guards alive in overdrive.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// the species registry, naming the plants this study touches
const species=lib.species;
/// what it costs: evening silk and essence, fifteen units of six seconds,
/// after seed splicing, once the first evening silk has steeped; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.eveningSilk,.n=1},
    .{.item=.essence,.n=1},
  },
  .units=15,.unitTime=6,
  .prereq=&.{.seedSplicing},
  .needs=.eveningSilk,
  .branch=true,
};
/// the species it lets the gardener plant: the halcyra
pub const unlocks=[_]species.Id{.halcyra};
