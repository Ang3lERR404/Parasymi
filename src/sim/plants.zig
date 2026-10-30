//! plant storage: one struct-of-arrays for every living plant in the world.
//! Rooted plants claim a size x size footprint of tiles (see world occupancy);
//! floating plants claim none: they hang at any free point, off the grid,
//! kept only from crowding another floater, and draw from the tile under them.
//! Neighbour links are cached as plain indices and rebuilt only when the
//! topology changes, so the per-tick ecology loop never touches a hash map.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the engine package
const engine=lib.engine;
/// all the maths: directions, footprint centres
const m=engine.core.math;
/// the chunk: tiles, occupancy and plant ids
const ck=lib.ck;
/// the world module
const world=lib.world;
/// the species registry: each plant's footprint and whether it floats
const species=lib.species;
/// the garden's streamed world, whose tiles plants claim
const World=world.World;
/// a plant's turn (R): the way it faced and when it began
const Turn=lib.turn.Turn;
/// the allocator type the plant lists grow with
const Allocator=std.mem.Allocator;
/// the test allocator and expectations
const testing=std.testing;
/// finds an id in a ring or the floater list
const indexOfScalar=std.mem.indexOfScalar;
/// spreads relinking over the pool (`jobs.each`)
const jobs=engine.core.jobs;
/// a plant's slot: distinct from a structure's
pub const Id=ck.PlantId;
/// what sits on a tile
const Occ=ck.Occ;
/// how placing a plant can fail: out of memory
const Error=Allocator.Error;
/// how many neighbours touch the footprint (ring 1)
pub const r1=12;
/// how many neighbours lie one tile further (ring 2)
pub const r2=20;
/// how close two floaters may hang, centre to centre (m)
pub const floatGap=0.8;
/// how near a cursor ray must pass a floater's float to touch it (m)
pub const floatTouch=0.6;
/// fewer plants than this a thread are relinked in one go
const linksMin=512;
/// a square of tiles: a footprint.
pub const Rect=struct{
  /// its top-left tile's world x
  x:i32,
  /// its top-left tile's world y
  y:i32,
  /// how many tiles across (and down) it is
  size:u8,
  /// Chebyshev tile distance between two squares: 0 when they overlap, 1
  /// when they touch, 2 with one tile between them.
  pub fn gap(a:Rect,b:Rect)i32{
    // how far apart the squares are across, and down
    const dx=@max(0,@max(b.x-(a.x+a.size-1),a.x-(b.x+b.size-1)));
    const dy=@max(0,@max(b.y-(a.y+a.size-1),a.y-(b.y+b.size-1)));
    return@max(dx,dy);
  }
};
/// one living plant: where it stands, what it is, how far grown and how
/// full of mana, and its neighbours
pub const Plant=struct{
  /// anchor tile (top-left of the footprint, or the tile under a floater): its world x
  x:i32,
  /// and its world y
  y:i32,
  /// where it stands across the ground (y 0): a floater's own free point,
  /// a rooted plant's footprint centre
  at:m.V3=@splat(0),
  /// the chunk its anchor tile lies in
  chunk:*ck.Chunk,
  /// its anchor tile's index within that chunk
  tile:u16,
  /// its species
  sp:species.Id,
  /// how far grown it is, 0 sprout .. 1 mature
  growth:f32=0,
  /// seconds to maturity at full mana, when not the species' own (0).
  span:f32=0,
  /// mana held, 0..1 of the species' cap
  mana:f32=1,
  /// how well it is, 0 dead .. 1 thriving
  health:f32=1,
  /// 0..1 random, drives animation phase and mesh variation.
  seed:f32,
  /// smoothed magnitude of mana moving through the plant (animation/glow).
  flow:f32=0,
  /// harvestable store: the species' yield condensed from mana.
  essence:f32=0,
  /// the way it was turned to (R), and how it got there
  dir:m.Dir=0,
  /// how it is turning (R), timed from when it began
  turn:Turn=.{},
  /// the plants touching its footprint (ring 1), packed, `.none` past the last
  n1:[r1]Id=@splat(.none),
  /// the plants one tile further out (ring 2), packed likewise
  n2:[r2]Id=@splat(.none),
};
/// every living plant, struct-of-arrays, with the floaters listed and
/// whether the neighbour links need rebuilding
pub const Plants=struct{
  /// every plant, one column per field
  list:std.MultiArrayList(Plant)=.empty,
  /// every floating plant, in no order
  floaters:std.ArrayList(Id)=.empty,
  /// whether a plant was placed or removed since links were last rebuilt
  topologyDirty:bool=false,
  /// frees the plant lists
  pub fn deinit(p:*Plants,gpa:Allocator)void{
    p.list.deinit(gpa);
    p.floaters.deinit(gpa);
  }
  /// how many plants are living
  pub fn len(p:*const Plants)usize{return p.list.len;}
  /// whether a plant of species `sp` may stand at world tile (wx, wy): a
  /// floater at the tile's centre, a rooted one on a free, fertile footprint
  pub fn canPlace(p:*const Plants,w:*const World,wx:i32,wy:i32,sp:species.Id)bool{
    // the species' definition
    const def=species.get(sp);
    if(def.floating)return p.canFloat(w,m.tileCentre(wx,wy,0));
    return w.footprintFree(wx,wy,def.size,ck.Kind.fertile);
  }
  /// whether a plant of species `sp` may stand at ground point `pt`: a
  /// floater right there, a rooted one on the footprint centred nearest it
  pub fn canPlaceNear(p:*const Plants,w:*const World,pt:m.V3,sp:species.Id)bool{
    if(species.get(sp).floating)return p.canFloat(w,pt);
    // the footprint's top-left tile
    const t=anchor(pt,sp);
    return p.canPlace(w,t[0],t[1],sp);
  }
  /// where a plant of species `sp` stands when put down from the cursor,
  /// over tile `t` at ground point `pt`: a floater right at `pt`, off the
  /// grid; a rooted one on the footprint whose top-left is `t`
  pub fn spot(sp:species.Id,t:[2]i32,pt:m.V3)m.V3{
    // the species' definition
    const def=species.get(sp);
    return if(def.floating)m.v3(pt[0],0,pt[2])else m.footprintCentre(t[0],t[1],def.size,0);
  }
  /// the anchor tile a plant of species `sp` takes for ground point `pt`:
  /// the tile under a floater, the top-left of the footprint centred
  /// nearest it for a rooted one
  fn anchor(pt:m.V3,sp:species.Id)[2]i32{
    // the species' definition, and how far its footprint's centre is from its top-left tile's
    const def=species.get(sp);
    const half=if(def.floating)0 else m.f(def.size-1)*0.5;
    return m.tileAt(pt-m.v3(half,0,half));
  }
  /// whether a floater may hang at ground point `pt`: over loaded ground,
  /// no nearer another floater than `floatGap` (it may hang over anything else)
  fn canFloat(p:*const Plants,w:*const World,pt:m.V3)bool{
    // the tile under the point
    const t=m.tileAt(pt);
    if(w.chunkOfTile(t[0],t[1])==null)return false;
    // every plant's point
    const ats=p.list.items(.at);
    for(p.floaters.items)|f|{
      // the way to that floater, flat on the ground
      const d=(ats[f.idx()]-pt)*m.v3(1,0,1);
      if(m.dot(d,d)<floatGap*floatGap)return false;
    }
    return true;
  }
  /// places a fresh plant of species `sp` at (wx, wy); returns whether it took root
  pub fn place(p:*Plants,gpa:Allocator,w:*World,wx:i32,wy:i32,sp:species.Id,seed:f32)Error!bool{
    return p.placeEx(gpa,w,wx,wy,.{.sp=sp,.seed=seed,.x=wx,.y=wy,.chunk=undefined,.tile=undefined});
  }
  /// place a fully specified plant at tile (wx, wy), a floater at its
  /// centre (x/y/at/chunk/tile are filled in here).
  pub fn placeEx(p:*Plants,gpa:Allocator,w:*World,wx:i32,wy:i32,proto:Plant)Error!bool{
    // the species' definition
    const def=species.get(proto.sp);
    return p.placeNear(gpa,w,m.footprintCentre(wx,wy,if(def.floating)1 else def.size,0),proto);
  }
  /// place a fully specified plant at ground point `pt`: a floater hangs
  /// right there, a rooted one takes the footprint centred nearest it
  /// (x/y/at/chunk/tile are filled in here).
  pub fn placeNear(p:*Plants,gpa:Allocator,w:*World,pt:m.V3,proto:Plant)Error!bool{
    if(!p.canPlaceNear(w,pt,proto.sp))return false;
    // the species' definition, its anchor tile, the chunk it lands in, and its new id
    const def=species.get(proto.sp);
    const t=anchor(pt,proto.sp);
    const c=w.chunkOfTile(t[0],t[1]).?;
    const idx=Id.of(p.list.len);
    // the plant as placed, its anchor, point and chunk filled in
    var pl=proto;
    pl.x=t[0];
    pl.y=t[1];
    pl.at=if(def.floating)m.v3(pt[0],0,pt[2])else m.footprintCentre(t[0],t[1],def.size,0);
    pl.chunk=c;
    pl.tile=@intCast(ck.localIndex(t[0],t[1]));
    try p.list.append(gpa,pl);
    if(def.floating){
      try p.floaters.append(gpa,idx);
      c.pins+=1;
    }else w.setFootprint(t[0],t[1],def.size,Occ.plant(idx));
    p.topologyDirty=true;
    return true;
  }
  /// the plant at a tile: a rooted one first, else one floating over it.
  pub fn at(p:*const Plants,w:*const World,wx:i32,wy:i32)?Id{
    if(w.occAt(wx,wy).asPlant())|i|return i;
    // every plant's anchor tile
    const xs=p.list.items(.x);
    const ys=p.list.items(.y);
    for(p.floaters.items)|f|if(xs[f.idx()]==wx and ys[f.idx()]==wy)return f;
    return null;
  }
  /// the floater a ray from `o` along unit `d` passes nearest its start,
  /// within `floatTouch` of where it hangs (`hang.at(id)`), and how far along
  /// the ray that is
  pub fn floaterOnRay(p:*const Plants,o:m.V3,d:m.V3,comptime Hang:type,hang:Hang)?Touch{
    // the nearest so far
    var best:?Touch=null;
    for(p.floaters.items)|f|{
      // where it hangs, how far along the ray it lies, and how far off it
      const c=hang.at(f);
      const t=m.dot(c-o,d);
      if(t<=0)continue;
      if(best)|b|if(t>=b.t)continue;
      const off=c-(o+d*m.splat3(t));
      if(m.dot(off,off)>floatTouch*floatTouch)continue;
      best=.{.id=f,.t=t};
    }
    return best;
  }
  /// a floater a ray touches, and how far along it
  pub const Touch=struct{
    /// the floater
    id:Id,
    /// how far along the ray (m)
    t:f32,
  };
  /// uproots whatever plant is at (wx, wy); returns whether there was one
  pub fn removeAt(p:*Plants,w:*World,wx:i32,wy:i32)bool{
    // the plant there
    const i=p.at(w,wx,wy) orelse return false;
    p.remove(w,i);
    return true;
  }
  /// swap-remove; re-points the footprint of the plant that moved into slot `i`.
  pub fn remove(p:*Plants,w:*World,id:Id)void{
    // its slot, the plant columns, and its species
    const i=id.idx();
    const s=p.list.slice();
    const def=species.get(s.items(.sp)[i]);
    if(def.floating){
      _=p.floaters.swapRemove(indexOfScalar(Id,p.floaters.items,id).?);
      s.items(.chunk)[i].pins-=1;
    }else w.setFootprint(s.items(.x)[i],s.items(.y)[i],def.size,.none);
    // the last slot, whose plant moves into the gap
    const last=p.list.len-1;
    if(i!=last){
      // that last plant's species and anchor tile
      const ld=species.get(s.items(.sp)[last]);
      const lx=s.items(.x)[last];
      const ly=s.items(.y)[last];
      if(ld.floating)p.floaters.items[indexOfScalar(Id,p.floaters.items,Id.of(last)).?]=id
      else w.moveFootprint(lx,ly,ld.size,Occ.plant(id));
    }
    p.list.swapRemove(i);
    // links stay valid without waiting for a rebuild: the removed plant
    // drops out of every ring, and the plant that moved into its slot is
    // found there (readers outside the tick, e.g. harvesting, rely on this)
    // the slot the last plant moved from, and the columns now
    const moved=Id.of(last);
    const s2=p.list.slice();
    for(s2.items(.n1))|*ring|relink(ring,id,moved);
    for(s2.items(.n2))|*ring|relink(ring,id,moved);
    p.topologyDirty=true;
  }
  /// drop `gone` from a ring and re-point `from` at `gone`'s slot, keeping
  /// the ring packed (readers stop at the first `.none`).
  fn relink(ring:[]Id,gone:Id,from:Id)void{
    // where the next kept entry goes
    var k:usize=0;
    for(ring)|e|{
      if(e==.none)break;
      if(e==gone)continue;
      ring[k]=if(e==from)gone else e;
      k+=1;
    }
    while(k<ring.len and ring[k]!=.none):(k+=1)ring[k]=.none;
  }
  /// the tiles a plant covers: its footprint, or the one tile it hovers over.
  pub fn extent(p:*const Plants,i:usize)Rect{
    // the plant columns, and its species
    const s=p.list.slice();
    const def=species.get(s.items(.sp)[i]);
    return.{.x=s.items(.x)[i],.y=s.items(.y)[i],.size=if(def.floating)1 else def.size};
  }
  /// world-space centre of a plant: its footprint's, or where it floats (x, z).
  pub fn centre(p:*const Plants,i:usize)[2]f32{
    // where it stands
    const c=p.list.items(.at)[i];
    return.{c[0],c[2]};
  }
  /// remakes every plant's neighbour rings from occupancy, over the pool
  pub fn rebuildLinks(p:*Plants,w:*World)void{
    // each plant fills only its own rows, so they are split over the pool
    jobs.each(w.io,p.list.len,linksMin,Relink,.{.p=p,.w=w},Relink.run);
    p.topologyDirty=false;
  }
  /// one range of plants' neighbour rows, made afresh from occupancy
  const Relink=struct{
    /// the plants being relinked
    p:*const Plants,
    /// the world whose occupancy they are read from
    w:*const World,
    /// remakes the neighbour rows of plants `lo..hi`
    fn run(r:Relink,lo:usize,hi:usize)void{
      // the plants, the world and the plant columns
      const p=r.p;
      const w=r.w;
      const s=p.list.slice();
      // each plant's anchor and species, and its two rings
      const xs=s.items(.x);
      const ys=s.items(.y);
      const sps=s.items(.sp);
      const n1=s.items(.n1);
      const n2=s.items(.n2);
      for(lo..hi)|i|{
        n1[i]=@splat(.none);
        n2[i]=@splat(.none);
        // this plant's species, and its footprint's width
        const def=species.get(sps[i]);
        const size:i32=if(def.floating)1 else def.size;
        // the tile row being read, two beyond the footprint each way
        var dy:i32=-2;
        while(dy<size+2):(dy+=1){
          // the tile column being read
          var dx:i32=-2;
          while(dx<size+2):(dx+=1){
            // how many tiles off the footprint this tile is, across and down
            const rx=if(dx<0)-dx else if(dx>=size)dx-size+1 else 0;
            const ry=if(dy<0)-dy else if(dy>=size)dy-size+1 else 0;
            // tiles under the footprint count as touching (a floater over a root)
            const ring=@max(@max(rx,ry),1);
            // that tile in the world
            const wx=xs[i]+dx;
            const wy=ys[i]+dy;
            if(w.occAt(wx,wy).asPlant())|j|link(n1,n2,i,j,ring);
          }
        }
        // floaters, by the tile each hangs over (one under the footprint touches it)
        // this plant's tiles
        const me=Rect{.x=xs[i],.y=ys[i],.size=@intCast(size)};
        for(p.floaters.items)|f|{
          // how far the floater's tile is from this plant's
          const gap=me.gap(.{.x=xs[f.idx()],.y=ys[f.idx()],.size=1});
          if(gap<=2)link(n1,n2,i,f,@max(gap,1));
        }
      }
    }
  };
  /// adds neighbour `j` to plant `i`'s ring 1 or 2, once, in the nearest ring
  fn link(n1:[][r1]Id,n2:[][r2]Id,i:usize,j:Id,ring:i32)void{
    if(j.idx()==i)return;
    // a multi-tile neighbour shows up on several tiles: keep it once, in the nearest ring
    for(n1[i])|e|if(e==j)return;
    if(ring==1){
      for(&n2[i])|*e|if(e.*==j){e.*=.none;};
      compact(&n2[i]);
      put(&n1[i],j);
    }else{
      for(n2[i])|e|if(e==j)return;
      put(&n2[i],j);
    }
  }
  /// fills the first empty place of a ring with `j` (dropped when full)
  fn put(arr:[]Id,j:Id)void{
    for(arr)|*e|if(e.*==.none){e.*=j;return;};
  }
  /// packs a ring's ids to its front, `.none` after
  fn compact(arr:[]Id)void{
    // where the next kept id goes
    var k:usize=0;
    for(arr)|e|if(e!=.none){arr[k]=e;k+=1;};
    while(k<arr.len):(k+=1)arr[k]=.none;
  }
};
test"footprints, floaters and links"{
  // the test allocator
  const gpa=testing.allocator;
  // a small loaded world
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // the chunk at the origin, made soil
  const c=w.chunkOfTile(0,0).?;
  for(0..5)|y|for(0..5)|x|{c.kind[y*ck.sizeTiles+x]=.soil;c.height[y*ck.sizeTiles+x]=1;};
  // the plants
  var p:Plants=.{};
  defer p.deinit(gpa);
  try testing.expect(try p.place(gpa,&w,1,1,.hollowheart,0.5));
  // the heart covers (1..2, 1..2): nothing else may root there
  try testing.expect(!try p.place(gpa,&w,2,2,.lumenroot,0.5));
  try testing.expect(try p.place(gpa,&w,3,1,.lumenroot,0.5));
  // a floater may hover over the heart itself, but not over another floater
  try testing.expect(try p.place(gpa,&w,2,2,.driftwisp,0.5));
  try testing.expect(!try p.place(gpa,&w,2,2,.driftwisp,0.5));
  // floaters hang off the grid: anywhere not crowding another
  const proto=Plant{.x=0,.y=0,.chunk=undefined,.tile=undefined,.sp=.driftwisp,.seed=0.5};
  try testing.expect(!try p.placeNear(gpa,&w,m.v3(2.5+floatGap*0.9,0,2.5),proto));
  try testing.expect(try p.placeNear(gpa,&w,m.v3(2.5+floatGap*1.1,0,2.4),proto));
  try testing.expectEqual(@as(i32,3),p.list.items(.x)[p.len()-1]);
  try testing.expectEqual(@as(f32,2.4),p.list.items(.at)[p.len()-1][2]);
  try testing.expect(p.at(&w,3,2)!=null);
  p.remove(&w,.of(p.len()-1));
  p.rebuildLinks(&w);
  // how many neighbours the heart has
  var links:usize=0;
  for(p.list.items(.n1)[0])|e|if(e!=.none){links+=1;};
  try testing.expectEqual(@as(usize,2),links);
  // 4 heart tiles + 1 root + 1 floater
  try testing.expectEqual(@as(u32,6),c.pins);
  p.remove(&w,.of(0));
  try testing.expectEqual(@as(u32,2),c.pins);
  try testing.expect(p.at(&w,3,1)!=null and p.at(&w,2,2)!=null);
}
test"links stay valid right after a remove, matching a rebuild"{
  // the test allocator
  const gpa=testing.allocator;
  // a small loaded world
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // the chunk at the origin, made soil
  const c=w.chunkOfTile(0,0).?;
  for(0..6)|y|for(0..6)|x|{c.kind[y*ck.sizeTiles+x]=.soil;c.height[y*ck.sizeTiles+x]=1;};
  // the plants
  var p:Plants=.{};
  defer p.deinit(gpa);
  // a 2x2 and a ring of 1x1s around it, plus a floater, all linked
  try testing.expect(try p.place(gpa,&w,2,2,.hollowheart,0.5));
  for([_][2]i32{.{1,1},.{4,2},.{2,4},.{1,3},.{4,4},.{0,2}})|t|try testing.expect(try p.place(gpa,&w,t[0],t[1],.lumenroot,0.5));
  try testing.expect(try p.place(gpa,&w,3,3,.driftwisp,0.5));
  // remove from the middle, from the front and the last slot, checking each time
  for([_]usize{3,0,4})|victim|{
    p.rebuildLinks(&w);
    p.remove(&w,.of(@min(victim,p.len()-1)));
    // how many plants remain
    const n=p.len();
    // each plant's rings as patched after the remove
    var got:[16][r1+r2]Id=undefined;
    for(0..n)|i|{
      // the plant columns
      const s=p.list.slice();
      for(s.items(.n1)[i],0..)|e,k|{if(e!=.none)try testing.expect(e.idx()<n);got[i][k]=e;}
      for(s.items(.n2)[i],0..)|e,k|{if(e!=.none)try testing.expect(e.idx()<n);got[i][r1+k]=e;}
    }
    // the patched links say exactly what a full rebuild says (as sets per ring)
    p.rebuildLinks(&w);
    // the plant columns, as a rebuild makes them
    const s=p.list.slice();
    for(0..n)|i|{
      for([2][]const Id{got[i][0..r1],got[i][r1..]},[2][]const Id{&s.items(.n1)[i],&s.items(.n2)[i]})|a,b|{
        // how many ids each ring holds, patched and rebuilt
        var ca:usize=0;
        var cb:usize=0;
        for(a)|e|if(e!=.none){ca+=1;try testing.expect(indexOfScalar(Id,b,e)!=null);};
        for(b)|e|if(e!=.none){cb+=1;};
        try testing.expectEqual(cb,ca);
      }
    }
  }
}
test"links made over the pool match links made in place"{
  // the test allocator
  const gpa=testing.allocator;
  // a small loaded world
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // the chunk at the origin, made soil
  const c=w.chunkOfTile(0,0).?;
  for(&c.kind,&c.height)|*k,*h|{k.*=.soil;h.*=1;}
  // the plants
  var p:Plants=.{};
  defer p.deinit(gpa);
  // a chunk sown full (enough plants to split), a floater over every third
  for(0..ck.sizeTiles)|y|for(0..ck.sizeTiles)|x|{
    // this tile in the world
    const wx:i32=@intCast(x);
    const wy:i32=@intCast(y);
    _=try p.place(gpa,&w,wx,wy,.lumenroot,0.5);
    if((x+y)%3==0)_=try p.place(gpa,&w,wx,wy,.driftwisp,0.5);
  };
  try testing.expect(p.len()>2*linksMin);
  p.rebuildLinks(&w);
  // the rings made in place, kept to compare
  const n1=try gpa.dupe([r1]Id,p.list.items(.n1));
  defer gpa.free(n1);
  const n2=try gpa.dupe([r2]Id,p.list.items(.n2));
  defer gpa.free(n2);
  w.io=testing.io;
  p.rebuildLinks(&w);
  for(n1,p.list.items(.n1))|a,b|try testing.expectEqualSlices(Id,&a,&b);
  for(n2,p.list.items(.n2))|a,b|try testing.expectEqualSlices(Id,&a,&b);
}
