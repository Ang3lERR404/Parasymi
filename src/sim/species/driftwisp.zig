//! DRIFTWISP: a floater that occupies no tile: a sap float holding up a
//! catcher dish, filaments trailing beneath. Drinks the night sky instead
//! of the ley and condenses it into starlight.
const lib=@import("../../lib.zig");
const species=lib.species;
const engine=lib.engine;
const color=engine.core.color;
pub const def:species.Species=.{
  .lineage=.symbiotic,.seed=.seedDriftwisp,.floating=true,.yields=.starlight,
  .matureTime=20,.manaCap=8,.leyDraw=0.5,.share=0.4,.drain=0,.yield=0.06,
  // light and hanging in the air: the wind carries it furthest
  .sway=1.8,
  .genome=.{
    .form=.drift,
    .stemH=0.1,.stemR=0.028,.segments=4,.curl=0.05,.wobble=0.1,
    .leaves=0,.leafLen=0.1,.leafW=0.05,.leafDroop=0,
    .petals=10,.bloomR=0.26,.thorns=0,.tendrils=11,.tendrilCurl=0.15,.tendrilWobble=0.12,
    .stemCol=color.rgb(0.5,0.6,0.8),.leafCol=color.rgb(0.6,0.7,1.0),.bloomCol=color.rgb(0.85,0.9,1.0),
  },
};
