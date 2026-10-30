//! mesh: VULTRIXI. a gathering crown and a ganglion grown into one floating
//! body (convergence_kit), hanging `hover` over its tile: a sac of both
//! saps knotted round by two rings of five pearl nodules (the ganglion's
//! knot), cupped from below by warm living petals each its own (the
//! gathering crown's), stamens standing on its crown, and five pale nerves
//! trailing beneath it exactly alike, curling as they hang. Its tether to
//! its monfris leaves from its crown (emitted, `monfrisTether`), the
//! tendril it reaches into a structure with from under it (emitted).
//! It grows on a hidden stalk through it (gfx/growth.zig): the sac swells
//! first, the nerves trail out with it, the nodules swell ring by ring,
//! the petals cup it, the stamens last.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error every building call may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, angles, easing
const m=engine.core.math;
/// the plant-piece mesh builder: petals, stamens
const mg=lib.meshgen;
/// colour mixing, for the nodules' blend of pale and core
const color=engine.core.color;
/// the garden's growth skeleton, which times every piece's growing
const growth=lib.growth;
/// the parasites' kit: nodules and their pale core colour
const pk=lib.parasiteKit;
/// the convergence kit: the sac of both saps, its colours and fives
const kit=lib.convergenceKit;
/// a seeded random stream, so each petal is its own yet the same every build
const Rng=engine.core.rng.Rng;
/// a point or direction in 3D
const V3=m.V3;
/// makes a `V3` from three numbers
const v3=m.v3;
/// how high its sac hangs over its tile (world units; its mesh carries
/// it, so breathing bobs the whole of it)
pub const hover:f32=1.05;
/// the heart of its sac, hanging `hover` over the tile's centre
pub const body=v3(0,hover,0);
/// the sac's radii across, up and deep (world units): a little taller than wide
pub const sacR=v3(0.075,0.085,0.075);
/// where its tether to its monfris leaves: just over the top of its sac
pub const crown=body+v3(0,sacR[1]*1.1,0);
/// where the tendril it reaches into a structure with leaves: just under its sac
pub const underAt=body-v3(0,sacR[1]*1.15,0);
/// how many warm petals cup the sac from below
const petals=6;
/// grows the whole Vultrixi on a hidden stalk through its sac: the sac
/// swells first, the five nerves trail beneath it, the two rings of nodules
/// swell, the petals cup it and the stamens stand on its crown last
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the skeleton every piece is hung on and timed by
  var k=growth.Skeleton.begin(b);
  // the hidden stalk, from under the sac up through it to its crown
  const stalk=k.trunk(&.{underAt,body-v3(0,sacR[1]*0.4,0),body+v3(0,sacR[1]*0.4,0),crown},.{.pace=2});
  // where the sac's vertices begin, so they can be hung on the stalk
  const sac=b.mark();
  try kit.sac(b,.{.center=body,.radii=sacR,.t=0.3,.arms=2,.swirl=1.0,.phase=0.9});
  try k.on(b,sac,stalk,0,.{.from=body,.span=k.get(stalk).time});
  // the nerves, trailing beneath alike and curling as they hang
  for(0..kit.fold)|i|{
    // this nerve's heading round the sac, and the flat direction it leaves along
    const a=m.ratio(i,kit.fold)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    // the nerve's seven guide points, out from under the sac and down
    var c:[7]V3=undefined;
    for(&c,0..)|*q,j|{
      // how far down the nerve this guide point is, 0..1
      const f=m.ratio(j,6);
      q.*=underAt+out*m.splat3(sacR[0]*(0.35+1.1*@sin(m.pi*f*0.7)))-v3(0,0.32*f,0)+out*m.splat3(0.03*f*f);
    }
    // the nerve as a branch off the stalk's foot, growing with it
    const id=k.branch(stalk,0,&c,.{.after=.with});
    try k.tube(b,id,.{.r0=0.008,.tip=0.12,.col=kit.pale,.part=.tendril,.sides=5,.t0=0,.t1=0.3});
    // where the nerve's end bead begins, and the point it sits at
    const bead=b.mark();
    const end=k.point(id,1);
    try pk.nodule(b,end,m.splat3(0.008),0.3,kit.pearl,kit.pale,kit.pearl);
    try k.on(b,bead,id,1,.{.from=end});
  }
  // the knot: two rings of five, the upper turned half a step
  for(0..2)|ring|for(0..kit.fold)|i|{
    // this nodule's heading round the sac, the upper ring turned half a step
    const a=(m.f(i)+0.5*m.f(ring))/m.f(kit.fold)*m.tau;
    // how high on the sac its ring sits: just under the middle, or up toward the crown
    const y=if(ring==0)-sacR[1]*0.15 else sacR[1]*0.55;
    // how far out its ring sits, and how big its nodule is (the upper ring smaller)
    const rr=sacR[0]*(if(ring==0)@as(f32,1.0)else 0.78);
    const nr=sacR[0]*(if(ring==0)@as(f32,0.34)else 0.26);
    // where this nodule sits on the sac
    const at=body+v3(@cos(a)*rr,y,@sin(a)*rr);
    // where this nodule's vertices begin
    const s=b.mark();
    try pk.nodule(b,at,v3(nr,nr*0.9,nr),0.5,kit.pale,color.mix(kit.pale,pk.core,0.4),kit.pearl);
    try k.on(b,s,stalk,if(ring==0)0.45 else 0.7,.{.from=body,.delay=0.02*m.f(i)});
  };
  // the cup of petals, each its own
  // the petals' own random stream, seeded so they never change
  var rng=Rng.init(0x7A11);
  // where the petals spring from, low on the sac
  const base=body-v3(0,sacR[1]*0.75,0);
  for(0..petals)|i|{
    // this petal's heading round the cup, nudged off even spacing
    const a=(m.f(i)+rng.range(-0.15,0.15))/petals*m.tau;
    // this petal's own size, a little under or over the rest
    const sc=rng.range(0.85,1.12);
    // where this petal's vertices begin
    const s=b.mark();
    try mg.petal(b,.{
      .base=base,.out=v3(@cos(a),0,@sin(a)),.len=0.13*sc,.width=0.055*sc,
      .rise=1.05+rng.range(-0.1,0.1),.flare=0.85,.cup=0.5,.col=kit.petalBase,.tip=kit.petalTip,.t=0.7,.part=.leaf,
    });
    try k.on(b,s,stalk,0.3,.{.from=base,.delay=0.03+0.02*m.f(i)});
  }
  // where the stamens' vertices begin
  const sta=b.mark();
  try mg.stamens(b,.{
    .heart=crown-v3(0,0.01,0),.axis=v3(0,1,0),.n=kit.fold,.len=0.06,.r=0.003,.anther=0.013,
    .lean=0.45,.arch=0.5,.col=kit.pearl,.t=1,.seed=0x7A12,
  });
  try k.on(b,sta,stalk,1,.{.from=crown,.delay=0.05});
  k.finish(b);
}
