//! mesh: POLYP. the heart of a halo: a short woven stalk on a root mat,
//! opening into a small cup of petals that holds a bead of resin, with a
//! ring of pale tentacles curling up around it. The diamond forms high
//! over it as the halo completes (meshes/halo.zig: the radiant lineage's,
//! gathered, not grown). The polyp grows along growth splines.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, splines, easing
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// the shared swatches, and the per-mesh random stream
const pal=lib.palette;
/// colour conversions, for the polyp's pearl and lilac
const color=engine.core.color;
/// the structure kit: root mat, foot leaves, resin pods
const kit=lib.structureKit;
/// the garden's growth timing: the skeleton the polyp grows along
const growth=lib.growth;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// how tall the stalk stands, up to the cup
const height:f32=0.55;
/// the pale pearl of the petal tips and stamens
const pearl=color.rgb(0.78,0.74,0.84);
/// the soft lilac of the tentacles
const lilac=color.rgb(0.62,0.52,0.78);
/// the dusky violet deep in the cup, at the petals' base
const heart=color.rgb(0.34,0.28,0.44);
/// the stalk's radius at `k` along it (0 foot .. 1 crown): tapering up,
/// flared at the foot and swelling a little again under the cup
fn stalkProfile(k:f32)f32{return 0.1*(1-0.35*k)+0.04*@exp(-k*10)+0.03*@exp(-(1-k)*8);}
/// the stalk's girth over its profile
const girth:f32=1.5;
/// the stalk rises this much slower than a unit a second's share
const stalkPace:f32=1.8;
/// where along the stalk the foot leaves unfold
const footAt:f32=0.1;
/// how many petals make the cup; the bead fills and the stamens rise after them
const petals=7;
/// how much later each petal of the cup opens than the one before (the
/// skeleton's time)
const petalStagger:f32=0.03;
/// builds the polyp. It grows on a hidden stalk (gfx/growth.zig): the roots
/// spread with it, the foot leaves unfold, the woven stalk rises, then the
/// cup opens petal by petal round its bead and stamens while the tentacles
/// reach up out of its heart.
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the polyp's own random stream, the same every build
  var rng=pal.rngFor("polyp");
  // the skeleton every part is timed along
  var k=growth.Skeleton.begin(b);
  // the cup's heart, just under the stalk's top
  const crown=v3(0,height-0.02,0);
  // the stalk's hidden spline, rising straight up
  const stalk=k.trunk(&.{v3(0,0,0),v3(0,height*0.5,0),v3(0,height,0)},.{.pace=stalkPace});
  try kit.rootMat(b,6,0.55,0.05,0x9071,.{.k=&k,.id=stalk});
  try kit.footLeaves(b,5,0.16,0.34,0.13,0x9072,.{.k=&k,.id=stalk,.u=footAt});
  {
    // the stalk's points, growth stamps and radii along its spline
    var sp:[growth.res]V3=undefined;
    var ts:[growth.res]f32=undefined;
    var rs:[growth.res]f32=undefined;
    k.path(stalk,0,1,&sp);
    for(&ts,&rs,0..)|*t,*r,i|{
      t.*=m.ratio(i,growth.res-1);
      r.*=stalkProfile(t.*)*girth;
    }
    // where the braid's vertices begin, to time them along the stalk
    const s=b.mark();
    try mg.braid(b,&sp,&ts,&rs,5,2.6,pal.strandWobble,0x9073,pal.core,color.rgb(0.42,0.38,0.5).toRgba8(255));
    try k.along(b,s,stalk);
  }
  // the cup: a whorl of short petals rising almost upright
  for(0..petals)|i|{
    // this petal's bearing round the crown
    const a=m.ratio(i,petals)*m.tau;
    // where its vertices begin
    const s=b.mark();
    try mg.petal(b,.{
      .base=crown,.out=v3(@cos(a),0,@sin(a)),.len=0.26,.width=0.12,
      .rise=1.05,.flare=0.55,.cup=0.5,
      .col=heart.toRgba8(255),.tip=pearl.toRgba8(255),.part=.leaf,
    });
    try k.on(b,s,stalk,1,.{.from=crown,.delay=petalStagger*m.f(i)});
  }
  // a bead of resin in the cup, stamens standing round it
  const bead=b.mark();
  try kit.resinPod(b,v3(0,height+0.04,0),v3(0.1,0.05,0.1),6,10);
  try k.on(b,bead,stalk,1,.{.from=crown,.delay=petalStagger*petals});
  // where the stamens' vertices begin
  const st=b.mark();
  try mg.stamens(b,.{
    .heart=crown,.axis=v3(0,1,0),.n=7,.len=0.17,.r=0.006,.anther=0.032,
    .lean=0.5,.arch=0.45,.col=pearl.toRgba8(255),.spin=0.45,.seed=0x9074,
  });
  try k.on(b,st,stalk,1,.{.from=crown,.delay=petalStagger*(petals+2)});
  // tentacles: grown from the crown, reaching up and out, curling in at the
  // tips, tapering to a point; each a branch out of the cup's heart (its
  // spline's first stretch hidden in the cup)
  for(0..6)|i|{
    // this tentacle's bearing, and the flat direction out along it
    const a=(m.f(i)+0.5+rng.range(-0.12,0.12))/6*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    // its control points (the first left for the skeleton to root)
    var c:[7]V3=undefined;
    mg.growthPath(.{.start=crown+out*m.splat3(0.08),.direction=m.norm(out*m.splat3(0.7)+v3(0,1,0)),.length=rng.range(0.4,0.5),.wobble=0.2,.curl=0.12,.seed=0x9080+%i*17},c[1..]);
    // the tip bends back toward the cup
    c[6]=c[6]-out*m.splat3(0.08);
    c[5]=c[5]-out*m.splat3(0.03);
    // its branch on the skeleton, off the stalk's top
    const arm=k.branch(stalk,1,&c,.{});
    // the drawn tentacle, resampled smooth
    var p:[14]V3=undefined;
    m.splineResample(c[1..],&p);
    // each point's growth stamp and radius
    var ts:[14]f32=undefined;
    var rs:[14]f32=undefined;
    for(&ts,&rs,0..)|*t,*r,j|{
      // how far along the tentacle, 0 root .. 1 tip
      const f=m.ratio(j,13);
      t.*=m.lerp(0.6,1,f);
      // swells from its root, tapers to a point
      r.*=0.024*@min(1,f*6+0.35)*(1-f*0.92);
    }
    // where its vertices begin
    const s=b.mark();
    try b.tubeR(&p,&ts,&rs,lilac.toRgba8(255),.tendril,5);
    try k.along(b,s,arm);
  }
  k.finish(b);
}
