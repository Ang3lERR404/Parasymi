//! LITHOPHAGY: the parasites learn to feed on stone: lithophages, which
//! draw the mineral nodes all round them into a crystal and sap it away as
//! grit, and ganglia, which hand what they are fed on to whatever round
//! them wants it.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: two essence and three grit a unit, fifteen units of six
/// seconds, after the hungering tendrils; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=2},
    .{.item=.grit,.n=3},
  },
  .units=15,
  .unitTime=6,
  .prereq=&.{.hungeringTendrils},
  .branch=true,
};
