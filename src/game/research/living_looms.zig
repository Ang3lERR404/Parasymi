//! LIVING LOOMS: the symbiotes lend their weaving to the garden: loomferns,
//! which weave fibre by themselves, and gathering crowns, which root out to
//! every plant round them and gather what is ripe.
const lib=@import("../../lib.zig");
const prog=lib.progression;
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.fibre,.n=2},
  },
  .units=15,
  .unitTime=6,
  .prereq=&.{.rootCommunion},
  .branch=true,
};
