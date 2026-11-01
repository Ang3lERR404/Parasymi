//! MIRE LILY: the first breed the rain opens, of both lineages. It roots
//! only in ground the rain has soaked: there it drinks the ground's water
//! (never the ley) and turns it into convergence essence; where the ground
//! dries it halts and slowly withers. Low broad pads round its foot, a
//! short stem lifting one pale cupped lily.
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's mire teal and pale lily
const color=engine.core.color;
/// the mire lily: a convergent herb drinking soaked ground into convergence
/// essence, withering where the ground dries
pub const def:species.Species=.{
  .lineage=.convergent,.seed=.seedMireLily,.yields=.convergenceEssence,
  .matureTime=40,.manaCap=20,.leyDraw=0,.share=0,.drain=0,.yield=0.25,
  // decision: water, not the ley, is what it lives on (the gardener's
  // brief: soaked ground turned into essence)
  .waterDraw=0.006,.needsSoak=true,
  // plucked from just under its bloom
  .pluck=0.3,
  // low and heavy with water, it sways a little less than a herb
  .sway=0.7,
  .genome=.{
    .form=.herb,
    .stemH=0.32,.stemR=0.025,.segments=4,.curl=0.05,.wobble=0.08,
    // broad flat pads lying round its foot
    .leaves=5,.leafLen=0.3,.leafW=0.2,.leafDroop=0,.leafFrom=0,
    // one cupped lily of six petals
    .petals=6,.bloomR=0.13,.thorns=0,.tendrils=0,
    .shoots=.{0,1},
    // its yield: three beads of convergence essence under the bloom
    .pods=3,.podR=0.028,.podAt=0.85,
    // mire teal stem, deep wet green pads, a pale lilac-blue lily
    .stemCol=color.rgb(0.25,0.45,0.42),.leafCol=color.rgb(0.2,0.42,0.3),.bloomCol=color.rgb(0.78,0.82,1.0),
  },
};
