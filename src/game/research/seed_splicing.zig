//! SEED SPLICING: germinators weave Vesper seeds, spliced from both lineages.
//! Needs both lineages studied, and their convergence witnessed.
const lib=@import("../../lib.zig");
const prog=lib.progression;
const species=lib.species;
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
pub const unlocks=[_]species.Id{.vesper};
