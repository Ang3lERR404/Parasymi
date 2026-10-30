//! the hotbar: a row of husks hanging from a vine, each empty or holding an item the gardener
//! dropped on it from the belly, with the belly's count of it and the
//! selection's name. Click selects; with the belly open, click lifts and
//! puts down.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: conversions, easing
const m=lib.engine.core.math;
/// the game itself: the bar, the selection, what is held
const play=lib.play;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// every player-facing string
const txt=lib.txt;
/// the structures registry, to know which placed things face a way
const st=lib.structures;
/// what can be held: item kinds
const items=lib.items;
/// the tools an item's icon is drawn with
const icon=lib.icon;
/// the belly panel, whose row vine the husks hang from
const belly=lib.hudBelly;
/// a husk slot, the HUD's shared component
const Slot=lib.hudSlot.Slot;
/// the HUD: picks, presses and rows
const hud=lib.hud;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// how far apart (pixels) the husks hang
const gap=s.slotGap;
/// a husk's radius (pixels)
const podR:f32=20;
/// the selected husk's radius (pixels), a little larger
const podRSel:f32=24;
/// how strong the selected husk's halo is, 0..255
const glowAlpha:u8=110;
/// how see-through a seed not yet understood is
const unknownAlpha:u8=110;
/// the vine's seed and growth key
const vineSeed:f32=5.5;
/// the selection's name sits this far above the husks, clear of the vine
const labelUp:f32=70;
/// a hotbar slot
pub const Pick=union(enum){
  /// the bar slot, counted from the left
  slot:usize
};
/// with the belly's slots open a slot lifts and puts down, else it is
/// selected; the other button takes its item off. Not while the world is
/// frozen.
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(!g.mode.live())return;
  // which bar slot was clicked
  const i=switch(p){.slot=>|i|i};
  switch(press){
    .use=>if(g.mode.sorting())g.clickBar(i)else{g.hot=i;},
    .remove=>g.bar[i]=null,
    .discard=>{},
  }
}
/// its item (not one lifted from it)
pub fn shows(g:*const play.Game,p:Pick)?items.Item{
  // which bar slot the row is
  const i=switch(p){.slot=>|i|i};
  return if(g.holds(.{.bar=i}))null else g.bar[i];
}
/// whether placing `item` puts down a structure that faces a way (R turns it).
fn turns(item:items.Item)bool{
  // the structure kind it grows, if any
  const k=st.kindOf(item) orelse return false;
  return st.defs.get(k).carrier;
}
/// draws the vine along the bottom middle with a husk per bar slot (the
/// selected one larger and haloed), each slot's key under it, each item
/// with the belly's count of it, and the selection's name above, with the
/// way it faces when it is a structure that turns.
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  // how many slots, the first one's x, and the row's height on screen
  const n=play.barSlots;
  const x0=w/2-gap*m.f(n-1)/2;
  const hy=h-86;
  // the hotbar's clock, for sway and growth
  const t=g.uiT();
  // the vine the husks hang from, growing along the row
  const vine=belly.rowVine(d,x0-gap/2,hy,n,vineSeed);
  try vine.draw(d,t);
  for(g.bar,0..)|slot,i|{
    // this husk's x, and whether it is the selected one
    const x=x0+gap*m.f(i);
    const sel=i==g.hot;
    // lifted onto the cursor, it is shown there instead
    const item=if(g.holds(.{.bar=i}))null else slot;
    // the item's colour, gold for an empty husk
    const col=if(item)|it|it.info().col else s.gold;
    // the husk itself, sized by whether it is selected
    var sl=Slot.around(.{x,hy},gap,gap,hud.row(.hotbar,.{.slot=i}),(if(sel)podRSel else podR)/gap);
    sl.grown=vine.reached(x);
    sl.lit=if(sel)1 else 0.25;
    sl.halo=if(sel).{col[0],col[1],col[2],glowAlpha}else null;
    sl.phase=m.f(i)*0.37;
    _=try d.text(x-4,hy+28,s.textSmall,s.dim,txt.nth(txt.s.hud.hotbarKeys,i));
    if(!try sl.draw(g,d))continue;
    const it=item orelse continue;
    // how solid its icon is: faint while it is not yet understood
    const alpha=if(play.known(g,it))255 else unknownAlpha;
    try icon.draw(d,it,sl.center(),sl.radius(),t,sl.phase,if(sel)1 else 0.6,alpha);
    try icon.count(d,sl.center(),sl.radius(),g.player.inv.count(it));
  }
  // the selected item, and room to write its name and facing in
  const item=g.selected() orelse return;
  var buf:[64]u8=undefined;
  // its name, and the label shown: its name, its facing, or not understood
  const name=txt.item(item).name;
  const label=if(!play.known(g,item))txt.s.hud.notUnderstood
    else if(turns(item))txt.bufRender(&buf,txt.s.hud.facingLabel,.{name,txt.nth(txt.s.hud.facing,g.placeDir)})
    else name;
  _=try d.text(w/2-Draw.width(label,s.textSub)/2,hy-labelUp,s.textSub,s.gold,label);
}
