//! ROOT COMMUNION: symbiotic links reach a second ring of neighbours.
const prog = @import("../progression.zig");
const ecology = @import("../../sim/ecology.zig");

pub const def:prog.Research = .{
  .name = "ROOT COMMUNION",
  .desc = "SYMBIOTIC LINKS REACH 2 TILES",
  .per_unit = &.{
    .{.item = .essence, .n = 2},
    .{.item = .fibre, .n = 1}
  },
  .units = 20,
  .unit_time = 5,
};

pub fn apply(m:*ecology.Mods) void { m.link2 = true; }