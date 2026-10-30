//! convergence: where a mature symbiote and a mature parasite meet, within
//! two tiles of each other or joined by a chain of conduits, a confluence
//! takes root on free ground beside them. Discovery-gated, never sown.
//!
//! The search is spread over ticks (a fixed budget of plants per tick) so a
//! dense garden never stalls a frame.
const lib=@import("../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const testing=std.testing;
const m=lib.engine.core.math;
const rng=lib.engine.core.rng;
const ck=lib.ck;
const World=lib.world.World;
const species=lib.species;
const plantsMod=lib.plants;
const st=lib.structures;
const prog=lib.progression;
const txt=lib.txt;
const Plants=plantsMod.Plants;
const PlantId=plantsMod.Id;
const Rect=plantsMod.Rect;
/// what grows where the lineages meet.
pub const hybrid=species.Id.confluence;
/// tiles apart that still count as meeting.
const meetCount=2;
/// plants examined per tick.
const budget=128;
/// a conduit chain longer than this is not followed (and never loops).
const maxChain=256;
/// growth time relative to the slower parent.
const spanScale=1.5;
pub const Seeker=struct{
  /// next plant to examine
  cursor:usize=0,
  /// "no room" is said once per session
  cramped:bool=false,
  pub fn tick(sk:*Seeker,gpa:Allocator,w:*World,p:*Plants,ss:*st.Structures,g:*prog.Progression)Allocator.Error!void{
    if(p.topologyDirty)p.rebuildLinks(w);
    const n=p.len();
    if(sk.cursor>=n)sk.cursor=0;
    // lineage structures side by side are witnessed once per sweep (after
    // the wrap: a sweep ends with the cursor at `n`, never at 0)
    if(sk.cursor==0)ss.meetings(g);
    if(n==0)return;
    // conduit chains are few: follow them all once per sweep
    if(sk.cursor==0)for(ss.list.items)|*s|{
      if(!s.def().carrier)continue;
      const pair=chain(w,p,ss,s) orelse continue;
      if(try sk.meet(gpa,w,p,g,pair[0],pair[1]))return;
    };
    const end=@min(n,sk.cursor+budget);
    defer sk.cursor=end;
    for(sk.cursor..end)|i|{
      if(!ripe(p,i,.symbiotic))continue;
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
    const at=spot(w,p,p.extent(a),p.extent(b))orelse{
      if(!sk.cramped)g.say(txt.s.msg.lineagesStrain,.{});
      sk.cramped=true;
      return false;
    };
    const span=@max(matureTime(p,a),matureTime(p,b))*spanScale;
    _=try p.placeEx(gpa,w,at[0],at[1],.{
      .x=at[0],.y=at[1],.chunk=undefined,.tile=undefined,.sp=hybrid,
      .seed=rng.unit(rng.hash2(0xC0F1,at[0],at[1])),.span=span,
    });
    g.say(txt.s.msg.confluenceRoots,.{});
    return true;
  }
};
fn ripe(p:*const Plants,i:usize,lin:species.Lineage)bool{
  const s=p.list.slice();
  return s.items(.growth)[i]>=1 and species.get(s.items(.sp)[i]).lineage==lin;
}
fn matureTime(p:*const Plants,i:usize)f32{
  const span=p.list.items(.span)[i];
  return if(span>0)span else species.get(p.list.items(.sp)[i]).matureTime;
}
/// is either parent already held by a confluence (within its containment)?
fn contained(p:*const Plants,a:usize,b:usize)bool{
  const r=species.get(hybrid).contain;
  const ea=p.extent(a);
  const eb=p.extent(b);
  for(p.list.items(.sp),0..)|sp,k|{
    if(sp!=hybrid)continue;
    const ek=p.extent(k);
    if(ek.gap(ea)<=r or ek.gap(eb)<=r)return true;
  }
  return false;
}
/// the free ground for a confluence nearest both parents, within the
/// symbiote's containment reach so it holds the pair once grown.
fn spot(w:*const World,p:*const Plants,a:Rect,b:Rect)?[2]i32{
  const size=species.get(hybrid).size;
  const r:i32=species.get(hybrid).contain;
  var best:?[2]i32=null;
  var score:i32=m.maxInt(i32);
  var y=a.y-r-size+1;
  while(y<a.y+a.size+r):(y+=1){
    var x=a.x-r-size+1;
    while(x<a.x+a.size+r):(x+=1){
      const e:Rect=.{.x=x,.y=y,.size=size};
      if(e.gap(a)>r)continue;
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
  const v=m.dirVec(s.dir);
  const from=p.at(w,s.x-v.x,s.y-v.z) orelse return null;
  var cur=s;
  for(0..maxChain)|_|{
    const cv=m.dirVec(cur.dir);
    const fx=cur.x+cv.x;
    const fz=cur.y+cv.z;
    if(ss.at(w,fx,fz))|j|{
      const next=ss.get(j);
      if(!next.def().carrier)return null;
      const nv=m.dirVec(next.dir);
      if(nv.x==-cv.x and nv.z==-cv.z)return null;
      cur=next;
      continue;
    }
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
const Garden=struct{
  w:World,
  p:Plants=.{},
  ss:st.Structures=.{},
  g:prog.Progression=.{},
  sk:Seeker=.{},
  fn init(gpa:Allocator,side:usize)Allocator.Error!Garden{
    var gd:Garden=.{.w=World.init(gpa,5)};
    try gd.w.stream(.{.x=0,.y=0},1,100);
    const c=gd.w.chunkOfTile(0,0).?;
    for(0..side)|y|for(0..side)|x|{
      c.kind[y*ck.sizeTiles+x]=.soil;
      c.height[y*ck.sizeTiles+x]=1;
      c.res[y*ck.sizeTiles+x]=0;
    };
    return gd;
  }
  fn deinit(gd:*Garden,gpa:Allocator)void{
    gd.p.deinit(gpa);
    gd.ss.deinit(gpa);
    gd.w.deinit();
  }
  fn mature(gd:*Garden,gpa:Allocator,x:i32,y:i32,sp:species.Id)!void{
    try testing.expect(try gd.p.placeEx(gpa,&gd.w,x,y,.{.x=x,.y=y,.chunk=undefined,.tile=undefined,.sp=sp,.seed=0.5,.growth=1,.mana=5}));
  }
  fn sweep(gd:*Garden,gpa:Allocator)Allocator.Error!void{
    for(0..4)|_|try gd.sk.tick(gpa,&gd.w,&gd.p,&gd.ss,&gd.g);
  }
  fn hybrids(gd:*const Garden)usize{
    var k:usize=0;
    for(gd.p.list.items(.sp))|sp|if(sp==hybrid){k+=1;};
    return k;
  }
};
test"mature lineages within two tiles grow one confluence"{
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
  const h=gd.p.len()-1;
  const e=gd.p.extent(h);
  try testing.expectEqual(@as(u8,2),e.size);
  var fp=m.footprint(e.x,e.y,e.size);
  while(fp.next())|p|try testing.expectEqual(h,gd.p.at(&gd.w,p[0],p[1]).?.idx());
  try testing.expect(!gd.p.canPlace(&gd.w,e.x+1,e.y+1,.lumenroot));
  try testing.expect(e.gap(gd.p.extent(0))<=species.get(hybrid).contain);
  // it grows for 1.5x the slower parent: mature after that, not before
  const span=species.get(.lumenroot).matureTime*spanScale;
  try testing.expectApproxEqAbs(span,gd.p.list.items(.span)[h],1e-4);
  var eco:lib.ecology.Ecology=.{};
  defer eco.deinit(gpa);
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
  const gpa=testing.allocator;
  var gd=try Garden.init(gpa,12);
  defer gd.deinit(gpa);
  try gd.mature(gpa,1,1,.lumenroot);
  try gd.mature(gpa,9,1,.thornleech);
  try gd.sweep(gpa);
  try testing.expectEqual(@as(usize,0),gd.hybrids());
  // lumenroot -> 7 conduits (facing +x) -> thornleech
  var x:i32=2;
  while(x<9):(x+=1)try testing.expect(try gd.ss.place(gpa,&gd.w,x,1,.conduit,0,0));
  try testing.expectEqual(@as(i32,1),m.dirVec(0).x);
  try gd.sweep(gpa);
  try testing.expectEqual(@as(usize,1),gd.hybrids());
}
test"no room, no confluence"{
  const gpa=testing.allocator;
  var gd=try Garden.init(gpa,12);
  defer gd.deinit(gpa);
  // a 3x2 patch of fertile ground in bare stone (well inside the chunk, so
  // the search never reaches generated land): no 2x2 spot beside the pair
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
