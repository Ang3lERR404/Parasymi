//! mesh: the root well, of both lineages (convergence kit). A rooted foot
//! and a short woven stem, from whose top staves of braided strands, pale
//! cored and green wound, curve out and up into a basket; a braided rim
//! runs round their lips, leaves round it reaching out and up to catch the
//! rain, and a small sac of both saps sits in its bottom. The water it
//! holds is its own mesh (`water`), risen in the basket as high as it is
//! full (structures/root_well.zig). All grown along one skeleton: the foot
//! and stem, the staves rising, the rim running round, its leaves opening.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors and lerps
const m=engine.core.math;
/// the garden's meshgen: builder, leaves, ellipsoids
const mg=lib.meshgen;
/// colour types
const color=engine.core.color;
/// growth splines: the skeleton the well grows along
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
/// the stem's top, where the staves leave it: the basket's bottom
const base=v3(0,0.16,0);
/// how many staves make the basket
const staves=7;
/// the basket's lip: how high, and how far out
const lipH:f32=0.78;
/// (how far out)
const lipR:f32=0.34;
/// how many leaves stand round the rim
const rimLeaves=9;
/// the woven stem's shape
const stemShape:pk.Stalk=.{.girth=0.07,.part=2.2,.from=0.2,.to=0.8};
/// how high up the lining the water stands full (a share of the wall)
const waterTop:f32=0.85;
/// where the surface of the water it holds lies, `full` (0..1) full: its
/// middle, and how far across it reaches, just inside the lining there
/// (structures/root_well.zig places `water` so)
pub fn surface(full:f32)struct{V3,f32}{
  // how far up the wall the surface stands
  const s=m.clamp01(full)*waterTop*liningTop;
  return.{v3(0,base[1]+liningThick+s*(lipH-base[1]),0),staveR(s)*liningIn-liningThick*1.5};
}
/// the shape a stave runs, its share `s` up from the bottom to the lip:
/// out from the stem, swelling into the basket's belly, drawing in a
/// little under the lip and flaring at it
fn staveR(s:f32)f32{return lipR*(0.25+0.95*@sin(s*m.pi*0.62)+0.08*s*s);}
/// builds the well whole: foot, stem, staves, rim, rim leaves, sac
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the skeleton every part is timed along
  var k=growth.Skeleton.begin(b);
  // the stem: up out of the soil to the basket's bottom
  const stem=k.trunk(&.{v3(0,-0.05,0),v3(0.01,0.08,-0.01),base},.{.pace=1.4});
  try kit.footOn(b,&k,stem,.{.r=0.11,.reach=0.5,.rootR=0.02,.seed=0x3E11});
  // the stem's woven path and sections
  var sp:[growth.res]V3=undefined;
  var sec:[growth.res]pk.Section=undefined;
  try kit.weaveOn(b,&k,stem,stemShape,.{.form=.stems,.seed=0x3E12},0,0.3,&sp,&sec);
  // the staves, out and up from the stem's top to the lip
  var first:growth.Id=undefined;
  for(0..staves)|i|{
    // its bearing, the way out along it, and its control points
    const a=m.ratio(i,staves)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    var c:[6]V3=undefined;
    for(&c,0..)|*p,j|{
      // how far up the stave
      const s=m.ratio(j,c.len-1);
      p.*=base+out*m.splat3(staveR(s))+v3(0,s*(lipH-base[1]),0);
    }
    const id=k.branch(stem,1,&c,.{.after=.with});
    if(i==0)first=id;
    try k.braid(b,id,.{.girth=0.02,.tip=0.6,.strands=3,.twist=2.5,.wobble=pal.strandWobble,.seed=0x3E20+%i*13,.core=kit.pale,.strand=kit.green,.t0=0.3,.t1=0.75});
  }
  // the rim: once round the lips, from the first stave's top, a little past
  var rc:[14]V3=undefined;
  for(&rc,0..)|*p,j|{
    // how far round
    const a=m.ratio(j,rc.len-1)*m.tau*1.04;
    p.*=v3(@cos(a)*staveR(1),lipH,@sin(a)*staveR(1));
  }
  const rim=k.branch(first,1,&rc,.{});
  try k.braid(b,rim,.{.girth=0.024,.tip=0.5,.strands=4,.twist=9,.wobble=pal.strandWobble,.seed=0x3E30,.core=kit.lilac,.strand=kit.green,.t0=0.75,.t1=0.9});
  // the rim's leaves, reaching out and up to catch the rain
  for(0..rimLeaves)|i|{
    // how far round the rim, and the way out there
    const u=(m.f(i)+0.5)/rimLeaves;
    const at=k.point(rim,u/1.04);
    const out=m.norm(v3(at[0],0,at[2]));
    const mk=b.mark();
    try mg.natural(b,at,m.norm(out+v3(0,0.9,0)),0.2,0.075,0.3,kit.leafDark,kit.leafLite,0.9,.stalked);
    try k.on(b,mk,rim,u/1.04,.{.from=at,.delay=0.02*m.f(i%3)});
  }
  // its lining: a thin bowl of both saps inside the staves, see-through,
  // so the water it holds shows through it; swelling out from the stem's
  // top as the staves rise
  const lining=b.mark();
  try bowl(b);
  try k.on(b,lining,stem,1,.{.from=base,.delay=0.05});
  // a small sac of both saps in its bottom
  const sac=b.mark();
  try kit.sac(b,.{.center=base+v3(0,0.03,0),.radii=v3(0.07,0.045,0.07),.t=0.8});
  try k.on(b,sac,stem,1,.{.from=base});
  k.finish(b);
}
/// rings up the lining's wall, and segments round it
const liningRows=12;
/// (segments round)
const liningSegs=48;
/// how thick the lining is (m), and how far inside the staves it lies
const liningThick:f32=0.01;
/// (how far inside, a share of the staves' reach)
const liningIn:f32=0.9;
/// how high up the staves the lining reaches (the rim covers its edge)
const liningTop:f32=0.95;
/// the lining's colour: both saps thinned to a pale lilac, see-through
const liningCol=color.rgb(0.78,0.7,0.95).toRgba8(150);
/// the lining: a thin bowl turned round the well's axis, its wall
/// following the staves (`staveR`) from the stem's top to just under the
/// rim, rounded over at its edge, closed at its bottom inside and out
/// (watertight); see-through (`.bloom`)
fn bowl(b:*mg.Builder)Allocator.Error!void{
  // its profile, up the outside, over the edge, down the inside: each
  // point's reach from the axis and height
  const n=2*liningRows+4;
  var pr:[n]m.Vec(f32,2)=undefined;
  pr[0]=.{0,base[1]};
  for(0..liningRows)|j|{
    // how far up the wall
    const s=m.ratio(j,liningRows-1)*liningTop;
    const y=base[1]+s*(lipH-base[1]);
    const r=staveR(s)*liningIn;
    pr[1+j]=.{r,y};
    pr[n-2-j]=.{r-liningThick,y+liningThick*(1-s)};
  }
  // over its edge
  const top=pr[liningRows];
  pr[liningRows+1]=.{top[0]-liningThick*0.5,top[1]+liningThick*0.6};
  pr[n-1]=.{0,base[1]+liningThick};
  // each profile point's normal, out of the wall (the profile turned a quarter)
  var nr:[n]m.Vec(f32,2)=undefined;
  for(0..n)|j|{
    // the way the profile runs here
    const d=pr[@min(j+1,n-1)]-pr[if(j==0)0 else j-1];
    nr[j]=.{d[1],-d[0]};
  }
  for(0..n-1)|j|for(0..liningSegs)|q|{
    // the quad's two rows and two bearings
    const a0=m.ratio(q,liningSegs)*m.tau;
    const a1=m.ratio(q+1,liningSegs)*m.tau;
    const corners=[4]struct{usize,f32}{.{j,a0},.{j,a1},.{j+1,a1},.{j+1,a0}};
    for([2][3]usize{.{0,1,2},.{0,2,3}})|tri|{
      // its three points and normals
      var p:[3]V3=undefined;
      var nn:[3]V3=undefined;
      for(tri,0..)|c,e|{
        const row,const a=corners[c];
        p[e]=v3(@cos(a)*pr[row][0],pr[row][1],@sin(a)*pr[row][0]);
        nn[e]=m.norm(v3(@cos(a)*nr[row][0],nr[row][1],@sin(a)*nr[row][0])+v3(0,1e-4,0));
      }
      // wound counter-clockwise seen from outside
      const flip=m.dot(m.cross(p[1]-p[0],p[2]-p[0]),nn[0]+nn[1]+nn[2])<0;
      for([3]usize{0,if(flip)2 else 1,if(flip)1 else 2})|e|try b.put(p[e],nn[e],liningCol,1,0,.bloom);
    }
  };
}
/// mesh: the surface of the water a root well holds: a thin round sheet
/// of pale blue a unit across, its well placing it as high and wide as it
/// is full (`surface`); see-through
pub const water=struct{
  /// builds the sheet: a flat ellipsoid round its origin
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(1,0.02,1),.col=color.rgb(0.5,0.72,1.0).toRgba8(210),.part=.bloom,.rings=4,.segs=24,.t=1});
  }
};
