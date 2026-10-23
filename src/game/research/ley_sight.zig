//! LEY SIGHT: the ley currents beneath the ground become visible.
const prog = @import("../progression.zig");

pub const def:prog.Research = .{
  .per_unit = &.{
    .{.item = .starlight, .n = 1}
  },
  .units = 10,
  .unit_time = 3,
};