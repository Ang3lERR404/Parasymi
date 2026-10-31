//! a slider, the seventh of the HUD's components: a young stem laid along
//! its track, a small bud at each of its stops (lit up to the one it is
//! set to), and a seed riding the stem at its value. Held and dragged along
//! (its panel's `drag` hook, `ui/slider.zig` for which stop), or turned a
//! stop at a time by the keys.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: conversions
const m=lib.engine.core.math;
/// a screen rectangle
const Box=lib.hud.Box;
/// where along a slider's track its stops lie
const track=lib.engine.ui.slider;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// how far in from the track's ends its first and last stops sit (pixels)
pub const pad:f32=10;
/// a stop's bud radius (pixels)
const stopR:f32=4;
/// how far the stem sways either way (pixels)
const swayPx:f32=1.2;
/// one slider as a row lays it out
pub const Slider=struct{
  /// its track's box: the stem runs along its middle
  box:Box,
  /// how many stops it has
  stops:usize,
  /// where it is set now, along its track (0..1, eased by its panel)
  at:f32,
  /// whether the mouse (or the keys) are on its row, or it is held
  over:bool=false,
  /// its sway's phase
  phase:f32=0,
  /// draws its stem, its stops' buds and the riding seed, at UI time `t`
  pub fn draw(sl:Slider,d:*Draw,t:f32)Allocator.Error!void{
    // the stem's height, its ends, and how far it sways now
    const b=sl.box;
    const y=b.y+b.h/2;
    const x0=b.x+pad;
    const x1=b.x+b.w-pad;
    const sway=swayPx*@sin(t*1.3+sl.phase);
    try d.limb(.{x0-4,y+sway},.{x1+4,y-sway},2.6,1.6,s.barkYoung,sl.phase);
    for(0..sl.stops)|i|{
      // where this stop sits, and whether the seed has passed it
      const f=track.at(i,sl.stops);
      const lit=f<=sl.at+0.001;
      const x=x0+(x1-x0)*f;
      try d.pod(x,y+sway*(1-2*f),stopR,if(lit)s.bud else s.budDormant,if(lit)0.7 else 0.1,sl.phase+m.f(i)*0.3);
    }
    // the seed riding the stem at its value
    const x=x0+(x1-x0)*m.clamp01(sl.at);
    if(sl.over)try d.glow(x,y,26,s.menuHover);
    try d.grain(x,y-3,14,20,if(sl.over)s.gold else s.bud,if(sl.over)0.4 else 0.15,t*0.2+sl.phase);
  }
};
/// the stop of `n` the cursor's `x` sets on the track `b`
pub fn stopAt(b:Box,x:f32,n:usize)usize{return track.stop(track.share(b,x,pad),n);}
