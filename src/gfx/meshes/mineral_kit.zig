//! shared pieces for the ground's minerals: crystals and faceted stones,
//! flat-faced (each face its own normal) so they catch the light as cut
//! planes. Not a mesh itself; the node meshes use it.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, cross and dot products
const m=engine.core.math;
/// the mesh builder, whose raw vertices the facets are put into
const mg=lib.meshgen;
/// colour conversions, for each corner's colour
const color=engine.core.color;
/// the vertex layout: the part role each facet is drawn as
const vertex=lib.vertex;
/// the engine's deterministic random stream, for uneven faces
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// one flat-shaded triangle, facing away from `inside`: its normal is the
/// face's own, flipped (with the winding) if it pointed inward; each corner
/// takes its own colour, all share growth stamp `t` and part role `part`.
pub fn facet(b:*mg.Builder,p:[3]V3,inside:V3,col:[3]color.Rgba8,t:f32,part:vertex.Part)Allocator.Error!void{
  // the face's normal as wound
  var n=m.norm(m.cross(p[1]-p[0],p[2]-p[0]));
  // whether it points inward, and the corner order that turns it outward
  const flip=m.dot(n,m.centroid(p[0],p[1],p[2])-inside)<0;
  if(flip)n=-n;
  const order=if(flip)[3]usize{0,2,1}else[3]usize{0,1,2};
  for(order)|i|try b.put(p[i],n,col[i],t,0,part);
}
/// how one crystal grows: where from, which way, how long and thick, and
/// in what colours
pub const Crystal=struct{
  /// where its foot stands (it sinks a little below this)
  base:V3,
  /// which way it points, a unit direction
  dir:V3,
  /// its length from base to point
  len:f32,
  /// its radius across the prism
  r:f32,
  /// how many faces round the prism (at most 8)
  sides:u32=6,
  /// fraction of the length taken by the pointed termination
  point:f32=0.28,
  /// the body's colour, at the foot
  col:color.Rgba8,
  /// the colour it pales to toward the point
  tip:color.Rgba8,
  /// the part role it is drawn as: glowing by default
  part:vertex.Part=.bloom,
};
/// a crystal: a faceted prism rising from its base (sunk a little) to a
/// pyramidal point, its faces slightly uneven like a grown crystal; turned
/// at random about its axis, each corner nudged in or out by `rng`
pub fn crystal(b:*mg.Builder,c:Crystal,rng:*Rng)Allocator.Error!void{
  // two directions square to the axis, to lay the prism's corners round it
  const side=m.norm(m.cross(c.dir,if(@abs(c.dir[1])<m.nearParallel)v3(0,1,0)else v3(1,0,0)));
  const fwd=m.cross(c.dir,side);
  // where the prism ends and the point begins, and the point itself
  const top=c.base+c.dir*m.splat3(c.len*(1-c.point));
  const apex=c.base+c.dir*m.splat3(c.len);
  // a point inside, for facing the faces out, and the sunk foot below the base
  const inside=c.base+c.dir*m.splat3(c.len*0.5);
  const foot=c.base-c.dir*m.splat3(c.r);
  // the prism's lower and upper rings of corners
  var lo:[8]V3=undefined;
  var hi:[8]V3=undefined;
  // how far the whole crystal is turned about its axis
  const turn=rng.range(0,m.tau);
  for(0..c.sides)|i|{
    // this corner's bearing, its uneven radius, and its offset off the axis
    const a=turn+m.tau*m.ratio(i,c.sides);
    const rr=c.r*rng.range(0.85,1.12);
    const o=side*m.splat3(@cos(a)*rr)+fwd*m.splat3(@sin(a)*rr);
    lo[i]=c.base+o;
    hi[i]=top+o*m.splat3(rng.range(0.85,1.0));
  }
  for(0..c.sides)|i|{
    // the next corner round
    const j=(i+1)%c.sides;
    try facet(b,.{lo[i],lo[j],hi[j]},inside,.{c.col,c.col,c.tip},0.3,c.part);
    try facet(b,.{lo[i],hi[j],hi[i]},inside,.{c.col,c.tip,c.tip},0.3,c.part);
    try facet(b,.{hi[i],hi[j],apex},inside,.{c.tip,c.tip,c.tip},1,c.part);
    try facet(b,.{lo[i],foot,lo[j]},inside,.{c.col,c.col,c.col},0,c.part);
  }
}
/// a faceted stone half sunk in the ground at `at`, radius `r`, `flat` how
/// tall it stands (a share of `r`): two irregular rings of points between
/// a flat-ish crown and a buried bottom, `col` on its flanks paling to
/// `lite` up its top faces
pub fn stone(b:*mg.Builder,at:V3,r:f32,flat:f32,col:color.Rgba8,lite:color.Rgba8,rng:*Rng)Allocator.Error!void{
  // how many corners round each ring
  const s=7;
  // the middle ring (its widest) and the upper ring (its shoulders)
  var mid:[s]V3=undefined;
  var up:[s]V3=undefined;
  // how far the whole stone is turned
  const turn=rng.range(0,m.tau);
  for(0..s)|i|{
    // this corner's jittered bearing and uneven radius
    const a=turn+m.tau*m.ratio(i,s)+rng.range(-0.2,0.2);
    const rr=r*rng.range(0.8,1.15);
    mid[i]=at+v3(@cos(a)*rr,r*flat*rng.range(0.1,0.35),@sin(a)*rr);
    // the shoulder's bearing, halfway to the next corner
    const a2=a+m.pi/m.f(s);
    up[i]=at+v3(@cos(a2)*rr*0.62,r*flat*rng.range(0.7,0.95),@sin(a2)*rr*0.62);
  }
  // the crown on top, nudged off centre, and the buried bottom
  const crown=at+v3(r*rng.range(-0.1,0.1),r*flat*1.05,r*rng.range(-0.1,0.1));
  const bottom=at-v3(0,r*flat*0.5,0);
  // a point inside, for facing the faces out
  const inside=at+v3(0,r*flat*0.3,0);
  for(0..s)|i|{
    // the next corner round
    const j=(i+1)%s;
    try facet(b,.{mid[i],mid[j],up[i]},inside,.{col,col,lite},0.4,.stem);
    try facet(b,.{mid[j],up[j],up[i]},inside,.{col,lite,lite},0.4,.stem);
    try facet(b,.{up[i],up[j],crown},inside,.{lite,lite,lite},0.5,.stem);
    try facet(b,.{mid[i],bottom,mid[j]},inside,.{col,col,col},0.4,.stem);
  }
}
