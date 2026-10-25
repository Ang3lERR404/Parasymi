//! WOVEN STONE: what a loomfern and a lithophage make between them, grown
//! side by side: weftstones, floating over the nodes, drawing them up and
//! ionizing what they draw into ley crystals.
const prog = @import("../progression.zig");

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
