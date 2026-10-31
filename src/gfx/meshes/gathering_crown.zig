//! mesh: GATHERING CROWN. a symbiote that gathers for the garden: a rosette
//! of broad leaves on a woven root mat, a short woven stalk opening into a
//! crown of cupped petals round a pod of resin sap where what it gathers
//! hangs (emitted, `bellyLump`s), stamens standing round the pod's crown.
//! Its roots out to the plants round it are its own (`Root(n)`, emitted
//! one per plant, by how far away the plant stands).
//! It grows on a hidden stalk (gfx/growth.zig): the roots spread with it,
//! the rosette unfolds leaf by leaf, the stalk rises, the pod swells and
//! the crown opens petal by petal round it, the stamens last.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// the plant-piece mesher: braids, petals, stamens, the builder itself
const mg=lib.meshgen;
/// the garden's palette: named colours (leaves, vine, core)
const pal=lib.palette;
/// colour conversions, for the petals' warm tips
const color=engine.core.color;
/// the structure kit: root mats, foot leaves, resin pods and rootlets
const kit=lib.structureKit;
/// the garden's growth timing: the hidden stalk everything grows along
const growth=lib.growth;
/// the conduit's mesh, whose woven side root (`arch`) the roots borrow
const conduit=lib.conduit;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// the stalk's top, where the crown of petals opens
pub const crown=v3(0,0.3,0);
/// the pod at the crown's heart, where what it gathers hangs
pub const podAt=crown+v3(0,0.07,0);
/// the pod's half-sizes along x, y and z
pub const podR=v3(0.1,0.09,0.1);
/// how many petals ring the crown
const petals=8;
/// how much later each petal opens than the one before (share of the growth)
const petalStagger:f32=0.025;
/// the distances its roots reach to (tiles), each a mesh of its own: the
/// plants on the 5x5 tiles round it
pub const reaches=[_]f32{1,m.sqrt2,2,2.2360680,2*m.sqrt2};
/// the warm amber the even petals' tips turn to
const warm=color.rgb(0.95,0.72,0.36).toRgba8(255);
/// the paler blush the odd petals' tips turn to
const blush=color.rgb(0.98,0.86,0.6).toRgba8(255);
/// builds the crown: the root mat and rosette at its foot, a braided stalk,
/// the resin pod at its top and eight petals opening round it one by one,
/// then the stamens; all hung on one growth skeleton in that order
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the growth skeleton everything below is hung on
  var k=growth.Skeleton.begin(b);
  // the hidden stalk: from just under the ground up to the crown
  const stalk=k.trunk(&.{v3(0,-0.03,0),v3(0.01,0.12,-0.008),v3(-0.006,0.22,0.004),crown},.{.pace=1.6});
  try kit.rootMat(b,9,0.55,0.04,0x6C01,.{.k=&k,.id=stalk});
  try kit.footLeaves(b,10,0.12,0.4,0.15,0x6C02,.{.k=&k,.id=stalk,.u=0.08});
  {
    // the stalk's path, its growth timing and its radius along it
    var sp:[growth.res]V3=undefined;
    var ts:[growth.res]f32=undefined;
    var rs:[growth.res]f32=undefined;
    k.path(stalk,0,1,&sp);
    for(&ts,&rs,0..)|*t,*r,i|{
      // how far up the stalk this point is (0..1)
      const u=m.ratio(i,growth.res-1);
      t.*=u*0.6;
      r.*=0.045*(0.8+0.45*@exp(-u*6)+0.35*@exp(-(1-u)*6));
    }
    // where the braid's vertices begin, so it rises along the stalk
    const s=b.mark();
    try mg.braid(b,&sp,&ts,&rs,4,2.4,pal.strandWobble,0x6C03,pal.core,pal.vine);
    try k.along(b,s,stalk);
  }
  // the pod, swelling out of the stalk's top, the crown opening round it
  // where the pod's vertices begin, so it swells out of the stalk's top
  const pod=b.mark();
  try kit.resinPod(b,podAt,podR,10,14);
  try k.on(b,pod,stalk,1,.{.from=crown});
  for(0..petals)|i|{
    // this petal's angle round the crown: the odd ones nudged half a step round
    const a=(m.f(i)+0.5*m.f(i%2))/petals*m.tau;
    // where this petal's vertices begin, so it opens in its turn
    const s=b.mark();
    try mg.petal(b,.{
      .base=crown,.out=v3(@cos(a),0,@sin(a)),.len=0.2,.width=0.085,
      .rise=1.15,.flare=0.9,.cup=0.5,.col=pal.leafDark,.tip=if(i%2==0)warm else blush,.part=.leaf,
    });
    try k.on(b,s,stalk,1,.{.from=crown,.delay=0.03+petalStagger*m.f(i)});
  }
  // where the stamens' vertices begin, so they stand last of all
  const sta=b.mark();
  try mg.stamens(b,.{
    .heart=podAt+v3(0,podR[1]*0.6,0),.axis=v3(0,1,0),.n=9,.len=0.11,.r=0.004,.anther=0.022,
    .lean=0.55,.arch=0.5,.col=pal.leafLite,.seed=0x6C04,
  });
  try k.on(b,sta,stalk,1,.{.from=podAt,.delay=0.06+petalStagger*petals});
  k.finish(b);
}
/// mesh: GATHERING ROOT. a root from under the crown along +X to a plant
/// `reaches[n]` tiles out, woven as a conduit's side root (`conduit.arch`):
/// it comes up beside the crown, arches low over the ground and digs in at
/// the plant's foot, splitting into rootlets round it. It grows along its
/// own spline by how far it has reached (emitted with that as `grown`), the
/// rootlets last, and withers back down it.
pub fn Root(comptime n:usize)type{
  return struct{
    /// how far the root runs: to just short of the plant's tile centre (tiles)
    const reachDistance=reaches[n]-0.22;
    /// builds the root: the woven arch out to the plant, then three rootlets
    /// splitting round its foot, each grown a little after the last
    pub fn build(b:*mg.Builder)Allocator.Error!void{
      // the growth skeleton the root is hung on
      var k=growth.Skeleton.begin(b);
      // the arch's spine, which the rootlets branch from at its end
      const spine=try conduit.arch(b,&k,.{
        .from=0.06,.to=reachDistance,.peak=0.07+0.025*m.f(n),.depth=0.06,.coreR=0.017,.strands=2,
        .turns=1.2+0.5*reaches[n],.core=.stem,.leaves=if(n<2)&.{2}else&.{2,3},.runners=false,.seed=0x6C10+%n*7,
      });
      // where the arch digs in, at the plant's foot
      const end=v3(reachDistance,-0.02,0);
      for([_]f32{-0.9,-0.1,0.8},0..)|a,i|{
        // where this rootlet's vertices begin, so it grows from the arch's end
        const s=b.mark();
        try kit.rootlet(b,end,m.norm(v3(@cos(a)*0.8,-0.45,@sin(a)*0.8)),0.2,0.012,0x6C20+%n*11+%i*29);
        try k.on(b,s,spine,1,.{.from=end,.delay=0.04*m.f(i)});
      }
      k.finish(b);
    }
  };
}
