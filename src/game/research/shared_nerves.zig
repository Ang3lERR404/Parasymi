//! SHARED NERVES: what a gathering crown and a ganglion make between them,
//! grown side by side: Vultrixi, floaters tethered to a monfris that
//! reach into the structures round them and pull out what it needs.
const lib=@import("../../lib.zig");
const prog=lib.progression;
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
