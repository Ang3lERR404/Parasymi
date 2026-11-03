//! BENT LIGHT: the first starglass, steeped in a driftwisp under a night
//! beam, shows how light bends through crystal: germinators weave the
//! heliocyra's seed, which casts light in strips and bends them on.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// the species registry, naming the plants this study touches
const species=lib.species;
/// what it costs: starlight and a ley shard, fifteen units of six seconds,
/// after drift spores, once the first starglass has steeped; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.starlight,.n=2},
    .{.item=.leyShard,.n=1},
  },
  .units=15,.unitTime=6,
  .prereq=&.{.driftSpores},
  .needs=.starglass,
  .branch=true,
};
/// the species it lets the gardener plant: the heliocyra
pub const unlocks=[_]species.Id{.heliocyra};
