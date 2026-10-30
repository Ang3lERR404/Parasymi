//! LEY SIGHT: the ley currents beneath the ground become visible.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: one starlight a unit, ten units of three seconds; the
/// first study, open from the start
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.starlight,.n=1}
  },
  .units=10,
  .unitTime=3,
};
