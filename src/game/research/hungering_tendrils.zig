//! HUNGERING TENDRILS: parasites drain twice as hard.
const lib=@import("../../lib.zig");
const prog=lib.progression;
const ecology=lib.ecology;
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=2},
    .{.item=.grit,.n=1},
  },
  .units=20,
  .unitTime=5,
};
pub fn apply(m:*ecology.Mods)void{m.drainMult=2;}
