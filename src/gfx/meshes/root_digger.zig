//! mesh: ROOT-DIGGER. a knot of roots that digs: four braided roots break
//! the ground, heaving the soil up round them, and twine up round each other
//! into a clutch, their tips curling over a small gourd of resin sap they
//! grip (what it has dug hangs inside, emitted `belly_lump`s), a tuft of
//! leaves sprouting from its crown, small leaves off the roots. Its digging
//! root to the node it works is its own (`root`, emitted toward the node).
//! It grows on hidden growth splines (gfx/growth.zig): the root mat
//! spreads as its stem rises, the gourd fills at the stem's top,
//! the clutch roots climb out of the soil round it with the stem, closing
//! over the gourd, the soil heaving where they break it and their leaves
//! unfolding as they pass, the tuft last.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const mg=lib.meshgen;
const pal=lib.palette;
const color=engine.core.color;
const vertex=lib.vertex;
const kit=lib.structureKit;
const conduit=lib.conduit;
const growth=lib.growth;
const Rng=engine.core.rng.Rng;
const V3=m.V3;
const v3=m.v3;
/// the gourd the clutch grips, where what it has dug hangs
pub const podAt=v3(0,0.32,0);
pub const podR=v3(0.13,0.125,0.13);
/// the stem: up out of the soil to the gourd's foot, then on through it to
/// the tuft at its crown
const stemPace:f32=1.6;
const crown=podAt+v3(0,podR[1]+0.035,0);
/// the clutch: roots round the knot, how far out they break the ground,
/// their girth, how far round they twine (radians) climbing to the gourd
const clutchCount=4;
const breakOut:f32=0.24;
const clutchR:f32=0.034;
const twine:f32=2.3;
const clutchPace:f32=1.3;
/// soil heaped where each clutch root breaks the ground: mounds (how far
/// out past it, how wide), clods tumbled about them
const mounds=[_][2]f32{.{0,0.05},.{0.045,0.036}};
const clods=3;
/// clutch root `i`'s control points: out under the soil from the stem's
/// foot, up out of it `BREAK_OUT` away, twining in round the knot and up
/// round the gourd's foot (clear of it), out round its widest and curling
/// in over its shoulder: fingers holding it
fn clutchCtrl(i:usize)[9]V3{
  var rng=Rng.init(0xD160+i*37);
  const a0=(m.f(i)+rng.range(-0.12,0.12))/clutchCount*m.tau+0.4;
  const out=rng.range(0.9,1.1);
  // (bearing past a0, out from the axis, height)
  const ks=[9][3]f32{
    .{0,0.02,-0.05},.{0.05,0.14,-0.05},.{0.1,breakOut*out,-0.012},.{0.5,0.21*out,0.055},
    .{1.0,0.13,0.14},.{1.45,0.12,0.22},.{1.85,podR[0]+0.035,podAt[1]+0.005},
    .{2.15,0.112,podAt[1]+0.09},.{twine,0.07,podAt[1]+0.115},
  };
  var c:[9]V3=undefined;
  for(&c,ks)|*p,k|{
    const a=a0+k[0];
    p.*=v3(@cos(a)*k[1],k[2],@sin(a)*k[1]);
  }
  return c;
}
pub fn build(b:*mg.Builder)Allocator.Error!void{
  var k=growth.Skeleton.begin(b);
  const stem=k.trunk(&.{v3(0,-0.05,0),v3(0.008,0.07,-0.006),podAt-v3(0,podR[1],0)},.{.pace=stemPace});
  try kit.rootMat(b,5,0.46,0.034,0xD161,.{.k=&k,.id=stem});
  // the gourd, swelling at the stem's top
  const g=b.mark();
  try kit.resinPod(b,podAt,podR,10,14);
  try k.on(b,g,stem,1,.{.from=podAt-v3(0,podR[1],0)});
  for(0..clutchCount)|i|try clutch(b,&k,stem,i);
  // the tuft: a sprout up out of the gourd's crown, leaves opening off it
  const sprout=k.branch(stem,1,&.{podAt-v3(0,podR[1],0),podAt+v3(0.004,0,0.003),crown},.{.delay=0.25});
  {
    const s=b.mark();
    try b.tube(&.{podAt+v3(0,podR[1]*0.8,0),crown},&.{0.8,0.9},0.02,0.013,pal.core,.stem,8);
    try k.on(b,s,sprout,0.8,.{.from=podAt+v3(0,podR[1]*0.8,0)});
  }
  for(0..5)|i|{
    const a=(m.f(i)+0.3)/5*m.tau;
    const dir=m.norm(v3(@cos(a),1.1+0.25*m.f(i%2),@sin(a)));
    const s=b.mark();
    try mg.blade(b,crown,dir,0.16+0.04*m.f(i%2),0.055,0.55,pal.leafDark,pal.leafLite,1,.leaf);
    try k.on(b,s,sprout,1,.{.from=crown,.delay=0.025*m.f(i)});
  }
  k.finish(b);
}
/// clutch root `i`: a braid out of the soil twining up to grip the gourd,
/// growing with the stem, the soil heaving up round it where it breaks
/// the ground; a small leaf or two off it as it climbs
fn clutch(b:*mg.Builder,k:*growth.Skeleton,stem:growth.Id,i:usize)Allocator.Error!void{
  const c=clutchCtrl(i);
  const id=k.branch(stem,0,&c,.{.after=.with,.pace=clutchPace,.delay=0.03*m.f(i)});
  {
    var rng=Rng.init(0xD165+%i*17);
    const u=k.nearest(id,c[2]);
    const at=k.point(id,u);
    const out=m.norm(v3(at[0],0,at[2]));
    const side=m.cross(v3(0,1,0),out);
    const s=b.mark();
    for(mounds)|h|{
      const p=at+out*m.splat3(h[0]);
      try mg.ellipsoid(b,.{.center=v3(p[0],-0.008,p[2]),.radii=v3(h[1],h[1]*0.55,h[1]),.col=pal.soil,.rings=5,.segs=9});
    }
    for(0..clods)|j|{
      const a=m.f(j)*2.1+rng.range(-0.4,0.4);
      const d=rng.range(0.06,0.09);
      const p=at+(side*m.splat3(@cos(a))+out*m.splat3(@sin(a)))*m.splat3(d);
      const cr=rng.range(0.012,0.02);
      try mg.ellipsoid(b,.{.center=v3(p[0],0.002,p[2]),.radii=v3(cr,cr*0.7,cr*1.1),.col=pal.soilDark,.rings=3,.segs=5});
    }
    try k.on(b,s,id,u,.{.from=v3(at[0],-0.01,at[2])});
  }
  try k.braid(b,id,.{.girth=clutchR,.tip=0.3,.strands=3,.twist=2.6,.wobble=pal.strandWobble,.seed=0xD163+%i*7,.core=pal.core,.strand=pal.vine,.t0=0.05,.t1=0.7});
  try k.leaves(b,id,.{.n=1+@as(u32,@intCast(i%2)),.len=0.12,.width=0.042,.from=0.42,.to=0.62,.t0=0.3,.t1=0.6,.col=pal.leafDark,.tip=pal.leafLite,.seed=0xD164+%i*5});
}
/// mesh: DIGGER ROOT. the root it digs with, from under the knot along +X
/// into the node on the next tile: woven as a conduit (`conduit.arch`), it
/// comes up beside the knot, arches over and dives into the node, a claw
/// of thick rootlets splaying through it. Its core runs the other way to a
/// conduit's (tu.x 0 in the node .. 1 at the knot), so what it draws out
/// swells and tints it on its way home (part.vert, `Look.carry`). It grows
/// along its own spline by how far it has reached (emitted with that as
/// `grown`), the claw last, and withers back down it.
pub const root=struct{
  pub const reachDistance:f32=0.9;
  /// the claw: rootlets splayed down through the node, each a little after
  /// the one before
  const claw=[_]f32{-1.4,-0.6,0.15,0.85,1.55};
  const clawStagger:f32=0.035;
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    var k=growth.Skeleton.begin(b);
    const start=b.mark();
    const spine=try conduit.arch(b,&k,.{
      .from=0.08,.to=reachDistance,.peak=0.15,.depth=0.09,.coreR=0.03,.strands=2,
      .turns=1.6,.core=.core,.leaves=&.{2,3},.runners=true,.seed=0xD170,
    });
    // its sap runs home
    for(b.v.items[start..])|*vx|if(vx.part==@intFromEnum(vertex.Part.core)){
      vx.tu[0]=1-vx.tu[0];
    };
    const end=v3(reachDistance,-0.03,0);
    for(claw,0..)|a,i|{
      const s=b.mark();
      try kit.rootlet(b,end,m.norm(v3(@cos(a)*0.75+0.2,-0.5,@sin(a)*0.75)),0.24,0.017,0xD171+%i*29);
      try k.on(b,s,spine,1,.{.from=end,.delay=clawStagger*m.f(i)});
    }
    k.finish(b);
  }
};
/// mesh: DIGGER CLOD. a clod of the node's soil the digging root prises
/// loose, a unit across: two lumps of earth stuck together, a grit chip in
/// it; flung up about the node as it draws an item out, falling back.
pub const clod=struct{
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(0.5,0.38,0.45),.col=pal.soil,.rings=4,.segs=6});
    try mg.ellipsoid(b,.{.center=v3(0.28,0.12,-0.1),.radii=v3(0.3,0.26,0.28),.col=pal.soilDark,.rings=3,.segs=5});
    try mg.ellipsoid(b,.{.center=v3(-0.2,0.2,0.18),.radii=v3(0.16,0.12,0.14),.col=color.rgb(0.55,0.52,0.47).toRgba8(255),.rings=3,.segs=4});
  }
};
