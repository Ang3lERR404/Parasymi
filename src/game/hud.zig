//! the HUD, composed only from grown shapes (ui/draw.zig): vine trellises
//! for panels, husks hanging from vines for slots, leafy stems for progress,
//! buds for bullets, seeds for ingredients, glows for focus.
//!
//! Each panel is its own module under `hud/` declaring
//!   draw(g, d, W, H) !void
//!   visible(g) bool              (optional; always drawn when absent)
//!   Pick                         (optional; what its rows are, as `row` makes them)
//!   click(g, p, press, in) void  (optional; what a click on one of its rows does)
//!   shows(g, p) ?Item            (optional; the item a row shows, for the tooltip)
//! Panels draw in declaration order, so later ones sit on top. A new panel is
//! one new file plus one line in `panels`.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// deep equality, to find a row by its pick
const eqlDeep=std.meta.eql;
/// the engine's registry builder, which turns `panels` into ids and dispatch
const registry=lib.engine.core.registry;
/// the game itself: its state, mode and what the mouse points at
const play=lib.play;
/// what can be held: item kinds
const items=lib.items;
/// the keys and buttons down this frame, handed to a panel's click
const Input=lib.engine.platform.input.Input;
/// the UI's draw batch, which every panel draws into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// a screen rectangle (x, y, w, h) that the mouse can land in
pub const Box=lib.engine.ui.box.Box;
/// all the maths: vectors, easing, angles
const m=lib.engine.core.math;
/// what a click on the HUD lands on: one of a panel's own rows (its `Pick`),
/// or just a panel (which keeps the click out of the world beneath it).
pub const Pick=union(enum){
  /// a bare panel: it swallows the click, nothing more
  panel,
  /// one of a panel's own rows, tagged by that panel
  row:Row
};
/// a row of some panel: tagged by the panel, holding that panel's `Pick`
/// (void for a panel without one)
const Row=reg.Union("Pick");
/// the panels, by name
pub const Panel=reg.Id;
/// panel `id`'s row `p`, as the HUD picks it
pub fn row(comptime id:Panel,p:@FieldType(Row,@tagName(id)))Pick{
  return.{.row=@unionInit(Row,@tagName(id),p)};
}
/// `p`, if it is one of panel `id`'s rows
pub fn own(comptime id:Panel,p:?Pick)?@FieldType(Row,@tagName(id)){
  // the row picked, or nothing when only a bare panel was hit
  const r=switch(p orelse return null){.panel=>return null,.row=>|r|r};
  return if(r==id)@field(r,@tagName(id))else null;
}
/// how a row was clicked: used (left), the other button (taking back, or
/// turning an option back), or thrown away
pub const Press=enum{
  /// the main button: use, take or place
  use,
  /// the other button: take back, or turn an option back
  remove,
  /// thrown away
  discard
};
/// a click on `p`: the panel that owns the row does what it does (its
/// `click` hook); a click on a bare panel puts down what is carried.
pub fn click(g:*play.Game,p:Pick,press:Press,in:*const Input)void{
  switch(p){
    .panel=>if(press==.use and g.mode.live())g.drop(),
    .row=>|r|switch(r){
      inline else=>|q,id|if(comptime reg.has(id,"click"))reg.module(id).click(g,q,press,in),
    },
  }
}
/// the item shown on the row `p`, if any (its panel's `shows` hook)
pub fn shows(g:*const play.Game,p:Pick)?items.Item{
  return switch(p){
    .panel=>null,
    .row=>|r|switch(r){
      inline else=>|q,id|if(comptime reg.has(id,"shows"))reg.module(id).shows(g,q)else null,
    },
  };
}
/// the research sapling's growth, kept between frames.
pub const Sapling=panels.research.Sapling;
/// the clickable areas the panels drew last frame. Panels add them as they
/// draw (backdrop first, rows on top); `build` clears them; play.update
/// hit-tests the mouse against them, one frame behind the draw.
pub const Rows=struct{
  /// how many clickable areas one frame may hold
  const max=96;
  /// each area's screen rectangle, in the order drawn
  box:[max]Box=undefined,
  /// what each area is, beside its rectangle
  pick:[max]Pick=undefined,
  /// how many areas are held this frame
  len:usize=0,
  /// adds the area `b` for `p`, on top of those already added; more than
  /// `max` in one frame is a bug and panics.
  pub fn add(r:*Rows,b:Box,p:Pick)void{
    if(r.len==max)@panic("more clickable HUD rows than Rows.MAX");
    r.box[r.len]=b;
    r.pick[r.len]=p;
    r.len+=1;
  }
  /// the topmost area under `pos` (screen pixels), if any.
  pub fn at(r:*const Rows,pos:[2]f32)?Pick{
    // the area being looked at, walking back from the topmost
    var i=r.len;
    while(i>0){
      i-=1;
      if(r.box[i].contains(pos))return r.pick[i];
    }
    return null;
  }
  /// the area last added for `p`, if any.
  pub fn find(r:*const Rows,p:Pick)?Box{
    // the area being looked at, walking back from the last added
    var i=r.len;
    while(i>0){
      i-=1;
      if(eqlDeep(r.pick[i],p))return r.box[i];
    }
    return null;
  }
};
/// every panel of the HUD, one module each, drawn in this order (later on top)
pub const panels=struct{
  /// the time of day and the sap belly's fill, top left
  pub const status=@import("hud/status.zig");
  /// the hotbar of seeds and tools along the bottom
  pub const hotbar=@import("hud/hotbar.zig");
  /// the card naming what the wolf is looking at
  pub const hover=@import("hud/hover.zig");
  /// the gathering tendril over the wolf's focus
  pub const gather=@import("hud/gather.zig");
  /// the wolf's sap belly, opened as a grid of husks
  pub const belly=@import("hud/belly.zig");
  /// the panel of the structure being tended
  pub const structure=@import("hud/structure.zig");
  /// the research sapling and its branches
  pub const research=@import("hud/research.zig");
  /// recent messages and the control hint
  pub const log=@import("hud/log.zig");
  /// the timings and counts shown with the debug key
  pub const debug=@import("hud/debug.zig");
  /// the free camera's reminder
  pub const inspect=@import("hud/inspect.zig");
  /// the aiming seed while looking out of the wolf's eyes
  pub const eyes=@import("hud/eyes.zig");
  /// an item's full name beside the cursor
  pub const tooltip=@import("hud/tooltip.zig");
  /// what the cursor carries, hanging off the pointer
  pub const carry=@import("hud/carry.zig");
  /// the pause menu
  pub const pause=@import("hud/pause.zig");
  /// the options panel
  pub const options=@import("hud/options.zig");
  /// the saved gardens list
  pub const gardens=@import("hud/gardens.zig");
  /// the naming card for a new garden
  pub const naming=@import("hud/naming.zig");
};
/// the panel registry built from `panels`: its ids, modules and hooks
const reg=registry.Registry(panels);
/// a row's bullet: a bud of radius `r` at (cx, cy), opening as `open` runs
/// to 1 (the row under the mouse).
pub fn bullet(d:*Draw,cx:f32,cy:f32,r:f32,col:Color,open:f32,seed:f32)Allocator.Error!void{
  try d.leaf(.{cx,cy+r},-m.halfPi,2*r,1.1*r,col,open,seed);
}
/// draws the whole HUD for this frame into `g.ui`: clears the batch and the
/// clickable rows, then draws each visible panel in turn on a screen
/// `screen` pixels wide and high.
pub fn build(g:*play.Game,screen:[2]f32)Allocator.Error!void{
  // the draw batch the panels draw into
  const d=&g.ui;
  d.clear(@floatCast(g.uiTime));
  g.rows.len=0;
  inline for(reg.ids)|id|{
    // this panel's module, and whether it is shown this frame
    const p=reg.module(id);
    const show=if(comptime reg.has(id,"visible"))p.visible(g)else true;
    if(show)try p.draw(g,d,screen[0],screen[1]);
  }
}
