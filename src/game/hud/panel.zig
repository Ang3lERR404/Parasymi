//! a panel, the fourth of the HUD's components: a vine trellis grown round
//! its box, which swallows the clicks that land on it (so they never reach
//! the garden beneath), its title centred along its top; a menu's sits
//! over a veil that dims the frozen world behind it. Its rows lay out
//! inside `box`.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the game itself: the clickable rows
const play=lib.play;
/// a screen rectangle
const Box=lib.hud.Box;
/// laying boxes out: a box in the middle of the screen
const layout=lib.engine.ui.layout;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the HUD's shared sizes and colours
const s=lib.style;
/// one panel as it is drawn
pub const Panel=struct{
  /// where it is on screen
  box:Box,
  /// its bed's colour
  col:Color,
  /// sets its vines and keys its growth (panels drawn at once take different seeds)
  seed:f32,
  /// a title centred along its top, if any
  title:?[]const u8=null,
  /// its title's text scale
  titleSize:f32=s.textBanner,
  /// whether the frozen world behind it is veiled (a menu)
  veil:bool=false,
  /// whether clicks landing on it are swallowed (a panel's backdrop row)
  blocks:bool=true,
  /// a menu's panel `w` by `h` in the middle of a screen `screen` pixels
  /// wide and high: veiled, on the pause menu's bed
  pub fn menu(screen:[2]f32,w:f32,h:f32,seed:f32,title:[]const u8)Panel{
    return.{.box=layout.centred(screen,w,h),.col=s.pausePanel,.seed=seed,.title=title,.veil=true};
  }
  /// draws its veil, trellis and title on a screen `screen` pixels wide and
  /// high, its backdrop registered to swallow clicks
  pub fn draw(p:Panel,g:*play.Game,d:*Draw,screen:[2]f32)Allocator.Error!void{
    if(p.veil)try d.glow(screen[0]/2,screen[1]/2,@max(screen[0],screen[1])*s.veilReach,s.veil);
    // its box
    const b=p.box;
    try d.trellis(b.x,b.y,b.w,b.h,p.col,p.seed);
    if(p.blocks)try g.rows.add(b,.panel);
    if(p.title)|t|_=try d.text(b.x+(b.w-Draw.width(t,p.titleSize))/2,b.y+s.titleY,p.titleSize,s.gold,t);
  }
};
