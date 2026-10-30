//! a plant from its genome, and the shoots branching off its spine.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const Rng=engine.core.rng.Rng;
const vertex=lib.vertex;
const species=lib.species;
const color=engine.core.color;
const parasiteKit=lib.parasiteKit;
const convergenceKit=lib.convergenceKit;
const radiantKit=lib.radiantKit;
const structureKit=lib.structureKit;
const V3=m.V3;
const Builder=lib.meshgen.Builder;
const keys=lib.meshgen.keys;
const drift=lib.meshgen.drifts.drift;
const grow=lib.meshgen.grow;
/// grow one of a species' mesh variants from its genome. Deterministic per
/// (species, variant): the stem and tendrils are grown vines, so every
/// variant leans, wobbles and curls a little differently. A confluence's
/// variants are instead its growth keys (see `KEYS`).
pub fn plant(b:*Builder,id:species.Id,variant:u32)Allocator.Error!void{
  const def=species.get(id);
  const g=def.genome;
  const seed=@as(u64,@intFromEnum(id))*977+77;
  switch(g.form){
    .herb=>try structureKit.plant(b,g,seed+@as(u64,variant)*131,variant,!def.floating),
    .coil=>try parasiteKit.plant(b,g,seed+@as(u64,variant)*131),
    .drift=>try drift(b,g,seed+@as(u64,variant)*131,variant),
    .radiant=>try radiantKit.plant(b,g,seed+@as(u64,variant)*131,variant),
    .star=>try radiantKit.star(b,g,seed+@as(u64,variant)*131,variant),
    // a confluence's variants are its growth keys, all grown from one seed
    .confluence=>try convergenceKit.confluence(b,g,seed,m.ratio(variant,keys-1)),
  }
}
/// how many offshoots a variant grows, between the genome's two counts.
pub fn shootCount(g:species.Genome,rng:*Rng)u32{
  const lo=g.shoots[0];
  const hi=@max(g.shoots[1],lo);
  return lo+rng.below(hi-lo+1);
}
/// where an offshoot ends: its tip and heading, its smoothed path, its
/// tu.x at the stem and the tip, and the first vertex after its stem
/// (for whatever grows along it).
pub const Shoot=struct{at:V3,axis:V3,path:[shootRes]V3,t0:f32,t1:f32,leaves:usize};
pub const shootRes=16;
/// an offshoot: a side stem grown from `k` along `spine`, leaving it toward
/// bearing `ang` at elevation `rise` and curving up toward the light as it
/// goes, tapering but never to nothing (a bud or bloom sits on its tip).
/// Its root is inside the main stem, at that stem's tu.x there (`t0`), so the two bend
/// alike; each ring is marked for `shootFold` by how far out it is.
pub fn offshoot(b:*Builder,spine:[]const V3,k:f32,t0:f32,ang:f32,len:f32,r0:f32,rise:f32,col:color.Rgba8,part:vertex.Part,seed:u64)Allocator.Error!Shoot{
  const res=shootRes;
  var sh=shootPath(spine,k,t0,ang,len,rise,seed);
  var ts:[res]f32=undefined;
  var rs:[res]f32=undefined;
  var cs:[res]color.Rgba8=undefined;
  for(&ts,&rs,&cs,0..)|*t,*r,*c,j|{
    const s=m.ratio(j,res-1);
    t.*=m.lerp(sh.t0,sh.t1,s);
    r.*=r0*m.lerp(1,0.55,s);
    c.*=col;
    c.a=m.unorm8(1-s);
  }
  try b.tubeC(&sh.path,&ts,&rs,&cs,null,part,5);
  sh.leaves=b.mark();
  return sh;
}
/// where an `offshoot` runs, built by the caller: its smoothed path, tip
/// and heading, its tu.x at the stem (`t0`) and the tip.
pub fn shootPath(spine:[]const V3,k:f32,t0:f32,ang:f32,len:f32,rise:f32,seed:u64)Shoot{
  const n=8;
  const res=shootRes;
  const root=m.alongPath(spine,k);
  const out=m.v3(@cos(ang),0,@sin(ang));
  var ctrl:[n]V3=undefined;
  ctrl[0]=root;
  for(1..n)|j|{
    const s=m.ratio(j,n-1);
    // heading turns from `rise` toward upright, mostly in its outer half
    const h=m.lerp(rise,1.35,s*s);
    ctrl[j]=ctrl[j-1]+(out*m.splat3(@cos(h))+m.v3(0,@sin(h),0))*m.splat3(len/(n-1));
  }
  grow(&ctrl,.{.start=root,.direction=m.norm(ctrl[n-1]-root),.length=len,.wobble=0.12,.curl=0.03,.seed=seed});
  var sh:Shoot=.{.at=undefined,.axis=undefined,.path=undefined,.t0=t0,.t1=@min(t0+0.15+len*0.2,1),.leaves=0};
  m.splineResample(&ctrl,&sh.path);
  sh.at=sh.path[res-1];
  sh.axis=m.norm(sh.path[res-1]-sh.path[res-4]);
  return sh;
}
/// `shootFold` for a stem built along an offshoot's `path` by its caller
/// (a braid): each vertex takes the weight of its nearest point of it.
pub fn shootFoldNearest(b:*Builder,start:usize,path:[]const V3)void{
  for(b.v.items[start..])|*v|{
    var best:usize=0;
    for(path,0..)|p,j|{
      if(m.len(p-v.pos)<m.len(path[best]-v.pos))best=j;
    }
    v.col.a=m.unorm8(1-m.ratio(best,path.len-1));
  }
}
/// mark every vertex since `start` as `w` of the way out along an offshoot
/// (colour alpha 1 - w; 1 everywhere else): until growth reaches it,
/// plant.vert folds an offshoot in against its stem by that much, so it
/// grows out of the stem, a bloom on it opening as it goes.
pub fn shootFold(b:*Builder,start:usize,w:f32)void{
  shootFoldRange(b,start,b.v.items.len,w);
}
/// `shootFold` for what grows along an offshoot (its leaves): each vertex
/// takes the weight of the point of `path` it grows from, so a leaf folds
/// in with the stem beneath it.
pub fn shootFoldAlong(b:*Builder,start:usize,path:[]const V3)void{
  var s=start;
  while(s<b.v.items.len){
    // the vertices of one leaf share its tu.x; weigh them by its base (tu.y 0)
    var e=s;
    var base=b.v.items[s].pos;
    while(e<b.v.items.len and b.v.items[e].tu[0]==b.v.items[s].tu[0]):(e+=1){
      if(b.v.items[e].tu[1]<1e-4)base=b.v.items[e].pos;
    }
    var best:usize=0;
    for(path,0..)|p,j|{
      if(m.len(p-base)<m.len(path[best]-base))best=j;
    }
    shootFoldRange(b,s,e,m.ratio(best,path.len-1));
    s=e;
  }
}
fn shootFoldRange(b:*Builder,start:usize,end:usize,w:f32)void{
  for(b.v.items[start..end])|*v|v.col.a=m.unorm8(1-w);
}
