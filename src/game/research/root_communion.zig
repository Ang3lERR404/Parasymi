//! ROOT COMMUNION: symbiotic links reach a second ring of neighbours.
const lib=@import("../../lib.zig");
const prog=lib.progression;
const ecology=lib.ecology;
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=2},
    .{.item=.fibre,.n=1}
  },
  .units=20,
  .unitTime=5,
};
pub fn apply(m:*ecology.Mods)void{m.link2=true;}
