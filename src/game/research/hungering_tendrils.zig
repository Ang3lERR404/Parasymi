//! HUNGERING TENDRILS: parasites drain twice as hard.
const prog = @import("../progression.zig");
const ecology = @import("../../sim/ecology.zig");

pub const def:prog.Research = .{
  .name = "HUNGERING TENDRILS", .desc = "PARASITES DRAIN X2",
  .per_unit = &.{.{.item = .essence, .n = 2}, .{.item = .grit, .n = 1}}, .units = 20, .unit_time = 5,
};

pub fn apply(m:*ecology.Mods) void { m.drain_mult = 2; }
