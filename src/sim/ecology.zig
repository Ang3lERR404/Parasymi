//! the fixed-tick ecology: mana from the ley field, symbiotic sharing,
//! parasitic draining, growth, essence and death. Two-phase (accumulate
//! deltas, then apply) so the result never depends on plant order.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the engine package
const engine=lib.engine;
/// the species registry: each plant's rates, lineage and reach
const species=lib.species;
/// plant storage: the plants and their neighbour rings
const plantsMod=lib.plants;
/// the chunk: each tile's ley
const ck=lib.ck;
/// the light grid: what each plant draws, the beams and the guards
const light=lib.light;
/// the world module
const world=lib.world;
/// the garden's streamed world, whose tiles the plants stand on
const World=world.World;
/// all the maths: clamps, conversions, footprints
const m=engine.core.math;
/// the allocator type the per-plant scratch grows with
const Allocator=std.mem.Allocator;
/// the test allocator and expectations
const testing=std.testing;
/// every living plant
const Plants=plantsMod.Plants;
/// a plant's slot
const Id=plantsMod.Id;
/// knobs that progression turns. The sim never imports game code.
pub const Mods=struct{
  /// symbiotic links reach the second ring.
  link2:bool=false,
  /// how much harder parasites drain (1: as their species says)
  drainMult:f32=1,
  /// how much more each species yields, by species
  yieldMult:[species.count]f32=@splat(1),
  /// how dark it is (0 day .. 1 night); floating plants drink starlight.
  night:f32=0,
  /// whether the starlit patches still shine (dark for good once the
  /// unforming begins): a catcher drinks only over a shining one
  starlit:bool=true,
  /// the relays the structures hold (a diamond), for the light grid
  relays:[]const light.Relay=&.{},
  /// the structures that draw light, for the light grid
  users:[]const light.User=&.{},
  /// how hard overdrive harms a plant (1; Tempered Light halves it)
  overdriveHarm:f32=1,
};
/// what a tick saw happen, for the game to tell of
pub const Events=struct{
  /// how many plants died this tick
  died:u32=0,
};
/// health lost per second by a plant short of the light it draws
const unpoweredWither:f32=0.06;
/// how much faster a plant grows and yields under a whole night's beam (2: 3x)
const overdriveBoost:f32=2;
/// health a plant loses a second under a whole night's beam, unguarded
/// (600 s days: about a night and a half)
const overdriveHurt:f32=0.004;
/// the share of a beamed plant's yield that is rare
const rareShare:f32=0.1;
/// how wet a tile's ground must be for a plant that needs soaked ground
/// to live (`Species.needsSoak`), and how fast it withers drier (health/s:
/// about eight minutes, so it waits out the dry spells between showers)
pub const soakedAt:f32=0.5;
const dryWither:f32=0.002;
/// the mana each unit of the ground's water drunk gives (`Species.waterDraw`)
pub const waterMana:f32=30;
/// floaters drink this share of their draw by day, all of it at full night
const dayDrink:f32=0.1;
/// a drawn ley tile refills this share of its deficit per second
const leyRefill:f32=0.15;
/// symbiotes pass on this share of their fill difference (times share and
/// cap) per second
const shareRate:f32=0.5;
/// how much a plant heals (health per second) for what is shared to it
const shareHeal:f32=0.02;
/// a parasite keeps this share of what it drains
/// (the rest is lost)
const drainKeep:f32=0.85;
/// below this share of its cap a drained plant is starved and loses health
const starved:f32=0.1;
/// health a starved plant loses per second
const starveHurt:f32=0.08;
/// growth: a starved plant still grows at this share of its pace
/// (the rest comes with its fill)
const growMin:f32=0.3;
/// how much each linked kin speeds its growth (a share per kin)
const kinGrow:f32=0.15;
/// how much each linked kin raises its yield (a share per kin)
const kinYield:f32=0.1;
/// below this fill a mature plant is nearly out of mana, and fades
const empty:f32=0.05;
/// health a mature, empty plant loses per second
const fadeTime:f32=0.05;
/// health every other plant heals per second
const heal:f32=0.02;
/// the drawn sap flow: how strongly mana moved per cap shows as flow
const flowGain:f32=4;
/// how quickly the shown flow eases toward the mana moved, per tick (0..1)
const flowEase:f32=0.05;
/// the ecology's per-tick scratch: what each plant gains or loses,
/// containment, the light grid, and the plants that died
pub const Ecology=struct{
  /// per plant: mana gained or lost this tick
  dm:std.ArrayList(f32)=.empty,
  /// per plant: health gained or lost this tick
  dh:std.ArrayList(f32)=.empty,
  /// per plant: mana moved through it this tick (its flow)
  df:std.ArrayList(f32)=.empty,
  /// per plant: its drain rate after containment (1, or `species.contained`).
  calm:std.ArrayList(f32)=.empty,
  /// the light grid, worked out each tick
  light:light.Light=.{},
  /// the plants that died this tick
  dead:std.ArrayList(Id)=.empty,
  /// frees the scratch
  pub fn deinit(e:*Ecology,gpa:Allocator)void{
    e.dm.deinit(gpa);e.dh.deinit(gpa);e.df.deinit(gpa);e.calm.deinit(gpa);e.dead.deinit(gpa);
    e.light.deinit(gpa);
  }
  /// mature containing plants (the confluence) calm every parasite within
  /// their reach: they keep draining, at a fraction of the rate.
  fn contain(e:*Ecology,gpa:Allocator,p:*const Plants,w:*const World)Allocator.Error!void{
    try e.calm.resize(gpa,p.len());
    @memset(e.calm.items,1);
    // the plant columns
    const s=p.list.slice();
    for(s.items(.sp),s.items(.growth),0..)|sp,growth,i|{
      // how far this plant contains parasites (tiles)
      const r:i32=species.get(sp).contain;
      if(r==0 or growth<1)continue;
      // its footprint
      const f=p.extent(i);
      // the tile row being read
      var y=f.y-r;
      while(y<f.y+f.size+r):(y+=1){
        // the tile column being read
        var x=f.x-r;
        while(x<f.x+f.size+r):(x+=1){
          // the plant on this tile, if any
          const j=p.at(w,x,y) orelse continue;
          if(species.get(s.items(.sp)[j.idx()]).lineage==.parasitic)e.calm.items[j.idx()]=species.contained;
        }
      }
    }
  }
  /// runs the ecology for `dt` seconds: mana drawn, shared and drained,
  /// growth and essence, health, then the dead removed; returns what happened
  pub fn tick(e:*Ecology,gpa:Allocator,p:*Plants,w:*World,mods:Mods,dt:f32)Allocator.Error!Events{
    // what happened this tick
    var ev:Events=.{};
    if(p.topologyDirty)p.rebuildLinks(w);
    // how many plants there are
    const n=p.len();
    // the light grid first: the structures read their light from it, plants or none
    try e.light.update(gpa,p,w,mods.relays,mods.users,mods.night,dt);
    if(n==0)return ev;
    try e.dm.resize(gpa,n);@memset(e.dm.items,0);
    try e.dh.resize(gpa,n);@memset(e.dh.items,0);
    try e.df.resize(gpa,n);@memset(e.df.items,0);
    try e.contain(gpa,p,w);
    // the containment, light, beam and guard each plant has this tick
    const calm=e.calm.items;
    const lit=e.light.lit.items;
    const beamed=e.light.beamed.items;
    const guarded=e.light.guarded.items;
    // each plant's mana, health and flow deltas
    const dm=e.dm.items;
    const dh=e.dh.items;
    const df=e.df.items;
    // the plant columns
    const s=p.list.slice();
    // each plant's species and the mana it holds
    const sps=s.items(.sp);
    const mana=s.items(.mana);
    // how far grown each is, its own span to maturity, and its health
    const growth=s.items(.growth);
    const span=s.items(.span);
    const health=s.items(.health);
    // the chunk and tile each stands on
    const chunks=s.items(.chunk);
    const tiles=s.items(.tile);
    // the essence each holds, and how much of it is rare
    const essence=s.items(.essence);
    const rare=s.items(.rare);
    // each plant's two neighbour rings
    const n1=s.items(.n1);
    const n2=s.items(.n2);
    for(0..n)|i|{
      // this plant's species, lineage and mana cap, and how full it is
      const sp=species.get(sps[i]);
      const lin=sp.lineage;
      const cap=sp.manaCap;
      const fill=mana[i]/cap;
      // ley field under the plant: draw, then let it slowly refill.
      // the chunk and tile it stands on
      const c=chunks[i];
      const t=tiles[i];
      if(sp.floating){
        // floaters never touch the ley: they drink the night sky; a
        // catcher only over a shining starlit patch, as much as it is rich
        const over=if(!sp.catches)1 else if(mods.starlit)c.starYield[t]else 0;
        dm[i]+=sp.leyDraw*(dayDrink+(1-dayDrink)*mods.night)*over*dt;
      }else{
        // the ley it draws this tick, at most what the tile holds
        const got=@min(c.ley[t],sp.leyDraw*dt);
        c.ley[t]+=(c.leyCap[t]-c.ley[t])*leyRefill*dt-got;
        dm[i]+=got;
        // the ground's water it drinks, at most what the tile holds
        const drunk=@min(c.water[t],sp.waterDraw*dt);
        c.water[t]-=drunk;
        dm[i]+=drunk*waterMana;
      }
      // how many of its kin it is linked with
      var kin:f32=0;
      if(sp.share>0){
        // how many rings it shares with
        const rings=if(mods.link2)@as(usize,2)else 1;
        for(0..rings)|ring|{
          // the ring being shared with
          const ns:[]const Id=if(ring==0)&n1[i]else&n2[i];
          for(ns)|id|{
            if(id==.none)break;
            // this neighbour's slot and species
            const j=id.idx();
            const sj=species.get(sps[j]);
            if(sj.lineage==.parasitic)continue;
            kin+=1;
            // how much fuller this plant is than its neighbour
            const diff=fill-mana[j]/sj.manaCap;
            if(diff<=0)continue;
            // the mana passed on this tick
            const f=diff*sp.share*cap*shareRate*dt;
            dm[i]-=f;dm[j]+=f;
            df[i]+=f;df[j]+=f;
            dh[j]+=shareHeal*dt;
          }
        }
      }
      if(sp.drain>0){
        for(n1[i])|id|{
          if(id==.none)break;
          // this neighbour's slot and lineage
          const j=id.idx();
          const lj=species.get(sps[j]).lineage;
          // whether it is prey: a parasite takes from non-parasites, a convergent
          // or radiant one from parasites
          const prey=switch(lin){
            .parasitic=>lj!=.parasitic,
            .convergent,.radiant=>lj==.parasitic,
            .symbiotic=>false,
          };
          if(!prey)continue;
          // the mana it takes this tick, calmed by containment
          const take=@min(mana[j],sp.drain*mods.drainMult*calm[i]*dt);
          dm[j]-=take;dm[i]+=take*drainKeep;
          df[i]+=take;df[j]+=take;
          if(mana[j]<starved*species.get(sps[j]).manaCap)dh[j]-=starveHurt*dt;
        }
      }
      // short of a quarter of the light it draws, a plant halts and withers
      if(sp.draw>0 and lit[i]<light.needAt){
        dh[i]-=unpoweredWither*dt;
        continue;
      }
      // a night beam on it: overdriven, it grows and yields faster, and,
      // unguarded, it slowly dies of it
      const beam=beamed[i];
      if(beam>0 and !guarded[i])dh[i]-=overdriveHurt*beam*mods.overdriveHarm*dt;
      // how fast it lives: by the light it draws, and the beam's overdrive
      const pace=(if(sp.draw>0)lit[i]else 1)*(1+overdriveBoost*beam);
      // on ground the rain has not soaked, one that needs it halts and withers
      if(sp.needsSoak and c.wet[t]<soakedAt){
        dh[i]-=dryWither*dt;
        continue;
      }
      if(growth[i]<1){
        // how long it takes to mature at full mana
        const mature=if(span[i]>0)span[i]else sp.matureTime;
        growth[i]=@min(1,growth[i]+dt/mature*(growMin+(1-growMin)*fill)*health[i]*(1+kinGrow*kin)*pace);
      }else{
        // mana condenses into essence held by the plant until harvested.
        // how much essence it has room for, and the mana condensed into it
        const room=cap-essence[i];
        const conv=@min(@min(mana[i],sp.yield*fill*dt*pace),room);
        dm[i]-=conv;
        // the essence it gains, a share of it rare under a beam
        const gained=@min(cap-essence[i],conv*mods.yieldMult[@intFromEnum(sps[i])]*(1+kinYield*kin));
        essence[i]+=gained;
        if(beam>0)rare[i]=@min(essence[i],rare[i]+gained*rareShare);
      }
      // (an unguarded plant under a beam never heals: it burns)
      dh[i]+=if(fill<empty and growth[i]>=1)-fadeTime*dt else if(beam>0 and !guarded[i])0 else heal*dt;
    }
    // each plant's shown flow
    const flow=s.items(.flow);
    e.dead.clearRetainingCapacity();
    for(0..n)|i|{
      // this plant's mana cap
      const cap=species.get(sps[i]).manaCap;
      mana[i]=m.clamp(mana[i]+dm[i],0,cap);
      health[i]=m.clamp(health[i]+dh[i],0,1);
      flow[i]+=(df[i]/dt/cap*flowGain-flow[i])*flowEase;
      if(health[i]<=0)try e.dead.append(gpa,.of(i));
    }
    // the dead to remove, from the last back so slots stay true
    var k=e.dead.items.len;
    while(k>0){k-=1;p.remove(w,e.dead.items[k]);}
    ev.died=@intCast(e.dead.items.len);
    return ev;
  }
};
/// tests run the sim at 60 Hz (the sim never imports game's `play.tickTime`)
const testHz=60;
/// one test tick (s)
const testDt:f32=1.0/m.f(testHz);
test"symbiotes share, parasites drain"{
  // the test allocator
  const gpa=testing.allocator;
  // a small loaded world
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // force a fertile strip for a deterministic test
  // the chunk at the origin
  const c=w.chunkOfTile(0,0).?;
  for(0..4)|x|c.kind[x]=.soil;
  // the plants, and the ecology over them
  var p:Plants=.{};
  defer p.deinit(gpa);
  var eco:Ecology=.{};
  defer eco.deinit(gpa);
  try testing.expect(try p.place(gpa,&w,0,0,.lumenroot,0.1));
  try testing.expect(try p.place(gpa,&w,1,0,.thornleech,0.2));
  for(0..testHz*30)|_|_=try eco.tick(gpa,&p,&w,.{},testDt);
  // each plant's essence
  const es=p.list.items(.essence);
  try testing.expect(p.len()<2 or es[0]+es[1]>0);
  try testing.expect(p.list.items(.flow)[0]>0 or p.len()<2);
}
test"a mature confluence halves parasite drain within 3 tiles"{
  // the test allocator
  const gpa=testing.allocator;
  // the mana the root loses in each case
  var loss:m.Vice(f32,3)=undefined;
  // no confluence; a mature one 2 tiles from the leech; one 4 tiles away
  for([_]?i32{null,3,5},0..)|at,k|{
    // a small loaded world
    var w=World.init(gpa,5);
    defer w.deinit();
    try w.stream(.{.x=0,.y=0},1,100);
    // the chunk at the origin, made soil
    const c=w.chunkOfTile(0,0).?;
    for(0..2)|y|for(0..8)|x|{c.kind[y*ck.sizeTiles+x]=.soil;c.height[y*ck.sizeTiles+x]=1;};
    // the plants, and the ecology over them
    var p:Plants=.{};
    defer p.deinit(gpa);
    var eco:Ecology=.{};
    defer eco.deinit(gpa);
    try testing.expect(try p.placeEx(gpa,&w,0,0,.{.x=0,.y=0,.chunk=undefined,.tile=undefined,.sp=.lumenroot,.seed=0,.mana=5}));
    try testing.expect(try p.place(gpa,&w,1,0,.thornleech,0));
    if(at)|x|try testing.expect(try p.placeEx(gpa,&w,x,0,.{.x=x,.y=0,.chunk=undefined,.tile=undefined,.sp=.confluence,.seed=0,.growth=1}));
    // the leech's 2-tile neighbourhood keeps the root's ley draw identical in every case
    _=try eco.tick(gpa,&p,&w,.{},0.1);
    loss[k]=5-p.list.items(.mana)[0];
  }
  // what the leech drains in a tenth of a second, uncontained
  const full=species.get(.thornleech).drain*0.1;
  try testing.expectApproxEqAbs(full*(1-species.contained),loss[0]-loss[1],1e-4);
  try testing.expectApproxEqAbs(loss[0],loss[2],1e-4);
}
test"a vesper lives on a solcyriphon's light and withers out of it"{
  // the test allocator
  const gpa=testing.allocator;
  // a small loaded world
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // the chunk at the origin
  const c=w.chunkOfTile(0,0).?;
  for(0..3)|y|for(0..20)|x|{c.kind[y*ck.sizeTiles+x]=.soil;};
  // the plants, and the ecology over them
  var p:Plants=.{};
  defer p.deinit(gpa);
  var eco:Ecology=.{};
  defer eco.deinit(gpa);
  // a grown solcyriphon over (2,0), a vesper beside it, another far off
  try testing.expect(try p.placeEx(gpa,&w,2,0,.{.x=2,.y=0,.chunk=undefined,.tile=undefined,.sp=.solcyriphon,.seed=0.1,.growth=1}));
  try testing.expect(try p.place(gpa,&w,3,0,.vesper,0.2));
  try testing.expect(try p.place(gpa,&w,15,0,.vesper,0.4));
  for(0..testHz*5)|_|_=try eco.tick(gpa,&p,&w,.{},testDt);
  // the near one grew, healthy; the far one stood still and withered
  const near=p.at(&w,3,0).?.idx();
  const far=p.at(&w,15,0).?.idx();
  try testing.expect(p.list.items(.growth)[near]>0 and p.list.items(.health)[near]>0.99);
  try testing.expectEqual(@as(f32,0),p.list.items(.growth)[far]);
  try testing.expect(p.list.items(.health)[far]<0.8);
}
test"a night beam overdrives the plant under it, steeping rare yield, and a halcyra keeps it alive"{
  // the test allocator
  const gpa=testing.allocator;
  // grown and healthy after a night's beam, rare yield, with and without a halcyra
  var after:[2]m.Vice(f32,3)=undefined;
  for(0..2)|k|{
    // a small loaded world
    var w=World.init(gpa,5);
    defer w.deinit();
    try w.stream(.{.x=0,.y=0},1,100);
    // the chunk at the origin, soil
    const c=w.chunkOfTile(0,0).?;
    for(0..6)|y|for(0..6)|x|{c.kind[y*ck.sizeTiles+x]=.soil;};
    // the plants, and the ecology over them
    var p:Plants=.{};
    defer p.deinit(gpa);
    var eco:Ecology=.{};
    defer eco.deinit(gpa);
    // a solcyriphon over a grown lumenroot, and in the second garden a halcyra beside it
    try testing.expect(try p.placeEx(gpa,&w,2,2,.{.x=2,.y=2,.chunk=undefined,.tile=undefined,.sp=.solcyriphon,.seed=0.1,.growth=1}));
    try testing.expect(try p.placeEx(gpa,&w,2,2,.{.x=2,.y=2,.chunk=undefined,.tile=undefined,.sp=.lumenroot,.seed=0.2,.growth=1}));
    if(k==1)try testing.expect(try p.placeEx(gpa,&w,3,2,.{.x=3,.y=2,.chunk=undefined,.tile=undefined,.sp=.halcyra,.seed=0.3,.growth=1}));
    for(0..testHz*60)|_|_=try eco.tick(gpa,&p,&w,.{.night=1},testDt);
    // the lumenroot
    const r=p.at(&w,2,2).?.idx();
    after[k]=.{p.list.items(.health)[r],p.list.items(.rare)[r],p.list.items(.essence)[r]};
  }
  // unguarded it is harmed and rare yield is steeping; guarded, unharmed
  try testing.expect(after[0][0]<0.99 and after[0][1]>0);
  try testing.expect(after[1][0]>0.99 and after[1][1]>0);
}
test"a mire lily drinks soaked ground and withers on dry"{
  // the test allocator
  const gpa=testing.allocator;
  // its growth, health and the tile's water left, on soaked then dry ground
  var after:[2]m.Vice(f32,3)=undefined;
  for([_]f32{1,0},0..)|wetness,k|{
    // a small loaded world
    var w=World.init(gpa,5);
    defer w.deinit();
    try w.stream(.{.x=0,.y=0},1,100);
    // the chunk at the origin, its first tile soil with water, wet as this case
    const c=w.chunkOfTile(0,0).?;
    c.kind[0]=.soil;
    c.water[0]=0.8;
    c.wet[0]=wetness;
    // the lily, and the ecology over it
    var p:Plants=.{};
    defer p.deinit(gpa);
    var eco:Ecology=.{};
    defer eco.deinit(gpa);
    try testing.expect(try p.place(gpa,&w,0,0,.mireLily,0.1));
    for(0..testHz*20)|_|_=try eco.tick(gpa,&p,&w,.{},testDt);
    after[k]=.{p.list.items(.growth)[0],p.list.items(.health)[0],c.water[0]};
  }
  // soaked: it grew and drank the ground's water, healthy
  try testing.expect(after[0][0]>0 and after[0][1]>0.99 and after[0][2]<0.8);
  // dry: it stood still and withered
  try testing.expectEqual(@as(f32,0),after[1][0]);
  try testing.expect(after[1][1]<0.99);
}
test"a halyriphon catches starlight only over a shining starlit patch"{
  // the test allocator
  const gpa=testing.allocator;
  // the mana each held after a night: over a patch, off one, over one gone dark
  var held:m.Vice(f32,3)=undefined;
  for(0..3)|k|{
    // a small loaded world
    var w=World.init(gpa,5);
    defer w.deinit();
    try w.stream(.{.x=0,.y=0},1,100);
    // the chunk at the origin: its tile (2, 2) in a patch (but in the second case)
    const c=w.chunkOfTile(0,0).?;
    @memset(&c.starYield,0);
    if(k!=1)c.starYield[2*ck.sizeTiles+2]=1;
    // the plants, and the ecology over them
    var p:Plants=.{};
    defer p.deinit(gpa);
    var eco:Ecology=.{};
    defer eco.deinit(gpa);
    // a grown halyriphon over the tile, its mana empty
    try testing.expect(try p.placeEx(gpa,&w,2,2,.{.x=2,.y=2,.chunk=undefined,.tile=undefined,.sp=.driftwisp,.seed=0.1,.growth=1,.mana=0}));
    for(0..testHz*10)|_|_=try eco.tick(gpa,&p,&w,.{.night=1,.starlit=k!=2},testDt);
    held[k]=p.list.items(.mana)[0]+p.list.items(.essence)[0];
  }
  try testing.expect(held[0]>0);
  try testing.expectEqual(@as(f32,0),held[1]);
  try testing.expectEqual(@as(f32,0),held[2]);
}
