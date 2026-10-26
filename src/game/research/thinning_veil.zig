//! THE THINNING VEIL: hybrids flourish, and the world itself begins to shift
//! (the first world event: sky and glow drift toward the celestial).
const lib = @import("../../lib.zig");
const prog = lib.progression;
const txt = lib.txt;
const ecology = lib.ecology;
const species = lib.species;

pub const def:prog.Research = .{
  .per_unit = &.{
    .{.item = .essence, .n = 5},
    .{.item = .starlight, .n = 2},
    .{.item = .ley_shard, .n = 2}
  },
  .units = 50,
  .unit_time = 12,
  .prereq = &.{.seed_splicing},
  .branch = true,
};

/// how far this knowledge pulls the veil (world event blend target).
pub const veil:f32 = 0.3;

pub fn apply(m:*ecology.Mods) void { m.yield_mult[@intFromEnum(species.Id.vesper)] = 3; }

pub fn completed(g:*prog.Progression) void { g.say(txt.s.msg.veil_thins, .{}); }