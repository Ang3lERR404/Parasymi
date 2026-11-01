//! mesh: the tanglehold, of both lineages (convergence kit): the store that
//! takes the sap cache's place once the unforming has taken it. A rooted
//! foot and a short woven stem; out of its top a great sac of both saps
//! swells, see-through, and staves of braided strands, pale cored and
//! green wound, arch up round it like the ribs of a cage to meet in a knot
//! over it, crowned with young leaves. What it holds hangs in the sac
//! (structures/tanglehold.zig). All grown along one skeleton: the foot and
//! stem, the staves arching up, the sac swelling, the crown opening.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors and lerps
const m=engine.core.math;
/// the garden's meshgen: builder, leaves
const mg=lib.meshgen;
/// growth splines: the skeleton the hold grows along
const growth=lib.growth;
/// the parasite kit: the woven stalk's shape
const pk=lib.parasiteKit;
/// the convergence kit: its foot, weave, sac and colours
const kit=lib.convergenceKit;
/// the shared palette: strand wobble
const pal=lib.palette;
/// a point or direction in 3D
const V3=m.V3;
/// builds a point or direction
const v3=m.v3;
/// the stem's top, where the sac and the staves leave it
const base=v3(0,0.18,0);
/// the sac's middle, where what it holds hangs (structures/tanglehold.zig)
pub const heart=v3(0,0.56,0);
/// the sac's half-sizes
pub const sacR=v3(0.3,0.34,0.3);
/// the knot over the sac where the staves meet
const knot=v3(0,0.98,0);
/// how many staves cage the sac
const staves=8;
/// how far out of the sac the staves arch (a share of its size)
const cageOut:f32=1.12;
/// how many young leaves crown the knot
const crownLeaves=5;
/// the woven stem's shape
const stemShape:pk.Stalk=.{.girth=0.08,.part=2.2,.from=0.2,.to=0.8};
/// builds the hold whole: foot, stem, staves, sac, crown
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the skeleton every part is timed along
  var k=growth.Skeleton.begin(b);
  // the stem: up out of the soil to the sac's foot
  const stem=k.trunk(&.{v3(0,-0.05,0),v3(-0.01,0.09,0.01),base},.{.pace=1.4});
  try kit.footOn(b,&k,stem,.{.r=0.13,.reach=0.6,.rootR=0.022,.seed=0x7A11});
  // the stem's woven path and sections
  var sp:[growth.res]V3=undefined;
  var sec:[growth.res]pk.Section=undefined;
  try kit.weaveOn(b,&k,stem,stemShape,.{.seed=0x7A12},0,0.3,&sp,&sec);
  // the staves: out of the stem's top, arching up round the sac to the
  // knot; the last, which the crown opens out of
  var last:growth.Id=undefined;
  for(0..staves)|i|{
    // its bearing, and its control points round the sac's side
    const a=(m.f(i)+0.5)/staves*m.tau;
    var c:[7]V3=undefined;
    for(&c,0..)|*p,j|{
      // how far round its arch, from the stem's top (0) to the knot (1)
      const s=m.ratio(j,c.len-1);
      const th=m.pi*(1-s);
      const out=@sin(th)*cageOut;
      p.*=heart+v3(@cos(a)*sacR[0]*out,-@cos(th)*sacR[1]*cageOut,@sin(a)*sacR[2]*out);
    }
    c[0]=base;
    c[c.len-1]=knot;
    const id=k.branch(stem,1,&c,.{.after=.with});
    last=id;
    try k.braid(b,id,.{.girth=0.02,.tip=0.7,.strands=3,.twist=3,.wobble=pal.strandWobble,.seed=0x7A20+%i*13,.core=kit.pale,.strand=kit.green,.t0=0.3,.t1=0.75});
  }
  // the sac of both saps, swelling out of the stem's top as the staves rise
  const sac=b.mark();
  try kit.sac(b,.{.center=heart,.radii=sacR,.t=0.8,.arms=3,.swirl=1.2,.rings=14,.segs=20});
  try k.on(b,sac,stem,1,.{.from=base,.delay=0.1});
  // the crown: young leaves out of the knot, opening up and out
  for(0..crownLeaves)|i|{
    // its bearing, and the way it reaches
    const a=m.ratio(i,crownLeaves)*m.tau+0.3;
    const mk=b.mark();
    try mg.natural(b,knot,m.norm(v3(@cos(a),1.1,@sin(a))),0.16,0.06,0.3,kit.leafDark,kit.leafLite,0.9,.stalked);
    try k.on(b,mk,last,1,.{.from=knot,.delay=0.02*m.f(i)});
  }
  k.finish(b);
}
