//! THORNLEECH: the first parasite, alien rather than hostile (a coil, built
//! by gfx/meshes/parasite_kit.zig: a lattice cage of a stalk with its sacs
//! hanging inside, a crown of five fronds each ending in a small cage of
//! its own). Drains every non-parasitic neighbour and the ley beneath it;
//! yields more, at their expense.
const lib=@import("../../lib.zig");
const species=lib.species;
const engine=lib.engine;
const color=engine.core.color;
pub const def:species.Species=.{
  .lineage=.parasitic,.seed=.seedThornleech,
  .matureTime=8,.manaCap=14,.leyDraw=1.0,.share=0,.drain=1.2,.yield=0.22,
  .genome=.{
    .form=.coil,
    // a coil: its stalk's height and girth, the sacs in its cage (`thorns`)
    // and the fronds of its crown (`tendrils`), its skin, fronds and sap
    // (it grows no leaves, petals or offshoots, and stands dead upright)
    .stemH=0.6,.stemR=0.045,.segments=0,.curl=0,.wobble=0,
    .leaves=0,.leafLen=0,.leafW=0,.leafDroop=0,
    .petals=0,.bloomR=0.06,.thorns=3,.tendrils=5,.shoots=.{0,0},
    .stemCol=color.rgb(0.56,0.54,0.62),.leafCol=color.rgb(0.68,0.62,0.82),.bloomCol=color.rgb(0.46,0.62,0.86),
  },
};
