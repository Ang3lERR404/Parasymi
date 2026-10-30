//! SHARED NERVES: what a gathering crown and a ganglion make between them,
//! grown side by side: Vultrixi, floaters tethered to a monfris that
//! reach into the structures round them and pull out what it needs.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: essence, fibre and convergence essence, twenty units of
/// eight seconds; opens once a crown has met a ganglion
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.fibre,.n=2},
    .{.item=.convergenceEssence,.n=1},
  },
  .units=20,
  .unitTime=8,
  .prereq=&.{.livingLooms,.lithophagy},
  .needs=.crownAndNerve,
  .branch=true,
};
