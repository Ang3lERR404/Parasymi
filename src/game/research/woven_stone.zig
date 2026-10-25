//! WOVEN STONE: what a loomfern and a lithophage make between them, grown
//! side by side: germinators weave weftstone seeds, a fern of both
//! lineages that weaves grit out of the ley.
const prog = @import("../progression.zig");
const species = @import("../../sim/species.zig");

pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .essence, .n = 3 },
    .{ .item = .grit, .n = 2 },
    .{ .item = .convergence_essence, .n = 1 },
  },
  .units = 20,
  .unit_time = 8,
  .prereq = &.{ .lithophagy, .living_looms },
  .needs = .loom_and_stone,
  .branch = true,
};

pub const unlocks = [_]species.Id{.weftstone};
