//! INTERWEAVING: what a weftstone and a driftbraid make between them,
//! grown side by side: monfris, 2x2 trees of both lineages that weave
//! the advanced tier, fed by the Vultrixi tethered to them.
const lib=@import("../../lib.zig");
const prog=lib.progression;
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
