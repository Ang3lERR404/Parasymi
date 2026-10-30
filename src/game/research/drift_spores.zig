//! DRIFT SPORES: the first floaters, Driftwisps, which condense starlight.
const lib=@import("../../lib.zig");
const prog=lib.progression;
const species=lib.species;
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.starlight,.n=2},
    .{.item=.essence,.n=1},
  },
  .units=15,
  .unitTime=4,
  .prereq=&.{.leySight},
  .branch=true,
};
pub const unlocks=[_]species.Id{.driftwisp};
