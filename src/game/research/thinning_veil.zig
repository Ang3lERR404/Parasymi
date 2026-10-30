//! THE THINNING VEIL: hybrids flourish, and the world itself begins to shift
//! (the first world event: sky and glow drift toward the celestial).
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// every player-facing string, for what is said once it is learned
const txt=lib.txt;
/// the living world's tick, whose modifiers this study changes
const ecology=lib.ecology;
/// the species registry, naming the plants this study touches
const species=lib.species;
/// what it costs: essence, starlight and ley shards, fifty units of twelve
/// seconds, after seed splicing; the largest study yet, a branch
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
/// how far this knowledge pulls the veil, the world event's blend target
/// (0..1, eased toward by `Progression.absorb`)
pub const veil:f32=0.3;
/// what it changes in the living world: vespers yield three times as much
pub fn apply(m:*ecology.Mods)void{m.yieldMult[@intFromEnum(species.Id.vesper)]=3;}
/// once learned, the log tells that the veil thins
pub fn completed(g:*prog.Progression)void{g.say(txt.s.msg.veilThins,.{});}
