//! SEED SPLICING: germinators weave Vesper seeds, spliced from both lineages.
//! Needs both lineages studied, and their convergence witnessed.
const prog = @import("../progression.zig");
const species = @import("../../sim/species.zig");

pub const def:prog.Research = .{
  .per_unit = &.{
    .{.item = .essence, .n = 3},
    .{.item = .starlight, .n = 1},
    .{.item = .ley_shard, .n = 1}
  },
  .units = 30, .unit_time = 8,
  .prereq = &.{
    .root_communion,
    .hungering_tendrils
  },
  .needs = .convergence,
  .branch = true,
};

pub const unlocks = [_]species.Id{.vesper};