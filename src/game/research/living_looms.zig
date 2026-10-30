//! LIVING LOOMS: the symbiotes lend their weaving to the garden: loomferns,
//! which weave fibre by themselves, and gathering crowns, which root out to
//! every plant round them and gather what is ripe.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: three essence and two fibre a unit, fifteen units of six
/// seconds, after root communion; a branch
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
