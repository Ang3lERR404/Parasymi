//! VESPER BLOOM: the first convergent hybrid, spliced where symbiote and
//! parasite touch. Shares with symbiotes and drains parasites. The evening
//! star's flower, of the radiant lineage's body (radiant_kit `star`): it
//! is gathered, never grown, falling in from the sky piece by piece, and
//! it needs celestial energy: outside a bloom's field it withers, its
//! pieces loosening and sinking as its light dims.
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's dusk violet and evening gold
const color=engine.core.color;
/// the vesper bloom: a convergent star of lumenroot and thornleech that
/// shares and drains, and withers outside a bloom's field
pub const def:species.Species=.{
  .lineage=.convergent,.seed=.seedVesper,
  .matureTime=16,.manaCap=24,.leyDraw=0.8,.share=0.6,.drain=0.8,.yield=0.4,
  // decision: the first plant that needs radiance (the brief names none)
  .needsRadiance=true,
  // it hangs over its tile on light; it does not bend from a root
  .sway=0.5,
  .genome=.{
    .form=.star,
    // stemH: how high its core hangs over its tile (it has no stem)
    .stemH=0.62,.stemR=0.03,.segments=4,.curl=0.05,.wobble=0.1,
    // its leaves float free beneath it, one of each lineage's in turn
    .leaves=5,.leafLen=0.28,.leafW=0.07,.leafDroop=0.5,
    // a five-rayed star
    .petals=5,.bloomR=0.17,.thorns=0,.tendrils=0,
    .shoots=.{0,0},
    // dusk: a deep violet body, dusky leaves, a pale gold evening light
    .stemCol=color.rgb(0.42,0.3,0.78),.leafCol=color.rgb(0.36,0.5,0.62),.bloomCol=color.rgb(1.0,0.86,0.6),
  },
  .parents=.{.lumenroot,.thornleech},
};
