//! what the wolf carries: the hotbar, the belly and an opened structure's slots.
const lib=@import("../../lib.zig");
const std=lib.std;
const eqlDeep=std.meta.eql;
const swap=std.mem.swap;
const engine=lib.engine;
const m=engine.core.math;
const items=lib.items;
const txt=lib.txt;
const st=lib.structures;
const hud=lib.hud;
const Game=lib.play.game.Game;
const headClear=lib.play.headClear;
const Held=lib.play.Held;
const stackAny=lib.play.stackAny;
const uiWrap=lib.play.uiWrap;
pub fn arsthraxiaState(g:*const Game)?lib.sound.Sounds.Cmd{
  for(g.structs.list.items)|*s|{
    if(s.kind()!=.arsthraxia)continue;
    const a=&s.state.arsthraxia;
    if(!a.lab.active and a.flare<=0)return null;
    return.{.arsthraxia=.{.progress=a.lab.t,.fed=a.fed,.complete=a.flare>0.9}};
  }
  return null;
}
/// the view is in the wolf's eyes: its head is not drawn (its shadow is)
pub fn headless(g:*const Game)bool{
  return switch(g.cam.view){
    .eyes=>|y|m.len(g.cam.viewEye()-y.pos)<headClear,
    .follow,.free,.returning=>false,
  };
}
/// is the cursor carrying `h`?
pub fn holds(g:*const Game,h:Held)bool{return if(g.held)|x|eqlDeep(x,h)else false;}
/// is the mouse over `p`?
pub fn points(g:*const Game,p:hud.Pick)bool{return if(g.pointed)|x|eqlDeep(x,p)else false;}
/// UI seconds, kept small enough for f32 sway and pulses.
pub fn uiT(g:*const Game)f32{return@floatCast(@mod(g.uiTime,uiWrap));}
/// the selected hotbar slot's item, if it holds one.
pub fn selected(g:*const Game)?items.Item{return g.bar[g.hot];}
/// what the cursor carries, if anything.
pub fn carried(g:*const Game)?items.Item{return if(g.held)|h|g.itemOf(h)else null;}
/// the item a slot holds.
pub fn itemOf(g:*const Game,h:Held)?items.Item{
  return switch(h){
    .slot=>|i|if(g.player.inv.slot[i])|s|s.item else null,
    .bar=>|i|g.bar[i],
    .store=>|i|if(g.storeSlot(i))|s|s.item else null,
  };
}
/// the structure whose panel is open, while it stands within reach.
pub fn opened(g:*const Game)?st.Id{
  if(g.mode!=.structure or !g.player.inReach(g.open[0],g.open[1]))return null;
  return g.structs.touched(&g.world,g.open[0],g.open[1]);
}
/// slot `i` of the open structure, if it holds a stack.
pub fn storeSlot(g:*const Game,i:usize)?items.Stack{
  const j=g.opened() orelse return null;
  return g.structs.list.items[j.idx()].inv.slot[i];
}
/// a click on belly slot `i`: lift its stack, or put down what is carried
/// there (`putDown`). A hotbar item carried off its slot is taken off the
/// hotbar. A structure's stack trades places only with one it would take.
pub fn clickSlot(g:*Game,i:usize)void{
  const slot=&g.player.inv.slot;
  const h=g.held orelse {
    if(slot[i]!=null)g.held=.{.slot=i};
    return;
  };
  g.held=null;
  switch(h){
    .bar=>|j|g.bar[j]=null,
    .slot=>|j|if(j!=i and putDown(&slot[j],&slot[i],stackAny,true)){g.held=h;},
    .store=>|j|{
      const id=g.opened() orelse return;
      const there=if(slot[i])|s|g.structs.wants(&g.prog,id,s.item)>=s.n else true;
      if(putDown(&g.structs.get(id).inv.slot[j],&slot[i],stackAny,there))g.held=h;
    },
  }
}
/// a click on slot `i` of the open structure: lift its stack, or put down
/// what is carried there, as much of it as the structure will take (it
/// trades places only when it takes the whole stack). A hotbar item is
/// just put down.
pub fn clickStore(g:*Game,i:usize)void{
  const id=g.opened() orelse return;
  const slot=&g.structs.get(id).inv.slot;
  const h=g.held orelse {
    if(slot[i]!=null)g.held=.{.store=i};
    return;
  };
  g.held=null;
  switch(h){
    .bar=>|j|g.bar[j]=null,
    .store=>|j|if(j!=i and putDown(&slot[j],&slot[i],stackAny,true)){g.held=h;},
    .slot=>|j|{
      const from=&g.player.inv.slot[j];
      const room=if(from.*)|s|g.structs.wants(&g.prog,id,s.item)else 0;
      if(putDown(from,&slot[i],room,room>=from.*.?.n))g.held=h;
    },
  }
}
/// a click on hotbar slot `i`: put what is carried there (a stack
/// assigns its item, a hotbar item trades places), or lift its item.
pub fn clickBar(g:*Game,i:usize)void{
  const h=g.held orelse {
    if(g.bar[i]!=null)g.held=.{.bar=i};
    return;
  };
  g.held=null;
  switch(h){
    .slot,.store=>g.bar[i]=g.itemOf(h) orelse g.bar[i],
    .bar=>|j|swap(?items.Item,&g.bar[i],&g.bar[j]),
  }
}
/// put down what is carried anywhere but a slot: a stack goes back where
/// it was, a hotbar item comes off the hotbar.
pub fn drop(g:*Game)void{
  const h=g.held orelse return;
  g.held=null;
  switch(h){
    .slot,.store=>{},
    .bar=>|i|g.bar[i]=null,
  }
}
/// throw away belly slot `i`'s stack for good. Only the belly's: a
/// structure's slots and the hotbar keep theirs.
pub fn discard(g:*Game,i:usize)void{
  const s=g.player.inv.slot[i] orelse return;
  g.player.inv.slot[i]=null;
  g.held=null;
  g.prog.say(txt.s.msg.discarded,.{s.n,txt.item(s.item).name});
}
/// move a whole stack straight across, belly to the open structure (as
/// much as it will take) or back (as much as fits).
pub fn moveAcross(g:*Game,from:Held)void{
  const id=g.opened() orelse return;
  switch(from){
    .slot=>|i|if(g.player.inv.slot[i])|*s|{
      s.n-=g.structs.insert(&g.prog,id,s.item,s.n);
      if(s.n==0)g.player.inv.slot[i]=null;
    },
    .store=>|i|if(g.structs.get(id).inv.slot[i])|*s|{
      s.n-=g.player.inv.add(s.item,s.n);
      if(s.n==0)g.structs.get(id).inv.slot[i]=null
      else g.prog.say(txt.s.msg.bellyFull,.{});
    },
    .bar=>{},
  }
}
/// put the carried stack `from` down on `to`: into an empty slot or onto
/// the same item, as much as fits and `cap` allows; else the two trade
/// places if `trade`. Returns whether some of it is still in hand.
pub fn putDown(from:*?items.Stack,to:*?items.Stack,cap:u32,trade:bool)bool{
  const f=if(from.*)|*p|p else return false;
  var room:u32=items.stack;
  if(to.*)|t|{
    if(t.item!=f.item){
      if(trade)swap(?items.Stack,from,to);
      return!trade;
    }
    room-|=t.n;
  }
  const k:u16=@intCast(@min(f.n,room,cap));
  if(k==0)return true;
  if(to.*)|*t|t.n+=k else to.*=.{.item=f.item,.n=k};
  f.n-=k;
  if(f.n>0)return true;
  from.*=null;
  return false;
}
