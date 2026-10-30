//! blades: a bent strip with a body, its vein on the cupped face.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const vertex=lib.vertex;
const color=engine.core.color;
const V3=m.V3;
const bladeSegs=lib.meshgen.bladeSegs;
const Builder=lib.meshgen.Builder;
const laminaThick=lib.meshgen.laminae.laminaThick;
const lamina=lib.meshgen.laminae.lamina;
/// curved blade (leaf/petal). `dir` horizontal outward, droops along its length.
pub fn blade(b:*Builder,base:V3,dir:V3,len:f32,width:f32,droop:f32,col:color.Rgba8,tip:color.Rgba8,t:f32,part:vertex.Part)Allocator.Error!void{
  var cs:[bladeSegs+1]V3=undefined;
  bladeSpine(&cs,base,dir,len,droop);
  try sheet(b,&cs,m.norm(m.cross(dir,m.v3(0,1,0))),width,col,tip,t,part);
}
/// a blade whose midrib follows the smooth spline through `path`, its
/// width lying along `side`.
pub fn bladeAlong(b:*Builder,path:[]const V3,side:V3,width:f32,col:color.Rgba8,tip:color.Rgba8,t:f32,part:vertex.Part)Allocator.Error!void{
  var cs:[bladeSegs+1]V3=undefined;
  m.splineResample(path,&cs);
  try sheet(b,&cs,side,width,col,tip,t,part);
}
/// the leaf along a midrib: a `lamina` (thin, bevelled at its edges,
/// a vein along its middle) with one row per point of `cs`.
fn sheet(b:*Builder,cs:*const[bladeSegs+1]V3,side:V3,width:f32,col:color.Rgba8,tip:color.Rgba8,t:f32,part:vertex.Part)Allocator.Error!void{
  const segs=bladeSegs;
  var ws:[segs+1]f32=undefined;
  for(0..segs+1)|i|{
    const k=m.f(i)/segs;
    ws[i]=width*@sin(k*m.pi)*(1-0.3*k);
  }
  var ns:[segs+1]V3=undefined;
  for(0..segs+1)|i|{
    const tan=cs[@min(i+1,segs)]-cs[if(i==0)0 else i-1];
    ns[i]=m.norm(m.cross(tan,side));
  }
  // folded along its midrib (its halves dipping to it, so it never reads
  // as a flat card), the vein running in the fold and fading to the tip
  var spine:[segs+1]V3=undefined;
  var sides:[segs+1]V3=undefined;
  var face:[segs+1]V3=undefined;
  var dish:[segs+1]f32=undefined;
  var vein:[segs+1]f32=undefined;
  var cols:[segs+1]color.Rgba8=undefined;
  for(0..segs+1)|i|{
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
    const k=m.ratio(i,bladeSegs);
    c.*=base+dir*m.splat3(len*k)+m.v3(0,len*(0.35*k-droop*k*k),0);
  }
}
