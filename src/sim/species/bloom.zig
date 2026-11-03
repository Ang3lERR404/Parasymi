//! CELESTIAL BLOOM: a relay of the light grid, a small pole. A floating
//! radiant plant that yields nothing and makes no light: grown, it links
//! with every relay within `link` tiles, carries on up to `carry` of the
//! light that reaches it along them, and lights the field round it
//! (`radiance`) for what draws light (sim/light.zig). Uprooting the bloom
//! that joins two relays cuts off everything beyond it.
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's pearl colours
const color=engine.core.color;
/// the celestial bloom: a floating relay, carrying up to 4 glow, its field
/// 3.5 tiles round, linking with relays within 10
pub const def:species.Species=.{
  // decision: radiant, drawn as it always was, with the symbiotes' sap
  .lineage=.radiant,.look=.symbiotic,.seed=.seedBloom,.floating=true,
  // no item, no output: it carries light instead (the sky feeds it, as it
  // does every floater; it never condenses essence)
  .matureTime=30,.manaCap=10,.leyDraw=0.5,.share=0,.drain=0,.yield=0,
  .radiance=3.5,.link=10,.carry=4,.halo=true,
  // high in the sky over the garden, above the fallen starlight (a
  // solcyriphon hangs higher still, over it)
  .hover=4.7,
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
