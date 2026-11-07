//! THORNLEECH: the first parasite, alien rather than hostile (a coil, built
//! by gfx/meshes/parasite_kit.zig: a lattice cage of a stalk with its sacs
//! hanging inside, a crown of five fronds each ending in a small cage of
//! its own). Drains every non-parasitic neighbour and the ley beneath it;
//! yields more, at their expense.
//! An older draft: the agreed design drinks its living neighbours' sap
//! through veins it lays on the ground, taking what they have too much of,
//! and grows as a leech, roots first (docs/todo.md, "The Hirusidandrath
//! grows as a leech").
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's grey skin, lilac fronds and blue sap
const color=engine.core.color;
/// the thornleech: the first parasite, quickest to mature, draining its neighbours
pub const def:species.Species=.{
  .lineage=.parasitic,.seed=.seedThornleech,
  .matureTime=8,.manaCap=14,.leyDraw=1.0,.share=0,.drain=1.2,.yield=0.22,
  // plucked from the sacs hanging in its cage
  .pluck=0.36,
  .genome=.{
    .form=.coil,
    // a coil: its stalk's height and girth, the sacs in its cage (`thorns`)
    // and the fronds of its crown (`tendrils`), its skin, fronds and sap
    // (it grows no leaves, petals or offshoots, and stands dead upright)
    .stemH=0.6,.stemR=0.045,.segments=0,.curl=0,.wobble=0,
    .leaves=0,.leafLen=0,.leafW=0,.leafDroop=0,
    .petals=0,.bloomR=0.06,.thorns=3,.tendrils=5,.shoots=.{0,0},
    // its yield ripens in the sacs in its cage, one a sac
    .pods=3,
    .stemCol=color.rgb(0.56,0.54,0.62),.leafCol=color.rgb(0.68,0.62,0.82),.bloomCol=color.rgb(0.46,0.62,0.86),
  },
};
