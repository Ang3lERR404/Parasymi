//! HELIOCYRA: the light grid's shaper, named helio (the sun) + Halcyra. A
//! heliotrope's flower head on a neck of light, a cut crystal at its heart,
//! turned (R) the way it casts its light as a sunflower follows the sun.
//! Fields are round; rows want lines: standing in a field it takes up to 3
//! glow and casts it on as a strip, a tile wide and 8 long; struck by
//! another's strip it bends it round a corner; under a solcyriphon at night
//! it turns the falling beam sideways into a strip (sim/light.zig).
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's amber and crystal
const color=engine.core.color;
/// the heliocyra: casts a strip 8 tiles long, carrying up to a whole beam
pub const def:species.Species=.{
  .lineage=.radiant,.seed=.seedHeliocyra,
  .matureTime=30,.manaCap=10,.leyDraw=0.4,.share=0,.drain=0,.yield=0,
  .strip=8,.carry=12,
  // its head turns on its neck of light; it does not bend from a root
  .sway=0.4,
  .genome=.{
    .form=.heliotrope,
    // stemH: how high its head hangs over its tile
    .stemH=0.7,.stemR=0.02,.segments=5,.curl=0.1,.wobble=0.1,
    .leaves=0,.leafLen=0.1,.leafW=0.05,.leafDroop=0,
    // a head of 14 ray petals round its crystal
    .petals=14,.bloomR=0.2,.thorns=0,.tendrils=0,
    .shoots=.{0,0},
    .stemCol=color.rgb(0.95,0.72,0.4),.leafCol=color.rgb(0.98,0.84,0.6),.bloomCol=color.rgb(1.0,0.78,0.42),
  },
};
