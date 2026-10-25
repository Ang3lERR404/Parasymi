//! SHARED NERVES: what a gathering crown and a ganglion make between them,
//! grown side by side: germinators weave nervecrown seeds, a hub of both
//! lineages that shares its mana far and calms the parasites round it.
const prog = @import("../progression.zig");
const species = @import("../../sim/species.zig");

pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .essence, .n = 3 },
    .{ .item = .fibre, .n = 2 },
    .{ .item = .convergence_essence, .n = 1 },
  },
  .units = 20,
  .unit_time = 8,
  .prereq = &.{ .living_looms, .lithophagy },
  .needs = .crown_and_nerve,
  .branch = true,
};

pub const unlocks = [_]species.Id{.nervecrown};
