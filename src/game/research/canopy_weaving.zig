//! CANOPY WEAVING: Hollowhearts, the first plants larger than a tile.
const prog = @import("../progression.zig");
const species = @import("../../sim/species.zig");

pub const def:prog.Research = .{
  .name = "CANOPY WEAVING", .desc = "WEAVE HOLLOWHEARTS: 2X2 MANA RESERVOIR TREES",
  .per_unit = &.{.{.item = .essence, .n = 3}, .{.item = .fibre, .n = 2}, .{.item = .grit, .n = 1}}, .units = 25, .unit_time = 6,
  .prereq = &.{.root_communion},
};

pub const unlocks = [_]species.Id{.hollowheart};
