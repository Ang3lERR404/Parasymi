//! mesh: BRAIDED CONDUIT. a root conduit grown dense: four sapwood cores,
//! one lane each (part `.core`: what a lane carries swells and tints its
//! own core as it passes, part.vert), twisting round one another along the
//! same arch a conduit makes (up out of the soil at its back edge, over,
//! down in at its front), bound in a looser weave of smaller roots with
//! leaves over its top and soil heaped where it breaks the ground.
//! `wrap` (and `wrapLeft`/`wrapRight`, turning in from the tile's +Z / -Z
//! edge) is the weave, leaves and soil; `Lane(turn, i)` the cores, each a
//! mesh of its own so each carries its own item; the bare `build` the whole
//! of a straight one, its preview.
//! Every piece grows along one growth spline per arch, the same in each
//! (gfx/growth.zig): the cores and weave dig on together.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, noise, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, splines
const m=engine.core.math;
/// the plant-piece mesher: frames, the builder these meshes are put into
const mg=lib.meshgen;
/// the garden's palette: sapwood's dark and light
const pal=lib.palette;
/// colour conversions, for mixing each core's grain
const color=engine.core.color;
/// smooth noise, for each core's swelling and grain
const noise=engine.core.noise;
/// the garden's growth timing: the arch's spline everything grows along
const growth=lib.growth;
/// the conduit's mesh, whose arch this one shares
const conduit=lib.conduit;
/// a point or direction in space
const V3=m.V3;
/// how many lanes it carries: one core each
pub const lanes=4;
/// rings along a core
const res=48;
/// how far each core lies off the arch's spine
/// (the four sit round it at quarters)
const bundle:f32=0.034;
/// each core's girth (its radius)
const laneR:f32=0.019;
/// how many turns the four make round one another over the arch
const twist:f32=1.1;
/// the binding: so few strands, wound so loosely, that the lanes show
/// between them; its girth clears the cores' however its knots run
const bindR:f32=0.066;
/// each lane's own grain, so the four read apart
const laneTone=[lanes]f32{0.25,0.55,0.8,0.4};
/// the arch a braided conduit makes turning `turn` (as a conduit's), the
/// weave's alone (no core: the lanes are its cores)
fn archOf(turn:f32)conduit.Arch{
  // each turn's weave has its own seed: straight, turning left, turning right
  const seed:u64=if(turn==0)0xB0D else if(turn>0)0xB1D else 0xB2D;
  return.{
    .turn=turn,.peak=conduit.peak*1.12,.coreR=bindR,.core=null,
    .strands=2,.turns=1.4,.leaves=&.{3,2,3,2,3,3},.seed=seed,
  };
}
/// builds a straight one whole, for its preview: the weave and all four cores
pub fn build(b:*mg.Builder)Allocator.Error!void{
  try wrapped(b,0);
  for(0..lanes)|i|try lane(b,0,i);
}
/// mesh: the weave, leaves and soil of a straight braided conduit
pub const wrap=struct{
  /// builds the straight weave
  pub fn build(b:*mg.Builder)Allocator.Error!void{try wrapped(b,0);}
};
/// mesh: the weave of one turning in from the tile's +Z edge
pub const wrapLeft=struct{
  /// builds the left-turning weave
  pub fn build(b:*mg.Builder)Allocator.Error!void{try wrapped(b,1);}
};
/// mesh: the weave of one turning in from the tile's -Z edge
pub const wrapRight=struct{
  /// builds the right-turning weave
  pub fn build(b:*mg.Builder)Allocator.Error!void{try wrapped(b,-1);}
};
/// lane `i`'s core of the arch turning `turn`
pub fn Lane(comptime turn:f32,comptime i:usize)type{
  return struct{
    /// builds that lane's core
    pub fn build(b:*mg.Builder)Allocator.Error!void{try lane(b,turn,i);}
  };
}
/// builds the weave of the arch turning `turn`: binding, leaves and soil on
/// one growth skeleton
fn wrapped(b:*mg.Builder,turn:f32)Allocator.Error!void{
  // the growth skeleton the weave is hung on
  var k=growth.Skeleton.begin(b);
  _=try conduit.arch(b,&k,archOf(turn));
  k.finish(b);
}
/// one lane's core: round the arch's spine at its own quarter, twisting
/// with the others, flaring with them where they break the ground; tu.x 0
/// where it comes up .. 1 where it goes down, as a conduit's core
fn lane(b:*mg.Builder,turn:f32,i:usize)Allocator.Error!void{
  // the arch this core follows, as the weave's
  const a=archOf(turn);
  // the spine's control points
  const ctrl=conduit.spineCtrl(a);
  // the growth skeleton the core is hung on
  var k=growth.Skeleton.begin(b);
  // the spine's spline, which the core grows along
  const spine=k.trunk(&ctrl,.{});
  // the spine resampled to one point per ring
  var sp:[res]V3=undefined;
  m.splineResample(&ctrl,&sp);
  // a twist-free frame along the spine: its normal and its binormal
  var frameNormal:[res]V3=undefined;
  var fb:[res]V3=undefined;
  mg.transport(&sp,&frameNormal,&fb);
  // the core's path, growth timing, radius and colour, ring by ring
  var path:[res]V3=undefined;
  var ts:[res]f32=undefined;
  var rs:[res]f32=undefined;
  var cols:[res]color.Rgba8=undefined;
  // this lane's own seed, so its grain and swelling are its own
  const seed=a.seed+%i*31;
  for(&path,&ts,&rs,&cols,0..)|*p,*t,*r,*c,j|{
    // how far along the arch this ring is (0..1), and its height above the soil
    const u=m.ratio(j,res-1);
    const y=sp[j][1];
    // how much it flares here: most where the arch breaks the ground (y near 0)
    const flare=conduit.flareAmount*@exp(-y*y/0.0012);
    // this core's angle round the spine here, turning as it goes
    const th=m.ratio(i,lanes)*m.tau+twist*m.tau*u;
    p.*=sp[j]+(frameNormal[j]*m.splat3(@cos(th))+fb[j]*m.splat3(@sin(th)))*m.splat3(bundle*(1+0.6*flare));
    t.*=u;
    r.*=laneR*(1+0.12*noise.grad(seed,u*6,0.5)+0.5*flare);
    c.*=color.mix(pal.sapwoodDark,pal.sapwood,m.clamp01(laneTone[i]+1.5*noise.grad(seed+%1,u*9,1.5)));
  }
  // where the core's vertices begin, so it digs on with the weave
  const s=b.mark();
  try b.tubeC(&path,&ts,&rs,&cols,null,.core,7);
  try k.along(b,s,spine);
  k.finish(b);
}
