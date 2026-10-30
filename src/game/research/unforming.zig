//! THE UNFORMING: the study that ends the garden as it was. Dormant until
//! a polyp has let a flower of both lineages drift; learned, the radiant
//! plants shatter and blink out of reality, the symbiotic and parasitic
//! lineages die, the arsthraxia evolves, and a seed falls from the sky
//! (game/unforming.zig: the first world event).
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// every player-facing string
const txt=lib.txt;
// decision: its cost is set here (the brief sets none): both lineages'
// condensed essence, the sky's light and a weftstone's ley crystal
/// what it costs: convergence essence, starlight and a ley crystal, thirty
/// units of ten seconds; locked until a polyp has let a flower drift, and
/// the diamond's lattice is understood
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.convergenceEssence,.n=3},
    .{.item=.starlight,.n=3},
    .{.item=.leyCrystal,.n=1},
  },
  .units=30,
  .unitTime=10,
  .prereq=&.{.celestialDefragmentation},
  .needs=.driftFlower,
  .branch=true,
};
/// once learned, the log tells that it is near (the event runs from game/unforming.zig)
pub fn completed(g:*prog.Progression)void{g.say(txt.s.msg.unformingNear,.{});}
