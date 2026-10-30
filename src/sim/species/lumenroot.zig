//! LUMENROOT: the first symbiote. Shares its mana with every non-parasitic
//! neighbour, and grows faster among kin. Its body is the symbiotic
//! lineage's (gfx/meshes/structure_kit.zig `plant`): a braided stem on a
//! mat of braided roots, a leaf rosette, a vine twining up it, its cyan
//! bloom opening out of a bead of resin sap.
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's greens and cyan bloom
const color=engine.core.color;
/// the lumenroot: the first symbiote, quick to grow, sharing most of its mana
pub const def:species.Species=.{
  .lineage=.symbiotic,.seed=.seedLumenroot,
  .matureTime=12,.manaCap=10,.leyDraw=0.6,.share=0.8,.drain=0,.yield=0.12,
  // plucked from its bloom, a bead of resin sap at the top of its stem
  .pluck=0.66,
  .genome=.{
    .stemH=0.75,.stemR=0.045,.segments=7,.curl=0,.wobble=0.1,
    .leaves=6,.leafLen=0.28,.leafW=0.1,.leafDroop=0.35,
    .petals=6,.bloomR=0.14,.thorns=0,.tendrils=0,.rosette=4,.vines=1,
    // its yield: three beads of resin sap clustered under its bloom
    .pods=3,.podR=0.026,.podAt=0.86,
    // the lineage's vine and leaf greens (gfx/meshes/palette.zig; its stem richer,
    // for the plant material mutes it), its own cyan bloom
    .stemCol=color.rgb(0.34,0.66,0.2),.leafCol=color.rgb(0.40,0.80,0.38),.bloomCol=color.rgb(0.55,0.95,1.0),
  },
};
