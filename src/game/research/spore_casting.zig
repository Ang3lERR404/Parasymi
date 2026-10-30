//! SPORE CASTING: the parasites learn to send: sporecasters, which turn
//! what they are fed into spore carriers that drift, however far, to the
//! sporecaster they are paired with. The loop conduits cannot close.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: essence, starlight and a ley shard, twenty-five units of
/// eight seconds, after lithophagy and the drift spores; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.starlight,.n=2},
    .{.item=.leyShard,.n=1},
  },
  .units=25,
  .unitTime=8,
  .prereq=&.{.lithophagy,.driftSpores},
  .branch=true,
};
