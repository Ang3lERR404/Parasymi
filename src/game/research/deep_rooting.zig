//! DEEP ROOTING: root-diggers, which work resource nodes so the wolf no
//! longer has to. The first gathering automation.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: five essence and three ley shards a unit, ten units of
/// five seconds, after ley sight; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=5},
    .{.item=.leyShard,.n=3},
  },
  .units=10,
  .unitTime=5,
  .prereq=&.{.leySight},
  .branch=true,
};
