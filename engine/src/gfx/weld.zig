//! welding triangle soups into an indexed mesh: a corner that is the very
//! same vertex as one before it (position, normal, colour, tu, role, skin
//! weights and growth record, bit for bit) is drawn from that one, so the
//! GPU shades it once and its vertex cache hands the result to every
//! triangle sharing it. Triangles keep their order (but for the late ones,
//! below) and their corners keep theirs, so what is drawn (blending, flat
//! values from the first corner) is exactly what the soup drew. Runs that blend vertex for vertex into
//! one another (growth keys) are welded together: a corner is shared only
//! where it is shared in every one of them, so they keep one index list and
//! still line up vertex for vertex. Triangles marked late (any of their
//! corners, in any run of their group) are put after the rest, each part
//! keeping its own order, so a pass that wants only them draws the tail.
//! The runs may lie in several soups (each built apart, on a thread of its
//! own), never copied into one. Each group is welded on its own (over the
//! pool, `jobs.each`), then all are laid end to end in the soups' order:
//! the same welding however split.
/// the standard library
const std=@import("std");
/// the allocator the welded lists grow with (shared by the pool's threads:
/// it must be thread-safe)
const Allocator=std.mem.Allocator;
/// the I/O whose pool groups are welded on
const Io=std.Io;
/// a counter shared by the pool's threads: the next group to take, how
/// many runs are welded
const Atomic=std.atomic.Value;
/// the thread fan-out groups are welded over
const jobs=@import("../core/jobs.zig");
/// a seeded random stream, for the soups the tests weld
const Rng=@import("../core/rng.zig").Rng;
/// the test helpers
const testing=std.testing;
/// a value's bytes, which welding compares
const asBytes=std.mem.asBytes;
/// a slice's bytes, which the tests compare
const sliceAsBytes=std.mem.sliceAsBytes;
/// the hash a corner's bytes are hashed with
const Wyhash=std.hash.Wyhash;
/// all the maths: conversions for the tests' soups
const m=@import("../core/math.zig");
/// the GPU layouts: mesh vertices, skin weights, growth records
const vertex=@import("vertex.zig");
/// one welded run, drawn with `drawIndexed(count, …, first, base, …)`: its
/// triangles' corners are `count` indices from `first`, each counting from
/// `base`, the first of its own `verts` vertices; its late triangles are
/// the indices from `first+early` on
pub const Run=extern struct{
  /// the first of its indices
  first:u32=0,
  /// how many indices (three a triangle)
  count:u32=0,
  /// where its own vertices begin, which every index counts from
  base:u32=0,
  /// how many vertices it has of its own
  verts:u32=0,
  /// how many of its indices come before its late triangles
  early:u32=0,
};
/// a triangle soup: three vertices a triangle, each with its skin weights
/// and growth record beside it (each list as long as the vertices, or
/// empty: none of them skinned, or grown, which keeps a soup that has none
/// from carrying a blank one a vertex)
pub const Soup=struct{
  /// the vertices
  v:[]const vertex.Mesh,
  /// each vertex's skin weights (empty: all blank)
  skin:[]const vertex.Skin=&.{},
  /// each vertex's growth record (empty: all blank)
  grow:[]const vertex.Grow=&.{},
  /// the vertices whose triangles go last (none: no triangle is late)
  late:?[]const bool=null,
  /// vertex `k`'s skin weights (blank when the soup keeps none)
  fn skinAt(s:Soup,k:usize)*const vertex.Skin{return if(s.skin.len==0)&blankSkin else &s.skin[k];}
  /// vertex `k`'s growth record (blank when the soup keeps none)
  fn growAt(s:Soup,k:usize)*const vertex.Grow{return if(s.grow.len==0)&blankGrow else &s.grow[k];}
};
/// the skin weights of a vertex nothing moves
const blankSkin=vertex.Skin{};
/// the growth record of a vertex not grown along a spline
const blankGrow=vertex.Grow{};
/// where a run lies: which soup, its first vertex there and how many
/// (count 0: the run is empty)
pub const Range=struct{
  /// the soup it lies in
  soup:u32=0,
  /// its first vertex in that soup
  first:u32=0,
  /// how many vertices (three a triangle)
  count:u32=0,
};
/// the welded meshes: every run's own vertices one after another, the
/// indices into them, and each run where it lies
pub const Welded=struct{
  /// the vertices kept
  v:std.ArrayList(vertex.Mesh)=.empty,
  /// each kept vertex's skin weights
  skin:std.ArrayList(vertex.Skin)=.empty,
  /// each kept vertex's growth record
  grow:std.ArrayList(vertex.Grow)=.empty,
  /// every run's corners, as indices from its base
  indices:std.ArrayList(u32)=.empty,
  /// each run given, welded (in the order given; an empty one empty)
  runs:[]Run=&.{},
  /// free its lists
  pub fn deinit(w:*Welded,gpa:Allocator)void{
    w.v.deinit(gpa);
    w.skin.deinit(gpa);
    w.grow.deinit(gpa);
    w.indices.deinit(gpa);
    gpa.free(w.runs);
  }
};
/// the corners of a group of runs as the welding map sees them: corner `j`
/// is the `j`th vertex of every run in the group at once
const Corners=struct{
  /// the soups the runs lie in
  soups:[]const Soup,
  /// where each run of the group lies
  at:[]const Range,
  /// a corner's bytes in every run, hashed
  pub fn hash(c:Corners,j:u32)u64{
    // the hash, fed every run's vertex, weights and record
    var h=Wyhash.init(0);
    for(c.at)|r|{
      // the soup this run lies in
      const s=c.soups[r.soup];
      h.update(asBytes(&s.v[r.first+j]));
      h.update(asBytes(s.skinAt(r.first+j)));
      h.update(asBytes(s.growAt(r.first+j)));
    }
    return h.final();
  }
  /// whether two corners are the same vertex in every run, bit for bit
  /// (the layouts are extern structs of 4-byte fields: no padding)
  pub fn eql(c:Corners,a:u32,b:u32)bool{
    for(c.at)|r|{
      // the soup this run lies in, and where it begins there
      const s=c.soups[r.soup];
      const f=r.first;
      if(!std.mem.eql(u8,asBytes(&s.v[f+a]),asBytes(&s.v[f+b])))return false;
      if(!std.mem.eql(u8,asBytes(s.skinAt(f+a)),asBytes(s.skinAt(f+b))))return false;
      if(!std.mem.eql(u8,asBytes(s.growAt(f+a)),asBytes(s.growAt(f+b))))return false;
    }
    return true;
  }
  /// whether the triangle from corner `t` is late: any of its corners in
  /// any run of the group
  fn late(c:Corners,t:u32)bool{
    for(c.at)|r|{
      // which of this soup's vertices are marked late (none: no triangle)
      const marks=c.soups[r.soup].late orelse continue;
      for(r.first+t..r.first+t+3)|k|if(marks[k])return true;
    }
    return false;
  }
};
/// the map from a corner to the kept vertex it is drawn from
const Map=std.HashMapUnmanaged(u32,u32,Corners,std.hash_map.default_max_load_percentage);
/// one group of runs to weld: its runs and where each lies (slices of the
/// lists all groups share), and how many corners each has
const Group=struct{
  /// its runs, in the order their soups lie in
  members:[]const u32,
  /// where each of them lies
  at:[]const Range,
  /// how many corners each run has (all alike)
  n:u32,
};
/// one group welded on its own: its indices from its own first kept
/// corner, the corners it keeps, how many indices come before its late
/// triangles; then where it lies in the whole
const Out=struct{
  /// its corners, each the kept corner it is drawn from
  indices:[]u32=&.{},
  /// the corners it keeps, in the order first met
  kept:[]u32=&.{},
  /// how many of its indices come before its late triangles
  early:u32=0,
  /// where its indices begin among all of them
  first:u32=0,
  /// where its first member's vertices begin among all of them
  base:u32=0,
};
/// the welding shared by the pool's threads: the groups, what each gives,
/// the next group to take and whether one ran out of memory
const Shared=struct{
  /// the soups the runs lie in
  soups:[]const Soup,
  /// the groups, in the order their soups lie in
  groups:[]const Group,
  /// what each group gives
  outs:[]Out,
  /// the allocator the groups' lists are made with (thread-safe)
  gpa:Allocator,
  /// the next group to take
  next:*Atomic(usize),
  /// set when a group ran out of memory
  failed:*Atomic(bool),
  /// counted up by every run welded, if anyone is watching
  progress:?*Atomic(u32),
  /// welds groups, one after another as they are taken, till none is left
  /// (each worker its own map and list, so groups need not be split evenly)
  fn weldAll(s:Shared,lo:usize,hi:usize)void{
    _=lo;
    _=hi;
    // this worker's map from corners to kept vertices, and its kept corners
    var map=Map.empty;
    defer map.deinit(s.gpa);
    var kept:std.ArrayList(u32)=.empty;
    defer kept.deinit(s.gpa);
    while(true){
      // the next group, none: done
      const i=s.next.fetchAdd(1,.monotonic);
      if(i>=s.groups.len)return;
      s.weldOne(&s.groups[i],&s.outs[i],&map,&kept)catch{
        s.failed.store(true,.monotonic);
        return;
      };
      if(s.progress)|p|_=p.fetchAdd(@intCast(s.groups[i].members.len),.monotonic);
    }
  }
  /// welds one group into `out`: the early triangles first, then the late
  /// ones, each corner the first kept corner equal to it in every run
  fn weldOne(s:Shared,gr:*const Group,out:*Out,map:*Map,kept:*std.ArrayList(u32))Allocator.Error!void{
    // how the group's corners are seen: each in every run at once
    const corners=Corners{.soups=s.soups,.at=gr.at};
    kept.clearRetainingCapacity();
    map.clearRetainingCapacity();
    out.indices=try s.gpa.alloc(u32,gr.n);
    // how many indices are written
    var at:u32=0;
    for([_]bool{false,true})|lateNow|{
      if(lateNow)out.early=at;
      // each triangle's first corner
      var t:u32=0;
      while(t<gr.n):(t+=3){
        if(corners.late(t)!=lateNow)continue;
        for(t..t+3)|c|{
          // this corner, and the kept vertex it is (a new one if none yet)
          const j:u32=@intCast(c);
          const got=try map.getOrPutContext(s.gpa,j,corners);
          if(!got.found_existing){
            got.value_ptr.*=@intCast(kept.items.len);
            try kept.append(s.gpa,j);
          }
          out.indices[at]=got.value_ptr.*;
          at+=1;
        }
      }
    }
    out.kept=try s.gpa.dupe(u32,kept.items);
  }
};
/// laying the welded groups end to end, shared by the pool's threads:
/// each group's indices and every member's kept vertices to their places
const Lay=struct{
  /// the soups the runs lie in
  soups:[]const Soup,
  /// the groups, in the order their soups lie in
  groups:[]const Group,
  /// what each group gave, and where it lies
  outs:[]const Out,
  /// what comes out
  w:*Welded,
  /// the next group to take
  next:*Atomic(usize),
  /// copies groups, as they are taken, till none is left
  fn layAll(l:Lay,lo:usize,hi:usize)void{
    _=lo;
    _=hi;
    while(true){
      // the next group, none: done
      const i=l.next.fetchAdd(1,.monotonic);
      if(i>=l.groups.len)return;
      // what the group gave
      const o=l.outs[i];
      @memcpy(l.w.indices.items[o.first..][0..o.indices.len],o.indices);
      for(l.groups[i].at,0..)|r,k|{
        // the soup this member lies in, and where its vertices go
        const s=l.soups[r.soup];
        const base=@as(usize,o.base)+k*o.kept.len;
        for(o.kept,base..)|c,d|{
          l.w.v.items[d]=s.v[r.first+c];
          l.w.skin.items[d]=s.skinAt(r.first+c).*;
          l.w.grow.items[d]=s.growAt(r.first+c).*;
        }
      }
    }
  }
};
/// weld the runs `ranges` of `soups`, each in the group `groups` names:
/// runs of one group are as long as each other and share their indices.
/// The welded runs come out in the order their soups lay in (soup by soup,
/// a group where its first run lay), so a later key's vertices stay after
/// an earlier one's. Groups are welded over `io`'s pool (null: here, the
/// same result); `progress`, if given, counts each run as it is welded
/// (empty ones at once). `gpa` must be thread-safe.
pub fn weld(gpa:Allocator,io:?Io,soups:[]const Soup,ranges:[]const Range,groups:[]const u32,progress:?*Atomic(u32))Allocator.Error!Welded{
  std.debug.assert(ranges.len==groups.len);
  for(soups)|s|std.debug.assert((s.skin.len==0 or s.skin.len==s.v.len) and (s.grow.len==0 or s.grow.len==s.v.len));
  // what comes out, freed again if welding fails
  var w=Welded{};
  errdefer w.deinit(gpa);
  w.runs=try gpa.alloc(Run,ranges.len);
  @memset(w.runs,.{});
  // the runs in the order their soups lie in
  const order=try gpa.alloc(u32,ranges.len);
  defer gpa.free(order);
  for(order,0..)|*o,i|o.*=@intCast(i);
  std.mem.sort(u32,order,ranges,earlier);
  // which runs are put in a group already
  const taken=try gpa.alloc(bool,ranges.len);
  defer gpa.free(taken);
  @memset(taken,false);
  // every group's members and where they lie, one after another, and
  // each group's span of them and corner count
  var members:std.ArrayList(u32)=.empty;
  defer members.deinit(gpa);
  var at:std.ArrayList(Range)=.empty;
  defer at.deinit(gpa);
  var spans:std.ArrayList(m.Vice(u32,3))=.empty;
  defer spans.deinit(gpa);
  // empty runs are welded at once
  var empty:u32=0;
  for(order)|i|{
    if(ranges[i].count==0)empty+=1;
    if(taken[i] or ranges[i].count==0)continue;
    // where this group's members begin
    const from:u32=@intCast(members.items.len);
    for(order)|j|if(!taken[j] and ranges[j].count>0 and groups[j]==groups[i]){
      std.debug.assert(ranges[j].count==ranges[i].count);
      try members.append(gpa,j);
      try at.append(gpa,ranges[j]);
      taken[j]=true;
    };
    std.debug.assert(ranges[i].count%3==0);
    try spans.append(gpa,.{from,@intCast(members.items.len),ranges[i].count});
  }
  if(progress)|p|_=p.fetchAdd(empty,.monotonic);
  // the groups, as slices of the shared lists
  const gs=try gpa.alloc(Group,spans.items.len);
  defer gpa.free(gs);
  for(gs,spans.items)|*g,s|g.*=.{.members=members.items[s[0]..s[1]],.at=at.items[s[0]..s[1]],.n=s[2]};
  // what each group gives, freed once laid out
  const outs=try gpa.alloc(Out,gs.len);
  defer gpa.free(outs);
  @memset(outs,.{});
  defer for(outs)|o|{
    gpa.free(o.indices);
    gpa.free(o.kept);
  };
  // the next group to take, and whether welding one failed
  var next=Atomic(usize).init(0);
  var failed=Atomic(bool).init(false);
  jobs.each(io,gs.len,1,Shared,.{.soups=soups,.groups=gs,.outs=outs,.gpa=gpa,.next=&next,.failed=&failed,.progress=progress},Shared.weldAll);
  if(failed.load(.monotonic))return error.OutOfMemory;
  // where each group lies in the whole, and how long the whole is
  var nIdx:u32=0;
  var nVert:u32=0;
  for(gs,outs)|g,*o|{
    // how many vertices each member keeps
    const kept:u32=@intCast(o.kept.len);
    o.first=nIdx;
    o.base=nVert;
    for(g.members,0..)|r,k|w.runs[r]=.{.first=nIdx,.count=g.n,.base=nVert+@as(u32,@intCast(k))*kept,.verts=kept,.early=o.early};
    nIdx+=g.n;
    nVert+=@as(u32,@intCast(g.members.len))*kept;
  }
  try w.indices.resize(gpa,nIdx);
  try w.v.resize(gpa,nVert);
  try w.skin.resize(gpa,nVert);
  try w.grow.resize(gpa,nVert);
  next.store(0,.monotonic);
  jobs.each(io,gs.len,1,Lay,.{.soups=soups,.groups=gs,.outs=outs,.w=&w,.next=&next},Lay.layAll);
  return w;
}
/// whether run `a` lies before run `b`: an earlier soup, or earlier in one
fn earlier(ranges:[]const Range,a:u32,b:u32)bool{
  return if(ranges[a].soup!=ranges[b].soup)ranges[a].soup<ranges[b].soup else ranges[a].first<ranges[b].first;
}
/// a soup vertex at `x` along, coloured by `k`
fn testVertex(x:f32,k:u8)vertex.Mesh{
  return.{.pos=.{x,0,0},.nrm=.{0,1,0},.col=.{.r=k,.g=0,.b=0,.a=255},.tu=.{0,0,0},.part=0};
}
/// every corner of run `r` drawn welded is the soup's own corner from
/// `from` on, bit for bit
fn expectSame(w:*const Welded,soup:Soup,from:u32,r:Run)!void{
  for(0..r.count)|c|{
    // the welded vertex this corner draws
    const k=r.base+w.indices.items[r.first+c];
    try testing.expect(k<r.base+r.verts);
    try testing.expectEqualSlices(u8,asBytes(&soup.v[from+c]),asBytes(&w.v.items[k]));
    try testing.expectEqualSlices(u8,asBytes(&soup.skin[from+c]),asBytes(&w.skin.items[k]));
    try testing.expectEqualSlices(u8,asBytes(&soup.grow[from+c]),asBytes(&w.grow.items[k]));
  }
}
test"a welded soup draws every corner exactly as it was, each shared vertex once"{
  // two triangles sharing an edge (a quad), then a lone one
  const v=[_]vertex.Mesh{
    testVertex(0,1),testVertex(1,1),testVertex(2,1),
    testVertex(2,1),testVertex(1,1),testVertex(3,1),
    testVertex(5,2),testVertex(6,2),testVertex(7,2),
  };
  const skin=[_]vertex.Skin{.{}}**9;
  var grow=[_]vertex.Grow{.{}}**9;
  // the lone triangle's first corner grows from elsewhere: kept apart from
  // an otherwise equal vertex
  grow[6].at=.{0.5,0,0,0};
  const soup=Soup{.v=&v,.skin=&skin,.grow=&grow};
  const ranges=[_]Range{.{.first=6,.count=3},.{.first=0,.count=6},.{}};
  var w=try weld(testing.allocator,null,&.{soup},&ranges,&.{0,1,2},null);
  defer w.deinit(testing.allocator);
  try testing.expectEqual(@as(u32,4),w.runs[1].verts);
  try testing.expectEqual(@as(u32,3),w.runs[0].verts);
  try testing.expectEqual(@as(u32,0),w.runs[2].count);
  // the quad lay first in the soup, so it comes first
  try testing.expect(w.runs[1].base<w.runs[0].base);
  try expectSame(&w,soup,0,w.runs[1]);
  try expectSame(&w,soup,6,w.runs[0]);
}
test"runs welded together share their indices and line up vertex for vertex"{
  // two keys of one quad: the second moves one shared corner, and splits
  // another the first shares
  const v=[_]vertex.Mesh{
    testVertex(0,1),testVertex(1,1),testVertex(2,1),testVertex(2,1),testVertex(1,1),testVertex(3,1),
    testVertex(0,1),testVertex(1.5,1),testVertex(2,1),testVertex(2,3),testVertex(1.5,1),testVertex(3,1),
  };
  const skin=[_]vertex.Skin{.{}}**12;
  const grow=[_]vertex.Grow{.{}}**12;
  const soup=Soup{.v=&v,.skin=&skin,.grow=&grow};
  const ranges=[_]Range{.{.first=6,.count=6},.{.first=0,.count=6}};
  var w=try weld(testing.allocator,null,&.{soup},&ranges,&.{7,7},null);
  defer w.deinit(testing.allocator);
  try testing.expectEqual(w.runs[0].first,w.runs[1].first);
  try testing.expectEqual(w.runs[0].verts,w.runs[1].verts);
  // shared only where shared in both: corner 1 and 4, not 2 and 3
  try testing.expectEqual(@as(u32,5),w.runs[0].verts);
  // the earlier key's vertices first, the later's right after
  try testing.expectEqual(w.runs[1].base+w.runs[1].verts,w.runs[0].base);
  try expectSame(&w,soup,0,w.runs[1]);
  try expectSame(&w,soup,6,w.runs[0]);
}
test"late triangles go last, each part in its own order, every corner as it was"{
  // four triangles: the first and third marked late by one corner each
  var v:[12]vertex.Mesh=undefined;
  for(&v,0..)|*x,i|x.*=testVertex(@floatFromInt(i),1);
  const skin=[_]vertex.Skin{.{}}**12;
  const grow=[_]vertex.Grow{.{}}**12;
  var late=[_]bool{false}**12;
  late[1]=true;
  late[8]=true;
  const soup=Soup{.v=&v,.skin=&skin,.grow=&grow,.late=&late};
  var w=try weld(testing.allocator,null,&.{soup},&.{.{.count=12}},&.{0},null);
  defer w.deinit(testing.allocator);
  // the run, and the soup triangle each of its triangles must be
  const r=w.runs[0];
  try testing.expectEqual(@as(u32,6),r.early);
  for([_]u32{1,3,0,2},0..)|tri,k|for(0..3)|c|{
    // the welded vertex this corner draws
    const at=r.base+w.indices.items[r.first+k*3+c];
    try testing.expectEqualSlices(u8,asBytes(&v[tri*3+c]),asBytes(&w.v.items[at]));
  };
}
test"welded over the pool from soups apart, runs come out exactly as from one soup here"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // the soup's random stream, the same every run
  var rng=Rng.init(0x3E1D);
  // forty runs of nine to sixty corners, every fourth a key of the one before
  var whole:[40]Range=undefined;
  var groups:[40]u32=undefined;
  // how many corners so far
  var n:u32=0;
  for(&whole,&groups,0..)|*r,*g,i|{
    // a key is as long as the run it follows
    const keyed=i%4==3;
    const len=if(keyed)whole[i-1].count else 3*(3+rng.below(18));
    r.*=.{.first=n,.count=len};
    g.*=if(keyed)groups[i-1]else@intCast(i);
    n+=len;
  }
  // corners drawn from a few values, so many are shared
  const v=try gpa.alloc(vertex.Mesh,n);
  defer gpa.free(v);
  const skin=try gpa.alloc(vertex.Skin,n);
  defer gpa.free(skin);
  const grow=try gpa.alloc(vertex.Grow,n);
  defer gpa.free(grow);
  const late=try gpa.alloc(bool,n);
  defer gpa.free(late);
  for(v,skin,grow,late)|*x,*k,*gr,*l|{
    x.*=testVertex(m.f(rng.below(6)),@intCast(rng.below(2)));
    k.*=.{.bones=rng.below(2)};
    gr.*=.{};
    l.*=rng.below(9)==0;
  }
  // the third soup's runs skinned by none (it keeps no skin list below)
  @memset(skin[whole[16].first..whole[23].first+whole[23].count],.{});
  const soup=Soup{.v=v,.skin=skin,.grow=grow,.late=late};
  // welded here from the one soup
  var here=try weld(gpa,null,&.{soup},&whole,&groups,null);
  defer here.deinit(gpa);
  // the same corners as five soups of eight runs each, welded over the pool
  var soups:[5]Soup=undefined;
  var apart:[40]Range=undefined;
  for(&soups,0..)|*s,k|{
    // the soup's first and last vertex in the one soup
    const lo=whole[k*8].first;
    const hi=whole[k*8+7].first+whole[k*8+7].count;
    // (the third keeps no skin, every other no growth records: all blank)
    s.*=.{.v=v[lo..hi],.skin=if(k==2)&.{}else skin[lo..hi],.grow=if(k%2==1)&.{}else grow[lo..hi],.late=late[lo..hi]};
    for(apart[k*8..][0..8],whole[k*8..][0..8])|*a,r|a.*=.{.soup=@intCast(k),.first=r.first-lo,.count=r.count};
  }
  var counted=Atomic(u32).init(0);
  var pooled=try weld(gpa,testing.io,&soups,&apart,&groups,&counted);
  defer pooled.deinit(gpa);
  try testing.expectEqual(@as(u32,whole.len),counted.load(.monotonic));
  try testing.expectEqualSlices(u8,sliceAsBytes(here.runs),sliceAsBytes(pooled.runs));
  try testing.expectEqualSlices(u32,here.indices.items,pooled.indices.items);
  try testing.expectEqualSlices(u8,sliceAsBytes(here.v.items),sliceAsBytes(pooled.v.items));
  try testing.expectEqualSlices(u8,sliceAsBytes(here.skin.items),sliceAsBytes(pooled.skin.items));
  try testing.expectEqualSlices(u8,sliceAsBytes(here.grow.items),sliceAsBytes(pooled.grow.items));
}
