//! HUNGERING TENDRILS: parasites drain twice as hard.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// the living world's tick, whose modifiers this study changes
const ecology=lib.ecology;
/// what it costs: two essence and a grit a unit, twenty units of five
/// seconds; open from the start
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=2},
    .{.item=.grit,.n=1},
  },
  .units=20,
  .unitTime=5,
};
/// what it changes in the living world: parasites drain at twice the rate
pub fn apply(m:*ecology.Mods)void{m.drainMult=2;}
