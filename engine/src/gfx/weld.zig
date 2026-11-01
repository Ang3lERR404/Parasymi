//! welding a triangle soup into an indexed mesh: a corner that is the very
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
/// the standard library
const std=@import("std");
/// the allocator the welded lists grow with
const Allocator=std.mem.Allocator;
/// the test helpers
const testing=std.testing;
/// a value's bytes, which welding compares
const asBytes=std.mem.asBytes;
/// the hash a corner's bytes are hashed with
const Wyhash=std.hash.Wyhash;
/// all the maths: the (first, count) rows runs are given as
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
/// and growth record beside it (the three lists equally long)
pub const Soup=struct{
  /// the vertices
  v:[]const vertex.Mesh,
  /// each vertex's skin weights
  skin:[]const vertex.Skin,
  /// each vertex's growth record
  grow:[]const vertex.Grow,
  /// the vertices whose triangles go last (none: no triangle is late)
  late:?[]const bool=null,
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
  /// the soup the runs lie in
  soup:Soup,
  /// where each run of the group begins in it
  firsts:[]const u32,
  /// a corner's bytes in every run, hashed
  pub fn hash(c:Corners,j:u32)u64{
    // the hash, fed every run's vertex, weights and record
    var h=Wyhash.init(0);
    for(c.firsts)|f|{
      h.update(asBytes(&c.soup.v[f+j]));
      h.update(asBytes(&c.soup.skin[f+j]));
      h.update(asBytes(&c.soup.grow[f+j]));
    }
    return h.final();
  }
  /// whether two corners are the same vertex in every run, bit for bit
  /// (the layouts are extern structs of 4-byte fields: no padding)
  pub fn eql(c:Corners,a:u32,b:u32)bool{
    for(c.firsts)|f|{
      if(!std.mem.eql(u8,asBytes(&c.soup.v[f+a]),asBytes(&c.soup.v[f+b])))return false;
      if(!std.mem.eql(u8,asBytes(&c.soup.skin[f+a]),asBytes(&c.soup.skin[f+b])))return false;
      if(!std.mem.eql(u8,asBytes(&c.soup.grow[f+a]),asBytes(&c.soup.grow[f+b])))return false;
    }
    return true;
  }
  /// whether the triangle from corner `t` is late: any of its corners in
  /// any run of the group
  fn late(c:Corners,t:u32)bool{
    // which soup vertices are marked late
    const marks=c.soup.late orelse return false;
    for(c.firsts)|f|for(f+t..f+t+3)|k|if(marks[k])return true;
    return false;
  }
};
/// the map from a corner to the kept vertex it is drawn from
const Map=std.HashMapUnmanaged(u32,u32,Corners,std.hash_map.default_max_load_percentage);
/// weld the runs `ranges` (first vertex, count) of `soup`, each in the
/// group `groups` names: runs of one group are as long as each other and
/// share their indices. The welded runs come out in the order their soup
/// lay in (a group where its first run lay), so a later key's vertices
/// stay after an earlier one's.
pub fn weld(gpa:Allocator,soup:Soup,ranges:[]const m.Vice(u32,2),groups:[]const u32)Allocator.Error!Welded{
  std.debug.assert(ranges.len==groups.len);
  std.debug.assert(soup.skin.len==soup.v.len and soup.grow.len==soup.v.len);
  // what comes out, freed again if welding fails
  var w=Welded{};
  errdefer w.deinit(gpa);
  w.runs=try gpa.alloc(Run,ranges.len);
  @memset(w.runs,.{});
  // the runs in the order their soup lies in
  const order=try gpa.alloc(u32,ranges.len);
  defer gpa.free(order);
  for(order,0..)|*o,i|o.*=@intCast(i);
  std.mem.sort(u32,order,ranges,earlier);
  // which runs are welded already
  const done=try gpa.alloc(bool,ranges.len);
  defer gpa.free(done);
  @memset(done,false);
  // the group being welded: its runs, where each begins, its kept corners
  var members:std.ArrayList(u32)=.empty;
  defer members.deinit(gpa);
  var firsts:std.ArrayList(u32)=.empty;
  defer firsts.deinit(gpa);
  var kept:std.ArrayList(u32)=.empty;
  defer kept.deinit(gpa);
  var map=Map.empty;
  defer map.deinit(gpa);
  for(order)|i|{
    if(done[i] or ranges[i][1]==0)continue;
    // this group's runs, in the order their soup lies in
    members.clearRetainingCapacity();
    firsts.clearRetainingCapacity();
    for(order)|j|if(!done[j] and ranges[j][1]>0 and groups[j]==groups[i]){
      std.debug.assert(ranges[j][1]==ranges[i][1]);
      try members.append(gpa,j);
      try firsts.append(gpa,ranges[j][0]);
      done[j]=true;
    };
    // how many corners each run has, and where the group's indices begin
    const n=ranges[i][1];
    std.debug.assert(n%3==0);
    const first:u32=@intCast(w.indices.items.len);
    // how the group's corners are seen: each in every run at once
    const corners=Corners{.soup=soup,.firsts=firsts.items};
    kept.clearRetainingCapacity();
    map.clearRetainingCapacity();
    try w.indices.ensureUnusedCapacity(gpa,n);
    // how many indices come before the late triangles
    var early:u32=0;
    // the early triangles first, then the late ones
    for([_]bool{false,true})|lateNow|{
      if(lateNow)early=@as(u32,@intCast(w.indices.items.len))-first;
      // each triangle's first corner
      var t:u32=0;
      while(t<n):(t+=3){
        if(corners.late(t)!=lateNow)continue;
        for(t..t+3)|c|{
          // this corner, and the kept vertex it is (a new one if none yet)
          const j:u32=@intCast(c);
          const got=try map.getOrPutContext(gpa,j,corners);
          if(!got.found_existing){
            got.value_ptr.*=@intCast(kept.items.len);
            try kept.append(gpa,j);
          }
          w.indices.appendAssumeCapacity(got.value_ptr.*);
        }
      }
    }
    for(members.items,firsts.items)|r,f|{
      w.runs[r]=.{.first=first,.count=n,.base=@intCast(w.v.items.len),.verts=@intCast(kept.items.len),.early=early};
      try w.v.ensureUnusedCapacity(gpa,kept.items.len);
      try w.skin.ensureUnusedCapacity(gpa,kept.items.len);
      try w.grow.ensureUnusedCapacity(gpa,kept.items.len);
      for(kept.items)|k|{
        w.v.appendAssumeCapacity(soup.v[f+k]);
        w.skin.appendAssumeCapacity(soup.skin[f+k]);
        w.grow.appendAssumeCapacity(soup.grow[f+k]);
      }
    }
  }
  return w;
}
/// whether run `a`'s soup lies before run `b`'s
fn earlier(ranges:[]const m.Vice(u32,2),a:u32,b:u32)bool{return ranges[a][0]<ranges[b][0];}
/// a soup vertex at `x` along, coloured by `k`
fn testVertex(x:f32,k:u8)vertex.Mesh{
  return.{.pos=.{x,0,0},.nrm=.{0,1,0},.col=.{.r=k,.g=0,.b=0,.a=255},.tu=.{0,0,0},.part=0};
}
/// every corner of run `r` drawn welded is the soup's own corner, bit for bit
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
  const ranges=[_]m.Vice(u32,2){.{6,3},.{0,6},.{0,0}};
  var w=try weld(testing.allocator,soup,&ranges,&.{0,1,2});
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
  const ranges=[_]m.Vice(u32,2){.{6,6},.{0,6}};
  var w=try weld(testing.allocator,soup,&ranges,&.{7,7});
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
  var w=try weld(testing.allocator,soup,&.{.{0,12}},&.{0});
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
