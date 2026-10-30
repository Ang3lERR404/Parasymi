//! BRAIDED ROOTS: conduits grown dense: braided conduits, four lanes bound
//! in one weave, each carrying its own kind of item, faster than a conduit.
const lib=@import("../../lib.zig");
const prog=lib.progression;
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.fibre,.n=3},
    .{.item=.grit,.n=1},
  },
  .units=20,
  .unitTime=6,
  .prereq=&.{.livingLooms},
  .branch=true,
};
