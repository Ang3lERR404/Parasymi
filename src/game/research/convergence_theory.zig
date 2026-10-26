//! CONVERGENCE THEORY: study of what grows where the lineages meet. The
//! confluence needs no research to take root; this only teaches what it gives.
const lib = @import("../../lib.zig");
const prog = lib.progression;
const txt = lib.txt;
const species = lib.species;

pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .essence, .n = 2 },
    .{ .item = .starlight, .n = 1 },
  },
  .units = 15,
  .unit_time = 8,
  .needs = .convergence,
};

/// species whose yield shows in the HUD once this is known.
pub const reveals = [_]species.Id{ .confluence };

pub fn completed(g:*prog.Progression) void {
  g.say(txt.s.msg.essence_converges, .{});
}