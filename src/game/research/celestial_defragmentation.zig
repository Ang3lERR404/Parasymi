//! CELESTIAL DEFRAGMENTATION: study of the diamond a halo leaves, the
//! lattice that gathered four blooms' light into one and fragments it into
//! a ring. Dormant until a diamond has formed; known, diamonds can be woven
//! and put down by hand.
const prog = @import("../progression.zig");

// decision: its cost is set here (the brief sets none): the lineages'
// condensed essence and the sky's light, as the diamond is made of
pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .convergence_essence, .n = 2 },
    .{ .item = .starlight, .n = 3 },
    .{ .item = .ley_shard, .n = 1 },
  },
  .units = 20,
  .unit_time = 10,
  .needs = .diamond,
  .branch = true,
};
