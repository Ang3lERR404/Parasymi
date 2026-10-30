//! mesh: GANGLION. a parasite's nerve knot: a bulbous foot half sunk in the
//! soil, a short stalk of the lineage's lattice parting round a sac on its
//! core, and on it a knot of pale nodules in two even rings of five round a
//! translucent bladder where what it holds hangs (emitted, `bellyLump`s),
//! a crown of five short lilac fronds curling over it, alike. Its nerves out to the neighbours it feeds are its own
//! (`nerve`, emitted per side), and pulses run out along them.
//! It grows on a hidden stalk (gfx/growth.zig): the foot swells and its
//! roots spread with it, the stalk rises, the nodules swell out of its
//! top ring by ring round the bladder, the fronds curl over last.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// the plant-piece mesher: braids, grown paths, the builder itself
const mg=lib.meshgen;
/// the garden's growth timing: the hidden stalk everything grows along
const growth=lib.growth;
/// the parasite kit: feet, roots, lattice stalks, bladders and nodules
const pk=lib.parasiteKit;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// the stalk's top, where the bladder swells from
const neck=v3(0,0.17,0);
/// how the lattice stalk is shaped: its girth, how far its strands part and
/// over which stretch of it (0..1) they open round the sac
const stalkShape:pk.Stalk=.{.girth=0.03,.part=2.0,.from=0.25,.to=0.92};
/// the bladder at the knot's heart, where what it holds hangs
pub const heartAt=v3(0,0.29,0);
/// the bladder's half-sizes along x, y and z
pub const heartR=v3(0.115,0.1,0.115);
/// how many rings of nodules circle the bladder
/// (the lower one round its flank, the upper round its waist)
const rings=2;
/// how much later each ring swells than the one below (share of the growth)
const ringStagger:f32=0.06;
/// how many fronds curl over the crown: the lineage's fivefold
const fronds=pk.fold;
/// builds the knot: the foot and roots, the lattice stalk and its organs,
/// the bladder, two rings of nodules round it, then the crown of fronds;
/// all hung on one growth skeleton in that order
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the growth skeleton everything below is hung on
  var k=growth.Skeleton.begin(b);
  // the hidden stalk: from just under the ground up to the neck
  const stalk=k.trunk(&.{v3(0,-0.03,0),v3(0.012,0.07,-0.008),neck},.{.pace=1.6});
  try pk.foot(b,&k,stalk,v3(0,-0.01,0),v3(0.11,0.07,0.11));
  try pk.roots(b,&k,stalk,pk.fold,0.22,0.014,0x6A7);
  try pk.stalk(b,&k,stalk,stalkShape);
  try pk.organs(b,&k,stalk,stalkShape,1,0.6);
  try pk.bladder(b,&k,stalk,1,heartAt,heartR,1,.{.from=neck});
  // the nodules: pale knots of nerve in two rings round the bladder, one
  // round its lower flank and a smaller one round its waist turned half a
  // step, each ring swelling out of the stalk's top at once
  for(0..rings)|ring|for(0..pk.fold)|i|{
    // this nodule's angle round the bladder: the upper ring turned half a step
    const a=(m.f(i)+0.5*m.f(ring))/m.f(pk.fold)*m.tau;
    // which way it sits off the bladder's centre: a little down, or a little up
    const dir=m.norm(v3(@cos(a),if(ring==0)@as(f32,-0.35)else 0.15,@sin(a)));
    // its size, the lower ring's a little larger
    const r:f32=if(ring==0)0.052 else 0.042;
    // where it sits: on the bladder's skin, pushed out by most of its own size
    const at=heartAt+dir*heartR+dir*m.splat3(r*0.7);
    // where its vertices begin, so it swells in its ring's turn
    const s=b.mark();
    try pk.nodule(b,at,v3(r,r*0.85,r),0.9,pk.skin,pk.core,pk.pearl);
    try k.on(b,s,stalk,1,.{.from=neck,.delay=0.04+ringStagger*m.f(ring)});
  };
  // a crown of short fronds curling in over the bladder, alike
  for(0..fronds)|i|{
    // this frond's angle round the crown (radians)
    const a=(m.f(i)+0.4)/fronds*m.tau;
    // the frond's control points, from the neck up over the bladder and in
    var c:[8]V3=undefined;
    for(&c,0..)|*p,j|{
      // how far along the frond this point is (0..1)
      const f=m.ratio(j,7);
      // how far round the bladder from its side over toward its top
      const th=m.lerp(m.pi*0.62,-0.25,f);
      // how far off the skin it is held, lifting toward the tip
      const lift=1.12+0.3*f*f;
      p.*=heartAt+v3(@sin(th)*@cos(a+0.3*f)*heartR[0]*lift,@cos(th)*heartR[1]*1.12-0.03*f*f*f,@sin(th)*@sin(a+0.3*f)*heartR[2]*lift);
    }
    c[0]=neck;
    mg.grow(c[1..],.{.start=c[1],.direction=v3(0,1,0),.length=0.3,.wobble=0.12,.seed=0x6B0});
    // the frond's own branch of the skeleton, grown after the nodules
    const id=k.branch(stalk,1,&c,.{.delay=0.14});
    try k.tube(b,id,.{.r0=0.011,.tip=0.15,.col=pk.lilac,.part=.tendril,.sides=5,.t0=0.8,.t1=1});
  }
  k.finish(b);
}
/// mesh: GANGLION NERVE. a nerve from under the knot out along +X to the
/// tile's edge, arching low and diving into the ground there toward the
/// neighbour it feeds; its core (part `.core`, tu.x 0 at the knot .. 1 at
/// the edge) carries a pulse of what it hands on (part.vert). It grows
/// out along its own spline as it reaches (emitted with that as `grown`).
pub const nerve=struct{
  /// builds the nerve: a low arch out along +X, its tapering lilac core
  /// (`.core`, tu.x 0..1 along it) sheathed in a braid of two pale strands
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the growth skeleton the nerve is hung on
    var k=growth.Skeleton.begin(b);
    // the arch's control points, from beside the knot out to the tile's edge
    var c:[6]V3=undefined;
    for(&c,0..)|*p,j|{
      // how far along the arch this point is (0..1)
      const f=m.ratio(j,5);
      p.*=v3(0.06+0.46*f,0.09*(1-f)+0.05*@sin(m.pi*f)-0.05*f*f*f,0);
    }
    mg.grow(c[1..],.{.start=c[1],.direction=v3(1,0,0),.length=0.46,.wobble=0.2,.seed=0x6C0});
    // the nerve's own spline, which everything grows along
    const id=k.trunk(&c,.{});
    // the core the pulse runs through, sheathed in two pale strands
    // the core's path, its growth timing and its radius along it
    var sp:[growth.res]V3=undefined;
    var ts:[growth.res]f32=undefined;
    var rs:[growth.res]f32=undefined;
    k.path(id,0,1,&sp);
    for(&ts,&rs,0..)|*t,*r,j|{
      // how far along the nerve this point is (0..1)
      const u=m.ratio(j,growth.res-1);
      t.*=u;
      r.*=0.016*(1-0.45*u);
    }
    // where the nerve's vertices begin, so it all grows out together
    const s=b.mark();
    try b.tubeR(&sp,&ts,&rs,pk.lilac,.core,6);
    // the sheath's radius: just wider than the core it wraps
    var sheath:[growth.res]f32=undefined;
    for(&sheath,rs)|*r,r0|r.*=r0*1.15;
    try mg.braid(b,&sp,&ts,&sheath,2,3.2,pk.wobble,0x6C1,pk.core,pk.pearl);
    try k.along(b,s,id);
    k.finish(b);
  }
};
