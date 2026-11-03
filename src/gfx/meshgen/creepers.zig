//! creepers: a moss creeper (the `creeper` form), lying low on the ground.
//! A cushion of moss at its heart, runners creeping out over the ground
//! from under it (`tendrils` of them, `stemH` long), arching a little
//! between the nodes where they touch down; at each node a small rosette
//! of leaves and a tuft of moss, rooting there with fine roots (the cushion
//! `bloomR` across). Its yield
//! ripens in beads nestled in the cushion.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, splines, lerps
const m=engine.core.math;
/// a seeded random stream, so each variant creeps a little differently
const Rng=engine.core.rng.Rng;
/// colour types and shading
const color=engine.core.color;
/// the species registry: a creeper's genome
const species=lib.species;
/// the garden's meshgen: builder, leaves, pods, grown vines
const mg=lib.meshgen;
/// a point or direction in 3D
const V3=m.V3;
/// builds a point or direction
const v3=m.v3;
/// the mesh builder creepers are poured into
const Builder=mg.Builder;
/// points along a runner, heart to tip
const runnerRes=24;
/// the nodes along a runner where it touches down and roots (share of its length)
const nodes=[_]f32{0.5,1};
/// how high a runner arches between its nodes (m)
const arch:f32=0.02;
/// lumps of moss in the cushion at its heart, and in each node's tuft
const cushionLumps=9;
/// (in a node's tuft)
const tuftLumps=3;
/// fine roots each node sends down
const nodeRoots=3;
/// a moss creeper grown from its genome, lying on the ground at its
/// origin; grown by tu.x (plant.vert): its cushion first, then its runners
/// creeping out, each node's rosette and tuft forming as the runner reaches it
pub fn creeper(b:*Builder,g:species.Genome,seed:u64,variant:u32)Allocator.Error!void{
  // its own random stream, and its colours
  var rng=Rng.init(seed);
  const runnerCol=g.stemCol.toRgba8(255);
  const mossCol=color.shade(g.leafCol,0.8);
  const mossTip=g.leafCol.toRgba8(255);
  // the cushion: soft lumps of moss heaped round its heart
  try lumps(b,&rng,v3(0,0,0),g.bloomR,cushionLumps,mossCol,mossTip,0);
  // the runners, out over the ground a golden angle apart
  for(0..g.tendrils)|i|{
    // its bearing and length
    const a=m.f(i)*m.goldenAngle+m.f(variant)*0.8+rng.range(-0.25,0.25);
    const len=g.stemH*rng.range(0.75,1.15);
    // its control points: out along the ground, wandering a little
    var c:[6]V3=undefined;
    mg.growthPath(.{.start=v3(0,0.01,0),.direction=v3(@cos(a),0,@sin(a)),.length=len,.wobble=0.35,.seed=seed+%i*53},&c);
    var p:[runnerRes]V3=undefined;
    m.splineResample(&c,&p);
    // each point's growth stamp and radius; laid on the ground, arching
    // between the nodes
    var ts:[runnerRes]f32=undefined;
    var rs:[runnerRes]f32=undefined;
    mg.taperRadii(g.stemR,0.25,&rs);
    for(&p,&ts,0..)|*q,*t,j|{
      // how far along the runner
      const s=m.ratio(j,runnerRes-1);
      q.*[1]=g.stemR+arch*@abs(@sin(s*m.pi*m.f(nodes.len)));
      t.*=m.lerp(0.2,0.95,s);
    }
    try b.tubeR(&p,&ts,&rs,runnerCol,.stem,5);
    // its nodes: a rosette of leaves and a tuft of moss, rooting there
    for(nodes)|k|{
      // where along the runner, and when it forms
      const at=m.alongPath(&p,k)-v3(0,g.stemR*0.5,0);
      const t=m.lerp(0.2,0.95,k);
      try lumps(b,&rng,at,g.bloomR*0.45,tuftLumps,mossCol,mossTip,t);
      for(0..g.leaves)|l|{
        // this leaf's bearing round the node
        const la=m.f(l)/m.f(g.leaves)*m.tau+a+rng.range(-0.3,0.3);
        try mg.leaf(b,.{
          .at=at+v3(0,g.stemR,0),.dir=m.norm(v3(@cos(la),0.35,@sin(la))),
          .len=g.leafLen*rng.range(0.8,1.15),.width=g.leafW*rng.range(0.85,1.1),.droop=g.leafDroop*rng.range(0.8,1.2),
          .twist=rng.range(-0.3,0.3),.wave=rng.range(0.05,0.15),.stalk=0.25,
          .col=color.shade(g.leafCol,0.7),.tip=mossTip,.stalkCol=runnerCol,.t=t,
        });
      }
      for(0..nodeRoots)|r|{
        // this root's bearing, and its points down into the ground
        const ra=m.f(r)/nodeRoots*m.tau+a;
        var rc:[4]V3=undefined;
        mg.growthPath(.{.start=at,.direction=m.norm(v3(@cos(ra),-1.5,@sin(ra))),.length=g.leafLen*0.6,.wobble=0.4,.seed=seed+%i*7+%r},&rc);
        var rp:[8]V3=undefined;
        m.splineResample(&rc,&rp);
        var rt:[8]f32=undefined;
        var rr:[8]f32=undefined;
        mg.taperRadii(g.stemR*0.5,0.3,&rr);
        for(&rt)|*x|x.*=t;
        try b.tubeR(&rp,&rt,&rr,color.shade(g.stemCol,0.5),.stem,4);
      }
    }
  }
  // its yield: beads nestled in the cushion
  for(0..g.pods)|k|{
    // this bead's bearing round the heart
    const pa=mg.pods.bearing(k,variant);
    try mg.pods.bead(b,g,k,v3(@cos(pa)*g.bloomR*0.4,g.bloomR*0.32,@sin(pa)*g.bloomR*0.4),g.podR,0.6);
  }
}
/// a heap of `n` soft lumps of moss round `at`, `r` across: low, flattened
/// ellipsoids, each its own size, the middle ones highest; formed at `t`
fn lumps(b:*Builder,rng:*Rng,at:V3,r:f32,n:usize,col:color.Rgba8,tip:color.Rgba8,t:f32)Allocator.Error!void{
  for(0..n)|i|{
    // where the lump sits, how big it is, and how high
    const a=m.f(i)*m.goldenAngle+rng.range(-0.3,0.3);
    const d=if(i==0)0 else r*0.55*@sqrt(m.ratio(i,n))*rng.range(0.8,1.1);
    const s=r*rng.range(0.32,0.45)*(1-0.35*d/r);
    try mg.ellipsoid(b,.{
      .center=at+v3(@cos(a)*d,s*0.35,@sin(a)*d),.radii=v3(s,s*0.62,s),
      .col=color.mix(col,tip,rng.range(0.2,0.8)),.part=.leaf,.rings=5,.segs=8,.t=t,
    });
  }
}
