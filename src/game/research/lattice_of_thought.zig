//! LATTICE OF THOUGHT: a minor study along Arsthraxia. Every arsthraxia grows:
//! an offshoot out of its stems, another satellite sap round its core.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// every player-facing string, for what is said once it is learned
const txt=lib.txt;
/// what it costs: essence, starlight and a ley shard, twenty-five units of
/// ten seconds, after the condensing whorl; a leaf
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.starlight,.n=2},
    .{.item=.leyShard,.n=1},
  },
  .units=25,
  .unitTime=10,
  .prereq=&.{.condensingWhorl},
};
/// what it teaches the labs: every arsthraxia grows once more (an offshoot,
/// a satellite sap) and condenses a little faster unfed
pub fn study(s:*prog.Study)void{prog.flourish(s);}
/// once learned, the log tells that the arsthraxias have grown
pub fn completed(g:*prog.Progression)void{g.say(txt.s.msg.arsthraxiaGrows,.{});}
