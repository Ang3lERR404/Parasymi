//! mesh: DRIFTBRAID. a braided conduit and a sporecaster grown into one
//! (convergence_kit): rooted both ways, a tall weave of green and pale
//! strands parting into a cage, four sapwood lanes winding up its core
//! inside it (each tinted as a braided conduit's lanes are by what they
//! carry), up to a spore sac of both saps where what it holds hangs
//! (emitted, `bellyLump`s), pursed at its crown into a pearl pore its
//! spore carriers rise out of and drift down into; five lilac fronds clasp
//! the sac exactly alike and flare out round the pore, each carrying
//! leaves of its own and ending in a flower of both.
//! It grows on a hidden stalk (gfx/growth.zig): the bulb swells and its
//! roots spread with it, the weave rises, the sac swells out of its top,
//! the pore purses, the fronds clasp and flare last, their leaves opening
//! as they pass and their flowers last of all.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// the plant-piece mesher: tubes, frames, the builder this mesh is put into
const mg=lib.meshgen;
/// colour conversions, for mixing the lanes' tints
const color=engine.core.color;
/// the garden's growth timing: the hidden stalk everything grows along
const growth=lib.growth;
/// the garden's palette: named colours (sapwood, leaves, strands)
const pal=lib.palette;
/// the parasite kit: stalks, nodules and frond paths
const pk=lib.parasiteKit;
/// the convergence kit: feet, weaves, sacs and blooms of both lineages
const kit=lib.convergenceKit;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// the weave's top, and its cage
const neck=v3(0,0.62,0);
/// how the weave's stalk is shaped: its girth, how far its strands part and
/// over which stretch of it (0..1) the cage opens
const stalkShape:pk.Stalk=.{.girth=0.042,.part=3.1,.from=0.12,.to=0.8};
/// the sac at the weave's top, where what it holds hangs
pub const sacAt=neck+v3(0,0.09,0);
/// the sac's half-sizes along x, y and z
pub const sacR=v3(0.1,0.12,0.1);
/// the pore at its crown its spores leave and land by
pub const poreAt=sacAt+v3(0,sacR[1]*1.05,0);
/// how many lanes wind up its core, and their tints (sapwood, warming to
/// amber, violet and blue: the lineages' saps and where they meet)
const lanes=4;
/// how many times each lane winds round the core on its way up
const laneTurns:f32=3.2;
/// builds the driftbraid: the foot and roots, the woven stalk, four lanes
/// winding up inside the cage, the sac and its pore at the top, then five
/// fronds clasping the sac and flaring out, each with leaves and a flower;
/// all hung on one growth skeleton so it grows in that order
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the growth skeleton everything below is hung on
  var k=growth.Skeleton.begin(b);
  // the hidden stalk: from just under the ground up to the weave's top
  const stalk=k.trunk(&.{v3(0,-0.03,0),v3(0.012,0.2,-0.01),v3(-0.01,0.42,0.008),neck},.{.pace=1.6});
  try kit.footOn(b,&k,stalk,.{.r=0.09,.reach=0.34,.rootR=0.016,.seed=0xD1F0});
  // the stalk's path, and the weave's section (how tight the cage is) along it
  var sp:[growth.res]V3=undefined;
  var sec:[growth.res]pk.Section=undefined;
  try kit.weaveOn(b,&k,stalk,stalkShape,.{.seed=0xD1F1},0,0.7,&sp,&sec);
  // the lanes, laid bare where the cage parts
  {
    // a twist-free frame along the stalk: its normal and its binormal
    var frameNormal:[growth.res]V3=undefined;
    var fb:[growth.res]V3=undefined;
    mg.transport(&sp,&frameNormal,&fb);
    // each lane's tint: plain sapwood, then sapwood leaning amber, violet, blue
    const tints=[lanes]color.Rgba8{pal.sapwood,color.mix(pal.sapwood,kit.amber,0.45),color.mix(pal.sapwood,kit.violet,0.5),color.mix(pal.sapwood,kit.blue,0.5)};
    // where the lanes' vertices begin, so they grow along the stalk together
    const mk=b.mark();
    for(tints,0..)|tint,li|{
      // one lane's path, its growth timing and its radius along the stalk
      var p:[growth.res]V3=undefined;
      var ts:[growth.res]f32=undefined;
      var rs:[growth.res]f32=undefined;
      for(&p,&ts,&rs,sec,0..)|*q,*t,*r,c,i|{
        // how far up the stalk this point is (0..1), and the lane's angle round the core there
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
  // where the sac's vertices begin, so it swells out of the stalk's top
  const sac=b.mark();
  try kit.sac(b,.{.center=sacAt,.radii=sacR,.t=0.75,.arms=3,.phase=0.6});
  try k.on(b,sac,stalk,1,.{.from=neck});
  // where the pore's vertices begin, so it purses just after the sac
  const pore=b.mark();
  try pk.nodule(b,poreAt,v3(sacR[0]*0.3,sacR[1]*0.2,sacR[0]*0.3),0.8,kit.pale,color.mix(kit.pale,pk.core,0.4),kit.pearl);
  try k.on(b,pore,stalk,1,.{.from=sacAt,.delay=0.05});
  // the fronds: up the sac's flank from its foot, held off its skin, then
  // flaring out round the pore and curling down, alike
  for(0..kit.fold)|i|{
    // this frond's angle round the sac (radians), set between the others
    const a=(m.f(i)+0.5)/m.f(kit.fold)*m.tau;
    // the frond's control points: four up the sac's flank, the rest flaring out
    var c:[11]V3=undefined;
    for(c[0..4],0..)|*q,j|{
      // how far round the sac's side this point sits, from its foot toward its waist
      const th=m.lerp(m.pi,0.5,m.ratio(j,3));
      q.*=sacAt+v3(@sin(th)*@cos(a)*sacR[0]*1.1,@cos(th)*sacR[1]*1.1,@sin(th)*@sin(a)*sacR[2]*1.1);
    }
    pk.frondPath(c[3],v3(@cos(a),0,@sin(a)),0.42,0.55,2.2,0xD1F2,c[3..]);
    // the frond's own branch of the skeleton, grown just after the sac
    const id=k.branch(stalk,1,&c,.{.delay=0.08});
    try k.tube(b,id,.{.r0=0.014,.tip=0.45,.col=kit.lilac,.part=.tendril,.sides=5,.t0=0.75,.t1=1});
    try k.leaves(b,id,.{.n=6,.len=0.08,.width=0.028,.from=0.3,.to=0.9,.t0=0.75,.t1=1,.col=kit.leafDark,.tip=kit.leafLite,.seed=0xD1F3+%i*97});
    // where the flower's vertices begin, so it opens last
    const fl=b.mark();
    // the frond's tip, where its flower sits
    const tip=k.point(id,1);
    try kit.bloom(b,.{.heart=tip,.len=0.06,.spin=a,.petals=6,.seed=0xD1F4});
    try k.on(b,fl,id,1,.{.from=tip});
  }
  k.finish(b);
}
