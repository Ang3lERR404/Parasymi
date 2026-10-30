//! mesh: POLYP. the heart of a halo: a colony of soft polyps budding from
//! one fleshy mound on a root mat. Each is a smooth column flaring into an
//! oral disc, its mouth a dark slit on a raised mound at the heart, ringed
//! by eight feathery tentacles that arch out and curl down at their tips;
//! the tallest holds a bead of resin in its mouth, and the closed buds of
//! young polyps sit low on the mound. The diamond forms high over it as the
//! halo completes (meshes/halo.zig: the radiant lineage's, gathered, not
//! grown). The colony grows along growth splines.
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
/// colour conversions and blends, for the colony's flesh
const color=engine.core.color;
/// the structure kit: root mat, resin pods
const kit=lib.structureKit;
/// the garden's growth timing: the skeleton the colony grows along
const growth=lib.growth;
/// the seeded random stream each polyp's crown is varied by
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// one polyp of the colony: where it rises from the mound, where its disc
/// stands, and how thick its column is
const Polyp=struct{
  /// where its column rises out of the mound
  foot:V3,
  /// where its oral disc sits, at the column's top
  top:V3,
  /// its column's radius
  r:f32,
};
/// the colony, tallest first, each leaning a little out from the mound's heart
const colony=[_]Polyp{
  .{.foot=v3(0.02,0.03,-0.01),.top=v3(0.04,0.62,-0.02),.r=0.05},
  .{.foot=v3(0.15,0.02,0.08),.top=v3(0.25,0.46,0.14),.r=0.044},
  .{.foot=v3(-0.14,0.02,0.11),.top=v3(-0.24,0.4,0.19),.r=0.04},
  .{.foot=v3(-0.08,0.02,-0.15),.top=v3(-0.13,0.33,-0.26),.r=0.037},
  .{.foot=v3(0.13,0.02,-0.13),.top=v3(0.22,0.27,-0.22),.r=0.034},
};
/// the closed buds of young polyps, low on the mound: where each sits
const buds=[_]V3{v3(0.0,0.07,0.21),v3(-0.22,0.07,-0.03),v3(0.25,0.06,-0.01)};
/// the fleshy mound the colony shares: its half-widths (its heart at the ground)
const mound=v3(0.3,0.12,0.28);
/// the dusky violet of the mound and the columns' feet
const flesh=color.rgb(0.56,0.46,0.66);
/// the pale pearly lilac the columns rise into
const pearl=color.rgb(0.78,0.72,0.86);
/// the warm rose-lilac of an oral disc (the open-mouthed hydras' too)
pub const disc=color.rgb(0.74,0.52,0.74);
/// the soft lilac at a tentacle's root
const lilac=color.rgb(0.62,0.52,0.78);
/// the near-white pearl a tentacle fades to at its tip
const tipCol=color.rgb(0.9,0.86,0.94);
/// the dark violet of a mouth's slit
const mouth=color.rgb(0.22,0.15,0.28);
/// tentacles round each disc
const tentacles=8;
/// long hanging tentacles round each disc, crowned `hanging`
const hangers=6;
/// how long a hanging tentacle runs, as a share of its column's radius
const hangReach:f32=8;
/// feathery side branches (pinnules) each side of a tentacle
const pinnules=7;
/// how wide an oral disc flares, as a share of its column's radius
pub const flare:f32=1.8;
/// how slender a column's stalk is, as a share of its radius (the disc,
/// mouth and tentacles keep the full radius)
const slender:f32=0.55;
/// how long a tentacle runs, as a share of its column's radius
const reach:f32=3;
/// the columns rise this much slower than a unit a second's share
const columnPace:f32=1.6;
/// points along a drawn column
const columnRings=24;
/// points along a drawn tentacle
const tentacleRings=16;
/// a column's radius at `k` along it (0 foot .. 1 disc), as a share of its
/// own: flared at the foot where it melts into the mound, narrowing a
/// little at the neck, then opening like a trumpet into the disc
fn columnProfile(k:f32)f32{
  // how far into the trumpet's flare (0 below it .. 1 the rim)
  const f=m.clamp01((k-0.74)/0.26);
  return(1+0.6*@exp(-k*10))*(1-0.1*@exp(-(k-0.68)*(k-0.68)*120))*(1+(flare/slender-1)*f*f);
}
/// a column's colour at `k` along it: dusky at the foot, pearl up its
/// length, warming to the disc's rose at the rim
fn columnColour(k:f32)color.Rgba8{
  return flesh.lerp(pearl,m.smooth(m.clamp01(k/0.7))).lerp(disc,m.smooth(m.clamp01((k-0.8)/0.2))).toRgba8(255);
}
/// builds the colony. It grows on a hidden stalk (gfx/growth.zig): the roots
/// spread with the mound, then each polyp's column rises out of it, its
/// disc and mouth open, and its tentacles reach out of the rim, their
/// pinnules unfurling as each front passes; the buds swell as they rise.
pub fn build(b:*mg.Builder)Allocator.Error!void{try colonyOf(b,.feathery);}
/// how a polyp's disc is crowned
pub const Crown=enum{
  /// eight feathery tentacles arching out and curling down
  feathery,
  /// six long thin tentacles hanging far down, beaded with stinging knots
  /// (the hydra's, `polypHydra.hanging`)
  hanging,
};
/// a mixed look, to compare beside it (`--samples=polyp,polypHanging`):
/// the colony's columns and discs, crowned with the hydra's long hanging
/// tentacles
pub const hanging=struct{
  /// builds the colony crowned with hanging tentacles
  pub fn build(b:*mg.Builder)Allocator.Error!void{try colonyOf(b,.hanging);}
};
/// the colony, every disc crowned as `crown` says
fn colonyOf(b:*mg.Builder,crown:Crown)Allocator.Error!void{
  // the colony's own random stream, the same every build
  var rng=pal.rngFor("polyp");
  // the skeleton every part is timed along
  var k=growth.Skeleton.begin(b);
  // the mound's hidden heart, which every polyp grows off
  const heart=try base(b,&k);
  for(colony,0..)|p,i|try polyp(b,&k,heart,p,i,crown,&rng);
  try budsOn(b,&k,heart);
  k.finish(b);
}
/// the root mat and the fleshy mound a colony shares, grown off a hidden
/// heart rising out of the soil (returned, for the colony to grow off)
pub fn base(b:*mg.Builder,k:*growth.Skeleton)Allocator.Error!growth.Id{
  // the mound's hidden heart, rising out of the soil
  const heart=k.trunk(&.{v3(0,-0.02,0),v3(0,0.03,0),v3(0,0.08,0)},.{.pace=columnPace*2});
  // decision: no foot leaves; the colony reads as soft flesh, not foliage
  try kit.rootMat(b,5,0.5,0.045,0x9071,.{.k=k,.id=heart});
  {
    // where the mound's vertices begin
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=mound,.col=flesh.toRgba8(255),.part=.tendril,.rings=10,.segs=18});
    try k.along(b,s,heart);
  }
  return heart;
}
/// the closed buds of young polyps low on the mound, swelling off its `heart`
pub fn budsOn(b:*mg.Builder,k:*growth.Skeleton,heart:growth.Id)Allocator.Error!void{
  for(buds,0..)|at,i|{
    // where this bud's vertices begin
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=at,.radii=v3(0.028,0.042,0.028),.col=flesh.lerp(pearl,0.6).toRgba8(255),.part=.tendril,.rings=6,.segs=8,.t=0.8});
    try mg.ellipsoid(b,.{.center=at+v3(0,0.038,0),.radii=v3(0.01,0.008,0.01),.col=mouth.toRgba8(255),.part=.tendril,.rings=4,.segs=6,.t=0.9});
    try k.on(b,s,heart,1,.{.from=at-v3(0,0.03,0),.delay=0.4+0.05*m.f(i)});
  }
}
/// one polyp `p` (the `i`th of the colony) off the mound's `heart`: its
/// column, disc, mouth and tentacles, crowned as `crown` says
fn polyp(b:*mg.Builder,k:*growth.Skeleton,heart:growth.Id,p:Polyp,i:usize,crown:Crown,rng:*Rng)Allocator.Error!void{
  // its column's control points (the first left for the skeleton to root),
  // rising nearly upright from its foot and leaning out toward its disc
  const d=p.top-p.foot;
  var c:[5]V3=undefined;
  c[1]=p.foot;
  c[2]=p.foot+v3(d[0]*0.2,d[1]*0.35,d[2]*0.2);
  c[3]=p.foot+v3(d[0]*0.62,d[1]*0.72,d[2]*0.62);
  c[4]=p.top;
  // its branch on the skeleton, the smaller ones a little later
  const column=k.branch(heart,1,&c,.{.pace=columnPace,.delay=0.08*m.f(i)});
  // the drawn column, resampled smooth, and its radius, colour and tu.x per ring
  var sp:[columnRings]V3=undefined;
  m.splineResample(c[1..],&sp);
  var ts:[columnRings]f32=undefined;
  var rs:[columnRings]f32=undefined;
  var cs:[columnRings]color.Rgba8=undefined;
  for(&ts,&rs,&cs,0..)|*t,*r,*col,j|{
    t.*=m.ratio(j,columnRings-1);
    r.*=p.r*slender*columnProfile(t.*);
    col.*=columnColour(t.*);
  }
  {
    // where the column's vertices begin
    const s=b.mark();
    try b.tubeC(&sp,&ts,&rs,&cs,null,.tendril,12);
    try k.along(b,s,column);
  }
  // the way the disc faces, and two directions across it
  const up=m.norm(sp[columnRings-1]-sp[columnRings-3]);
  const e1=m.norm(m.cross(up,if(@abs(up[2])<m.nearParallel)v3(0,0,1)else v3(1,0,0)));
  const e2=m.cross(up,e1);
  // the disc's radius, and where the column ends in it
  const dr=p.r*flare;
  const top=sp[columnRings-1];
  try mouthOn(b,k,column,top,up,dr,rng);
  if(i==0){
    // the tallest holds a bead of resin in its mouth
    const s=b.mark();
    try kit.resinPod(b,top+up*m.splat3(dr*0.3),v3(dr*0.3,dr*0.24,dr*0.3),6,10);
    try k.on(b,s,column,1,.{.from=top,.delay=0.05});
  }
  // the tentacles' bearings are offset on every other polyp, so no two
  // crowns line up
  const turn:f32=if(i%2==0)0 else 0.5;
  if(crown==.hanging){
    for(0..hangers)|j|{
      // this tentacle's bearing, and the flat way out along it
      const a=(m.f(j)+turn+rng.range(-0.2,0.2))/hangers*m.tau;
      const out=e1*m.splat3(@cos(a))+e2*m.splat3(@sin(a));
      try lib.polypHydra.hanging(b,k,column,.{.root=top+out*m.splat3(dr*0.86)+up*m.splat3(dr*0.04),.out=out,.up=up,.len=p.r*hangReach*rng.range(0.85,1.15),.r0=p.r*0.3},rng);
    }
    return;
  }
  for(0..tentacles)|j|try tentacle(b,k,column,.{.top=top,.up=up,.e1=e1,.e2=e2,.dr=dr,.r=p.r},(m.f(j)+turn+rng.range(-0.15,0.15))/tentacles*m.tau,rng);
}
/// the mouth on an oral disc `dr` wide at the tip `top` of spline
/// `column`, facing `up`: a raised mound at the disc's heart, a dark slit
/// along its crest (shared with the open-mouthed hydras)
pub fn mouthOn(b:*mg.Builder,k:*growth.Skeleton,column:growth.Id,top:V3,up:V3,dr:f32,rng:*Rng)Allocator.Error!void{
  // where its vertices begin
  const s=b.mark();
  try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(dr*0.42,dr*0.2,dr*0.36),.col=disc.lerp(pearl,0.35).toRgba8(255),.part=.tendril,.rings=6,.segs=12,.t=1});
  try mg.ellipsoid(b,.{.center=v3(0,dr*0.17,0),.radii=v3(dr*0.26,dr*0.06,dr*0.07),.col=mouth.toRgba8(255),.part=.tendril,.rings=4,.segs=10,.t=1});
  b.xform(s,m.chain(&.{m.translate(top),m.alignY(up),m.rotY(rng.range(0,m.tau))}));
  try k.on(b,s,column,1,.{.from=top});
}
/// an oral disc a crown of tentacles grows round
pub const Disc=struct{
  /// where its heart is, the column's top
  top:V3,
  /// the way it faces
  up:V3,
  /// two directions across it, square to each other and to `up`
  e1:V3,
  /// (the second)
  e2:V3,
  /// its radius
  dr:f32,
  /// its column's radius, which the tentacles' size follows
  r:f32,
};
/// one tentacle off disc `o`'s rim at bearing `a` on spline `column`: it
/// rises out of the rim, arches outward and curls down at its tip, tapering
/// to a point, soft pinnules feathering both its sides
pub fn tentacle(b:*mg.Builder,k:*growth.Skeleton,column:growth.Id,o:Disc,a:f32,rng:*Rng)Allocator.Error!void{
  // the flat way out along its bearing, the way across it, and its length
  const out=o.e1*m.splat3(@cos(a))+o.e2*m.splat3(@sin(a));
  const across=m.norm(m.cross(o.up,out));
  const len=o.r*reach*rng.range(0.85,1.1);
  // a little sideways drift, so no two arch alike
  const drift=rng.range(-0.1,0.1)*len;
  // where it leaves the rim
  const rim=o.top+out*m.splat3(o.dr*0.86)+o.up*m.splat3(o.dr*0.04);
  // its control points (the first left for the skeleton to root): up out
  // of the rim, over and out, then curling down at the tip
  const shape=[_][3]f32{.{0,0,0},.{0.14,0.3,0},.{0.4,0.42,0.3},.{0.66,0.34,0.7},.{0.82,0.18,1},.{0.92,0.02,1.2}};
  var c:[7]V3=undefined;
  for(shape,c[1..])|q,*pt|pt.*=rim+out*m.splat3(q[0]*len)+o.up*m.splat3(q[1]*len)+across*m.splat3(q[2]*drift);
  // its branch on the skeleton, off the column's top
  const arm=k.branch(column,1,&c,.{});
  // the drawn tentacle, resampled smooth, and its tu.x, radius and colour per ring
  var p:[tentacleRings]V3=undefined;
  m.splineResample(c[1..],&p);
  var ts:[tentacleRings]f32=undefined;
  var rs:[tentacleRings]f32=undefined;
  var cs:[tentacleRings]color.Rgba8=undefined;
  // its radius at the root
  const r0=o.r*0.34;
  for(&ts,&rs,&cs,0..)|*t,*r,*col,j|{
    // how far along the tentacle, 0 root .. 1 tip
    const f=m.ratio(j,tentacleRings-1);
    t.*=m.lerp(0.6,1,f);
    // swells from its root, tapers to a point
    r.*=r0*@min(1,f*5+0.4)*(1-f*0.94);
    col.*=lilac.lerp(tipCol,m.smooth(f)).toRgba8(255);
  }
  {
    // where its vertices begin
    const s=b.mark();
    try b.tubeC(&p,&ts,&rs,&cs,null,.tendril,6);
    try k.along(b,s,arm);
  }
  // the pinnules: short soft fingers either side, bending toward the tip
  // as a feather's barbs do, shorter toward it, their ends rounded
  for(0..pinnules)|q|{
    // how far along the tentacle this pair sits
    const u=0.15+0.7*m.ratio(q,pinnules-1);
    try pinnulePair(b,k,arm,&p,u,across,o.r*0.8*(1-u*0.5),r0*0.4*(1-u*0.4),lilac.lerp(tipCol,m.smooth(u)+0.1).toRgba8(255));
  }
}
/// a pair of pinnules at `u` along tentacle `p` (grown on spline `arm`):
/// soft fingers `pl` long and `pr` thick either side (`across`), bending
/// toward the tip as a feather's barbs do, their ends rounded
pub fn pinnulePair(b:*mg.Builder,k:*growth.Skeleton,arm:growth.Id,p:[]const V3,u:f32,across:V3,pl:f32,pr:f32,col:color.Rgba8)Allocator.Error!void{
  // where the pair sits, and the way the tentacle runs there
  const at=m.alongPath(p,u);
  const tg=m.norm(m.alongPath(p,u+0.03)-m.alongPath(p,u-0.03));
  // their tu.x
  const pt=m.lerp(0.6,1,u);
  for([_]f32{-1,1})|sg|{
    // the way it leaves the tentacle, and the way it bends to at its end
    const d0=m.norm(across*m.splat3(sg)+tg*m.splat3(0.4));
    const d1=m.norm(across*m.splat3(sg*0.6)+tg);
    // its points, tu.x and radii: swelling a little, then rounding off
    var fp:[5]V3=undefined;
    var fts:[5]f32=undefined;
    var frs:[5]f32=undefined;
    for(&fp,&fts,&frs,[_]f32{0,0.3,0.6,0.85,1},[_]f32{0.8,1,0.95,0.7,0.25})|*x,*t,*r,f,w|{
      x.*=at+m.norm(d0+(d1-d0)*m.splat3(f))*m.splat3(pl*f);
      t.*=pt;
      r.*=pr*w;
    }
    // where its vertices begin
    const s=b.mark();
    try b.tubeR(&fp,&fts,&frs,col,.tendril,5);
    try k.on(b,s,arm,k.nearest(arm,at),.{.from=at});
  }
}
