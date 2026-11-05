//! DRIFTWISP: a floater that occupies no tile: a sap float holding up a
//! catcher dish, filaments trailing beneath. Drinks the night sky instead
//! of the ley and condenses it into starlight.
const lib=@import("../../lib.zig");
/// the species registry: what a species is
const species=lib.species;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for its genome's pale blues
const color=engine.core.color;
/// the driftwisp (in game the halyriphon, the gardener's lumi lantern): a
/// floating radiant plant that condenses starlight, swaying most of all
pub const def:species.Species=.{
  // decision (the gardener, 2026-11-05): radiant, so it shatters at the
  // unforming as the light grid does; drawn with the symbiotes' sap as ever
  .lineage=.radiant,.look=.symbiotic,.seed=.seedDriftwisp,.floating=true,.catches=true,.yields=.starlight,
  // a night beam's overdrive steeps starglass in its dish
  .rare=.starglass,
  .matureTime=20,.manaCap=8,.leyDraw=0.5,.share=0.4,.drain=0,.yield=0.06,
  // plucked from its catcher dish, where its yield pools over the float
  .pluck=0.31,
  // its filaments trailing a metre beneath the float
  .trails=1.1,
  // its crown's petals glow lilac by night, lighting the fog round it
  .crownGlow=.{.high=0.24,.col=.{0.5,0.32,0.85},.reach=2.4},
  // light and hanging in the air: the wind carries it furthest
  .sway=1.8,
  .genome=.{
    .form=.drift,
    .stemH=0.1,.stemR=0.028,.segments=4,.curl=0.05,.wobble=0.1,
    .leaves=0,.leafLen=0.1,.leafW=0.05,.leafDroop=0,
    .petals=10,.bloomR=0.26,.thorns=0,.tendrils=11,.tendrilCurl=0.15,.tendrilWobble=0.12,
    // its yield: three beads of starlight pooled in its dish
    .pods=3,.podR=0.03,
    .stemCol=color.rgb(0.5,0.6,0.8),.leafCol=color.rgb(0.6,0.7,1.0),.bloomCol=color.rgb(0.85,0.9,1.0),
  },
};
