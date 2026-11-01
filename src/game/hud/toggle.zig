//! a toggle, the sixth of the HUD's components: a bud on a short stem that
//! is shut while off and opens into a lit bloom when on, easing between as
//! it turns; it glows under the mouse (or the keys). Its row is clicked to
//! turn it; what it turns is its panel's.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: angles, easing
const m=lib.engine.core.math;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// how many petals an open bloom shows
const petals=5;
/// a petal's length and width (pixels), fully open
const petalLen:f32=15;
/// a petal's width (pixels)
const petalW:f32=9;
/// the stem's length under the bud (pixels)
const stemLen:f32=14;
/// one toggle as a row lays it out
pub const Toggle=struct{
  /// where its bud sits (pixels)
  at:m.Vice(f32,2),
  /// how far it is turned on (0 off .. 1 on), eased by its panel
  on:f32,
  /// whether the mouse (or the keys) are on its row
  over:bool=false,
  /// its sway's phase
  phase:f32=0,
  /// draws its stem, bud and petals as open as it is on, at UI time `t`
  pub fn draw(tg:Toggle,d:*Draw,t:f32)Allocator.Error!void{
    // where the bud sits, how open it is, and how far it sways now
    const c=tg.at;
    const open=m.smooth(m.clamp01(tg.on));
    const sway=0.06*@sin(t*1.7+tg.phase);
    try d.limb(.{c[0],c[1]+stemLen},.{c[0]+sway*20,c[1]+2},2.2,1.4,s.barkYoung,tg.phase);
    if(open>0.02)try d.glow(c[0],c[1],18+14*open,.{s.gold[0],s.gold[1],s.gold[2],@intFromFloat(70*open)});
    if(tg.over)try d.glow(c[0],c[1],26,s.menuHover);
    // the petals fanning out as it opens, shut together into a bud when off
    for(0..petals)|i|{
      // this petal's angle round the bud: gathered upward when shut
      const a=-m.halfPi+sway+(m.f(i)-m.f(petals-1)/2)*(0.18+1.0*open);
      try d.leaf(c,a,petalLen*(0.6+0.4*open),petalW,if(open>0.5)s.bud else s.leaf,open,tg.phase+m.f(i)*0.37);
    }
    try d.pod(c[0],c[1],3.5+1.5*open,s.gold,open,tg.phase);
  }
};
