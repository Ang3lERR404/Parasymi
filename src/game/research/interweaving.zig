//! INTERWEAVING: what a weftstone and a driftbraid make between them,
//! grown side by side: monfris, 2x2 trees of both lineages that weave
//! everything of both lineages, fed by the Vultrixi tethered to them.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: essence, a ley crystal and convergence essence, thirty
/// units of eight seconds; opens once a weftstone has met a driftbraid
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.leyCrystal,.n=1},
    .{.item=.convergenceEssence,.n=2},
  },
  .units=30,
  .unitTime=8,
  .prereq=&.{.wovenStone,.braidedDrift},
  .needs=.weftAndDrift,
  .branch=true,
};
