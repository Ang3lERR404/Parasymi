//! SPORE CASTING: the parasites learn to send: sporecasters, which turn
//! what they are fed into spore carriers that drift, however far, to the
//! sporecaster they are paired with. The loop conduits cannot close.
const prog = @import("../progression.zig");

pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .essence, .n = 3 },
    .{ .item = .starlight, .n = 2 },
    .{ .item = .ley_shard, .n = 1 },
  },
  .units = 25,
  .unit_time = 8,
  .prereq = &.{ .lithophagy, .drift_spores },
  .branch = true,
};
