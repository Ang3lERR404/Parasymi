//! SEED SPLICING: germinators weave Vesper seeds, spliced from both lineages.
//! Needs both lineages studied, and their convergence witnessed.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// the species registry, naming the plants this study touches
const species=lib.species;
/// what it costs: essence, starlight and a ley shard, thirty units of
/// eight seconds, after both lineages and their convergence; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.starlight,.n=1},
    .{.item=.leyShard,.n=1}
  },
  .units=30,.unitTime=8,
  .prereq=&.{
    .rootCommunion,
    .hungeringTendrils
  },
  .needs=.convergence,
  .branch=true,
};
/// the species it lets the gardener plant: the vesper
pub const unlocks=[_]species.Id{.vesper};
