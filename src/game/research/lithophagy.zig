//! LITHOPHAGY: the parasites learn to feed on stone: lithophages, which
//! draw the mineral nodes all round them into a crystal and sap it away as
//! grit, and ganglia, which hand what they are fed on to whatever round
//! them wants it.
const lib = @import("../../lib.zig");
const prog = lib.progression;

pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .essence, .n = 2 },
    .{ .item = .grit, .n = 3 },
  },
  .units = 15,
  .unit_time = 6,
  .prereq = &.{ .hungering_tendrils },
  .branch = true,
};
