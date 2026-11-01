//! STORM CALLING: once the first rain has fallen, storm spires may be
//! woven: kin of the weftstone that charge on ley crystals under the rain
//! and strike the cloud into storms.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: convergence essence and ley crystals, thirty units of
/// ten seconds, after the root wells and the first rain; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.convergenceEssence,.n=3},
    .{.item=.leyCrystal,.n=2},
  },
  .units=30,.unitTime=10,
  .prereq=&.{.rootWells},
  .needs=.firstRain,
  .branch=true,
};
