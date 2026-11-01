//! shared pieces for the ground's minerals: crystals, flat-faced (each
//! face its own normal) so they catch the light as cut planes, and
//! weathered stones, smooth boulders ground down to rounded worn faces.
//! Not a mesh itself; the node meshes use it.
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
  const order=if(flip)m.Vice(usize,3){0,2,1}else m.Vice(usize,3){0,1,2};
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
/// rings from a boulder's buried foot to its crown, at full detail
const boulderRings=12;
/// sides round each of its rings, at full detail
const boulderSides=18;
/// how many worn faces a boulder is ground down to
const boulderCuts=7;
/// how many lumps and dents swell or sink its body
const boulderLumps=4;
/// how softly a worn face rounds off into the body round it
const cutSoft:f32=0.05;
/// a boulder's shape before it is scaled: worn faces (planes it is ground
/// down to) and lumps, round its centre
const Boulder=struct{
  /// each worn face's outward direction
  cutN:[boulderCuts]V3,
  /// how far out each lies
  cutD:[boulderCuts]f32,
  /// each lump's direction
  lumpN:[boulderLumps]V3,
  /// how far each swells (a dent below zero)
  lumpA:[boulderLumps]f32,
  /// how far out (a share of its radius) the body reaches in direction `d`:
  /// a sphere swelled and dented by its lumps, ground down to its worn
  /// faces, each rounded off smoothly into the rest
  fn reach(bd:*const Boulder,d:V3)f32{
    // the body before its worn faces
    var r:f32=1;
    for(bd.lumpN,bd.lumpA)|n,a|r+=a*@exp((m.dot(d,n)-1)*5);
    for(bd.cutN,bd.cutD)|n,c|{
      // how squarely the face meets this direction
      const k=m.dot(d,n);
      if(k<0.05)continue;
      r=smin(r,c/k,cutSoft);
    }
    return r;
  }
};
/// the smaller of `a` and `b`, the corner between them rounded over `k`
fn smin(a:f32,b:f32,k:f32)f32{
  // how far toward `a` the blend leans
  const h=m.clamp01(0.5+0.5*(b-a)/k);
  return m.lerp(b,a,h)-k*h*(1-h);
}
/// a weathered stone half sunk in the ground at `at`, radius `r`, `flat`
/// how tall it stands (a share of `r`): a smooth boulder, lumpy, ground
/// down to a few worn faces whose edges are rounded off, its foot buried;
/// `col` on its flanks paling to `lite` up its sky-turned faces, shaded as
/// stone (part `.stone`: grain, flecks, hollows, lichen)
pub fn stone(b:*mg.Builder,at:V3,r:f32,flat:f32,col:color.Rgba8,lite:color.Rgba8,rng:*Rng)Allocator.Error!void{
  // its shape: worn faces and lumps
  var bd:Boulder=undefined;
  for(&bd.cutN,&bd.cutD)|*n,*d|{
    n.*=m.norm(v3(rng.range(-1,1),rng.range(-0.25,1),rng.range(-1,1)));
    d.*=rng.range(0.66,0.86);
  }
  for(&bd.lumpN,&bd.lumpA)|*n,*a|{
    n.*=m.norm(v3(rng.range(-1,1),rng.range(-0.6,1),rng.range(-1,1)));
    a.*=rng.range(-0.1,0.16);
  }
  // how many rings and sides it keeps at this level of detail
  const rings=@max(4,@as(usize,boulderRings)>>@intCast(b.lod));
  const sides=b.around(boulderSides,7);
  // its centre (raised so a third of it lies buried) and its half sizes
  const centre=at+v3(0,r*flat*0.3,0);
  const half=v3(r,r*flat*0.75,r);
  // how far it is turned
  const turn=rng.range(0,m.tau);
  // each ring's points, from the buried foot (ring 0) up to the crown
  var pts:[boulderRings+1][boulderSides]V3=undefined;
  for(0..rings+1)|i|for(0..sides)|j|{
    // the way out from the centre: up from straight down, and round
    const th=m.ratio(i,rings)*m.pi;
    const ph=turn+m.ratio(j,sides)*m.tau;
    const d=v3(@sin(th)*@cos(ph),-@cos(th),@sin(th)*@sin(ph));
    pts[i][j]=centre+d*half*m.splat3(bd.reach(d));
  };
  // each point's normal: across its ring and up between its neighbours
  // (straight down and up at the foot and crown), turned outward
  var nrm:[boulderRings+1][boulderSides]V3=undefined;
  for(0..rings+1)|i|for(0..sides)|j|{
    // the points either side round the ring, and below and above
    const across=pts[i][(j+1)%sides]-pts[i][(j+sides-1)%sides];
    const up=pts[@min(i+1,rings)][j]-pts[if(i==0)0 else i-1][j];
    var n=if(i==0)v3(0,-1,0)else if(i==rings)v3(0,1,0)else m.norm(m.cross(across,up));
    if(m.dot(n,pts[i][j]-centre)<0)n=-n;
    nrm[i][j]=n;
  };
  for(0..rings)|i|for(0..sides)|j|{
    // the next side round
    const k=(j+1)%sides;
    // the band's quad, below then above (a triangle at the foot and crown)
    const q=[4]m.Vice(usize,2){.{i,j},.{i,k},.{i+1,k},.{i+1,j}};
    for([_]usize{0,2,1,0,3,2},0..)|c,o|{
      if(i==0 and o<3)continue;
      if(i+1==rings and o>=3)continue;
      // this corner
      const at2=q[c];
      const n=nrm[at2[0]][at2[1]];
      try b.put(pts[at2[0]][at2[1]],n,color.mix(col,lite,m.smooth(m.clamp01(n[1]*0.8+0.2))),0.4,0,.stone);
    }
  };
}
