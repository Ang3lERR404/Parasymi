//! INTERWEAVING: what a weftstone and a driftbraid make between them,
//! grown side by side: monfris, 2x2 trees of both lineages that weave
//! the advanced tier, fed by the Vultrixi tethered to them.
const prog = @import("../progression.zig");

pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .essence, .n = 3 },
    .{ .item = .ley_crystal, .n = 1 },
    .{ .item = .convergence_essence, .n = 2 },
  },
  .units = 30,
  .unit_time = 8,
  .prereq = &.{ .woven_stone, .braided_drift },
  .needs = .weft_and_drift,
  .branch = true,
};
