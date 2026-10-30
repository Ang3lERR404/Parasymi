//! what the wolf does to the world: gather, put (sow/grow), weave, feed and
//! take from structures, interact with them, harvest, uproot, turn what
//! stands, pick up the seed of what stands, catch starlight. Each action works
//! on the Game and reports through the progression log.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator putting a plant or structure down may need
const Allocator=std.mem.Allocator;
/// finds a value in a slice, for the hotbar slot holding an item
const indexOfScalar=std.mem.indexOfScalar;
/// the test harness
const testing=std.testing;
/// all the maths: vectors, tiles, directions, casts
const m=lib.engine.core.math;
/// the chunk grid: tiles, their kinds and what is left in their nodes
const ck=lib.ck;
/// the species registry: what a plant yields, whether it floats, its seed
const species=lib.species;
/// the garden's plants: where one put down from the cursor stands
const Plants=lib.plants.Plants;
/// what can be held: items and the belly's bags
const items=lib.items;
/// the weaving recipes
const craft=lib.craft;
/// the structures registry: placing, feeding, emptying, configuring
const st=lib.structures;
/// what each kind of ground's nodes give
const resources=lib.resources;
/// plucking a ripe plant by paw: how long, how many plucks
const pluck=lib.pluck;
/// the game's state and its helpers (`known`, the default seed)
const play=lib.play;
/// every player-facing string
const txt=lib.txt;
/// the whole running game the actions work on
const Game=play.Game;
/// how long the wolf works a node for one item (s)
pub const gatherTime:f32=0.45;
/// how long a one-off gesture keeps the hands busy (s): putting something
/// down or uprooting it, feeding or emptying a structure
pub const lingerPut:f32=0.35;
/// how long feeding or emptying a structure keeps the hands busy (s)
const lingerTrade:f32=0.4;
/// wait before the next put (s): after one, and after warning of none left
const putCooldown:f32=0.25;
/// remove, held and swept: the wait before the next tile's thing goes (s)
pub const removeCooldown:f32=0.2;
/// how long before a "none left" warning may be said again (s)
const warnCooldown:f32=1.5;
/// starlight within `attract` tiles of the chest drifts to it, faster the
/// closer (`pull` less `pullFalloff` per tile away), and is absorbed within `absorb`
const attract:f32=2.4;
/// how fast the nearest starlight is drawn in (a share of the gap a second)
const pull:f32=5;
/// how much slower each tile further out is drawn
const pullFalloff:f32=1.5;
/// how close (tiles) a mote must come to the chest to be taken in
const absorb:f32=0.65;
/// works a resource node for a tick: every `gatherTime` it puts one item in
/// the belly and spends one from the node. Returns whether the wolf keeps
/// working this tile (the node still has some and the belly had room).
pub fn gather(g:*Game,c:*ck.Chunk,t:usize,dt:f32)bool{
  // the node this tile's ground offers; none, and there is nothing to gather
  const node=resources.of(c.kind[t]) orelse return false;
  g.gatherT+=dt;
  if(g.gatherT<gatherTime)return true;
  g.gatherT=0;
  if(g.player.inv.add(node.item,1)==0){
    if(!g.fullWarned)g.prog.say(txt.s.msg.bellyFull,.{});
    g.fullWarned=true;
    return false;
  }
  c.res[t]-=1;
  return c.res[t]>0;
}
/// put the selected hotbar item into the world: sow a seed or grow a bulb.
pub fn put(g:*Game,h:[2]i32)Allocator.Error!void{
  // the hotbar's chosen item; none, and nothing is put
  const item=g.selected() orelse return;
  // anything but a seed or a bulb stays in the belly
  if(item.plants()==null and st.kindOf(item)==null)return;
  if(!play.known(g,item))return;
  if(g.player.inv.count(item)==0){
    g.prog.say(txt.s.msg.noItem,.{txt.item(item).name});
    g.plantCd=warnCooldown;
    return;
  }
  // a plant faces the way the next thing put down does, as a structure
  // whether it took root: a seed sown as a plant, a bulb grown as a structure
  const ok=if(item.plants())|sp |
    try g.plants.placeNear(g.gpa,&g.world,Plants.spot(sp,h,g.hoverAt),.{
      .x=h[0],.y=h[1],.chunk=undefined,.tile=undefined,.sp=sp,.seed=g.rng.float(),.dir=g.placeDir,
    })
  else if(st.kindOf(item))|k |
    try g.structs.placeNear(g.gpa,&g.world,st.Structures.spot(k,h,g.hoverAt),k,g.placeDir,g.rng.float())
  else false;
  if(ok){
    if(st.kindOf(item)!=null)g.structs.sprout(.of(g.structs.list.items.len-1));
    _=g.player.inv.take(item,1);
    g.plantCd=putCooldown;
    g.linger=lingerPut;
  }
}
/// whether the chosen hotbar item may go down at this tile: a seed where
/// its plant fits, a bulb where its structure does
pub fn canPut(g:*const Game,h:[2]i32)bool{
  // the hotbar's chosen item; none, and nothing can be put
  const item=g.selected() orelse return false;
  if(item.plants())|sp|return g.plants.canPlaceNear(&g.world,Plants.spot(sp,h,g.hoverAt),sp);
  if(st.kindOf(item))|k|return g.structs.canPlaceNear(&g.world,st.Structures.spot(k,h,g.hoverAt),k);
  return false;
}
/// queues weave `i` (an index into `craft.hand`) in the wolf's own hands,
/// taking its ingredients now; the log says why if it cannot
pub fn weaveByHand(g:*Game,i:usize)void{
  // seeds (and what binds the lineages) come only from a germinator
  if(craft.germinatorOnly(i))return;
  // the recipe asked for
  const r=craft.hand[i];
  if(!r.unlocked(&g.prog))return g.prog.say(txt.s.msg.notUnderstood,.{txt.item(r.out).name});
  if(!g.weave.push(g.player.inv.bag(),i))g.prog.say(txt.s.msg.cannotWeave,.{txt.item(r.out).name});
}
/// give a structure everything from the belly it will take.
pub fn feed(g:*Game,j:st.Id)void{
  // how many things the structure took in all
  var moved:u32=0;
  for(&g.player.inv.slot)|*slot|if(slot.*)|*s|{
    // seeds and bulbs stay in the belly, ready to be placed
    if(s.item.plants()!=null or st.kindOf(s.item)!=null)continue;
    // how many of this stack it took
    const n=g.structs.insert(&g.prog,j,s.item,s.n);
    moved+=n;
    s.n-=n;
    if(s.n==0)slot.*=null;
  };
  g.linger=lingerTrade;
  if(moved==0)g.prog.say(txt.s.msg.wantsNothing,.{});
}
/// what a click (or the interact key) on a structure does: one that hands
/// something over straight away does (into the belly, or back if it is
/// full), one that keeps items opens its panel, one that is paired is
/// configured, any other is fed from the belly.
pub fn interact(g:*Game,h:[2]i32,j:st.Id)void{
  // the structure clicked
  const s=g.structs.get(j);
  if(st.handOver(s))|it|{
    if(g.player.inv.add(it,1)==0){
      _=s.inv.add(it,1);
      g.prog.say(txt.s.msg.bellyFull,.{});
    }
    g.linger=lingerTrade;
    return;
  }
  if(s.def().store){
    g.open=h;
    g.mode=.structure;
  }else if(st.configurable(s.kind()))st.configure(&g.structs,j,&g.prog)
  else feed(g,j);
}
/// turn what stands at a tile a quarter, clockwise or `back`: a rooted
/// thing uproots itself on its roots and digs back in facing its new way,
/// a floater only turns (sim/turn.zig). Not again until it has finished.
/// Returns whether anything stands there.
pub fn turnAt(g:*Game,h:[2]i32,back:bool)bool{
  // a quarter turn one way or three quarters the other
  const by:m.Dir=if(back)3 else 1;
  if(g.structs.at(&g.world,h[0],h[1]))|j|{
    // the structure standing there
    const s=g.structs.get(j);
    if(!s.turn.busy(g.time,!s.def().floating)){
      s.turn=.{.from=s.dir,.at=g.time};
      s.dir+%=by;
    }
    return true;
  }
  // the plant standing there; none, and nothing is turned
  const id=g.plantAt(h) orelse return false;
  // the plant list's columns, the plant's row, and whether it roots
  const p=g.plants.list.slice();
  const i=id.idx();
  const rooted=!species.get(p.items(.sp)[i]).floating;
  if(!p.items(.turn)[i].busy(g.time,rooted)){
    p.items(.turn)[i]=.{.from=p.items(.dir)[i],.at=g.time};
    p.items(.dir)[i]+%=by;
  }
  return true;
}
/// take up the seed (or bulb) of what stands at a tile, facing as it does:
/// the hotbar slot holding it is chosen; else, from the belly, it goes on
/// the chosen slot if that is empty, else the first empty one, else over
/// the chosen one. Returns whether anything stands there.
pub fn pick(g:*Game,h:[2]i32)bool{
  // what to pick up and which way it faced: a structure's bulb or a plant's seed
  const item:items.Item,const dir:m.Dir=if(g.structs.at(&g.world,h[0],h[1]))|j|blk:{
    // the structure standing there
    const s=g.structs.get(j);
    // (what forms by itself, a diamond, has no bulb to pick)
    if(st.kindOf(s.def().item)!=s.kind())return true;
    break:blk.{s.def().item,s.dir};
  }else if(g.plantAt(h))|id|blk:{
    // the plant list's columns, and the plant's seed (none: nothing to pick)
    const p=g.plants.list.slice();
    const seed=species.get(p.items(.sp)[id.idx()]).seed orelse return true;
    break:blk.{seed,p.items(.dir)[id.idx()]};
  }else return false;
  g.placeDir=dir;
  if(indexOfScalar(?items.Item,&g.bar,item))|i|{
    g.hot=i;
    return true;
  }
  if(g.player.inv.count(item)==0){
    g.prog.say(txt.s.msg.noItem,.{txt.item(item).name});
    return true;
  }
  // the hotbar slot it goes in: the chosen one if empty, else the first
  // empty one, else the chosen one anyway
  const slot=if(g.bar[g.hot]==null)g.hot else indexOfScalar(?items.Item,&g.bar,null) orelse g.hot;
  g.bar[slot]=item;
  g.hot=slot;
  return true;
}
/// empty a structure into the belly (what fits).
pub fn takeFrom(g:*Game,j:st.Id)void{
  // the structure being emptied
  const s=g.structs.get(j);
  for(&s.inv.slot)|*slot|if(slot.*)|*it|{
    // how many of this stack fit in the belly
    const n=g.player.inv.add(it.item,it.n);
    it.n-=n;
    if(it.n==0)slot.*=null;
  };
  if(st.release(s))|h|if(g.player.inv.add(h,1)==0)g.prog.say(txt.s.msg.bellyFull,.{});
  g.linger=lingerTrade;
}
/// uproot a structure: its bulb and contents come back (what fits).
/// anything that doesn't fit is lost.
pub fn unbuild(g:*Game,j:st.Id)void{
  // the structure, lifted out of the world; its memory freed once emptied
  var s=g.structs.remove(&g.world,j);
  defer s.deinit(g.gpa);
  // how many things found no room
  var lost:u32=0;
  // add returns how many fit; 1 - that = how many were lost
  lost+=1-g.player.inv.add(s.def().item,1);
  // (first: it may put what it has out back into its slots)
  if(st.release(&s))|h|lost+=1-g.player.inv.add(h,1);
  for(s.inv.slot)|slot|if(slot)|it|{
    lost+=it.n-g.player.inv.add(it.item,it.n);
  };
  if(lost>0)g.prog.say(txt.s.msg.spilled,.{lost});
}
/// start plucking a mature plant's yield by paw (`pluckOn` carries it on).
/// Plants never set seed (a germinator weaves them).
pub fn harvest(g:*Game,h:[2]i32)void{
  // the plant standing there, its row, the plant list's columns, its species
  const id=g.plantAt(h) orelse return;
  const i=id.idx();
  const s=g.plants.list.slice();
  const sp=s.items(.sp)[i];
  if(s.items(.growth)[i]<1){
    g.prog.say(txt.s.msg.stillGrowing,.{txt.plant(sp).name,s.items(.growth)[i]*100});
    return;
  }
  // the whole essence it has ripened
  const es=m.floorTo(u16,s.items(.essence)[i]);
  if(es==0){
    g.prog.say(txt.s.msg.notRipe,.{});
    return;
  }
  // (pressed again on the plant being plucked, the pluck goes on)
  if(g.pluck)|p|if(p.id==id)return;
  g.pluck=.{.id=id,.at=s.items(.at)[i],.left=@min(es,pluck.most)};
}
/// one frame of plucking: the pluck under way goes on, the yield that
/// comes loose shared out of what the plant has ripened into the belly (a
/// paw carrying it in). Returns how far through the pluck (0..1), or null
/// when there is none (its plant gone, the belly full, or all taken).
pub fn pluckOn(g:*Game,dt:f32)?f32{
  // the pluck under way
  const p=if(g.pluck)|*p|p else return null;
  // the plant plucked: gone, or another moved into its slot, and it ends
  const i=p.id.idx();
  const s=g.plants.list.slice();
  if(i>=s.len or m.len(s.items(.at)[i]-p.at)>1e-4){
    g.pluck=null;
    return null;
  }
  p.t+=dt;
  if(!p.freed and p.t>=pluck.loose*pluck.time){
    p.freed=true;
    // what it has ripened whole, its share for this pluck (rounded up),
    // what it yields, and how many the belly took
    const es=m.floorTo(u16,s.items(.essence)[i]);
    const n=(es+p.left-1)/p.left;
    const yields=species.get(s.items(.sp)[i]).yields;
    const got=g.player.inv.add(yields,n);
    s.items(.essence)[i]-=m.f(got);
    p.got+=got;
    if(got>0){
      g.player.bead=yields;
      g.player.stowUnit();
    }
    // the belly full, this pluck is the last
    if(got<n){
      g.prog.say(txt.s.msg.bellyFull,.{});
      p.left=1;
    }
    if(es==got)p.left=1;
  }
  if(p.t<pluck.time)return p.share();
  p.left-=1;
  if(p.left==0){
    // what an unstudied plant gives is learned only by taking it
    const sp=s.items(.sp)[i];
    if(p.got>0 and !g.prog.yieldKnown(sp))g.prog.say(txt.s.msg.givesUp,.{p.got,txt.item(species.get(sp).yields).name});
    g.pluck=null;
    return null;
  }
  p.t-=pluck.time;
  p.freed=false;
  return p.share();
}
/// pull a plant up: a sown plant always comes back as its seed, ready to be
/// sown again, so it stays in the ground while the belly has no room for it.
/// One that was never sown (a confluence) gives nothing back.
pub fn uproot(g:*Game,h:[2]i32)void{
  // the plant standing there; none, and nothing is uprooted
  const id=g.plantAt(h) orelse return;
  if(species.get(g.plants.list.items(.sp)[id.idx()]).seed)|seed|{
    if(g.player.inv.add(seed,1)==0)return g.prog.say(txt.s.msg.bellyFull,.{});
  }
  g.plants.remove(&g.world,id);
}
/// starlight drifts toward the wolf's chest and is absorbed on touch.
pub fn catchStarlight(g:*Game,dt:f32)void{
  // where the motes are drawn to, and the mote being looked at
  const chest=g.player.chest();
  var i:usize=0;
  while(i<g.stars.motes.items.len){
    // the mote, the way to the chest, and how far that is
    const mo=&g.stars.motes.items[i];
    if(mo.shattering()){i+=1;continue;}
    const d=chest-mo.pos;
    const dist=m.len(d);
    if(dist<attract){
      mo.pulled=true;
      mo.pos+=d*m.splat3(@min(1,dt*(pull-dist*pullFalloff)));
    }else if(mo.pulled){
      mo.pulled=false;
    }
    if(dist<absorb and g.player.inv.add(.starlight,1)==1){
      _=g.stars.motes.swapRemove(i);
      continue;
    }
    i+=1;
  }
}
test"plants never set seed; an uprooted plant comes back as its seed"{
  // the test allocator, a fresh game, and the tile two right of the wolf
  const gpa=testing.allocator;
  var g=try Game.init(gpa,play.defaultSeed);
  defer g.deinit();
  // the wolf's tile
  const x,const z=m.tileAt(g.player.pos);
  // the chunk two tiles right of the wolf, and that tile within it
  const cc=g.world.chunkOfTile(x+2,z).?;
  const t=ck.localIndex(x+2,z);
  cc.kind[t]=.soil;
  cc.res[t]=0;
  try testing.expect(try g.plants.placeEx(gpa,&g.world,x+2,z,.{
    .x=x+2,.y=z,.chunk=undefined,.tile=undefined,.sp=.lumenroot,
    .seed=0.5,.growth=1,.essence=2.5,
  }));
  harvest(&g,.{x+2,z});
  // plucked by paw over the next frames, until all it ripened is taken
  while(pluckOn(&g,1.0/60.0)!=null){}
  try testing.expectEqual(@as(u32,2),g.player.inv.count(.essence));
  try testing.expectEqual(@as(u32,0),g.player.inv.count(.seedLumenroot));
  uproot(&g,.{x+2,z});
  try testing.expect(g.plants.at(&g.world,x+2,z)==null);
  try testing.expectEqual(@as(u32,1),g.player.inv.count(.seedLumenroot));
}
test"a harvest is plucked by paw: a few plucks, each yield carried in as a bead"{
  // the test allocator, a fresh game, and the tile two right of the wolf
  const gpa=testing.allocator;
  var g=try Game.init(gpa,play.defaultSeed);
  defer g.deinit();
  // the wolf's tile, the chunk two tiles right of it and that tile within it
  const x,const z=m.tileAt(g.player.pos);
  const cc=g.world.chunkOfTile(x+2,z).?;
  const t=ck.localIndex(x+2,z);
  cc.kind[t]=.soil;
  cc.res[t]=0;
  try testing.expect(try g.plants.placeEx(gpa,&g.world,x+2,z,.{
    .x=x+2,.y=z,.chunk=undefined,.tile=undefined,.sp=.lumenroot,
    .seed=0.5,.growth=1,.essence=7.5,
  }));
  harvest(&g,.{x+2,z});
  // nothing is taken at the press: it comes loose pluck by pluck
  try testing.expectEqual(@as(u32,0),g.player.inv.count(.essence));
  // how many times the belly took some, and what it held last
  var plucks:u32=0;
  var had:u32=0;
  while(pluckOn(&g,1.0/60.0)!=null){
    // what the belly holds now
    const now=g.player.inv.count(.essence);
    if(now>had)plucks+=1;
    had=now;
  }
  try testing.expectEqual(@as(u32,pluck.most),plucks);
  try testing.expectEqual(@as(u32,7),g.player.inv.count(.essence));
  try testing.expect(g.player.bead==.essence);
  // moving off (the pluck let go) takes nothing more
  g.plants.list.items(.essence)[g.plantAt(.{x+2,z}).?.idx()]=3;
  harvest(&g,.{x+2,z});
  g.pluck=null;
  try testing.expect(pluckOn(&g,1)==null);
  try testing.expectEqual(@as(u32,7),g.player.inv.count(.essence));
}
test"seeds are woven only by a germinator, which is woven from gathered matter"{
  for(craft.byHand)|i|try testing.expect(!craft.germinatorOnly(i));
  for(craft.hand)|r|if(r.out==.germinator)for(r.in)|ing|{
    try testing.expect(ing.item==.fibre or ing.item==.grit or ing.item==.starlight);
  };
}
test"a confluence gives only convergence essence"{
  // the test allocator, and a fresh game
  const gpa=testing.allocator;
  var g=try Game.init(gpa,play.defaultSeed);
  defer g.deinit();
  // the wolf's tile, and the 2x2 footprint two tiles right of it
  const x,const z=m.tileAt(g.player.pos);
  var fp=m.footprint(x+2,z,2);
  while(fp.next())|p|{
    // the chunk holding this footprint tile, and the tile within it
    const cc=g.world.chunkOfTile(p[0],p[1]).?;
    const t=ck.localIndex(p[0],p[1]);
    cc.kind[t]=.soil;
    cc.res[t]=0;
  }
  try testing.expect(try g.plants.placeEx(gpa,&g.world,x+2,z,.{
    .x=x+2,.y=z,.chunk=undefined,.tile=undefined,.sp=.confluence,
    .seed=0.5,.growth=1,.essence=3.5,
  }));
  harvest(&g,.{x+3,z+1});
  // plucked by paw over the next frames, until all it ripened is taken
  while(pluckOn(&g,1.0/60.0)!=null){}
  try testing.expectEqual(@as(u32,3),g.player.inv.count(.convergenceEssence));
  try testing.expectEqual(@as(u32,0),g.player.inv.count(.seedLumenroot));
  try testing.expectEqual(@as(u32,0),g.player.inv.count(.seedThornleech));
  try testing.expect(species.fromSeed(.convergenceEssence)==null);
  // never sown, so uprooting it gives nothing back
  uproot(&g,.{x+3,z+1});
  try testing.expect(g.plants.at(&g.world,x+3,z+1)==null);
  try testing.expectEqual(@as(u32,3),g.player.inv.total());
}
