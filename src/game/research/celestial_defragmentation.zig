//! CELESTIAL DEFRAGMENTATION: study of the diamond a halo leaves, the
//! lattice that gathered four blooms' light into one and fragments it into
//! a ring. Dormant until a diamond has formed; known, diamonds can be woven
//! and put down by hand.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
// decision: its cost is set here (the brief sets none): the lineages'
// condensed essence and the sky's light, as the diamond is made of
/// what it costs: convergence essence, starlight and a ley shard, twenty
/// units of ten seconds; locked until a diamond has formed
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.convergenceEssence,.n=2},
    .{.item=.starlight,.n=3},
    .{.item=.leyShard,.n=1},
  },
  .units=20,
  .unitTime=10,
  .needs=.diamond,
  .branch=true,
};
