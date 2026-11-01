//! time of day (a sun or moon pod) and how full the wolf's sap belly is.
const lib=@import("../../lib.zig");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=lib.engine.core.math;
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the game itself: the sky and the wolf's belly
const play=lib.play;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// every player-facing string
const txt=lib.txt;
/// the card's left edge (pixels)
const panelX=s.edge;
/// the card's top edge (pixels)
const panelY:f32=14;
/// the card's width (pixels)
const panelW:f32=300;
/// the card's height (pixels)
const panelH:f32=74;
/// the sun or moon pod's centre (pixels from the left)
const orbX:f32=52;
/// the sun or moon pod's centre (pixels from the top)
const orbY:f32=50;
/// the pod's radius (pixels)
const orbR:f32=17;
/// the radius of its glow (pixels)
const glowR:f32=30;
/// how strong that glow is, 0..255
const glowAlpha:u8=90;
/// draws the top-left card: a sun pod by day or a moon pod by night, open
/// as far as the hour is deep, the hour's name, and the sap tendril filled
/// as the belly is.
pub fn draw(g:*play.Game,d:*Draw,_:f32,_:f32)Allocator.Error!void{
  try d.trellis(panelX,panelY,panelW,panelH,s.card,0.1);
  // how light the day is (0..1), and whether the sun or moon shows
  const day=g.sky.daylight();
  const orb=if(day>0.5)s.sun else s.moon;
  // the pod's colour, faded for its glow
  const glow=m.Vice(u8,4){orb[0],orb[1],orb[2],glowAlpha};
  try d.glow(orbX,orbY,glowR,glow);
  try d.pod(orbX,orbY,orbR,orb,0.4+0.6*(if(day>0.5)day else 1-day),0.3);
  _=try d.text(orbX+32,30,s.textHeading,s.white,g.sky.name());
  _=try d.text(orbX+32,56,s.textSub,s.dim,txt.s.hud.sap);
  try d.tendril(118,52,180,s.barHBold,s.sap,g.player.inv.fill(),0.2);
}
