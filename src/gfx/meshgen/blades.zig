//! blades: a bent strip with a body, its vein on the cupped face.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, splines, easing
const m=engine.core.math;
/// the garden's part roles
const vertex=lib.vertex;
/// colour types and mixing, for the base-to-tip fade
const color=engine.core.color;
/// a point or direction in 3D
const V3=m.V3;
/// the seeded stream a natural leaf is varied by
const Rng=engine.core.rng.Rng;
/// how many segments a blade's midrib is cut into
const bladeSegs=lib.meshgen.bladeSegs;
/// the mesh builder blades are poured into
const Builder=lib.meshgen.Builder;
/// half a lamina's thickness, as a share of its broadest half-width
const laminaThick=lib.meshgen.laminae.laminaThick;
/// builds a leaf or petal with a body (laminae.zig)
const lamina=lib.meshgen.laminae.lamina;
/// how a branch flares into the stem it leaves (a leaf's stalk into its stem)
const collar=lib.meshgen.collar;
/// makes a vector from three numbers
const v3=m.v3;
/// how many rows a leaf's blade is cut into, base to tip (a lamina's most)
const leafRows=16;
/// curved blade (leaf/petal). `dir` horizontal outward, droops along its length.
pub fn blade(b:*Builder,base:V3,dir:V3,len:f32,width:f32,droop:f32,col:color.Rgba8,tip:color.Rgba8,t:f32,part:vertex.Part)Allocator.Error!void{
  // the midrib's points, base to tip
  var cs:[bladeSegs+1]V3=undefined;
  bladeSpine(&cs,base,dir,len,droop);
  try sheet(b,&cs,m.norm(m.cross(dir,m.v3(0,1,0))),width,col,tip,t,part);
}
/// a blade whose midrib follows the smooth spline through `path`, its
/// width lying along `side`.
pub fn bladeAlong(b:*Builder,path:[]const V3,side:V3,width:f32,col:color.Rgba8,tip:color.Rgba8,t:f32,part:vertex.Part)Allocator.Error!void{
  // the midrib's points, resampled evenly from the path
  var cs:[bladeSegs+1]V3=undefined;
  m.splineResample(path,&cs);
  try sheet(b,&cs,side,width,col,tip,t,part);
}
/// the leaf along a midrib: a `lamina` (thin, bevelled at its edges,
/// a vein along its middle) with one row per point of `cs`.
fn sheet(b:*Builder,cs:*const[bladeSegs+1]V3,side:V3,width:f32,col:color.Rgba8,tip:color.Rgba8,t:f32,part:vertex.Part)Allocator.Error!void{
  // how many segments the blade has, base to tip
  const segs=bladeSegs;
  // the blade's half-width at each row: swelling from base, narrowing to the tip
  var ws:[segs+1]f32=undefined;
  for(0..segs+1)|i|{
    // how far along the blade this row is (0 base .. 1 tip)
    const k=m.f(i)/segs;
    ws[i]=width*@sin(k*m.pi)*(1-0.3*k);
  }
  // which way each row faces: across the midrib and the side
  var ns:[segs+1]V3=undefined;
  for(0..segs+1)|i|{
    // the midrib's direction at this row, from its neighbours
    const tan=cs[@min(i+1,segs)]-cs[if(i==0)0 else i-1];
    ns[i]=m.norm(m.cross(tan,side));
  }
  // folded along its midrib (its halves dipping to it, so it never reads
  // as a flat card), the vein running in the fold and fading to the tip
  // each row's spine (lifted off the midrib), its side, the face it cups to,
  // how far its edges dip, its vein's height and its colour
  var spine:[segs+1]V3=undefined;
  var sides:[segs+1]V3=undefined;
  var face:[segs+1]V3=undefined;
  var dish:[segs+1]f32=undefined;
  var vein:[segs+1]f32=undefined;
  var cols:[segs+1]color.Rgba8=undefined;
  for(0..segs+1)|i|{
    // how far along the blade this row is (0..1)
    const k=m.f(i)/segs;
    spine[i]=cs[i]+ns[i]*m.splat3(ws[i]*0.25);
    sides[i]=side;
    face[i]=-ns[i];
    dish[i]=ws[i]*0.25;
    vein[i]=laminaThick*width*0.8*(1-0.7*k);
    cols[i]=color.mix(col,tip,k);
  }
  try lamina(b,.{.spine=&spine,.side=&sides,.face=&face,.width=&ws,.dish=&dish,.bow=1,.broad=width,.vein=&vein,.col=&cols,.t=t,.part=part});
}
/// the midrib of a drooping blade: out along `dir`, curving by `droop`.
pub fn bladeSpine(cs:*[bladeSegs+1]V3,base:V3,dir:V3,len:f32,droop:f32)void{
  for(cs,0..)|*c,i|{
    // how far along the blade this point is (0..1)
    const k=m.ratio(i,bladeSegs);
    c.*=base+dir*m.splat3(len*k)+m.v3(0,len*(0.35*k-droop*k*k),0);
  }
}
/// how a leaf is shaped: where it leaves its stem, the way it reaches, how
/// long and broad, how it droops, twists, ripples and curls, its teeth and
/// its stalk, its colours and when it grows
pub const Leaf=struct{
  /// where its stalk leaves the stem
  at:V3,
  /// the way it reaches out (roughly level)
  dir:V3,
  /// its blade's length
  len:f32,
  /// its blade's broadest half-width
  width:f32,
  /// how far it droops toward its tip
  droop:f32=0.35,
  /// how far its tip curls down past the droop
  curl:f32=0,
  /// how far its blade twists about its midrib, base to tip (radians)
  twist:f32=0,
  /// how much its edges ripple, as a share of its width
  wave:f32=0,
  /// how many teeth along each edge (0: a smooth edge)
  teeth:f32=0,
  /// how long its stalk is, as a share of its blade
  stalk:f32=0,
  /// how narrow its blade is drawn in (1: broad .. small: folded shut)
  open:f32=1,
  /// its colour at the base, and at the tip
  col:color.Rgba8,
  /// (at the tip)
  tip:color.Rgba8,
  /// its stalk's colour
  stalkCol:color.Rgba8,
  /// how far along the plant's growth it forms (tu.x)
  t:f32,
};
/// one leaf: its stalk (a tapering tube flaring into the stem), then its
/// blade, a lamina along a drooping, curling midrib, twisting as it goes,
/// its outline ovate with teeth cut along it and its edges rippling
pub fn leaf(b:*Builder,l:Leaf)Allocator.Error!void{
  // the flat way out, and the side its blade's width first lies along
  const out=m.norm(v3(l.dir[0],0,l.dir[2]));
  const side0=m.norm(m.cross(out,v3(0,1,0)));
  // the stalk: from the stem out and up a little to where the blade begins
  var base=l.at;
  if(l.stalk>0){
    const sl=l.len*l.stalk;
    var sp:[5]V3=undefined;
    var st:[5]f32=undefined;
    var sr:[5]f32=undefined;
    for(&sp,&st,&sr,0..)|*p,*t,*r,i|{
      // how far along the stalk, 0..1
      const s=m.ratio(i,4);
      p.*=l.at+out*m.splat3(sl*s)+v3(0,sl*(0.45*s-0.15*s*s),0);
      t.*=l.t;
      r.*=l.width*0.07*m.lerp(1,0.6,s)*collar(s);
    }
    try b.tubeR(&sp,&st,&sr,l.stalkCol,.stem,5);
    base=sp[4];
  }
  // the midrib: out along `dir`, drooping, its tip curling down
  var cs:[leafRows]V3=undefined;
  for(&cs,0..)|*c,i|{
    // how far along the blade, 0..1
    const k=m.ratio(i,leafRows-1);
    c.*=base+l.dir*m.splat3(l.len*k)+v3(0,l.len*(0.35*k-l.droop*k*k-l.curl*k*k*k*k),0);
  }
  // each row's half-width, the way it lies, the face it cups to, its rise,
  // the vein's height and its colour
  var ws:[leafRows]f32=undefined;
  var sides:[leafRows]V3=undefined;
  var face:[leafRows]V3=undefined;
  var spine:[leafRows]V3=undefined;
  var dish:[leafRows]f32=undefined;
  var vein:[leafRows]f32=undefined;
  var cols:[leafRows]color.Rgba8=undefined;
  for(0..leafRows)|i|{
    // how far along the blade, 0..1
    const k=m.ratio(i,leafRows-1);
    // ovate: broadest a third of the way out, drawn to a point; teeth cut
    // back between their points, fading at the base and tip
    var w=l.width*@sin(k*m.pi)*(1-0.3*k)*l.open;
    if(l.teeth>0){
      const saw=@mod(k*l.teeth,1);
      w*=1-0.22*saw*@sin(k*m.pi);
    }
    ws[i]=w;
    // the midrib's way here, and the side turned by the twist so far
    const tan=m.norm(cs[@min(i+1,leafRows-1)]-cs[if(i==0)0 else i-1]);
    const a=l.twist*k;
    const side=m.norm(side0*m.splat3(@cos(a))+m.cross(tan,side0)*m.splat3(@sin(a)));
    const n=m.norm(m.cross(tan,side));
    sides[i]=side;
    face[i]=-n;
    spine[i]=cs[i]+n*m.splat3(w*0.25);
    dish[i]=w*(0.25+l.wave*@sin(k*m.tau*2.5));
    vein[i]=laminaThick*l.width*0.8*(1-0.7*k);
    cols[i]=color.mix(l.col,l.tip,k);
  }
  try lamina(b,.{.spine=&spine,.side=&sides,.face=&face,.width=&ws,.dish=&dish,.bow=1,.broad=l.width,.vein=&vein,.col=&cols,.t=l.t,.part=.leaf});
}
/// whether a leaf grows on a stalk of its own (a simple leaf) or sits on
/// its rachis (a leaflet of a compound leaf, a fern's pinna)
pub const Stalk=enum{
  /// on a stalk of its own
  stalked,
  /// sitting straight on what bears it
  sessile,
};
/// how many teeth a small leaf's edge holds each side, at least and at most
const naturalTeeth=[2]f32{4,6};
/// a natural leaf in place of a plain blade (same reach, size, droop,
/// colours and growth): its own twist, ripple, tip curl and teeth drawn
/// from where it grows, so no two leaves are alike, on its own stalk or not
pub fn natural(b:*Builder,base:V3,dir:V3,len:f32,width:f32,droop:f32,col:color.Rgba8,tip:color.Rgba8,t:f32,stalk:Stalk)Allocator.Error!void{
  // the leaf's own stream, seeded by where it grows
  const h:u32=@bitCast(base[0]*7919.3+base[1]*1047.29+base[2]*12997.09+len*511.7);
  var rng=Rng.init(@as(u64,h)*%0x9E3779B97F4A7C15+%1);
  try leaf(b,.{
    .at=base,.dir=dir,.len=len*rng.range(0.85,1.15),.width=width*rng.range(0.85,1.12),.droop=droop*rng.range(0.75,1.3),
    .curl=rng.range(0,0.2),.twist=rng.range(-0.55,0.55),.wave=rng.range(0.05,0.16),.teeth=rng.range(naturalTeeth[0],naturalTeeth[1]),
    .stalk=switch(stalk){.stalked=>rng.range(0.2,0.35),.sessile=>0},
    .col=col,.tip=tip,.stalkCol=col,.t=t,
  });
}
