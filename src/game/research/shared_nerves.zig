//! SHARED NERVES: what a gathering crown and a ganglion make between them,
//! grown side by side: Vultrixi, floaters tethered to a monfris that
//! reach into the structures round them and pull out what it needs.
const prog = @import("../progression.zig");

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
