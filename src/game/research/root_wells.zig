//! ROOT WELLS: once the first rain has fallen, root wells may be woven:
//! baskets of both lineages that store the rain above the ground and pour
//! it back round them through the dry spells.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: convergence essence and ley crystals, twenty units of
/// ten seconds, after the unforming and the first rain; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.convergenceEssence,.n=2},
    .{.item=.leyCrystal,.n=1},
  },
  .units=20,.unitTime=10,
  .prereq=&.{.unforming},
  .needs=.firstRain,
  .branch=true,
};
