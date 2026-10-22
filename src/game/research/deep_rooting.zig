//! DEEP ROOTING: root-diggers, which work resource nodes so the wolf no
//! longer has to. The first gathering automation.
const prog = @import("../progression.zig");

pub const def:prog.Research = .{
  .name = "DEEP ROOTING", .desc = "WEAVE ROOT-DIGGERS: THEY GATHER FROM A NODE BESIDE THEM",
  .per_unit = &.{.{.item = .essence, .n = 5}, .{.item = .ley_shard, .n = 3}}, .units = 10, .unit_time = 5,
  .prereq = &.{.ley_sight},
};
