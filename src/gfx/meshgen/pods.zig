//! pods: a plant's yield ripening on it, beads of sap where the paws pluck
//! it. Each is a closed bead marked `.pod` (col.a its place among the
//! plant's pods, tu.y its radius), so plant.vert swells it from a pale nub
//! about its own centre as the plant ripens, and every pod empties in turn
//! as its yield is taken; what it hangs from is the plant's own body.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, ratios
const m=engine.core.math;
/// colour types: a pod's stalk
const color=engine.core.color;
/// the species registry: a genome's pods
const species=lib.species;
/// a point or direction in 3D
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// the mesh builder pods are poured into
const Builder=lib.meshgen.Builder;
/// builds a closed ellipsoid: the bead itself
const ellipsoid=lib.meshgen.ellipsoid;
/// how many rings a bead is drawn with, pole to pole
const beadRings=8;
/// how many quads round each ring
const beadSegs=12;
/// marks every vertex from `start` on as pod `k` of `n`, `r` across (its
/// distance from the bead's centre along its normal: plant.vert shrinks it
/// back toward that centre)
pub fn mark(b:*Builder,start:usize,k:usize,n:usize,r:f32)void{
  for(b.v.items[start..])|*v|{
    v.part=@intFromEnum(lib.vertex.Part.pod);
    v.col.a=m.unorm8((m.f(k)+0.5)/m.f(n));
    v.tu[1]=r;
  }
}
/// pod `k` of the genome's: a round bead of sap `r` across at `at`, formed
/// with what grows at `t` (tu.x); white, for the shaders colour it as
/// what the plant yields
pub fn bead(b:*Builder,g:species.Genome,k:usize,at:V3,r:f32,t:f32)Allocator.Error!void{
  // where the bead's vertices begin
  const s=b.mark();
  try ellipsoid(b,.{.center=at,.radii=m.splat3(r),.col=color.rgb(1,1,1).toRgba8(255),.part=.pod,.rings=beadRings,.segs=beadSegs,.t=t});
  mark(b,s,k,g.pods,r);
}
/// pod `k` hanging from a stem: a short stalk out of `root` (on the stem's
/// skin, the way `out` and a little down), tapering into a bead at its end
/// that hangs below it. Returns where the bead sits.
pub fn hanging(b:*Builder,g:species.Genome,k:usize,root:V3,out:V3,drop:f32,stalk:color.Rgba8,t:f32)Allocator.Error!V3{
  // the bead's radius, how far out its stalk reaches and where it ends
  const r=g.podR;
  const reach=r*1.5;
  const at=root+out*m.splat3(reach)-v3(0,drop+r*0.5,0);
  // the stalk: arching out, then down into the bead's crown
  const path=[_]V3{root-out*m.splat3(r*0.3),root+out*m.splat3(reach*0.6)+v3(0,r*0.15,0),at+out*m.splat3(r*0.05)+v3(0,r*0.9,0),at+v3(0,r*0.3,0)};
  const ts=[_]f32{t,t,t,t};
  const rs=[_]f32{r*0.32,r*0.24,r*0.2,r*0.16};
  try b.tubeR(&path,&ts,&rs,stalk,.stem,5);
  try bead(b,g,k,at,r,t);
  return at;
}
/// the place pod `k` of `n` takes round a stem: its bearing, turned by the
/// golden angle from the one before so they never line up
pub fn bearing(k:usize,variant:u32)f32{return m.f(k)*2.39996+m.f(variant)*0.8;}
test"a bead is marked as its pod, its radius on every vertex"{
  // a builder, a genome with three pods, and the bead
  var b=Builder{.gpa=std.testing.allocator};
  defer b.deinit();
  var g=lib.species.get(.lumenroot).genome;
  g.pods=3;
  try bead(&b,g,1,v3(0,1,0),0.05,0.8);
  try std.testing.expect(b.v.items.len>0);
  for(b.v.items)|v|{
    try std.testing.expectEqual(@as(u32,@intFromEnum(lib.vertex.Part.pod)),v.part);
    try std.testing.expectEqual(m.unorm8(0.5),v.col.a);
    try std.testing.expectApproxEqAbs(@as(f32,0.05),v.tu[1],1e-6);
    // the centre sits a radius in along its normal
    const c=v3(v.pos[0],v.pos[1],v.pos[2])-v3(v.nrm[0],v.nrm[1],v.nrm[2])*m.splat3(0.05);
    try std.testing.expect(m.len(c-v3(0,1,0))<1e-3);
  }
}
