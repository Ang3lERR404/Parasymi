//! the garden's meshes tested: blades and growth keys.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the test allocator and expectations
const testing=std.testing;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, crosses, dots
const m=engine.core.math;
/// colour types, for a test blade's green
const color=engine.core.color;
/// a point or direction in 3D
const V3=m.V3;
/// the mesh builder the tests pour into
const Builder=lib.meshgen.Builder;
/// how many growth keys a confluence is built at
const keys=lib.meshgen.keys;
/// a growth key and the blend toward the next
const Key=lib.meshgen.Key;
/// builds a curved blade
const blade=lib.meshgen.blades.blade;
/// the key a confluence sits at for a growth
const growthKey=lib.meshgen.growthKey;
/// builds one whole plant of a species
const plant=lib.meshgen.shoots.plant;
test"a blade has a body: both faces, wound outward, its vein on the cupped face"{
  // a fresh builder the blade is poured into
  var b:Builder=.{.gpa=testing.allocator};
  defer b.deinit();
  // the blade's colour, the same base to tip
  const c=color.rgb(0.3,0.6,0.2).toRgba8(255);
  try blade(&b,m.v3(0,0,0),m.v3(1,0,0),1,0.2,0.3,c,c,1,.leaf);
  // how many triangles face up, how many face down, and the one being read
  var up:usize=0;
  var down:usize=0;
  var tri:usize=0;
  while(tri<b.v.items.len):(tri+=3){
    // this triangle's three vertices, their positions
    const v=b.v.items[tri..tri+3];
    const p:[3]V3=.{v[0].pos,v[1].pos,v[2].pos};
    // their summed normals, and the triangle's own facing from its winding
    const n:V3=@as(V3,v[0].nrm)+@as(V3,v[1].nrm)+@as(V3,v[2].nrm);
    const g=m.cross(p[1]-p[0],p[2]-p[0]);
    if(m.len(g)<1e-9)continue;
    try testing.expect(m.dot(g,n)>0);
    if(m.norm(g)[1]>0.5)up+=1;
    if(m.norm(g)[1]<-0.5)down+=1;
  }
  try testing.expect(up>0 and down>0);
  // the vein's crest is paler than the blade, and stands on the face looking up
  // whether any vertex was the vein's paler colour
  var pale=false;
  for(b.v.items)|vx|if(vx.col.r>c.r+10){
    pale=true;
    try testing.expect(vx.nrm[1]>0);
  };
  try testing.expect(pale);
}
test"a confluence's growth keys share one vertex layout and grow taller"{
  // a fresh builder each key is poured into
  var b:Builder=.{.gpa=testing.allocator};
  defer b.deinit();
  // each key's vertex count and its top's height
  var counts:[keys]usize=undefined;
  var tops:[keys]f32=undefined;
  for(0..keys)|v|{
    b.v.clearRetainingCapacity();
    try plant(&b,.confluence,@intCast(v));
    counts[v]=b.v.items.len;
    // the highest point of this key's mesh
    var hi:f32=0;
    for(b.v.items)|x|hi=@max(hi,x.pos[1]);
    tops[v]=hi;
  }
  for(counts[1..])|c|try testing.expectEqual(counts[0],c);
  for(tops[1..],tops[0..keys-1])|t,prev|try testing.expect(t>=prev);
  // keys cover growth end to end; between keys the blend is the fraction
  try testing.expectEqual(Key{.v=0,.f=0},growthKey(.confluence,0).?);
  // the key at full growth
  const end=growthKey(.confluence,1).?;
  try testing.expect(end.v==keys-2 and end.f==1);
  try testing.expect(growthKey(.lumenroot,0.5)==null);
}
test"every plant that yields ripens it in all its pods, where the paws reach for it"{
  inline for(lib.species.ids)|id|{
    // its kind, and the shape a grown one takes (a confluence's last key)
    const def=lib.species.get(id);
    const variant:u32=if(def.genome.form==.confluence)keys-1 else 0;
    var b:Builder=.{.gpa=testing.allocator};
    defer b.deinit();
    try plant(&b,id,variant);
    // which pods were found, and the heights of their vertices summed
    var seen=[_]bool{false}**16;
    var sum:f32=0;
    var n:usize=0;
    for(b.v.items)|v|if(v.part==@intFromEnum(lib.vertex.Part.pod)){
      seen[@min(m.floorTo(usize,m.f(v.col.a)/255*m.f(def.genome.pods)),15)]=true;
      sum+=v.pos[1];
      n+=1;
    };
    // as many pods as its genome, each its own; none on a plant that yields nothing
    var found:usize=0;
    for(seen)|s|found+=@intFromBool(s);
    try testing.expectEqual(@as(usize,def.genome.pods),found);
    if(n>0)try testing.expect(@abs(sum/m.f(n)-def.pluck)<0.15);
  }
}
test"a floater's touched body covers all of its mesh, so what is looked at is what is touched"{
  inline for(lib.species.ids)|id|{
    // its kind; only floaters are touched by their body
    const def=lib.species.get(id);
    if(def.floating){
      // its mesh, grown whole
      var b:Builder=.{.gpa=testing.allocator};
      defer b.deinit();
      try plant(&b,id,0);
      for(b.v.items)|v|{
        // how far below and above its float the vertex lies, and how far out
        try testing.expect(v.pos[1]>=-def.trails-0.05);
        try testing.expect(v.pos[1]<=def.crests+0.05);
        try testing.expect(m.lenOf(f32,2,.{v.pos[0],v.pos[2]})<=def.girth+0.05);
      }
    }
  }
}
test"every plant's mesh is whole: no vertex lands nowhere"{
  inline for(lib.species.ids)|id|{
    // its mesh, grown whole
    var b:Builder=.{.gpa=testing.allocator};
    defer b.deinit();
    try plant(&b,id,0);
    for(b.v.items)|v|for(0..3)|k|try testing.expect(@abs(v.pos[k])<1e4);
  }
}
