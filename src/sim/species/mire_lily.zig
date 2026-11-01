//! MIRE LILY: the first breed the rain opens, of both lineages. It roots
//! only in ground the rain has soaked: there it drinks the ground's water
//! (never the ley) and turns it into convergence essence; where the ground
//! dries it halts and slowly withers. A water lily: its crown rooted under
//! the pooled rain, long stems rising to round notched pads lying on the
//! water, and one pale many-petalled bloom resting on it.
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's mire teal and pale lily
const color=engine.core.color;
/// the mire lily: a convergent water lily drinking soaked ground into convergence
/// essence, withering where the ground dries
pub const def:species.Species=.{
  .lineage=.convergent,.seed=.seedMireLily,.yields=.convergenceEssence,
  .matureTime=40,.manaCap=20,.leyDraw=0,.share=0,.drain=0,.yield=0.25,
  // decision: water, not the ley, is what it lives on (the gardener's
  // brief: soaked ground turned into essence)
  .waterDraw=0.006,.needsSoak=true,.onWater=true,
  // plucked from the beads floating by its bloom
  .pluck=0.03,
  // it floats: its pads drift and bob on the water (plant.vert), never bend
  .sway=0.7,
  .genome=.{
    .form=.lily,
    // stemH: how deep under the water its crown roots; stemR its stems'
    .stemH=0.45,.stemR=0.012,.segments=4,.curl=0.05,.wobble=0.08,
    // round notched pads lying on the water, leafLen across
    .leaves=6,.leafLen=0.17,.leafW=0.17,.leafDroop=0,.leafFrom=0,
    // one bloom of many pointed petals
    .petals=12,.bloomR=0.11,.thorns=0,.tendrils=0,
    .shoots=.{0,0},
    // its yield: three beads of convergence essence floating by the bloom
    .pods=3,.podR=0.022,
    // mire teal stems, rich green pads, a pale lilac-blue lily
    .stemCol=color.rgb(0.25,0.45,0.42),.leafCol=color.rgb(0.2,0.52,0.24),.bloomCol=color.rgb(0.78,0.82,1.0),
  },
};
