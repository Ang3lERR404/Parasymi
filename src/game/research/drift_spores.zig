//! DRIFT SPORES: the first floaters, Driftwisps, which condense starlight.
const prog = @import("../progression.zig");
const species = @import("../../sim/species.zig");

pub const def:prog.Research = .{
  .name = "DRIFT SPORES",
  .desc = "WEAVE DRIFTWISPS: FLOATERS THAT CONDENSE STARLIGHT",
  .per_unit = &.{
    .{ .item = .starlight, .n = 2 },
    .{ .item = .essence, .n = 1 },
  },
  .units = 15,
  .unit_time = 4,
  .prereq = &.{ .ley_sight },
};

pub const unlocks = [_]species.Id{ .driftwisp };