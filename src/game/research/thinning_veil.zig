//! THE THINNING VEIL: hybrids flourish, and the world itself begins to shift
//! (the first world event: sky and glow drift toward the celestial).
const lib=@import("../../lib.zig");
const prog=lib.progression;
const txt=lib.txt;
const ecology=lib.ecology;
const species=lib.species;
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=5},
    .{.item=.starlight,.n=2},
    .{.item=.leyShard,.n=2}
  },
  .units=50,
  .unitTime=12,
  .prereq=&.{.seedSplicing},
  .branch=true,
};
/// how far this knowledge pulls the veil (world event blend target).
pub const veil:f32=0.3;
pub fn apply(m:*ecology.Mods)void{m.yieldMult[@intFromEnum(species.Id.vesper)]=3;}
pub fn completed(g:*prog.Progression)void{g.say(txt.s.msg.veilThins,.{});}
