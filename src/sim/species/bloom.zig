//! CELESTIAL BLOOM: the garden's power source. A floating symbiote that
//! yields nothing; it radiates. Mature, it holds a field of celestial
//! energy around it (`radiance`), and it links with every other bloom
//! within `link` tiles into one network: a growing bloom joined to a
//! network that holds a mature one radiates too, so uprooting the bloom
//! that joins them cuts off everything downstream. Plants that need
//! radiance (`needsRadiance`) halt and wither outside every field.
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's pearl colours
const color=engine.core.color;
/// the celestial bloom: a floating radiant symbiote, holding a field of
/// light 3.5 tiles round and linking with blooms within 10
pub const def:species.Species=.{
  .lineage=.symbiotic,.seed=.seedBloom,.floating=true,
  // no item, no output: it radiates instead (the sky feeds it, as it does
  // every floater; it never condenses essence)
  .matureTime=30,.manaCap=10,.leyDraw=0.5,.share=0,.drain=0,.yield=0,
  .radiance=3.5,.link=10,
  // the highest living thing in the garden, above the fallen starlight
  .hover=3.2,
  // it drifts and bobs; it does not bend from a root
  .sway=0.6,
  // pearl: plant.frag lays an iridescent film over it (it belongs to the sky)
  .genome=.{
    .form=.radiant,
    .stemH=0.12,.stemR=0.03,.segments=4,.curl=0.05,.wobble=0.1,
    .leaves=0,.leafLen=0.1,.leafW=0.05,.leafDroop=0,
    .petals=12,.bloomR=0.3,.thorns=0,.tendrils=5,.tendrilCurl=0.2,.tendrilWobble=0.2,
    // no stem to branch from: its petals float free of the core
    .shoots=.{0,0},
    .stemCol=color.rgb(0.72,0.76,0.86),.leafCol=color.rgb(0.85,0.88,0.95),.bloomCol=color.rgb(0.95,0.95,1.0),
  },
};
