//! LATTICE OF THOUGHT: a minor study along Arsthraxia. Every arsthraxia grows:
//! an offshoot out of its stems, another satellite sap round its core.
const lib=@import("../../lib.zig");
const prog=lib.progression;
const txt=lib.txt;
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
pub fn study(s:*prog.Study)void{prog.flourish(s);}
pub fn completed(g:*prog.Progression)void{g.say(txt.s.msg.arsthraxiaGrows,.{});}
