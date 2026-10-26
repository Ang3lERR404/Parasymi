//! DRIFT SPORES: the first floaters, Driftwisps, which condense starlight.
const lib = @import("../../lib.zig");
const prog = lib.progression;
const species = lib.species;

pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .starlight, .n = 2 },
    .{ .item = .essence, .n = 1 },
  },
  .units = 15,
  .unit_time = 4,
  .prereq = &.{ .ley_sight },
  .branch = true,
};

pub const unlocks = [_]species.Id{ .driftwisp };