//! the lumi lantern's sap lantern (a floater's comb-jelly body) and the
//! light split into colours along its comb rows; radiantKit.lumi gathers it.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, splines, waves
const m=engine.core.math;
/// the species registry: a drift's genome, sizes and colours
const species=lib.species;
/// colour types, shades and mixing
const color=engine.core.color;
/// a point or direction in 3D
const V3=m.V3;
/// the mesh builder drifts are poured into
const Builder=lib.meshgen.Builder;
/// a smooth surface over a grid of points: the lantern's skin
const patch=lib.meshgen.patch;
/// the lantern's comb rows: how many stand out of it, mouth to top
const lanternRows=8;
/// how far a comb row stands out of the skin, as a share of the radius
const lanternRib:f32=0.11;
/// how sharp a comb row's crest is (higher: a narrower ridge)
const lanternCrestCount:f32=4;
/// how far the comb rows turn round the lantern, mouth to top (turns)
const lanternTwist:f32=0.7;
/// a driftwisp's float: a comb-jelly lantern of sap, an egg a little taller
/// than wide, broadest below its middle, with eight comb rows standing out
/// of it from its mouth to its top, turning a little as they go. The rows
/// carry the light split into colours (pale rainbow along each one); the
/// skin between them is clear sap. One shared-vertex sheet closed at both
/// poles, so it is watertight.
pub fn lantern(b:*Builder,g:species.Genome,radius:f32,seed:u64)Allocator.Error!void{
  // the lantern's rows (mouth to top) and points round each row
  const rowCount=17;
  const colCount=49;
  // each point's position, normal, colour and tu.y
  var pts:[rowCount*colCount]V3=undefined;
  var nrms:[rowCount*colCount]V3=undefined;
  var cols:[rowCount*colCount]color.Rgba8=undefined;
  var us:[rowCount*colCount]f32=undefined;
  // the clear sap skin between the rows
  const skin=color.shade(g.bloomCol,0.8);
  // where on the rainbow this lantern's light begins
  const hue0=m.f(seed%97)/97;
  for(0..rowCount)|i|for(0..colCount)|j|{
    // how far up the lantern this row is (0..1)
    const s=m.ratio(i,rowCount-1);
    // this point's bearing round it
    const ph=m.ratio(j,colCount-1)*m.tau;
    // where this point sits in the grid
    const at=i*colCount+j;
    pts[at]=lanternAt(radius,s,ph);
    // the poles' normals point straight out of them; elsewhere, across the
    // sheet's two directions
    nrms[at]=if(i==0)m.v3(0,-1,0)else if(i==rowCount-1)m.v3(0,1,0)else n:{
      // a small step, to read the sheet's slope either side
      const e:f32=0.002;
      // the sheet's slope up and round, from either side
      const ds=lanternAt(radius,s+e,ph)-lanternAt(radius,s-e,ph);
      const dp=lanternAt(radius,s,ph+e)-lanternAt(radius,s,ph-e);
      break:n m.norm(m.cross(ds,dp));
    };
    // how much comb crest lies here
    const crest=lanternCrest(s,ph);
    // where on the rainbow this point's light lies
    const x=hue0+s*1.3+m.f(j)/colCount*0.5;
    // the split light along the comb row: a pale rainbow
    const film=splitLight(x);
    cols[at]=color.mix(skin,color.mix(film,color.rgb(1,1,1).toRgba8(255),0.35),crest*0.8);
    us[at]=0;
  };
  try patch(b,rowCount,colCount,&pts,&nrms,&cols,&us,0.5,.bloom);
}
/// how much of a comb row's crest lies at height `s` (0 mouth .. 1 top) and
/// bearing `ph`
fn lanternCrest(s:f32,ph:f32)f32{
  return m.pow(f32,@max(0.5+0.5*@cos(lanternRows*ph+lanternTwist*s*m.tau),0),lanternCrestCount);
}
/// a point on the lantern at height `s` (0 its mouth .. 1 its top) and bearing `ph`
pub fn lanternAt(radius:f32,s:f32,ph:f32)V3{
  // the height, held to the lantern (0..1)
  const k=m.clamp01(s);
  // the radius here: an egg, broadest low, ribbed by the combs
  // (the sine held off below zero: at the top it rounds a hair under, and
  // its power would be no number)
  const r=radius*m.pow(f32,@max(@sin(k*m.pi),0),0.7)*(1.08-0.22*k)*(1+lanternRib*lanternCrest(k,ph));
  return m.v3(@cos(ph)*r,radius*m.lerp(-0.85,1.0,k),@sin(ph)*r);
}
/// the light split into colours at `x` along the rainbow (one turn per
/// unit): a lantern's comb rows, whole or lifted off it as threads
pub fn splitLight(x:f32)color.Rgba8{
  return color.rgb(0.5+0.5*@cos(m.tau*x),0.5+0.5*@cos(m.tau*(x+0.33)),0.5+0.5*@cos(m.tau*(x+0.67))).toRgba8(255);
}
