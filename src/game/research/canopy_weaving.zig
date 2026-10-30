//! CANOPY WEAVING: Hollowhearts, the first plants larger than a tile.
const lib=@import("../../lib.zig");
const prog=lib.progression;
const species=lib.species;
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.fibre,.n=2},
    .{.item=.grit,.n=1},
  },
  .units=25,
  .unitTime=6,
  .prereq=&.{.rootCommunion},
  .branch=true,
};
pub const unlocks=[_]species.Id{.hollowheart};
