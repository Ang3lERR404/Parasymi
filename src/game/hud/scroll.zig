//! a scrolled list, the fifth of the HUD's components: rows in a box, each
//! sliding by as the list scrolls (ui/scroll.zig says where), fading out
//! past its ends and cut to its box, and a young stem down its side with a
//! seed riding it where the list is: the wheel scrolls it, the stem held
//! drags it (its panel's `drag` hook calls `dragged`).
const lib=@import("../../lib.zig");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=lib.engine.core.math;
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the game itself: what is pointed at and held
const play=lib.play;
/// the HUD: picks and rows
const hud=lib.hud;
/// a screen rectangle
const Box=hud.Box;
/// where a scrolled list is
const Scroll=lib.engine.ui.scroll.Scroll;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the stem's clickable width (pixels)
pub const stemW:f32=28;
/// how far the stem sways either way (pixels)
const swayPx:f32=1.5;
/// how far in from the list's ends the seed rides (pixels)
const ride:f32=12;
/// a list of `total` rows `rowH` tall in `box`, scrolled by `at`
pub const List=struct{
  /// the list's box on screen (its rows are cut to it)
  box:Box,
  /// one row's height (pixels)
  rowH:f32,
  /// how many rows it holds
  total:usize,
  /// where it is scrolled to
  at:*const Scroll,
  /// rows fade out over this much of a row past its ends
  fade:f32=0.5,
  /// the middle height (pixels) of row `i` now
  pub fn mid(li:List,i:usize)f32{return li.box.y+li.rowH*(li.at.place(i)+0.5);}
  /// how much of row `i` shows (0..1)
  pub fn shows(li:List,i:usize)f32{return li.at.shows(i,li.fade);}
  /// row `i`'s box `w` wide from `x`, cut to the list (null when wholly
  /// past its ends)
  pub fn row(li:List,i:usize,x:f32,w:f32)?Box{
    // its middle, and its top and bottom cut to the list
    const c=li.mid(i);
    const y0=@max(c-li.rowH/2,li.box.y);
    const y1=@min(c+li.rowH/2,li.box.y+li.box.h);
    return if(y1>y0).{.x=x,.y=y0,.w=w,.h=y1-y0}else null;
  }
  /// the stem's box down the list's right side
  pub fn stemBox(li:List)Box{return.{.x=li.box.x+li.box.w-stemW,.y=li.box.y,.w=stemW,.h=li.box.h};}
  /// draws the stem (only while the list runs past what fits), a seed
  /// riding it where the list is, lit pointed at or held, and registers it
  /// as `pick`, at UI time `t`
  pub fn stem(li:List,g:*play.Game,d:*Draw,pick:hud.Pick,t:f32)Allocator.Error!void{
    if(li.at.most(li.total)<=0)return;
    // its box, the line it runs down, and whether it is pointed at or held
    const b=li.stemBox();
    const x=b.x+stemW/2;
    const over=g.points(pick) or g.grips(pick);
    // how far it sways now (pixels)
    const sway=swayPx*@sin(t*1.3);
    try d.limb(.{x+sway,b.y+4},.{x-sway,b.y+b.h-4},3,2,s.barkYoung,0);
    // where the seed rides on it
    const y=b.y+ride+(b.h-2*ride)*li.at.share(li.total);
    try d.grain(x,y,14,22,if(over)s.gold else s.bud,if(over)0.4 else 0.1,t*0.2);
    try g.rows.add(b,pick);
  }
};
/// the stem held, the cursor at `at` over its box `b`: the list `l` of
/// `total` rows dragged there
pub fn dragged(l:*Scroll,total:usize,b:Box,at:m.Vice(f32,2))void{l.drag(b.local(at)[1],total);}
