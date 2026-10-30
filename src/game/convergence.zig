//! convergence: where a mature symbiote and a mature parasite meet, within
//! two tiles of each other or joined by a chain of conduits, a confluence
//! takes root on free ground beside them. Discovery-gated, never sown.
//!
//! The search is spread over ticks (a fixed budget of plants per tick) so a
//! dense garden never stalls a frame.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator a new confluence's plant row may need
const Allocator=std.mem.Allocator;
/// the test harness
const testing=std.testing;
/// all the maths: directions, tiles, extremes
const m=lib.engine.core.math;
/// the deterministic hashes a confluence's seed is drawn from
const rng=lib.engine.core.rng;
/// the chunk grid: tile kinds and sizes (tests)
const ck=lib.ck;
/// the garden's streamed world of chunks
const World=lib.world.World;
/// the species registry: lineages, sizes, containment, maturing times
const species=lib.species;
/// the plant list module
const plantsMod=lib.plants;
/// the structures registry: conduits and the lineage structures' meetings
const st=lib.structures;
/// the research tree, where the meeting is witnessed
const prog=lib.progression;
/// every player-facing string
const txt=lib.txt;
/// every plant in the garden, as columns
const Plants=plantsMod.Plants;
/// one plant's handle in that list
const PlantId=plantsMod.Id;
/// a square of tiles a plant covers: corner and size
const Rect=plantsMod.Rect;
/// what grows where the lineages meet.
pub const hybrid=species.Id.confluence;
/// how many tiles apart a symbiote and a parasite may stand and still meet
const meetCount=2;
/// how many plants are examined each tick
const budget=128;
/// how many conduits a chain may run before it is given up on (so a loop never hangs)
const maxChain=256;
/// how long a confluence takes to grow, as a multiple of the slower parent's time
const spanScale=1.5;
/// the sweep that looks for meetings, a little each tick: where it is up
/// to and whether it has complained of no room
pub const Seeker=struct{
  /// next plant to examine
  cursor:usize=0,
  /// "no room" is said once per session
  cramped:bool=false,
  /// looks over the next `budget` plants for a mature symbiote beside a
  /// mature parasite (and, once a sweep, follows every conduit chain and
  /// witnesses lineage structures side by side); at most one confluence a tick
  pub fn tick(sk:*Seeker,gpa:Allocator,w:*World,p:*Plants,ss:*st.Structures,g:*prog.Progression)Allocator.Error!void{
    if(p.topologyDirty)p.rebuildLinks(w);
    // how many plants there are
    const n=p.len();
    if(sk.cursor>=n)sk.cursor=0;
    // lineage structures side by side are witnessed once per sweep (after
    // the wrap: a sweep ends with the cursor at `n`, never at 0)
    if(sk.cursor==0)ss.meetings(g);
    if(n==0)return;
    // conduit chains are few: follow them all once per sweep
    if(sk.cursor==0)for(ss.list.items)|*s|{
      if(!s.def().carrier)continue;
      // the ripe symbiote and parasite at the chain's two ends, if any
      const pair=chain(w,p,ss,s) orelse continue;
      if(try sk.meet(gpa,w,p,g,pair[0],pair[1]))return;
    };
    // where this tick's share of the sweep ends
    const end=@min(n,sk.cursor+budget);
    defer sk.cursor=end;
    for(sk.cursor..end)|i|{
      if(!ripe(p,i,.symbiotic))continue;
      // the plant list's columns
      const s=p.list.slice();
      for([2][]const PlantId{&s.items(.n1)[i],&s.items(.n2)[i]})|ring|for(ring)|id|{
        if(id==.none)break;
        if(!ripe(p,id.idx(),.parasitic))continue;
        // one spawn per tick: placing a plant invalidates the links
        if(try sk.meet(gpa,w,p,g,i,id.idx()))return;
        break;
      };
    }
  }
  /// a symbiote `a` and a parasite `b` have met. Returns whether a confluence
  /// took root.
  fn meet(sk:*Seeker,gpa:Allocator,w:*World,p:*Plants,g:*prog.Progression,a:usize,b:usize)Allocator.Error!bool{
    g.discover(.convergence);
    if(contained(p,a,b))return false;
    // the free 2x2 ground nearest both; none, and the lineages strain
    const at=spot(w,p,p.extent(a),p.extent(b))orelse{
      if(!sk.cramped)g.say(txt.s.msg.lineagesStrain,.{});
      sk.cramped=true;
      return false;
    };
    // how long the confluence takes to grow: half again the slower parent
    const span=@max(matureTime(p,a),matureTime(p,b))*spanScale;
    _=try p.placeEx(gpa,w,at[0],at[1],.{
      .x=at[0],.y=at[1],.chunk=undefined,.tile=undefined,.sp=hybrid,
      .seed=rng.unit(rng.hash2(0xC0F1,at[0],at[1])),.span=span,
    });
    g.say(txt.s.msg.confluenceRoots,.{});
    return true;
  }
};
/// whether plant `i` is fully grown and of lineage `lin`
fn ripe(p:*const Plants,i:usize,lin:species.Lineage)bool{
  // the plant list's columns
  const s=p.list.slice();
  return s.items(.growth)[i]>=1 and species.get(s.items(.sp)[i]).lineage==lin;
}
/// how long plant `i` takes to mature: its own span if it has one, else its species'
fn matureTime(p:*const Plants,i:usize)f32{
  // its own growing time (0: none of its own)
  const span=p.list.items(.span)[i];
  return if(span>0)span else species.get(p.list.items(.sp)[i]).matureTime;
}
/// is either parent already held by a confluence (within its containment)?
fn contained(p:*const Plants,a:usize,b:usize)bool{
  // how far a confluence's hold reaches, and the parents' squares
  const r=species.get(hybrid).contain;
  const ea=p.extent(a);
  const eb=p.extent(b);
  for(p.list.items(.sp),0..)|sp,k|{
    if(sp!=hybrid)continue;
    // the confluence's square
    const ek=p.extent(k);
    if(ek.gap(ea)<=r or ek.gap(eb)<=r)return true;
  }
  return false;
}
/// the free ground for a confluence nearest both parents, within the
/// symbiote's containment reach so it holds the pair once grown.
fn spot(w:*const World,p:*const Plants,a:Rect,b:Rect)?[2]i32{
  // a confluence's size, and how far its hold reaches
  const size=species.get(hybrid).size;
  const r:i32=species.get(hybrid).contain;
  // the best spot so far, and its score (lower: nearer both parents)
  var best:?[2]i32=null;
  var score:i32=m.maxInt(i32);
  // the row being tried
  var y=a.y-r-size+1;
  while(y<a.y+a.size+r):(y+=1){
    // the column being tried
    var x=a.x-r-size+1;
    while(x<a.x+a.size+r):(x+=1){
      // the confluence's square if it stood here
      const e:Rect=.{.x=x,.y=y,.size=size};
      if(e.gap(a)>r)continue;
      // its score: how far from both parents
      const sc=e.gap(a)+e.gap(b);
      if(sc>=score or !p.canPlace(w,x,y,hybrid))continue;
      best=.{x,y};
      score=sc;
    }
  }
  return best;
}
/// the plants at either end of a chain of conduits starting at `s`: the one
/// it pulls from and the one the last conduit faces, if they are a mature
/// symbiote and a mature parasite (returned in that order).
fn chain(w:*const World,p:*const Plants,ss:*st.Structures,s:*const st.Structure)?[2]usize{
  // the way the first conduit faces, and the plant behind it it pulls from
  const v=m.dirVec(s.dir);
  const from=p.at(w,s.x-v.x,s.y-v.z) orelse return null;
  // the conduit reached so far
  var cur=s;
  for(0..maxChain)|_|{
    // its facing, and the tile in front of it
    const cv=m.dirVec(cur.dir);
    const fx=cur.x+cv.x;
    const fz=cur.y+cv.z;
    if(ss.at(w,fx,fz))|j|{
      // the conduit in front, carrying on the chain
      const next=ss.get(j);
      if(!next.def().carrier)return null;
      // its facing (one facing back makes a dead end)
      const nv=m.dirVec(next.dir);
      if(nv.x==-cv.x and nv.z==-cv.z)return null;
      cur=next;
      continue;
    }
    // the plant at the chain's end, and both plants' rows
    const to=p.at(w,fx,fz) orelse return null;
    const a=from.idx();
    const b=to.idx();
    if(ripe(p,a,.symbiotic) and ripe(p,b,.parasitic))return.{a,b};
    if(ripe(p,b,.symbiotic) and ripe(p,a,.parasitic))return.{b,a};
    return null;
  }
  return null;
}
// ---- tests ----
/// a small test garden: a world with fertile ground, its plants,
/// structures, knowledge and a sweep
const Garden=struct{
  /// the world, one chunk streamed round the origin
  w:World,
  /// the plants in it
  p:Plants=.{},
  /// the structures in it
  ss:st.Structures=.{},
  /// what has been learned and witnessed
  g:prog.Progression=.{},
  /// the sweep under test
  sk:Seeker=.{},
  /// makes a garden whose first `side` x `side` tiles are flat, bare soil
  fn init(gpa:Allocator,side:usize)Allocator.Error!Garden{
    // the garden, with one ring of chunks streamed in
    var gd:Garden=.{.w=World.init(gpa,5)};
    try gd.w.stream(.{.x=0,.y=0},1,100);
    // the chunk at the origin
    const c=gd.w.chunkOfTile(0,0).?;
    for(0..side)|y|for(0..side)|x|{
      c.kind[y*ck.sizeTiles+x]=.soil;
      c.height[y*ck.sizeTiles+x]=1;
      c.res[y*ck.sizeTiles+x]=0;
    };
    return gd;
  }
  /// frees the garden's plants, structures and world
  fn deinit(gd:*Garden,gpa:Allocator)void{
    gd.p.deinit(gpa);
    gd.ss.deinit(gpa);
    gd.w.deinit();
  }
  /// puts down a fully grown plant of `sp` at a tile, with mana to spare
  fn mature(gd:*Garden,gpa:Allocator,x:i32,y:i32,sp:species.Id)!void{
    try testing.expect(try gd.p.placeEx(gpa,&gd.w,x,y,.{.x=x,.y=y,.chunk=undefined,.tile=undefined,.sp=sp,.seed=0.5,.growth=1,.mana=5}));
  }
  /// runs four ticks: enough to sweep the small garden whole
  fn sweep(gd:*Garden,gpa:Allocator)Allocator.Error!void{
    for(0..4)|_|try gd.sk.tick(gpa,&gd.w,&gd.p,&gd.ss,&gd.g);
  }
  /// how many confluences have grown
  fn hybrids(gd:*const Garden)usize{
    // the count so far
    var k:usize=0;
    for(gd.p.list.items(.sp))|sp|if(sp==hybrid){k+=1;};
    return k;
  }
};
test"mature lineages within two tiles grow one confluence"{
  // the test allocator, and a fresh 10x10 garden
  const gpa=testing.allocator;
  var gd=try Garden.init(gpa,10);
  defer gd.deinit(gpa);
  try gd.mature(gpa,2,2,.lumenroot);
  // a seedling parasite does not count yet
  try testing.expect(try gd.p.place(gpa,&gd.w,4,2,.thornleech,0.5));
  try gd.sweep(gpa);
  try testing.expectEqual(@as(usize,0),gd.hybrids());
  gd.p.list.items(.growth)[1]=1;
  try gd.sweep(gpa);
  try testing.expectEqual(@as(usize,1),gd.hybrids());
  try testing.expect(gd.g.found.contains(.convergence));
  // it contains the pair, so no second one grows
  try gd.sweep(gpa);
  try testing.expectEqual(@as(usize,1),gd.hybrids());
  // 2x2: it claims four tiles, all pointing at it
  // the confluence (the newest plant), and its square
  const h=gd.p.len()-1;
  const e=gd.p.extent(h);
  try testing.expectEqual(@as(u8,2),e.size);
  // the walk over every tile of its footprint
  var fp=m.footprint(e.x,e.y,e.size);
  while(fp.next())|p|try testing.expectEqual(h,gd.p.at(&gd.w,p[0],p[1]).?.idx());
  try testing.expect(!gd.p.canPlace(&gd.w,e.x+1,e.y+1,.lumenroot));
  try testing.expect(e.gap(gd.p.extent(0))<=species.get(hybrid).contain);
  // it grows for 1.5x the slower parent: mature after that, not before
  // how long it should take: half again the lumenroot's maturing time
  const span=species.get(.lumenroot).matureTime*spanScale;
  try testing.expectApproxEqAbs(span,gd.p.list.items(.span)[h],1e-4);
  // the living world's tick, run on the garden
  var eco:lib.ecology.Ecology=.{};
  defer eco.deinit(gpa);
  // a frame's step, and seconds grown so far
  const dt:f32=1.0/30.0;
  var t:f32=0;
  // full mana and health: growth is exactly 1 / span per second
  while(gd.p.list.items(.growth)[h]<1):(t+=dt){
    gd.p.list.items(.mana)[h]=species.get(hybrid).manaCap;
    gd.p.list.items(.health)[h]=1;
    _=try eco.tick(gpa,&gd.p,&gd.w,.{},dt);
    try testing.expect(t<span*1.2);
  }
  try testing.expect(t>span*0.85);
}
test"lineages too far apart meet only through a conduit chain"{
  // the test allocator, and a fresh 12x12 garden
  const gpa=testing.allocator;
  var gd=try Garden.init(gpa,12);
  defer gd.deinit(gpa);
  try gd.mature(gpa,1,1,.lumenroot);
  try gd.mature(gpa,9,1,.thornleech);
  try gd.sweep(gpa);
  try testing.expectEqual(@as(usize,0),gd.hybrids());
  // lumenroot -> 7 conduits (facing +x) -> thornleech
  // the next conduit's column
  var x:i32=2;
  while(x<9):(x+=1)try testing.expect(try gd.ss.place(gpa,&gd.w,x,1,.conduit,0,0));
  try testing.expectEqual(@as(i32,1),m.dirVec(0).x);
  try gd.sweep(gpa);
  try testing.expectEqual(@as(usize,1),gd.hybrids());
}
test"no room, no confluence"{
  // the test allocator, and a fresh 12x12 garden
  const gpa=testing.allocator;
  var gd=try Garden.init(gpa,12);
  defer gd.deinit(gpa);
  // a 3x2 patch of fertile ground in bare stone (well inside the chunk, so
  // the search never reaches generated land): no 2x2 spot beside the pair
  // the chunk at the origin
  const c=gd.w.chunkOfTile(0,0).?;
  for(0..12)|y|for(0..12)|xx|{c.kind[y*ck.sizeTiles+xx]=.stone;};
  for(5..7)|y|for(5..8)|xx|{c.kind[y*ck.sizeTiles+xx]=.soil;};
  try gd.mature(gpa,5,5,.lumenroot);
  try gd.mature(gpa,7,6,.thornleech);
  try gd.sweep(gpa);
  try testing.expectEqual(@as(usize,0),gd.hybrids());
  try testing.expect(gd.sk.cramped);
}
test"lineage structures grown side by side are witnessed, once each"{
  // the test allocator, and a fresh 12x12 garden
  const gpa=testing.allocator;
  var gd=try Garden.init(gpa,12);
  defer gd.deinit(gpa);
  // four tiles apart (three between): not yet
  try testing.expect(try gd.ss.place(gpa,&gd.w,1,1,.loomfern,0,0));
  try testing.expect(try gd.ss.place(gpa,&gd.w,6,1,.lithophage,0,0));
  try gd.sweep(gpa);
  try testing.expect(!gd.g.found.contains(.loomAndStone));
  // a still growing one does not count
  try testing.expect(try gd.ss.place(gpa,&gd.w,4,3,.lithophage,0,0));
  gd.ss.sprout(gd.ss.at(&gd.w,4,3).?);
  try gd.sweep(gpa);
  try testing.expect(!gd.g.found.contains(.loomAndStone));
  gd.ss.get(gd.ss.at(&gd.w,4,3).?).grown=1;
  try gd.sweep(gpa);
  try testing.expect(gd.g.found.contains(.loomAndStone));
  // its study opens, the other pairs' stay dormant
  gd.g.done.insert(.lithophagy);
  gd.g.done.insert(.livingLooms);
  try testing.expectEqual(prog.Status.open,gd.g.status(.wovenStone));
  try testing.expectEqual(prog.Status.locked,gd.g.status(.braidedDrift));
  try testing.expect(!gd.g.found.contains(.braidAndSpore));
}
test"lineage structures are witnessed in a garden that has plants"{
  // the test allocator, and a fresh 12x12 garden
  const gpa=testing.allocator;
  var gd=try Garden.init(gpa,12);
  defer gd.deinit(gpa);
  try gd.mature(gpa,10,10,.lumenroot);
  // sweeps run before the pair stands, as in play
  try gd.sweep(gpa);
  try testing.expect(try gd.ss.place(gpa,&gd.w,1,1,.loomfern,0,0));
  try testing.expect(try gd.ss.place(gpa,&gd.w,3,1,.lithophage,0,0));
  try gd.sweep(gpa);
  try testing.expect(gd.g.found.contains(.loomAndStone));
}
