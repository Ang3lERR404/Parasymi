//! mesh: POLYP, HYDRA. a look for the polyp, laid beside it to compare
//! (`--samples=polyp,polypHydra`): one tall, slender, stretchy body
//! gripping the soil with a foot disc, swelling a little at its gut, its
//! head a pointed cone with the mouth at its tip. Six very long thin
//! tentacles leave from under the cone, arch up and out and hang far down,
//! beaded with stinging knots; a young hydra buds from its side with a
//! small crown of its own. It grows along growth splines.
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
/// colour conversions and blends, for the hydra's flesh
const color=engine.core.color;
/// the structure kit: the root mat under its foot
const kit=lib.structureKit;
/// the garden's growth timing: the skeleton the hydra grows along
const growth=lib.growth;
/// the seeded random stream its tentacles are varied by
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// the pale pearl-cream of its body
const pearl=color.rgb(0.8,0.74,0.86);
/// the dusky violet of its foot
const foot=color.rgb(0.5,0.42,0.6);
/// the deeper lilac of its gut, where it swells
const gut=color.rgb(0.7,0.6,0.78);
/// the pale lilac of its tentacles
const thread=color.rgb(0.72,0.64,0.84);
/// the white of a stinging knot on a tentacle
const knot=color.rgb(0.98,0.96,1);
/// the dark violet of its mouth
const mouth=color.rgb(0.22,0.15,0.28);
/// points along a drawn body
const bodyRings=40;
/// points along a drawn tentacle (fine enough for its knots)
const tentacleRings=48;
/// stinging knots along a tentacle
const knots:f32=9;
/// the bodies grow this much slower than a unit a second's share
const bodyPace:f32=1.6;
/// one hydra body grown along a spline: how thick, how many tentacles and
/// how long, and the colour at its foot
const Body=struct{
  /// its body's radius
  r:f32,
  /// how many tentacles crown it
  arms:u32,
  /// how long each tentacle runs
  reach:f32,
  /// the colour at its foot (the young one's is its parent's flesh)
  base:color.Rgb,
};
/// builds the hydra. It grows on a hidden stalk (gfx/growth.zig): the roots
/// and foot disc spread, the body rises, its head cone closes, the long
/// tentacles reach out of it and down, and last the young one buds from its side.
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // its own random stream, the same every build
  var rng=pal.rngFor("polypHydra");
  // the skeleton every part is timed along
  var k=growth.Skeleton.begin(b);
  // its body, rising in a soft S
  const trunk=k.trunk(&.{v3(0,0,0),v3(0.02,0.25,0.01),v3(-0.025,0.5,0.03),v3(0.02,0.76,0)},.{.pace=bodyPace});
  try kit.rootMat(b,4,0.32,0.035,0x9171,.{.k=&k,.id=trunk});
  {
    // the foot disc gripping the soil
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=v3(0,0.005,0),.radii=v3(0.065,0.018,0.065),.col=foot.toRgba8(255),.part=.tendril,.rings=6,.segs=14});
    try k.along(b,s,trunk);
  }
  try body(b,&k,trunk,.{.r=0.03,.arms=6,.reach=1,.base=foot},&rng);
  // the young one, budding from its side and turning upward
  const side=k.point(trunk,0.42);
  const bud=k.branch(trunk,0.42,&.{side,side+v3(0.07,0.02,0.04),side+v3(0.13,0.08,0.07),side+v3(0.15,0.17,0.08)},.{.pace=bodyPace,.delay=0.2});
  try body(b,&k,bud,.{.r=0.016,.arms=4,.reach=0.2,.base=gut},&rng);
  k.finish(b);
}
/// one hydra along spline `id`: its body, head cone and mouth, and its
/// crown of tentacles
fn body(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,o:Body,rng:*Rng)Allocator.Error!void{
  // the drawn body, and its tu.x, radius and colour per ring
  var sp:[bodyRings]V3=undefined;
  k.path(id,0,1,&sp);
  var ts:[bodyRings]f32=undefined;
  var rs:[bodyRings]f32=undefined;
  var cs:[bodyRings]color.Rgba8=undefined;
  for(&ts,&rs,&cs,0..)|*t,*r,*c,j|{
    // how far up the body, 0 foot .. 1 head
    const f=m.ratio(j,bodyRings-1);
    t.*=f;
    // slender, swelling at its gut, narrowing to the head
    r.*=o.r*(0.8+0.45*@exp(-(f-0.66)*(f-0.66)*20))*(1-0.2*m.smooth(m.clamp01((f-0.88)/0.12)));
    c.*=o.base.lerp(pearl,m.smooth(m.clamp01(f/0.4))).lerp(gut,0.5*@exp(-(f-0.66)*(f-0.66)*30)).toRgba8(255);
  }
  {
    // where the body's vertices begin
    const s=b.mark();
    try b.tubeC(&sp,&ts,&rs,&cs,null,.tendril,10);
    try k.along(b,s,id);
  }
  // the head: where the body ends, the way it faces, two ways across it
  const top=sp[bodyRings-1];
  const up=m.norm(sp[bodyRings-1]-sp[bodyRings-3]);
  const e1=m.norm(m.cross(up,if(@abs(up[2])<m.nearParallel)v3(0,0,1)else v3(1,0,0)));
  const e2=m.cross(up,e1);
  // the head's radius, where the body ends
  const hr=rs[bodyRings-1];
  {
    // the head cone, closing to a point round the mouth at its tip
    var cp:[6]V3=undefined;
    var ct:[6]f32=undefined;
    var cr:[6]f32=undefined;
    for(&cp,&ct,&cr,[_]f32{0,0.2,0.45,0.7,0.88,1},[_]f32{1,0.96,0.82,0.58,0.32,0})|*p,*t,*r,f,w|{
      p.*=top+up*m.splat3(f*o.r*2.4);
      t.*=1;
      r.*=hr*w;
    }
    // where the head's vertices begin
    const s=b.mark();
    try b.tubeR(&cp,&ct,&cr,pearl.lerp(thread,0.4).toRgba8(255),.tendril,10);
    try mg.ellipsoid(b,.{.center=top+up*m.splat3(o.r*2.25),.radii=m.splat3(o.r*0.28),.col=mouth.toRgba8(255),.part=.tendril,.rings=4,.segs=6,.t=1});
    try k.on(b,s,id,1,.{.from=top});
  }
  for(0..o.arms)|j|{
    // this tentacle's bearing, the flat way out along it and across it
    const a=(m.f(j)+rng.range(-0.2,0.2))/m.f(o.arms)*m.tau;
    const out=e1*m.splat3(@cos(a))+e2*m.splat3(@sin(a));
    const across=m.norm(m.cross(up,out));
    // how long it runs, and how far it drifts aside as it hangs
    const len=o.reach*rng.range(0.85,1.15);
    const drift=rng.range(-0.25,0.25)*len;
    // where it leaves the head, just under the cone
    const root=top+out*m.splat3(hr*0.85)+up*m.splat3(o.r*0.3);
    // up and out, over, then hanging far down, drifting aside
    const shape=[_][3]f32{.{0,0,0},.{0.08,0.12,0},.{0.22,0.24,0.1},.{0.38,0.22,0.3},.{0.5,0.06,0.55},.{0.56,-0.14,0.78},.{0.58,-0.34,0.92},.{0.57,-0.5,1}};
    var c:[9]V3=undefined;
    for(shape,c[1..])|q,*pt|pt.*=root+out*m.splat3(q[0]*len)+up*m.splat3(q[1]*len)+across*m.splat3(q[2]*drift);
    // keep its far end above the soil
    for(c[1..])|*pt|pt[1]=@max(pt[1],0.08+0.05*rng.float());
    // its branch on the skeleton, off the head
    const arm=k.branch(id,1,&c,.{});
    // the drawn tentacle, and its tu.x, radius and colour per ring
    var p:[tentacleRings]V3=undefined;
    m.splineResample(c[1..],&p);
    var tts:[tentacleRings]f32=undefined;
    var trs:[tentacleRings]f32=undefined;
    var tcs:[tentacleRings]color.Rgba8=undefined;
    // its radius at the root
    const r0=o.r*0.3;
    for(&tts,&trs,&tcs,0..)|*t,*r,*cc,i|{
      // how far along, 0 root .. 1 tip
      const f=m.ratio(i,tentacleRings-1);
      t.*=m.lerp(0.6,1,f);
      // a stinging knot swelling here and there along it (a smooth field)
      const bead=m.smooth(m.clamp01(@sin(f*knots*m.tau)*2-1));
      r.*=r0*@min(1,f*6+0.4)*(1-f*0.9)*(1+0.9*bead);
      cc.*=thread.lerp(knot,bead).toRgba8(255);
    }
    // where its vertices begin
    const s=b.mark();
    try b.tubeC(&p,&tts,&trs,&tcs,null,.tendril,6);
    try k.along(b,s,arm);
  }
}
