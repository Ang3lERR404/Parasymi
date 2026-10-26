//! ROOT COMMUNION: symbiotic links reach a second ring of neighbours.
const lib = @import("../../lib.zig");
const prog = lib.progression;
const ecology = lib.ecology;

pub const def:prog.Research = .{
  .per_unit = &.{
    .{.item = .essence, .n = 2},
    .{.item = .fibre, .n = 1}
  },
  .units = 20,
  .unit_time = 5,
};

pub fn apply(m:*ecology.Mods) void { m.link2 = true; }