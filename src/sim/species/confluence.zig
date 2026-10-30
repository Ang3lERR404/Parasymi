//! CONFLUENCE: the convergence hybrid. Never sown: it takes root on its own
//! where a mature symbiote and a mature parasite meet (game/convergence.zig),
//! grows for half again as long as the slower parent, and once mature
//! contains the parasites around it rather than killing them. Condenses
//! convergence essence. Its body tells the meeting (gfx/meshes/
//! convergence_kit.zig `confluence`): a trunk of each lineage winding up
//! round the other and fusing into one weave of both, crowned by flowers.
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's trunks and flowers
const color=engine.core.color;
/// the confluence: a 2x2 convergent hybrid of lumenroot and thornleech,
/// never sown, containing parasites within 3 tiles once mature
pub const def:species.Species=.{
  .lineage=.convergent,.seed=null,.size=2,.yields=.convergenceEssence,
  // decision: matureTime is the fallback for a confluence without parents
  // (1.5x the slower first pair); a spawned one carries its own span.
  .matureTime=18,.manaCap=40,.leyDraw=1.6,.share=0.5,.drain=0,.yield=0.12,
  .contain=3,.sway=1.5,
  // plucked where its trunks fuse, as high as the wolf reaches up
  .pluck=1.45,
  .stages=4,
  .genome=.{
    .form=.confluence,
    // its height and the girth of its trunks, its flowers' petals and
    // size (the rest of its body is the kit's; colours too)
    .stemH=2.8,.stemR=0.2,.segments=0,.curl=0,.wobble=0.08,
    .leaves=0,.leafLen=0,.leafW=0,.leafDroop=0,
    .petals=8,.bloomR=0.55,.thorns=0,.tendrils=0,.shoots=.{0,0},
    // its yield: four beads of the lineages' sap where its trunks fuse
    .pods=4,.podR=0.055,
    .stemCol=color.rgb(0.36,0.58,0.24),.leafCol=color.rgb(0.68,0.62,0.82),.bloomCol=color.rgb(0.58,0.36,0.9),
  },
  .parents=.{.lumenroot,.thornleech},
};
