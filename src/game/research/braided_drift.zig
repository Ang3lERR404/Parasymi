//! BRAIDED DRIFT: what a braided conduit and a sporecaster make between
//! them, grown side by side: driftbraids, paired, sending what each is fed
//! to the other by spore and taking in what it sends back.
const prog = @import("../progression.zig");

pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .essence, .n = 3 },
    .{ .item = .ley_shard, .n = 1 },
    .{ .item = .convergence_essence, .n = 1 },
  },
  .units = 25,
  .unit_time = 8,
  .prereq = &.{ .spore_casting, .braided_roots },
  .needs = .braid_and_spore,
  .branch = true,
};
