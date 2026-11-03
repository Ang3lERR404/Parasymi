//! SOLCYRIPHON: the light grid's maker, and the only thing that makes
//! light. A radiant flower hung high: a lens of facets round a glowing
//! heart, petals rising round it open to the sky, threads of light trailing
//! beneath like a jellyfish's. It drinks starlight straight from the sky,
//! and the sun is a star too: by day it spreads its light round itself, by
//! night it folds up, its threads drawn in, and pours all of it down in one
//! beam onto whatever hangs or stands right under it (sim/light.zig).
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's pearl and gold
const color=engine.core.color;
/// the solcyriphon: hung high over its tile, 6 glow spread over 3 tiles by
/// day, a 12 glow beam by night; links with relays within 10 tiles
pub const def:species.Species=.{
  .lineage=.radiant,.seed=.seedSolcyriphon,.floating=true,
  // it makes light, not essence: the sky feeds it as it does every floater
  .matureTime=40,.manaCap=10,.leyDraw=0.5,.share=0,.drain=0,.yield=0,
  .radiance=3,.link=10,.glow=.{6,12},.carry=12,
  // high over everything, so a bloom or a plant may hang or stand under it
  .hover=5.5,
  // it drifts and bobs; it does not bend from a root
  .sway=0.4,
  .genome=.{
    .form=.lens,
    .stemH=0.1,.stemR=0.03,.segments=4,.curl=0.05,.wobble=0.1,
    .leaves=0,.leafLen=0.1,.leafW=0.05,.leafDroop=0,
    // a lens of 10 facets, 7 petals rising round it, 9 threads beneath
    .petals=7,.bloomR=0.34,.thorns=10,.tendrils=9,.tendrilCurl=0.15,.tendrilWobble=0.2,
    .shoots=.{0,0},
    // pearl petals, a gold heart's light
    .stemCol=color.rgb(0.78,0.74,0.92),.leafCol=color.rgb(0.86,0.84,0.98),.bloomCol=color.rgb(1.0,0.86,0.52),
  },
};
