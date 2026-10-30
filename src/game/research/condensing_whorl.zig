//! CONDENSING WHORL: a minor study along Arsthraxia. Every arsthraxia grows:
//! an offshoot out of its stems, another satellite sap round its core.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// every player-facing string, for what is said once it is learned
const txt=lib.txt;
/// what it costs: essence and starlight, twenty units of eight seconds,
/// after the sap satellites; a leaf, not a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=3},
    .{.item=.starlight,.n=2},
  },
  .units=20,
  .unitTime=8,
  .prereq=&.{.sapSatellites},
};
/// what it teaches the labs: every arsthraxia grows once more (an offshoot,
/// a satellite sap) and condenses a little faster unfed
pub fn study(s:*prog.Study)void{prog.flourish(s);}
/// once learned, the log tells that the arsthraxias have grown
pub fn completed(g:*prog.Progression)void{g.say(txt.s.msg.arsthraxiaGrows,.{});}
