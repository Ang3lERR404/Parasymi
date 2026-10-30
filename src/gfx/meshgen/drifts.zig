//! the drifting plants: tendrils and lanterns.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const Rng=engine.core.rng.Rng;
const species=lib.species;
const color=engine.core.color;
const V3=m.V3;
const Builder=lib.meshgen.Builder;
const bud=lib.meshgen.flowers.bud;
const ellipsoid=lib.meshgen.ellipsoid;
const filament=lib.meshgen.flowers.filament;
const flower=lib.meshgen.flowers.flower;
const grow=lib.meshgen.grow;
const growthPath=lib.meshgen.growthPath;
const offshoot=lib.meshgen.shoots.offshoot;
const patch=lib.meshgen.patch;
const petal=lib.meshgen.petals.petal;
const shootCount=lib.meshgen.shoots.shootCount;
const shootFold=lib.meshgen.shoots.shootFold;
const stamens=lib.meshgen.petals.stamens;
/// a floater: nothing reaches the ground. A translucent sap float holds it
/// up; above it a short neck lifts a wide catcher dish open to the sky (it
/// drinks starlight); beneath it long filaments trail down toward the
/// ground, swaying most at their tips, so it hangs in the air rather than
/// standing on it. The origin is the float's centre.
pub fn drift(b:*Builder,g:species.Genome,seed:u64,variant:u32)Allocator.Error!void{
  var rng=Rng.init(seed);
  const floatR=g.bloomR*0.62;
  // the float: a comb-jelly lantern, a spore held inside it
  try lantern(b,g,floatR,seed);
  try ellipsoid(b,.{
    .center=m.v3(0,-floatR*0.05,0),.radii=m.v3(floatR*0.26,floatR*0.36,floatR*0.26),
    .col=color.rgb(1.0,0.92,0.62).toRgba8(255),.part=.stem,.rings=6,.segs=8,.t=0.95,
  });
  // the neck and the catcher dish: two whorls opening wide and shallow
  const neck=m.v3(rng.range(-0.02,0.02),floatR*0.95+g.stemH,rng.range(-0.02,0.02));
  var nc:[4]V3=undefined;
  growthPath(.{.start=m.v3(0,floatR*0.75,0),.direction=m.norm(neck-m.v3(0,floatR*0.75,0)),.length=m.len(neck-m.v3(0,floatR*0.75,0)),.wobble=g.wobble,.seed=seed^0x57E4},&nc);
  var np:[8]V3=undefined;
  m.splineResample(&nc,&np);
  var nt:[8]f32=undefined;
  var nr:[8]f32=undefined;
  for(&nt,&nr,0..)|*t,*r,i|{
    const k=m.ratio(i,7);
    t.*=m.lerp(0.55,0.9,k);
    r.*=g.stemR*m.lerp(1.3,0.8,k);
  }
  try b.tubeR(&np,&nt,&nr,g.stemCol.toRgba8(255),.stem,6);
  const inner=@max(g.petals/2,3);
  for(0..g.petals+inner)|i|{
    const outer=i<g.petals;
    const ang=if(outer)m.ratio(i,g.petals)*m.tau+m.f(variant)else(m.f(i-g.petals)+0.5)/m.f(inner)*m.tau;
    try petal(b,.{
      .base=np[7],.out=m.v3(@cos(ang),0,@sin(ang)),
      .len=g.bloomR*(if(outer)@as(f32,1)else 0.6),
      .width=g.bloomR*(if(outer)@as(f32,0.5)else 0.42),
      .rise=if(outer)0.55 else 1.0,.flare=if(outer)0.35 else 0.4,.cup=0.45,
      .col=color.shade(g.bloomCol,0.8),.tip=g.bloomCol.toRgba8(255),
    });
  }
  // stamens fanning out over the dish
  try stamens(b,.{
    .heart=np[7],.axis=m.norm(np[7]-np[5]),.n=@max(g.petals/2+2,5),
    .len=g.bloomR*0.45,.r=g.bloomR*0.022,.anther=g.bloomR*0.11,
    .lean=0.45,.arch=0.5,.col=filament(g),.t=0.9,.spin=m.f(variant),.seed=seed,
  });
  // offshoots: slender stalks leaning out of the neck beneath the dish,
  // each lifting a bud or a small bloom of its own to the sky
  var srng=Rng.init(seed^0x0FF5);
  const shoots=shootCount(g,&srng);
  for(0..shoots)|i|{
    const k=srng.range(0.05,0.45);
    const ang=m.ratio(i,@max(shoots,1))*m.tau+0.5+m.f(variant)*1.1+srng.range(-0.4,0.4);
    const len=g.bloomR*srng.range(1.0,1.5);
    const tip=try offshoot(b,&np,k,m.lerp(0.55,0.9,k),ang,len,g.stemR*0.6,srng.range(0.15,0.45),g.stemCol.toRgba8(255),.stem,seed+%i*211);
    const s=b.mark();
    if(srng.float()<0.5)
      try flower(b,g,tip.at,tip.axis,srng.range(0.35,0.45),m.f(i)*2.1,tip.t1,.skin)
    else
      try bud(b,g,tip.at,tip.axis,srng.range(0.4,0.55),m.f(i)*1.3,tip.t1);
    shootFold(b,s,1);
  }
  // trailing filaments out of the lantern's mouth: hair-thin threads, each
  // waving in its own plane (and a little across it), the waves widening
  // toward the free tip, which tapers to nothing. plant.vert runs a slow
  // wave down them as well, so they ripple like a jelly's.
  for(0..g.tendrils)|i|{
    const a=m.ratio(i,g.tendrils)*m.tau+rng.range(-0.25,0.25);
    const out=m.v3(@cos(a),0,@sin(a));
    const from=out*m.splat3(floatR*0.22)+m.v3(0,-floatR*0.55,0);
    // every other one shorter, so they hang in two lengths
    const len=if(i%2==0)rng.range(0.75,1.05)else rng.range(0.45,0.7);
    const to=from+out*m.splat3(rng.range(0.06,0.14))+m.v3(0,-len,0);
    const dir=m.norm(to-from);
    const across=m.norm(m.cross(dir,out));
    const waves=rng.range(2.2,3.4);
    const ph=rng.range(0,m.tau);
    var fc:[14]V3=undefined;
    for(&fc,0..)|*c,j|{
      const k=m.ratio(j,fc.len-1);
      const amp=tendrilWave*m.smooth(@min(1,k*3))*(0.5+0.5*k);
      const w=k*waves*m.tau+ph;
      c.*=from+(to-from)*m.splat3(k)+out*m.splat3(@sin(w)*amp)+across*m.splat3(@sin(w*0.5+1.3)*amp*0.45);
    }
    grow(&fc,.{.start=from,.direction=dir,.length=m.len(to-from),.wobble=g.tendrilWobble,.seed=seed+%i*31});
    var fp:[40]V3=undefined;
    m.splineResample(&fc,&fp);
    var ft:[40]f32=undefined;
    var fr:[40]f32=undefined;
    for(&ft,&fr,0..)|*t,*r,j|{
      const k=m.ratio(j,fp.len-1);
      // tu.x rises toward the tips so they sway most, like a pendulum
      t.*=m.lerp(0.3,1,k);
      r.*=tendrilR*(1-k)*(0.4+0.6*(1-k));
    }
    try b.tubeR(&fp,&ft,&fr,g.leafCol.toRgba8(255),.tendril,4);
  }
}
/// a driftwisp filament's thickness at the mouth, and how far its waves swing
const tendrilR:f32=0.0075;
const tendrilWave:f32=0.045;
/// the lantern: comb rows standing out of it, how sharp their crests, and
/// how far they turn round it from mouth to top
const lanternRows=8;
const lanternRib:f32=0.11;
const lanternCrestCount:f32=4;
const lanternTwist:f32=0.7;
/// a driftwisp's float: a comb-jelly lantern of sap, an egg a little taller
/// than wide, broadest below its middle, with eight comb rows standing out
/// of it from its mouth to its top, turning a little as they go. The rows
/// carry the light split into colours (pale rainbow along each one); the
/// skin between them is clear sap. One shared-vertex sheet closed at both
/// poles, so it is watertight.
fn lantern(b:*Builder,g:species.Genome,radius:f32,seed:u64)Allocator.Error!void{
  const rowCount=17;
  const colCount=49;
  var pts:[rowCount*colCount]V3=undefined;
  var nrms:[rowCount*colCount]V3=undefined;
  var cols:[rowCount*colCount]color.Rgba8=undefined;
  var us:[rowCount*colCount]f32=undefined;
  const skin=color.shade(g.bloomCol,0.8);
  const hue0=m.f(seed%97)/97;
  for(0..rowCount)|i|for(0..colCount)|j|{
    const s=m.ratio(i,rowCount-1);
    const ph=m.ratio(j,colCount-1)*m.tau;
    const at=i*colCount+j;
    pts[at]=lanternAt(radius,s,ph);
    // the poles' normals point straight out of them; elsewhere, across the
    // sheet's two directions
    nrms[at]=if(i==0)m.v3(0,-1,0)else if(i==rowCount-1)m.v3(0,1,0)else n:{
      const e:f32=0.002;
      const ds=lanternAt(radius,s+e,ph)-lanternAt(radius,s-e,ph);
      const dp=lanternAt(radius,s,ph+e)-lanternAt(radius,s,ph-e);
      break:n m.norm(m.cross(ds,dp));
    };
    const crest=lanternCrest(s,ph);
    const x=hue0+s*1.3+m.f(j)/colCount*0.5;
    const film=color.rgb(0.5+0.5*@cos(m.tau*x),0.5+0.5*@cos(m.tau*(x+0.33)),0.5+0.5*@cos(m.tau*(x+0.67))).toRgba8(255);
    cols[at]=color.mix(skin,color.mix(film,color.rgb(1,1,1).toRgba8(255),0.35),crest*0.8);
    us[at]=0;
  };
  try patch(b,rowCount,colCount,&pts,&nrms,&cols,&us,0.5,.bloom);
}
/// how much of a comb row's crest lies at height `s` (0 mouth .. 1 top) and
/// bearing `ph`
fn lanternCrest(s:f32,ph:f32)f32{
  return m.pow(f32,0.5+0.5*@cos(lanternRows*ph+lanternTwist*s*m.tau),lanternCrestCount);
}
/// a point on the lantern at height `s` (0 its mouth .. 1 its top) and bearing `ph`
fn lanternAt(radius:f32,s:f32,ph:f32)V3{
  const k=m.clamp01(s);
  const r=radius*m.pow(f32,@sin(k*m.pi),0.7)*(1.08-0.22*k)*(1+lanternRib*lanternCrest(k,ph));
  return m.v3(@cos(ph)*r,radius*m.lerp(-0.85,1.0,k),@sin(ph)*r);
}
