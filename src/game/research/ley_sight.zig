//! LEY SIGHT: the ley currents beneath the ground become visible.
const lib=@import("../../lib.zig");
const prog=lib.progression;
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.starlight,.n=1}
  },
  .units=10,
  .unitTime=3,
};
