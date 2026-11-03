//! TEMPERED LIGHT: once a night beam has first overdriven a plant, the
//! gardener learns to temper it: overdrive harms a plant half as hard, so
//! an unguarded one lives about three nights under the beam instead of a
//! night and a half. A buffer only; the halcyra is the cure.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// the living world's tick, whose overdrive harm it halves
const ecology=lib.ecology;
/// what it costs: starlight and essence, fifteen units of six seconds,
/// after ley sight, once a plant has been overdriven; a leaf
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.starlight,.n=1},
    .{.item=.essence,.n=1},
  },
  .units=15,.unitTime=6,
  .prereq=&.{.leySight},
  .needs=.overdrive,
};
/// overdrive harms half as hard
pub fn apply(md:*ecology.Mods)void{md.overdriveHarm*=0.5;}
