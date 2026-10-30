//! ARSTHRAXIA: study of the bloom that studies. Its thought quickens:
//! every arsthraxia condenses faster, fed or not, and vines climb its
//! stems. The minor studies along it each grow the arsthraxias (an
//! offshoot, another satellite sap).
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// what it costs: two essence and a starlight a unit, fifteen units of six
/// seconds; a branch of the sapling, open from the start
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=2},
    .{.item=.starlight,.n=1},
  },
  .units=15,
  .unitTime=6,
  .branch=true,
};
/// what it teaches the labs: a fifth more unfed pace, a quarter more speed
/// fed or not, and vines climbing every arsthraxia
pub fn study(s:*prog.Study)void{
  s.unfed+=0.2;
  s.speed+=0.25;
  s.vines=true;
}
