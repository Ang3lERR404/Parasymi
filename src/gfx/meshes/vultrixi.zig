//! mesh: VULTRIXI. a gathering crown and a ganglion grown into one floating
//! body (convergence_kit), hanging `HOVER` over its tile: a sac of both
//! saps knotted round by two rings of five pearl nodules (the ganglion's
//! knot), cupped from below by warm living petals each its own (the
//! gathering crown's), stamens standing on its crown, and five pale nerves
//! trailing beneath it exactly alike, curling as they hang. Its tether to
//! its monfris leaves from its crown (emitted, `monfris_tether`), the
//! tendril it reaches into a structure with from under it (emitted).
//! It grows on a hidden stalk through it (gfx/growth.zig): the sac swells
//! first, the nerves trail out with it, the nodules swell ring by ring,
//! the petals cup it, the stamens last.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const mg=lib.meshgen;
const color=engine.core.color;
const growth=lib.growth;
const pk=lib.parasiteKit;
const kit=lib.convergenceKit;
const Rng=engine.core.rng.Rng;
const V3=m.V3;
const v3=m.v3;
/// how high it hangs (its mesh carries it: breathing bobs it)
pub const hover:f32=1.05;
pub const body=v3(0,hover,0);
pub const sacR=v3(0.075,0.085,0.075);
/// where its tether leaves (its crown) and its tendril (under it)
pub const crown=body+v3(0,sacR[1]*1.1,0);
pub const underAt=body-v3(0,sacR[1]*1.15,0);
const petals=6;
pub fn build(b:*mg.Builder)Allocator.Error!void{
  var k=growth.Skeleton.begin(b);
  const stalk=k.trunk(&.{underAt,body-v3(0,sacR[1]*0.4,0),body+v3(0,sacR[1]*0.4,0),crown},.{.pace=2});
  const sac=b.mark();
  try kit.sac(b,.{.center=body,.radii=sacR,.t=0.3,.arms=2,.swirl=1.0,.phase=0.9});
  try k.on(b,sac,stalk,0,.{.from=body,.span=k.get(stalk).time});
  // the nerves, trailing beneath alike and curling as they hang
  for(0..kit.fold)|i|{
    const a=m.ratio(i,kit.fold)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    var c:[7]V3=undefined;
    for(&c,0..)|*q,j|{
      const f=m.ratio(j,6);
      q.*=underAt+out*m.splat3(sacR[0]*(0.35+1.1*@sin(m.pi*f*0.7)))-v3(0,0.32*f,0)+out*m.splat3(0.03*f*f);
    }
    const id=k.branch(stalk,0,&c,.{.after=.with});
    try k.tube(b,id,.{.r0=0.008,.tip=0.12,.col=kit.pale,.part=.tendril,.sides=5,.t0=0,.t1=0.3});
    const bead=b.mark();
    const end=k.point(id,1);
    try pk.nodule(b,end,m.splat3(0.008),0.3,kit.pearl,kit.pale,kit.pearl);
    try k.on(b,bead,id,1,.{.from=end});
  }
  // the knot: two rings of five, the upper turned half a step
  for(0..2)|ring|for(0..kit.fold)|i|{
    const a=(m.f(i)+0.5*m.f(ring))/m.f(kit.fold)*m.tau;
    const y=if(ring==0)-sacR[1]*0.15 else sacR[1]*0.55;
    const rr=sacR[0]*(if(ring==0)@as(f32,1.0)else 0.78);
    const nr=sacR[0]*(if(ring==0)@as(f32,0.34)else 0.26);
    const at=body+v3(@cos(a)*rr,y,@sin(a)*rr);
    const s=b.mark();
    try pk.nodule(b,at,v3(nr,nr*0.9,nr),0.5,kit.pale,color.mix(kit.pale,pk.core,0.4),kit.pearl);
    try k.on(b,s,stalk,if(ring==0)0.45 else 0.7,.{.from=body,.delay=0.02*m.f(i)});
  };
  // the cup of petals, each its own
  var rng=Rng.init(0x7A11);
  const base=body-v3(0,sacR[1]*0.75,0);
  for(0..petals)|i|{
    const a=(m.f(i)+rng.range(-0.15,0.15))/petals*m.tau;
    const sc=rng.range(0.85,1.12);
    const s=b.mark();
    try mg.petal(b,.{
      .base=base,.out=v3(@cos(a),0,@sin(a)),.len=0.13*sc,.width=0.055*sc,
      .rise=1.05+rng.range(-0.1,0.1),.flare=0.85,.cup=0.5,.col=kit.petalBase,.tip=kit.petalTip,.t=0.7,.part=.leaf,
    });
    try k.on(b,s,stalk,0.3,.{.from=base,.delay=0.03+0.02*m.f(i)});
  }
  const sta=b.mark();
  try mg.stamens(b,.{
    .heart=crown-v3(0,0.01,0),.axis=v3(0,1,0),.n=kit.fold,.len=0.06,.r=0.003,.anther=0.013,
    .lean=0.45,.arch=0.5,.col=kit.pearl,.t=1,.seed=0x7A12,
  });
  try k.on(b,sta,stalk,1,.{.from=crown,.delay=0.05});
  k.finish(b);
}
