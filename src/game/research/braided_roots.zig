//! BRAIDED ROOTS: conduits grown dense: braided conduits, four lanes bound
//! in one weave, each carrying its own kind of item, faster than a conduit.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: essence, fibre and grit, twenty units of six seconds,
/// after the living looms; a branch
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
