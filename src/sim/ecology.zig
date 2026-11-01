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
  /// fields of celestial energy held by something other than a bloom (a
  /// completed halo); they power plants as a bloom's field does
  fields:[]const Field=&.{},
};
/// a disc of celestial energy around a tile: every tile within `radius` of it.
pub const Field=struct{
  /// the tile at its centre: world x
  x:i32,
  /// and world y
  y:i32,
  /// how far out it reaches (tiles)
  radius:f32=0,
  /// whether world tile (wx, wy) lies in it
  pub fn holds(fl:Field,wx:i32,wy:i32)bool{
    // how far the tile lies from the centre, across and down
    const dx=wx-fl.x;
    const dy=wy-fl.y;
    return m.f(dx*dx+dy*dy)<=fl.radius*fl.radius;
  }
  /// how far out it reaches on either axis
  pub fn reach(fl:Field)i32{return m.floorTo(i32,fl.radius);}
};
/// what a tick saw happen, for the game to tell of
pub const Events=struct{
  /// how many plants died this tick
  died:u32=0,
};
/// health lost per second by a plant that needs radiance and has none
const unpoweredWither:f32=0.06;
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
/// celestial energy (the blooms'). Blooms link with every bloom of their
/// kind within `link` tiles into networks; a network radiates when it holds
/// at least one mature bloom, and then every bloom in it, growing or not,
/// holds its field. A plant needs only one radiating bloom within range.
/// Worked out each tick from the blooms alone: their links pairwise (they
/// are few), then each radiating bloom's field by the tiles under it, the
/// same way containment is; plants are never scanned against blooms.
pub const Radiance=struct{
  /// per plant: whether it stands in a radiating bloom's field
  powered:std.ArrayList(bool)=.empty,
  /// per plant: whether it is a bloom that radiates
  radiating:std.ArrayList(bool)=.empty,
  /// linked pairs of blooms (drawn as threads of light); `live` when their
  /// network radiates
  links:std.ArrayList(Link)=.empty,
  /// scratch: the blooms' plant indices, their networks (union-find roots)
  /// and which networks hold a mature bloom: the blooms' plant indices
  blooms:std.ArrayList(u32)=.empty,
  /// each bloom's network, as a union-find parent
  root:std.ArrayList(u32)=.empty,
  /// per network: whether it holds a mature bloom
  live:std.ArrayList(bool)=.empty,
  /// two blooms linked: their plants, and whether their network radiates
  pub const Link=struct{
    /// one bloom of the pair
    a:Id,
    /// the other
    b:Id,
    /// whether their network radiates
    live:bool,
  };
  /// frees the scratch and per-plant lists
  pub fn deinit(r:*Radiance,gpa:Allocator)void{
    r.powered.deinit(gpa);r.radiating.deinit(gpa);r.links.deinit(gpa);r.blooms.deinit(gpa);r.root.deinit(gpa);r.live.deinit(gpa);
  }
  /// the root of bloom `i`'s network (union-find, walking up its parents)
  fn find(r:*Radiance,i:u32)u32{
    // the bloom being walked up from
    var k=i;
    while(r.root.items[k]!=k)k=r.root.items[k];
    return k;
  }
  /// works out, for this tick, which plants are powered, which blooms
  /// radiate and which pairs of blooms are linked, from the blooms and the
  /// standing `fields` alone
  pub fn update(r:*Radiance,gpa:Allocator,p:*const Plants,w:*const World,fields:[]const Field)Allocator.Error!void{
    // how many plants there are
    const n=p.len();
    try r.powered.resize(gpa,n);
    @memset(r.powered.items,false);
    try r.radiating.resize(gpa,n);
    @memset(r.radiating.items,false);
    r.links.clearRetainingCapacity();
    r.blooms.clearRetainingCapacity();
    // the plant columns
    const s=p.list.slice();
    // standing fields (halos) power what lies inside them; they are few and
    // small, so their tiles are walked as a bloom's are
    for(fields)|fl|{
      // how far the field reaches either way
      const reach=fl.reach();
      // walks the square of tiles round it
      var it=m.footprint(fl.x-reach,fl.y-reach,@intCast(2*reach+1));
      while(it.next())|t|{
        if(!fl.holds(t[0],t[1]))continue;
        // the plant rooted on this tile, if any
        const j=w.occAt(t[0],t[1]).asPlant() orelse continue;
        r.powered.items[j.idx()]=true;
      }
      // and every floater over a tile it holds (they may share one)
      for(p.floaters.items)|f|{
        if(fl.holds(s.items(.x)[f.idx()],s.items(.y)[f.idx()]))r.powered.items[f.idx()]=true;
      }
    }
    for(s.items(.sp),0..)|sp,i|{
      if(species.get(sp).radiance>0)try r.blooms.append(gpa,@intCast(i));
    }
    // how many blooms there are
    const bn=r.blooms.items.len;
    if(bn==0)return;
    // networks: every pair within linking range joins
    try r.root.resize(gpa,bn);
    for(r.root.items,0..)|*x,k|x.*=@intCast(k);
    // each plant's anchor tile, across and down
    const xs=s.items(.x);
    const ys=s.items(.y);
    for(0..bn)|a|for(a+1..bn)|b|{
      // the two blooms' plants
      const ia=r.blooms.items[a];
      const ib=r.blooms.items[b];
      // how far apart they may stand and still link: the shorter reach of the two
      const reach=@min(species.get(s.items(.sp)[ia]).link,species.get(s.items(.sp)[ib]).link);
      // how far apart they are, across and down
      const dx=m.f(xs[ia]-xs[ib]);
      const dy=m.f(ys[ia]-ys[ib]);
      if(dx*dx+dy*dy>reach*reach)continue;
      try r.links.append(gpa,.{.a=.of(ia),.b=.of(ib),.live=false});
      // the two blooms' networks
      const ra=r.find(@intCast(a));
      const rb=r.find(@intCast(b));
      if(ra!=rb)r.root.items[ra]=rb;
    };
    // a network radiates when it holds a mature bloom
    try r.live.resize(gpa,bn);
    @memset(r.live.items,false);
    for(r.blooms.items,0..)|i,k|{
      if(s.items(.growth)[i]>=1)r.live.items[r.find(@intCast(k))]=true;
    }
    for(r.blooms.items,0..)|i,k|{
      if(r.live.items[r.find(@intCast(k))])r.radiating.items[i]=true;
    }
    for(r.links.items)|*l|l.live=r.radiating.items[l.a.idx()];
    // each radiating bloom powers the plants on the tiles in its field
    for(r.blooms.items)|i|{
      if(!r.radiating.items[i])continue;
      // the bloom's field's radius, and its reach in whole tiles
      const rad=species.get(s.items(.sp)[i]).radiance;
      const reach:i32=@intFromFloat(@ceil(rad));
      // walks the square of tiles round it
      var it=m.footprint(-reach,-reach,@intCast(2*reach+1));
      while(it.next())|d|{
        if(m.f(d[0]*d[0]+d[1]*d[1])>rad*rad)continue;
        // the plant on this tile, if any
        const j=p.at(w,xs[i]+d[0],ys[i]+d[1]) orelse continue;
        r.powered.items[j.idx()]=true;
      }
    }
  }
};
/// the ecology's per-tick scratch: what each plant gains or loses,
/// containment, radiance, and the plants that died
pub const Ecology=struct{
  /// per plant: mana gained or lost this tick
  dm:std.ArrayList(f32)=.empty,
  /// per plant: health gained or lost this tick
  dh:std.ArrayList(f32)=.empty,
  /// per plant: mana moved through it this tick (its flow)
  df:std.ArrayList(f32)=.empty,
  /// per plant: its drain rate after containment (1, or `species.contained`).
  calm:std.ArrayList(f32)=.empty,
  /// the blooms' networks and fields, worked out each tick
  radiance:Radiance=.{},
  /// the plants that died this tick
  dead:std.ArrayList(Id)=.empty,
  /// frees the scratch
  pub fn deinit(e:*Ecology,gpa:Allocator)void{
    e.dm.deinit(gpa);e.dh.deinit(gpa);e.df.deinit(gpa);e.calm.deinit(gpa);e.dead.deinit(gpa);
    e.radiance.deinit(gpa);
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
    if(n==0)return ev;
    try e.dm.resize(gpa,n);@memset(e.dm.items,0);
    try e.dh.resize(gpa,n);@memset(e.dh.items,0);
    try e.df.resize(gpa,n);@memset(e.df.items,0);
    try e.contain(gpa,p,w);
    try e.radiance.update(gpa,p,w,mods.fields);
    // the containment and power each plant has this tick
    const calm=e.calm.items;
    const powered=e.radiance.powered.items;
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
    // the essence each holds
    const essence=s.items(.essence);
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
        // floaters never touch the ley: they drink the night sky
        dm[i]+=sp.leyDraw*(dayDrink+(1-dayDrink)*mods.night)*dt;
      }else{
        // the ley it draws this tick, at most what the tile holds
        const got=@min(c.ley[t],sp.leyDraw*dt);
        c.ley[t]+=(c.leyCap[t]-c.ley[t])*leyRefill*dt-got;
        dm[i]+=got;
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
      // without celestial energy a plant that needs it halts and withers
      if(sp.needsRadiance and !powered[i]){
        dh[i]-=unpoweredWither*dt;
        continue;
      }
      if(growth[i]<1){
        // how long it takes to mature at full mana
        const mature=if(span[i]>0)span[i]else sp.matureTime;
        growth[i]=@min(1,growth[i]+dt/mature*(growMin+(1-growMin)*fill)*health[i]*(1+kinGrow*kin));
      }else{
        // mana condenses into essence held by the plant until harvested.
        // how much essence it has room for, and the mana condensed into it
        const room=cap-essence[i];
        const conv=@min(@min(mana[i],sp.yield*fill*dt),room);
        dm[i]-=conv;
        essence[i]=@min(cap,essence[i]+conv*mods.yieldMult[@intFromEnum(sps[i])]*(1+kinYield*kin));}
      dh[i]+=if(fill<empty and growth[i]>=1)-fadeTime*dt else heal*dt;
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
test"blooms power plants in range, link into networks, and uprooting cuts them off"{
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
  // a mature bloom over (2,0), a vesper (which needs radiance) beside it
  try testing.expect(try p.placeEx(gpa,&w,2,0,.{.x=2,.y=0,.chunk=undefined,.tile=undefined,.sp=.bloom,.seed=0.1,.growth=1}));
  try testing.expect(try p.place(gpa,&w,0,0,.vesper,0.2));
  // a young bloom 7 tiles on (within linking range, out of the first's
  // field) and a second vesper inside only its field
  try testing.expect(try p.placeEx(gpa,&w,9,0,.{.x=9,.y=0,.chunk=undefined,.tile=undefined,.sp=.bloom,.seed=0.3}));
  try testing.expect(try p.place(gpa,&w,11,0,.vesper,0.4));
  // the vesper by the mature bloom, and the one by the young bloom
  const near=p.at(&w,0,0).?;
  const far=p.at(&w,11,0).?;
  for(0..testHz)|_|_=try eco.tick(gpa,&p,&w,.{},testDt);
  // the first draws from the mature bloom; the second from the young one,
  // which radiates because it is linked to a network with a mature bloom
  try testing.expect(eco.radiance.powered.items[near.idx()]);
  try testing.expect(eco.radiance.powered.items[far.idx()]);
  try testing.expectEqual(@as(usize,1),eco.radiance.links.items.len);
  try testing.expect(eco.radiance.links.items[0].live);
  try testing.expect(p.list.items(.growth)[near.idx()]>0);
  // uproot the mature bloom: the young one's network holds no mature bloom
  // now, so nothing radiates, and both vespers halt and wither
  try testing.expect(p.removeAt(&w,2,0));
  // the near vesper's growth before the power goes
  const growthBefore=p.list.items(.growth)[p.at(&w,0,0).?.idx()];
  for(0..testHz*5)|_|_=try eco.tick(gpa,&p,&w,.{},testDt);
  // the two vespers' slots now
  const a=p.at(&w,0,0).?.idx();
  const b=p.at(&w,11,0).?.idx();
  try testing.expect(!eco.radiance.powered.items[a]and!eco.radiance.powered.items[b]);
  try testing.expectEqual(growthBefore,p.list.items(.growth)[a]);
  try testing.expect(p.list.items(.health)[a]<0.8 and p.list.items(.health)[b]<0.8);
  // one bloom left: nothing to link to
  try testing.expectEqual(@as(usize,0),eco.radiance.links.items.len);
}
