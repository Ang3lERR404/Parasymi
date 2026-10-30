//! ARSTHRAXIA: study of the bloom that studies. Its thought quickens:
//! every arsthraxia condenses faster, fed or not, and vines climb its
//! stems. The minor studies along it each grow the arsthraxias (an
//! offshoot, another satellite sap).
const lib=@import("../../lib.zig");
const prog=lib.progression;
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=2},
    .{.item=.starlight,.n=1},
  },
  .units=15,
  .unitTime=6,
  .branch=true,
};
pub fn study(s:*prog.Study)void{
  s.unfed+=0.2;
  s.speed+=0.25;
  s.vines=true;
}
