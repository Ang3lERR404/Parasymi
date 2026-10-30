//! time of day (a sun or moon pod) and how full the wolf's sap belly is.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const play=lib.play;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const txt=lib.txt;
const panelX=s.edge;
const panelY:f32=14;
const panelW:f32=300;
const panelH:f32=74;
const orbX:f32=52;
const orbY:f32=50;
const orbR:f32=17;
const glowR:f32=30;
const glowAlpha:u8=90;
pub fn draw(g:*play.Game,d:*Draw,_:f32,_:f32)Allocator.Error!void{
  try d.trellis(panelX,panelY,panelW,panelH,s.card,0.1);
  const day=g.sky.daylight();
  const orb=if(day>0.5)s.sun else s.moon;
  const glow=[4]u8{orb[0],orb[1],orb[2],glowAlpha};
  try d.glow(orbX,orbY,glowR,glow);
  try d.pod(orbX,orbY,orbR,orb,0.4+0.6*(if(day>0.5)day else 1-day),0.3);
  _=try d.text(orbX+32,30,s.textHeading,s.white,g.sky.name());
  _=try d.text(orbX+32,56,s.textSub,s.dim,txt.s.hud.sap);
  try d.tendril(118,52,180,s.barHBold,s.sap,g.player.inv.fill(),0.2);
}
