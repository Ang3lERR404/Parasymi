//! WOVEN STONE: what a loomfern and a lithophage make between them, grown
//! side by side: weftstones, floating over the nodes, drawing them up and
//! ionizing what they draw into ley crystals.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: essence, grit and convergence essence, twenty units of
/// eight seconds; opens once a loomfern has met a lithophage
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.grit,.n=2},
    .{.item=.convergenceEssence,.n=1},
  },
  .units=20,
  .unitTime=8,
  .prereq=&.{.lithophagy,.livingLooms},
  .needs=.loomAndStone,
  .branch=true,
};
