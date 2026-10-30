//! mesh: MONFRIS. a weftstone and a driftbraid grown into one 2x2 tree
//! (convergenceKit, the driftbraid's look): out of each corner of its
//! ground a weave of green and pale strands rises, its foot rooted both
//! ways, the four winding round one another as they climb and closing in
//! until they meet and run on as one great weave, parting into a cage;
//! at its top a great sac of both saps where what it holds hangs and what
//! it weaves forms (emitted), a flower of both crowning it, and five lilac
//! boughs arching out round it exactly alike, each with leaves of its own
//! and a flower of both at its tip.
//! It grows on a hidden trunk (gfx/growth.zig): the four corner weaves dig
//! up out of the soil together with it, their roots spreading, and wind
//! inward; the trunk's weave rises from where they meet, the sac swells
//! out of its top, the boughs arch out last, their flowers after them.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, angles, easing
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// colour conversions, for blending the root bulbs
const color=engine.core.color;
/// the garden's growth timing: the skeleton the tree grows along
const growth=lib.growth;
/// the shared swatches: wood and strand wobble
const pal=lib.palette;
/// the parasite kit: stalk shapes, sections, nodules, frond paths
const pk=lib.parasiteKit;
/// the convergence kit: weaves, sacs, blooms of both lineages
const kit=lib.convergenceKit;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// where the corner weaves come up, out from the centre of its 2x2 ground
const cornerAt:f32=0.62;
/// where the corner weaves meet over the middle
const meetCount=v3(0,0.75,0);
/// the top of the one weave they become
const topAt=v3(0,1.45,0);
/// how far round (radians) the corner weaves turn as they climb
const turnRate:f32=0.9*m.pi;
/// a corner weave's shape: slim, parting into a cage along its upper stretch
const cornerStalk:pk.Stalk=.{.girth=0.055,.part=2.2,.from=0.38,.to=0.82,.foot=0.6};
/// the trunk's one great weave: twice as thick, caged over most of its length
const trunkStalk:pk.Stalk=.{.girth=0.11,.part=2.0,.from=0.2,.to=0.78,.foot=0.2};
/// the sac's radii at its top, where what it holds hangs and what it weaves forms
pub const sacR=v3(0.17,0.2,0.17);
/// the sac's centre, sitting down onto the trunk's top
pub const sacAt=topAt+v3(0,sacR[1]*0.85,0);
/// how many boughs arch round the sac: the lineages' fivefold
const boughs=kit.fold;
/// builds the tree: the hidden trunk, its four corner weaves, the great
/// weave from where they meet, the sac, the boughs with their leaves and
/// flowers, and the flower crowning the sac.
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the skeleton every part is timed along
  var k=growth.Skeleton.begin(b);
  // the hidden trunk: up from under the middle of its ground to its top
  const trunk=k.trunk(&.{v3(0,-0.3,0),v3(0,0.25,0),meetCount,v3(0.015,1.1,-0.01),topAt},.{.pace=1.4});
  // the corner weaves: each digs up at its corner and winds in to `meetCount`
  for(0..4)|i|try corner(b,&k,trunk,i);
  // the one weave, from where they meet to its top
  {
    // the weave's points, growth stamps and cross-sections along the trunk
    var sp:[growth.res]V3=undefined;
    var ts:[growth.res]f32=undefined;
    var sec:[growth.res]pk.Section=undefined;
    // how far along the trunk it starts, just under where they meet
    const from=k.nearest(trunk,meetCount-v3(0,0.08,0));
    k.path(trunk,from,1,&sp);
    for(&ts,0..)|*t,j|t.*=m.lerp(0.45,0.8,m.ratio(j,growth.res-1));
    kit.sections(trunkStalk,&sec);
    // where the weave's vertices begin
    const mk=b.mark();
    try kit.weave(b,&sp,&ts,&sec,.{.seed=0x4EA1});
    try k.along(b,mk,trunk);
  }
  // where the sac's vertices begin
  const sac=b.mark();
  try kit.sac(b,.{.center=sacAt,.radii=sacR,.t=0.85,.arms=3,.swirl=1.1,.phase=2.1});
  try k.on(b,sac,trunk,1,.{.from=topAt});
  // the boughs, alike: up the sac's flank from its foot, then arching out
  for(0..boughs)|i|{
    // this bough's bearing round the sac
    const a=(m.f(i)+0.5)/m.f(boughs)*m.tau;
    // its control points
    var c:[11]V3=undefined;
    for(c[0..4],0..)|*q,j|{
      // the angle down from the sac's crown, from near its foot up its flank
      const th=m.lerp(m.pi*0.9,0.6,m.ratio(j,3));
      q.*=sacAt+v3(@sin(th)*@cos(a)*sacR[0]*1.1,@cos(th)*sacR[1]*1.1,@sin(th)*@sin(a)*sacR[2]*1.1);
    }
    pk.frondPath(c[3],v3(@cos(a),0,@sin(a)),0.7,0.75,2.0,0x4EA2,c[3..]);
    // its branch on the skeleton, a little after the sac
    const id=k.branch(trunk,1,&c,.{.delay=0.06});
    try k.tube(b,id,.{.r0=0.024,.tip=0.4,.col=kit.lilac,.part=.tendril,.sides=6,.t0=0.8,.t1=1});
    try k.leaves(b,id,.{.n=4,.len=0.12,.width=0.04,.from=0.4,.to=0.85,.t0=0.8,.t1=1,.col=kit.leafDark,.tip=kit.leafLite,.seed=0x4EA3+%i*97});
    // where its flower's vertices begin, and the bough's tip it opens at
    const fl=b.mark();
    const tip=k.point(id,1);
    try kit.bloom(b,.{.heart=tip,.len=0.09,.spin=a,.petals=6,.seed=0x4EA4});
    try k.on(b,fl,id,1,.{.from=tip});
  }
  // a flower of both crowning the sac
  const crown=b.mark();
  // its heart, on the sac's top
  const heart=sacAt+v3(0,sacR[1]*1.0,0);
  try kit.bloom(b,.{.heart=heart,.len=0.16,.petals=8,.seed=0x4EA5});
  try k.on(b,crown,trunk,1,.{.from=heart,.delay=0.1});
  k.finish(b);
}
/// corner weave `i`: up out of the soil at its corner (the stretch from
/// under the middle out to it is underground), winding inward as it climbs
/// to meet the others; rooted both ways where it breaks the ground
fn corner(b:*mg.Builder,k:*growth.Skeleton,trunk:growth.Id,i:usize)Allocator.Error!void{
  // this corner's bearing, and where it breaks the ground
  const a0=(m.f(i)+0.5)/4*m.tau;
  const foot=v3(@cos(a0)*cornerAt,0,@sin(a0)*cornerAt);
  // its control points: two underground, then the climb
  var c:[9]V3=undefined;
  c[0]=v3(0,-0.3,0);
  c[1]=foot*m.splat3(0.85)-v3(0,0.12,0);
  for(c[2..],0..)|*q,j|{
    // how far up the climb, its bearing, and its distance from the middle
    const f=m.ratio(j,6);
    const a=a0+turnRate*f;
    const r=cornerAt*(1-m.smooth(f));
    q.*=v3(@cos(a)*r,-0.02+meetCount[1]*f,@sin(a)*r);
  }
  // its branch on the skeleton, growing with the trunk
  const id=k.branch(trunk,0,&c,.{.after=.with});
  // scratch for the weave's points and cross-sections
  var sp:[growth.res]V3=undefined;
  var sec:[growth.res]pk.Section=undefined;
  try kit.weaveOn(b,k,id,cornerStalk,.{.seed=0x4EB0+%i*31},0,0.45,&sp,&sec);
  // its roots, both ways, out of where it breaks the ground
  const u=k.nearest(id,foot);
  // where the root bulb's vertices begin
  const bulb=b.mark();
  try pk.nodule(b,foot+v3(0,0.01,0),v3(0.09,0.045,0.09),0,kit.pale,color.mix(kit.pale,pk.core,0.4),kit.pearl);
  try k.on(b,bulb,id,u,.{.from=foot});
  for(0..3)|j|{
    // this root's bearing, fanned round the corner's
    const ra=a0+(m.f(j)-1)*0.7;
    // its control points
    var rc:[6]V3=undefined;
    kit.rootPath(foot,ra,0.05,0.32,0.25,0x4EC0+%i*13+%j,&rc);
    // its branch, growing as the corner weave passes the ground
    const root=k.branch(id,u,&rc,.{.after=.passing});
    if(j==1){
      try k.tube(b,root,.{.r0=0.014,.tip=0.05,.col=kit.pearl,.sides=5});
    }else{
      try k.braid(b,root,.{.girth=0.022,.tip=0.3,.wobble=pal.strandWobble,.seed=0x4ED0+%i*7+%j,.core=pal.core,.strand=kit.green});
    }
  }
}
/// mesh: VULTRIXI TETHER. the tether from a Vultrixi to its monfris, built
/// straight up +Y over 0..1 (bent on the GPU along its curve): a green
/// strand and a pale one twined round each other, a violet knot where they
/// cross, as thin at either end as along it (it hangs between two).
pub const tether=struct{
  /// builds the tether: two strands twisting opposite ways round the axis,
  /// and (at full detail only) a knot at every fourth crossing.
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // points per strand, how many turns each makes, and how far off the axis
    const n=40;
    const twists:f32=9;
    const radius:f32=0.006;
    for([_]f32{1,-1},[_]color.Rgba8{kit.green,kit.pearl})|way,col|{
      // this strand's points, growth stamps and radii
      var p:[n]V3=undefined;
      var ts:[n]f32=undefined;
      var rs:[n]f32=undefined;
      for(&p,&ts,&rs,0..)|*q,*t,*r,j|{
        // how far up the tether, 0..1
        const f=m.ratio(j,n-1);
        // its bearing round the axis, the pale strand starting opposite
        const a=way*f*twists*m.tau+(if(way>0)@as(f32,0)else m.pi);
        q.*=v3(@cos(a)*radius,f,@sin(a)*radius);
        t.*=f;
        r.*=0.0032;
      }
      try b.tubeR(&p,&ts,&rs,col,.tendril,4);
    }
    if(b.lod>0)return;
    // they cross wherever each has turned a quarter more than a whole half
    // turn (f = (2n + 1) / 4 twists); a knot at every fourth crossing
    var j:u32=1;
    while(m.f(j)<4*twists):(j+=8){
      // how far up the tether this crossing lies
      const f=m.f(j)/(4*twists);
      try mg.ellipsoid(b,.{.center=v3(0,f,0),.radii=m.splat3(radius*1.6),.col=kit.knot,.part=.tendril,.rings=4,.segs=6,.t=f});
    }
  }
};
