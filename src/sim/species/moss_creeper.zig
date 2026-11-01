//! MOSS CREEPER: a breed the rain opens, of both lineages. It lies low,
//! a cushion of moss sending runners out over the ground, and where the
//! rain has soaked the soil round it, it turns that soil to moss, tile by
//! tile (game/moss.zig), so a grove may root where none could.
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's runners and moss
const color=engine.core.color;
/// the moss creeper: a convergent groundcover spreading moss onto soaked soil
pub const def:species.Species=.{
  .lineage=.convergent,.seed=.seedMossCreeper,.yields=.convergenceEssence,
  .matureTime=50,.manaCap=16,.leyDraw=0.1,.share=0,.drain=0,.yield=0.1,
  // it drinks a little of the ground's water as well as the ley
  .waterDraw=0.002,
  // decision: a tile of moss every half minute or so, within two tiles
  .creeps=30,.creepReach=2,
  // plucked from the beads in its cushion
  .pluck=0.05,
  // it lies on the ground: its leaves lift in the gusts, it never bends
  .sway=0.4,
  .genome=.{
    .form=.creeper,
    // stemH: how far its runners reach; stemR their radius
    .stemH=0.55,.stemR=0.007,.segments=4,.curl=0.1,.wobble=0.35,
    // leaves in each node's rosette, small and rounded
    .leaves=4,.leafLen=0.07,.leafW=0.04,.leafDroop=0.3,.leafFrom=0,
    // bloomR: how wide its cushion of moss heaps (each node's tuft under half)
    .petals=0,.bloomR=0.15,.thorns=0,
    // runners out from its heart
    .tendrils=6,
    .shoots=.{0,0},
    // its yield: three beads in its cushion
    .pods=3,.podR=0.018,
    // violet-tinged runners of both lineages, deep mossy green
    .stemCol=color.rgb(0.42,0.36,0.4),.leafCol=color.rgb(0.32,0.55,0.2),.bloomCol=color.rgb(0.8,0.85,0.5),
  },
};
