//! CONVERGENCE THEORY: study of what grows where the lineages meet. The
//! confluence needs no research to take root; this only teaches what it gives.
const prog = @import("../progression.zig");
const species = @import("../../sim/species.zig");

pub const def:prog.Research = .{
  .name = "CONVERGENCE THEORY", .desc = "LEARN WHAT THE CONFLUENCE CONDENSES",
  .per_unit = &.{.{.item = .essence, .n = 2}, .{.item = .starlight, .n = 1}},
  .units = 15, .unit_time = 8,
  .needs = .convergence,
};

/// species whose yield shows in the HUD once this is known.
pub const reveals = [_]species.Id{.confluence};

pub fn completed(g:*prog.Progression) void { g.say("WHERE THE LINEAGES MEET, ESSENCE CONVERGES", .{}); }
