//! HOLLOWHEART: a 2x2 heart-tree. A deep mana reservoir that feeds
//! everything around its footprint.
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's bark, leaves and bloom
const color=engine.core.color;
/// the hollowheart: a slow 2x2 symbiote tree holding deep mana and sharing it richly
pub const def:species.Species=.{
  .lineage=.symbiotic,.seed=.seedHollowheart,.size=2,
  .matureTime=45,.manaCap=60,.leyDraw=2.4,.share=0.9,.drain=0,.yield=0.5,
  // plucked from under its canopy, as high as the wolf reaches up
  .pluck=1.4,
  // a heavy tree: it leans, it does not wave
  .sway=0.6,
  .genome=.{
    .stemH=2.1,.stemR=0.16,.segments=12,.curl=0.06,.wobble=0.08,
    .leaves=20,.leafLen=0.75,.leafW=0.24,.leafDroop=0.45,.leafFrom=0.55,
    .petals=7,.bloomR=0.4,.thorns=0,.tendrils=6,.shoots=.{2,5},.vines=2,
    .stemCol=color.rgb(0.3,0.24,0.18),.leafCol=color.rgb(0.25,0.65,0.4),.bloomCol=color.rgb(1.0,0.8,0.5),
  },
};
