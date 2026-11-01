//! lilies: a water lily (the `lily` form), its origin on the water's
//! surface. Its crown roots under the water (`stemH` deep), long slack
//! stems rising from it to round pads lying flat on the surface, each
//! notched to its middle where its stem meets it underneath, and one bloom
//! of many pointed petals resting on the water on its own stem, its yield
//! in beads floating round it. Where there is no water it lies on the mud,
//! its stems sunk in the ground.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, splines, lerps
const m=engine.core.math;
/// a seeded random stream, so each variant lies a little differently
const Rng=engine.core.rng.Rng;
/// colour types and shading
const color=engine.core.color;
/// the species registry: a lily's genome
const species=lib.species;
/// the garden's meshgen: builder, laminae, flowers, pods, grown vines
const mg=lib.meshgen;
/// a point or direction in 3D
const V3=m.V3;
/// builds a point or direction
const v3=m.v3;
/// the mesh builder lilies are poured into
const Builder=mg.Builder;
/// rows along each half of a pad, back edge to front
const padRows=14;
/// how wide a pad's notch opens at its edge (of its radius), closing to its middle
const notch:f32=0.16;
/// how far each pad lies over the one beneath it, so none flicker (m)
const padStack:f32=0.0015;
/// how high a pad lies over the water (m): over its ripples, its bob and
/// the water rising since it was last read back, so it never sinks under
const padFloat:f32=0.025;
/// points along a stem, crown to pad
const stemRes=16;
/// how many roots the crown sends down
const roots=4;
/// the golden angle: each pad a little apart from the last
const golden:f32=2.39996;
/// how many sepals lie under a bloom
const sepals=4;
/// a bloom's rings of petals, outer to inner: how many, how long (of the
/// bloom's radius), how steeply each rises and how far it flares open
const rings=[_]m.Vec(f32,4){.{12,1,0.18,0.12},.{10,0.85,0.55,0.25},.{8,0.62,1.0,0.35}};
/// how narrow a petal is (its half-width, of its length): pointed
const petalNarrow:f32=0.24;
/// how many stamens stand in a bloom's heart
const heartStamens=16;
/// the heart's gold
const heartCol=color.rgb(1.0,0.78,0.28);
/// a water lily grown from its genome, its origin the water's surface;
/// grown by tu.x (plant.vert): its crown first, then its stems rising and
/// their pads opening one by one, its bloom last
pub fn lily(b:*Builder,g:species.Genome,seed:u64,variant:u32)Allocator.Error!void{
  // its own random stream; how deep its crown sits
  var rng=Rng.init(seed);
  const deep=g.stemH;
  const crown=v3(0,-deep,0);
  // its colours: stems, the pads' deep green and their paler, warmer rims
  const stemCol=g.stemCol.toRgba8(255);
  const padCol=color.shade(g.leafCol,0.85);
  const rimCol=color.mix(g.leafCol.toRgba8(255),color.rgb(0.62,0.45,0.32).toRgba8(255),0.35);
  // the crown: a rhizome lying in the mud, roots reaching down from it
  try mg.ellipsoid(b,.{.center=crown,.radii=v3(g.stemR*4,g.stemR*2.5,g.stemR*3),.col=color.shade(g.stemCol,0.5),.part=.stem,.rings=6,.segs=8,.t=0});
  for(0..roots)|i|{
    // this root's bearing, and its points down into the mud
    const a=m.ratio(i,roots)*m.tau+m.f(variant);
    var c:[5]V3=undefined;
    mg.growthPath(.{.start=crown,.direction=m.norm(v3(@cos(a),-1.2,@sin(a))),.length=deep*0.5,.wobble=0.3,.seed=seed+%i*19},&c);
    var p:[10]V3=undefined;
    m.splineResample(&c,&p);
    // each point's growth stamp and radius
    var ts:[10]f32=undefined;
    var rs:[10]f32=undefined;
    mg.taperRadii(g.stemR*0.8,0.3,&rs);
    for(&ts)|*t|t.*=0;
    try b.tubeR(&p,&ts,&rs,color.shade(g.stemCol,0.45),.stem,4);
  }
  // the pads, spread round the crown a golden angle apart, each farther
  // out than the last, stacked so the later lie over the earlier
  for(0..g.leaves)|i|{
    // its bearing, how far out its middle lies, its radius and when it opens
    const a=m.f(i)*golden+m.f(variant)*0.9+rng.range(-0.3,0.3);
    const out=g.leafLen*(0.9+0.75*m.ratio(i,@max(g.leaves,1)))*rng.range(0.85,1.15);
    const r=g.leafLen*rng.range(0.75,1.05);
    const t=m.lerp(0.25,0.8,m.ratio(i,@max(g.leaves,1)));
    const mid=v3(@cos(a)*out,padFloat+padStack*m.f(i),@sin(a)*out);
    try stem(b,crown,mid-v3(0,padFloat*2,0),g.stemR,stemCol,t,seed+%i*37);
    // the notch faces back toward the crown, a little turned
    const back=a+m.pi+rng.range(-0.6,0.6);
    try pad(b,mid,v3(-@cos(back),0,-@sin(back)),r,padCol,rimCol,t);
  }
  // the bloom on its own stem, resting on the water near the middle
  const fa=m.f(variant)*1.7+0.4;
  const top=v3(@cos(fa)*g.leafLen*0.35,padFloat+0.01,@sin(fa)*g.leafLen*0.35);
  try stem(b,crown,top-v3(0,0.01,0),g.stemR*1.1,stemCol,0.85,seed^0xF10);
  try bloom(b,g,top,m.f(variant),0.95);
  // its yield: beads floating on the water round the bloom
  for(0..g.pods)|k|{
    // this bead's bearing round the bloom
    const pa=mg.pods.bearing(k,variant);
    try mg.pods.bead(b,g,k,top+v3(@cos(pa)*g.bloomR*1.25,g.podR*0.6-0.01,@sin(pa)*g.bloomR*1.25),g.podR,0.95);
  }
}
/// a water lily's bloom open on the water at `top`: four green sepals
/// lying flat under it, then rings of narrow pointed petals, the outer
/// lying almost flat, each ring further in standing more upright and
/// shorter, opening into a star round a golden heart of stamens
fn bloom(b:*Builder,g:species.Genome,top:V3,spin:f32,t:f32)Allocator.Error!void{
  // the sepals: green above, flat on the water
  for(0..sepals)|i|{
    // this sepal's bearing
    const a=(m.f(i)+0.5)/sepals*m.tau+spin;
    try mg.petal(b,.{
      .base=top,.out=v3(@cos(a),0,@sin(a)),.len=g.bloomR*0.95,.width=g.bloomR*0.3,
      .rise=0.1,.flare=0.05,.cup=0.15,
      .col=color.shade(g.leafCol,0.6),.tip=g.leafCol.toRgba8(255),.t=t-0.03,.part=.leaf,
    });
  }
  // the rings of petals, outer to inner: how many, how long, how wide,
  // how steeply each rises and flares
  for(rings,0..)|ring,k|{
    // its petals' count, their bearing offset so each ring sits between
    // the last's, their base lifted a little over the last's
    const n:usize=@intFromFloat(ring[0]);
    const off=m.f(k)*0.5;
    const base=top+v3(0,0.004*m.f(k),0);
    for(0..n)|i|{
      // this petal's bearing
      const a=(m.f(i)+off)/m.f(n)*m.tau+spin*0.37;
      try mg.petal(b,.{
        .base=base,.out=v3(@cos(a),0,@sin(a)),.len=g.bloomR*ring[1],.width=g.bloomR*ring[1]*petalNarrow,
        .rise=ring[2],.flare=ring[3],.cup=0.45,
        .col=color.mix(g.bloomCol.toRgba8(255),heartCol.toRgba8(255),0.25),.tip=g.bloomCol.toRgba8(255),.t=t,
      });
    }
  }
  // the golden heart: many stamens standing up out of it
  try mg.stamens(b,.{
    .heart=top+v3(0,0.01,0),.axis=v3(0,1,0),.n=heartStamens,
    .len=g.bloomR*0.4,.r=g.bloomR*0.03,.anther=g.bloomR*0.16,
    .lean=0.45,.arch=0.4,.col=heartCol.toRgba8(255),.spin=spin,.t=t,.seed=@as(u32,@bitCast(spin)),
  });
}
/// a stem rising from the crown under the water to `to`, slack and a
/// little wandering, tapering to its rounded ends; formed from `t`'s first
/// tenth up to `t` along it
fn stem(b:*Builder,crown:V3,to:V3,r:f32,col:color.Rgba8,t:f32,seed:u64)Allocator.Error!void{
  // its control points: up from the crown, leaning out toward where it ends
  var c:[6]V3=undefined;
  for(&c,0..)|*p,j|{
    // how far along, and how far it has leant out by then (slack: it rises
    // first, then reaches over)
    const s=m.ratio(j,c.len-1);
    const over=s*s*(3-2*s);
    p.*=v3(to[0]*over,m.lerp(crown[1],to[1],@sqrt(s)),to[2]*over);
  }
  mg.grow(&c,.{.start=c[0],.direction=m.norm(c[5]-c[0]),.length=m.dist(c[5],c[0]),.wobble=0.2,.seed=seed});
  // the stem resampled smooth, its growth stamps and radii
  var p:[stemRes]V3=undefined;
  m.splineResample(&c,&p);
  var ts:[stemRes]f32=undefined;
  var rs:[stemRes]f32=undefined;
  mg.taperRadii(r,0.2,&rs);
  for(&ts,0..)|*x,j|x.*=m.lerp(t*0.1,t,m.ratio(j,stemRes-1));
  try b.tubeR(&p,&ts,&rs,col,.stem,5);
}
/// a pad lying flat at `mid`, `r` across, its notch opening toward `-dir`:
/// two lobes, each a lamina from the back edge to the front, meeting
/// along the front and parted by the notch behind the middle; deep green,
/// warming toward the rim
fn pad(b:*Builder,mid:V3,dir:V3,r:f32,col:color.Rgba8,rim:color.Rgba8,t:f32)Allocator.Error!void{
  // the way across the pad, and its face (up)
  const side=m.norm(m.cross(v3(0,1,0),dir));
  const up=v3(0,1,0);
  // where its vertices begin, for its veins (below)
  const first=b.mark();
  for([_]f32{-1,1})|s|{
    // each row's middle, the way across it, its face, half-width, dish and colour
    var sp:[padRows]V3=undefined;
    var sd:[padRows]V3=undefined;
    var fc:[padRows]V3=undefined;
    var wd:[padRows]f32=undefined;
    var ds:[padRows]f32=undefined;
    var cs:[padRows]color.Rgba8=undefined;
    for(0..padRows)|i|{
      // how far along the pad (-1 back .. 1 front), the circle's half-chord
      // there, and how wide the notch has opened by then
      const x=m.lerp(-1,1,m.ratio(i,padRows-1));
      const chord=r*@sqrt(@max(1-x*x,0));
      const gap=@min(r*notch*@max(-x,0),chord);
      // the lobe: from the notch out to the rim
      const half=(chord-gap)*0.5;
      sp[i]=mid+dir*m.splat3(x*r)+side*m.splat3(s*(gap+half));
      sd[i]=side;
      fc[i]=up;
      wd[i]=half;
      ds[i]=0;
      cs[i]=color.mix(col,rim,@abs(x)*0.6);
    }
    try mg.lamina(b,.{.spine=&sp,.side=&sd,.face=&fc,.width=&wd,.dish=&ds,.broad=r*0.5,.col=&cs,.t=t,.part=.leaf});
  }
  // its veins run out from its middle: each vertex carries how far out it
  // lies (tu.y, 0 middle .. 1 rim) and how far round from the notch
  // (tu.z, -1 .. -3; surface.glsl `padSheet`)
  for(b.v.items[first..])|*v|{
    // its place from the middle, back toward the notch and across
    const d=v3(v.pos[0],0,v.pos[2])-v3(mid[0],0,mid[2]);
    const round=@mod(m.atan2(m.dot(d,side),-m.dot(d,dir)),m.tau)/m.tau;
    v.tu[1]=m.clamp01(m.len(d)/r);
    v.tu[2]=-1-2*round;
  }
}
