//! HELD LIGHT: light bent through starglass and veiled in evening silk can
//! be held: germinators weave the astrocyme's seed, a spiral bouquet that
//! stores light to spare and gives it back when its users go short.
const lib=@import("../../lib.zig");
/// the research tree: what a study costs and what it teaches
const prog=lib.progression;
/// the species registry, naming the plants this study touches
const species=lib.species;
/// what it costs: starlight and essence, twenty units of eight seconds,
/// after bent light and the halcyon veil; a branch
pub const def:prog.Research=.{
  .perUnit=&.{
    .{.item=.starlight,.n=2},
    .{.item=.essence,.n=1},
  },
  .units=20,.unitTime=8,
  .prereq=&.{
    .bentLight,
    .halcyonVeil,
  },
  .branch=true,
};
/// the species it lets the gardener plant: the astrocyme
pub const unlocks=[_]species.Id{.astrocyme};
