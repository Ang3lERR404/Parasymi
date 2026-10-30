//! mesh: DRIFTBRAID. a braided conduit and a sporecaster grown into one
//! (convergence_kit): rooted both ways, a tall weave of green and pale
//! strands parting into a cage, four sapwood lanes winding up its core
//! inside it (each tinted as a braided conduit's lanes are by what they
//! carry), up to a spore sac of both saps where what it holds hangs
//! (emitted, `belly_lump`s), pursed at its crown into a pearl pore its
//! spore carriers rise out of and drift down into; five lilac fronds clasp
//! the sac exactly alike and flare out round the pore, each carrying
//! leaves of its own and ending in a flower of both.
//! It grows on a hidden stalk (gfx/growth.zig): the bulb swells and its
//! roots spread with it, the weave rises, the sac swells out of its top,
//! the pore purses, the fronds clasp and flare last, their leaves opening
//! as they pass and their flowers last of all.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const mg=lib.meshgen;
const color=engine.core.color;
const growth=lib.growth;
const pal=lib.palette;
const pk=lib.parasiteKit;
const kit=lib.convergenceKit;
const V3=m.V3;
const v3=m.v3;
/// the weave's top, and its cage
const neck=v3(0,0.62,0);
const stalkShape:pk.Stalk=.{.girth=0.042,.part=3.1,.from=0.12,.to=0.8};
/// the sac at the weave's top, where what it holds hangs
pub const sacAt=neck+v3(0,0.09,0);
pub const sacR=v3(0.1,0.12,0.1);
/// the pore at its crown its spores leave and land by
pub const poreAt=sacAt+v3(0,sacR[1]*1.05,0);
/// how many lanes wind up its core, and their tints (sapwood, warming to
/// amber, violet and blue: the lineages' saps and where they meet)
const lanes=4;
const laneTurns:f32=3.2;
pub fn build(b:*mg.Builder)Allocator.Error!void{
  var k=growth.Skeleton.begin(b);
  const stalk=k.trunk(&.{v3(0,-0.03,0),v3(0.012,0.2,-0.01),v3(-0.01,0.42,0.008),neck},.{.pace=1.6});
  try kit.footOn(b,&k,stalk,.{.r=0.09,.reach=0.34,.rootR=0.016,.seed=0xD1F0});
  var sp:[growth.res]V3=undefined;
  var sec:[growth.res]pk.Section=undefined;
  try kit.weaveOn(b,&k,stalk,stalkShape,.{.seed=0xD1F1},0,0.7,&sp,&sec);
  // the lanes, laid bare where the cage parts
  {
    var frameNormal:[growth.res]V3=undefined;
    var fb:[growth.res]V3=undefined;
    mg.transport(&sp,&frameNormal,&fb);
    const tints=[lanes]color.Rgba8{pal.sapwood,color.mix(pal.sapwood,kit.amber,0.45),color.mix(pal.sapwood,kit.violet,0.5),color.mix(pal.sapwood,kit.blue,0.5)};
    const mk=b.mark();
    for(tints,0..)|tint,li|{
      var p:[growth.res]V3=undefined;
      var ts:[growth.res]f32=undefined;
      var rs:[growth.res]f32=undefined;
      for(&p,&ts,&rs,sec,0..)|*q,*t,*r,c,i|{
        const u=m.ratio(i,growth.res-1);
        const a=m.ratio(li,lanes)*m.tau+u*laneTurns*m.tau;
        q.*=sp[i]+(frameNormal[i]*m.splat3(@cos(a))+fb[i]*m.splat3(@sin(a)))*m.splat3(c.tight*0.42);
        t.*=u*0.7;
        r.*=c.tight*0.3;
      }
      try b.tubeR(&p,&ts,&rs,tint,.stem,5);
    }
    try k.along(b,mk,stalk);
  }
  // the sac and its pore
  const sac=b.mark();
  try kit.sac(b,.{.center=sacAt,.radii=sacR,.t=0.75,.arms=3,.phase=0.6});
  try k.on(b,sac,stalk,1,.{.from=neck});
  const pore=b.mark();
  try pk.nodule(b,poreAt,v3(sacR[0]*0.3,sacR[1]*0.2,sacR[0]*0.3),0.8,kit.pale,color.mix(kit.pale,pk.core,0.4),kit.pearl);
  try k.on(b,pore,stalk,1,.{.from=sacAt,.delay=0.05});
  // the fronds: up the sac's flank from its foot, held off its skin, then
  // flaring out round the pore and curling down, alike
  for(0..kit.fold)|i|{
    const a=(m.f(i)+0.5)/m.f(kit.fold)*m.tau;
    var c:[11]V3=undefined;
    for(c[0..4],0..)|*q,j|{
      const th=m.lerp(m.pi,0.5,m.ratio(j,3));
      q.*=sacAt+v3(@sin(th)*@cos(a)*sacR[0]*1.1,@cos(th)*sacR[1]*1.1,@sin(th)*@sin(a)*sacR[2]*1.1);
    }
    pk.frondPath(c[3],v3(@cos(a),0,@sin(a)),0.42,0.55,2.2,0xD1F2,c[3..]);
    const id=k.branch(stalk,1,&c,.{.delay=0.08});
    try k.tube(b,id,.{.r0=0.014,.tip=0.45,.col=kit.lilac,.part=.tendril,.sides=5,.t0=0.75,.t1=1});
    try k.leaves(b,id,.{.n=3,.len=0.08,.width=0.028,.from=0.45,.to=0.85,.t0=0.75,.t1=1,.col=kit.leafDark,.tip=kit.leafLite,.seed=0xD1F3+%i*97});
    const fl=b.mark();
    const tip=k.point(id,1);
    try kit.bloom(b,.{.heart=tip,.len=0.06,.spin=a,.petals=6,.seed=0xD1F4});
    try k.on(b,fl,id,1,.{.from=tip});
  }
  k.finish(b);
}
