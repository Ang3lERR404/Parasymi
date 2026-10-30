//! DEEP ROOTING: root-diggers, which work resource nodes so the wolf no
//! longer has to. The first gathering automation.
const lib=@import("../../lib.zig");
const prog=lib.progression;
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
