//! the hotbar: a row of husks hanging from a vine, each empty or holding an item the gardener
//! dropped on it from the belly, with the belly's count of it and the
//! selection's name. Click selects; with the belly open, click lifts and
//! puts down.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const m=lib.engine.core.math;
const play=lib.play;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const txt=lib.txt;
const st=lib.structures;
const items=lib.items;
const icon=lib.icon;
const belly=lib.hudBelly;
const Slot=lib.hudSlot.Slot;
const hud=lib.hud;
const Input=lib.engine.platform.input.Input;
const gap=s.slotGap;
const podR:f32=20;
const podRSel:f32=24;
const glowAlpha:u8=110;
/// how see-through a seed not yet understood is
const unknownAlpha:u8=110;
/// the vine's seed and growth key
const vineSeed:f32=5.5;
/// the selection's name sits this far above the husks, clear of the vine
const labelUp:f32=70;
/// a hotbar slot
pub const Pick=union(enum){slot:usize};
/// with the belly's slots open a slot lifts and puts down, else it is
/// selected; the other button takes its item off. Not while the world is
/// frozen.
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(!g.mode.live())return;
  const i=switch(p){.slot=>|i|i};
  switch(press){
    .use=>if(g.mode.sorting())g.clickBar(i)else{g.hot=i;},
    .remove=>g.bar[i]=null,
    .discard=>{},
  }
}
/// its item (not one lifted from it)
pub fn shows(g:*const play.Game,p:Pick)?items.Item{
  const i=switch(p){.slot=>|i|i};
  return if(g.holds(.{.bar=i}))null else g.bar[i];
}
/// whether placing `item` puts down a structure that faces a way (R turns it).
fn turns(item:items.Item)bool{
  const k=st.kindOf(item) orelse return false;
  return st.defs.get(k).carrier;
}
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  const n=play.barSlots;
  const x0=w/2-gap*m.f(n-1)/2;
  const hy=h-86;
  const t=g.uiT();
  const vine=belly.rowVine(d,x0-gap/2,hy,n,vineSeed);
  try vine.draw(d,t);
  for(g.bar,0..)|slot,i|{
    const x=x0+gap*m.f(i);
    const sel=i==g.hot;
    // lifted onto the cursor, it is shown there instead
    const item=if(g.holds(.{.bar=i}))null else slot;
    const col=if(item)|it|it.info().col else s.gold;
    var sl=Slot.around(.{x,hy},gap,gap,hud.row(.hotbar,.{.slot=i}),(if(sel)podRSel else podR)/gap);
    sl.grown=vine.reached(x);
    sl.lit=if(sel)1 else 0.25;
    sl.halo=if(sel).{col[0],col[1],col[2],glowAlpha}else null;
    sl.phase=m.f(i)*0.37;
    _=try d.text(x-4,hy+28,s.textSmall,s.dim,txt.nth(txt.s.hud.hotbarKeys,i));
    if(!try sl.draw(g,d))continue;
    const it=item orelse continue;
    const alpha=if(play.known(g,it))255 else unknownAlpha;
    try icon.draw(d,it,sl.center(),sl.radius(),t,sl.phase,if(sel)1 else 0.6,alpha);
    try icon.count(d,sl.center(),sl.radius(),g.player.inv.count(it));
  }
  const item=g.selected() orelse return;
  var buf:[64]u8=undefined;
  const name=txt.item(item).name;
  const label=if(!play.known(g,item))txt.s.hud.notUnderstood
    else if(turns(item))txt.bufRender(&buf,txt.s.hud.facingLabel,.{name,txt.nth(txt.s.hud.facing,g.placeDir)})
    else name;
  _=try d.text(w/2-Draw.width(label,s.textSub)/2,hy-labelUp,s.textSub,s.gold,label);
}
