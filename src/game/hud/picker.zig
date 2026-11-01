//! a picker, the eighth of the HUD's components: one of a few values, shown
//! between two leaves that point the ways it turns. Each leaf is a box of
//! its own the mouse lands on (back on the left, on on the right), opening
//! under it; the keys turn it with left and right. What it picks from is
//! its panel's.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: angles
const m=lib.engine.core.math;
/// the game itself: what is pointed at
const play=lib.play;
/// the HUD: picks and rows
const hud=lib.hud;
/// a screen rectangle
const Box=hud.Box;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// how far either leaf sits from the value's middle (pixels)
pub const leafOff:f32=84;
/// a leaf's length (pixels)
const leafLen:f32=20;
/// a leaf's width (pixels)
const leafW:f32=12;
/// a leaf's clickable box, square round it (pixels)
const leafHit:f32=36;
/// one picker as a row lays it out
pub const Picker=struct{
  /// the middle of its value's line (pixels)
  center:m.Vice(f32,2),
  /// what it is set to, as shown
  value:[]const u8,
  /// what a click on its left leaf picks (turning it back)
  less:hud.Pick,
  /// what a click on its right leaf picks (turning it on)
  more:hud.Pick,
  /// whether the mouse (or the keys) are on its row
  over:bool=false,
  /// its sway's phase
  phase:f32=0,
  /// the box of its leaf `side` of the value (-1 left, +1 right)
  pub fn leafBox(p:Picker,side:f32)Box{
    return Box.around(.{p.center[0]+side*leafOff,p.center[1]+8},leafHit,leafHit);
  }
  /// draws its value and leaves (each opening under the mouse, or both
  /// with its row) and registers the leaves, at UI time `t`
  pub fn draw(p:Picker,g:*play.Game,d:*Draw,t:f32)Allocator.Error!void{
    // the value's middle, and the leaves' height
    const c=p.center;
    const mid=c[1]+8;
    _=try d.text(c[0]-Draw.width(p.value,s.textLabel)/2,c[1],s.textLabel,s.gold,p.value);
    // how far they sway now
    const sway=0.08*@sin(t*2+p.phase);
    for([_]f32{-1,1},[_]hud.Pick{p.less,p.more})|side,pick|{
      // whether the mouse is on this leaf, and how open it is
      const on=g.points(pick);
      const open:f32=if(on)1 else if(p.over)0.85 else 0.6;
      if(on)try d.glow(c[0]+side*leafOff,mid,22,s.menuHover);
      try d.leaf(.{c[0]+side*leafOff,mid},if(side<0)m.pi+sway else -sway,leafLen,leafW,s.leaf,open,p.phase+0.25+side*0.25);
      try g.rows.add(p.leafBox(side),pick);
    }
  }
};
