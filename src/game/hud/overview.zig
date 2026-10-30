//! alt mode ({@overview} toggles it): over every structure in view, what it
//! weaves (the chosen weave's seed, haloed, its husk lit as it works) or,
//! weaving nothing, what it holds (its most plentiful items, side by side,
//! each with how many); over the wolf, what its hands are weaving. Each sits
//! in a small husk, as the belly's slots do, laid over the garden where the
//! thing stands. Drawn first, under every other panel.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, conversions
const m=lib.engine.core.math;
/// the game itself: the structures, the wolf's weave, the camera
const play=lib.play;
/// the structures: their recipes and what they hold
const st=lib.structures;
/// the weave recipes: what a chosen one makes
const craft=lib.craft;
/// what can be held: item kinds
const items=lib.items;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the tools an item's icon is drawn with
const icon=lib.icon;
/// how far (metres, across either axis) from what the camera follows a
/// structure may stand and still be shown
const reach:f32=40;
/// how high over a structure's ground (metres, past its own float) its
/// icons sit
const lift:f32=0.6;
/// how high over the wolf's feet (metres) its weave sits
const wolfLift:f32=2.4;
/// a husk's radius (pixels)
const huskR:f32=15;
/// an icon's radius in it (pixels): the belly's share of its husk
const iconR:f32=huskR*24.0/21.0;
/// how far apart (pixels) held items' husks sit
const gap:f32=34;
/// most kinds of item shown over one structure
const most=3;
/// shown while alt mode is on, in play (not over the menus, nor flying)
pub fn visible(g:*const play.Game)bool{return g.overview and g.mode.live() and g.mode!=.inspect;}
/// draws, over every structure near and on screen, what it weaves or
/// holds, and over the wolf what it weaves
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  // the clock for sway and pulses
  const t=g.uiT();
  for(g.structs.list.items,0..)|*sp,i|{
    // where it stands, its icons' anchor, and where that lands on screen
    const ctr=sp.at+m.v3(0,g.heightAt(sp.x,sp.y)+sp.def().hover+lift,0);
    if(@abs(ctr[0]-g.cam.target[0])>reach or @abs(ctr[2]-g.cam.target[2])>reach)continue;
    const at=g.cam.screenOf(ctr,w,h) orelse continue;
    if(at[0]<-huskR or at[0]>w+huskR or at[1]<-huskR or at[1]>h+huskR)continue;
    // a phase of its own, so neighbours sway apart
    const phase=sp.seed+m.f(i)*0.37;
    if(st.chosen(sp))|r|{
      try weave(d,craft.hand[r].out,at,sp.activity,t,phase);
    }else try held(d,sp,at,t,phase);
  }
  // the wolf's hands, weaving
  if(g.weave.busy()){
    // the weave under way, and where it shows over the wolf
    const out=craft.hand[g.weave.queue[0]].out;
    if(g.cam.screenOf(g.player.pos+m.v3(0,wolfLift,0),w,h))|at|try weave(d,out,at,g.weave.progress(),t,0.5);
  }
}
/// a weave's seed in a haloed husk at `at`, lit as far as `lit` (0..1)
fn weave(d:*Draw,out:items.Item,at:[2]f32,lit:f32,t:f32,phase:f32)Allocator.Error!void{
  try d.glow(at[0],at[1],huskR*1.6,s.researchActive);
  try d.husk(at[0],at[1],huskR,s.podEmpty,m.clamp01(lit),phase);
  try icon.draw(d,out,at,iconR,t,phase,0.3+0.7*m.clamp01(lit),255);
}
/// the most plentiful kinds of what `sp` holds (up to `most`), each in a
/// husk with how many, side by side centred on `at`
fn held(d:*Draw,sp:*const st.Structure,at:[2]f32,t:f32,phase:f32)Allocator.Error!void{
  // the kinds held and how many of each, most plentiful first
  var kinds:[most]items.Stack=undefined;
  var n:usize=0;
  for(sp.inv.slot)|slot|if(slot)|it|{
    // this kind's place among those found, if it was found before
    const found=for(kinds[0..n],0..)|k,j|{
      if(k.item==it.item)break j;
    }else null;
    if(found)|j|{
      kinds[j].n+|=it.n;
    }else if(n<most){
      kinds[n]=it;
      n+=1;
    }
  };
  std.mem.sort(items.Stack,kinds[0..n],{},more);
  // where the first sits, the row centred on `at`
  const x0=at[0]-gap*(m.f(n)-1)/2;
  for(kinds[0..n],0..)|k,j|{
    // this husk's centre
    const c=[2]f32{x0+gap*m.f(j),at[1]};
    try d.husk(c[0],c[1],huskR,s.podEmpty,0.3,phase+m.f(j)*0.4);
    try icon.draw(d,k.item,c,iconR,t,phase+m.f(j)*0.4,0.6,255);
    try icon.count(d,c,iconR,k.n);
  }
}
/// whether `a` is held in greater number than `b` (most plentiful first)
fn more(_:void,a:items.Stack,b:items.Stack)bool{return a.n>b.n;}
