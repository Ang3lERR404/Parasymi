//! LIVING LOOMS: the symbiotes lend their weaving to the garden: loomferns,
//! which weave fibre by themselves, and gathering crowns, which root out to
//! every plant round them and gather what is ripe.
const prog = @import("../progression.zig");

pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .essence, .n = 3 },
    .{ .item = .fibre, .n = 2 },
  },
  .units = 15,
  .unit_time = 6,
  .prereq = &.{ .root_communion },
  .branch = true,
};
