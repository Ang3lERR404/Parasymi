//! ASTROCYME: the light grid's store, named for a cyme, a flower cluster
//! that blooms in order. A spiral bouquet of radiant flowers winding up a
//! thread of light over its tile, each flower one share of what it holds:
//! empty, every flower's petals drift loose round it; filling, one flower
//! at a time, from the bottom up, gathers its petals and opens. It takes
//! in whatever light its relays have to spare and gives it back whenever
//! the users round it go short, day or night (sim/light.zig).
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's violet and gold
const color=engine.core.color;
/// the astrocyme: holds 720 glow-seconds in six flowers, taking or giving
/// up to 4 glow, its own field 3 tiles round; links within 10
pub const def:species.Species=.{
  .lineage=.radiant,.seed=.seedAstrocyme,
  .matureTime=45,.manaCap=10,.leyDraw=0.4,.share=0,.drain=0,.yield=0,
  .radiance=3,.link=10,.carry=4,.store=720,
  // its flowers hang on light over its tile; it does not bend from a root
  .sway=0.5,
  .genome=.{
    .form=.bouquet,
    // stemH: how high its spiral winds over its tile
    .stemH=1.1,.stemR=0.02,.segments=6,.curl=0.3,.wobble=0.1,
    .leaves=0,.leafLen=0.1,.leafW=0.05,.leafDroop=0,
    // six flowers of seven petals
    .petals=6,.bloomR=0.11,.thorns=7,.tendrils=0,
    .shoots=.{0,0},
    .stemCol=color.rgb(0.62,0.5,0.9),.leafCol=color.rgb(0.8,0.72,0.98),.bloomCol=color.rgb(1.0,0.84,0.62),
  },
};
