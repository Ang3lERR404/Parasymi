//! HALCYRA: the light grid's guard, named for halcyon: calm, sheltered. A
//! small radiant flower hooded by a see-through veil like a jellyfish's
//! bell, broad crystal petals at the veil's edge tilting into the beam and
//! scattering it off as sparkles. Put down beside a plant, it leans over
//! it, its thread of light wound round it, and guards that one alone; put
//! down with no plant beside it, the thread opens into a net over every
//! plant within 2 tiles. A plant it guards takes a night beam's overdrive
//! and never dies of it (sim/light.zig).
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's pale blue veil
const color=engine.core.color;
/// the halcyra: guards one plant beside it, or all within 2 tiles alone
pub const def:species.Species=.{
  .lineage=.radiant,.seed=.seedHalcyra,
  .matureTime=30,.manaCap=10,.leyDraw=0.4,.share=0,.drain=0,.yield=0,
  .guards=2,
  // it leans over what it guards on light; it does not bend from a root
  .sway=0.5,
  .genome=.{
    .form=.veil,
    // stemH: how high its veil hangs over its tile
    .stemH=0.5,.stemR=0.02,.segments=5,.curl=0.1,.wobble=0.1,
    .leaves=0,.leafLen=0.1,.leafW=0.05,.leafDroop=0,
    // five flower petals under the veil, nine crystal petals at its edge
    .petals=5,.bloomR=0.16,.thorns=9,.tendrils=1,
    .shoots=.{0,0},
    .stemCol=color.rgb(0.7,0.82,0.95),.leafCol=color.rgb(0.82,0.92,1.0),.bloomCol=color.rgb(0.92,0.96,1.0),
  },
};
