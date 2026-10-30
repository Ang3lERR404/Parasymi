//! BRAIDED DRIFT: what a braided conduit and a sporecaster make between
//! them, grown side by side: driftbraids, paired, sending what each is fed
//! to the other by spore and taking in what it sends back.
const lib=@import("../../lib.zig");
const prog=lib.progression;
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.leyShard,.n=1},
    .{.item=.convergenceEssence,.n=1},
  },
  .units=25,
  .unitTime=8,
  .prereq=&.{.sporeCasting,.braidedRoots},
  .needs=.braidAndSpore,
  .branch=true,
};
