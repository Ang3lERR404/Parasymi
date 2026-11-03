//! CONVERGENCE THEORY: study of what grows where the lineages meet. The
//! confluence needs no research to take root; this only teaches what it gives.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// every player-facing string, for what is said once it is learned
const txt=lib.txt;
/// the species registry, naming the plants this study touches
const species=lib.species;
/// what it costs: two essence and a starlight a unit, fifteen units of
/// eight seconds; locked until the lineages have been seen to converge
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.essence,.n=2},
    .{.item=.starlight,.n=1},
  },
  .units=15,
  .unitTime=8,
  .needs=.convergence,
  .lineage=.convergent,
};
/// the species whose yield shows in the HUD once this is known: the confluence
pub const reveals=[_]species.Id{.confluence};
/// once learned, the log tells that essence converges
pub fn completed(g:*prog.Progression)void{
  g.say(txt.s.msg.essenceConverges,.{});
}
