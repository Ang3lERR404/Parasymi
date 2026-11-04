//! the drifting plants: tendrils and lanterns.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, splines, waves
const m=engine.core.math;
/// a seeded random stream: each drift sways and trails its own way
const Rng=engine.core.rng.Rng;
/// the species registry: a drift's genome, sizes and colours
const species=lib.species;
/// colour types, shades and mixing
const color=engine.core.color;
/// a point or direction in 3D
const V3=m.V3;
/// the mesh builder drifts are poured into
const Builder=lib.meshgen.Builder;
/// builds a closed bud on an offshoot
const bud=lib.meshgen.flowers.bud;
/// builds a closed ellipsoid: the spore in the float
const ellipsoid=lib.meshgen.ellipsoid;
/// a flower's filament colour
const filament=lib.meshgen.flowers.filament;
/// builds a small open bloom on an offshoot
const flower=lib.meshgen.flowers.flower;
/// bends control points the way a vine grows
const grow=lib.meshgen.grow;
/// the control points of a grown vine: the neck
const growthPath=lib.meshgen.growthPath;
/// grows a slender stalk off the neck
const offshoot=lib.meshgen.shoots.offshoot;
/// a smooth surface over a grid of points: the lantern's skin
const patch=lib.meshgen.patch;
/// builds one petal of the catcher dish
const petal=lib.meshgen.petals.petal;
/// how many offshoots a drift puts out
const shootCount=lib.meshgen.shoots.shootCount;
/// folds an offshoot's bloom in against its stem until growth reaches it
const shootFold=lib.meshgen.shoots.shootFold;
/// builds the stamens fanning over the dish
const stamens=lib.meshgen.petals.stamens;
/// a floater: nothing reaches the ground. A translucent sap float holds it
/// up; above it a short neck lifts a wide catcher dish open to the sky (it
/// drinks starlight); beneath it long filaments trail down toward the
/// ground, swaying most at their tips, so it hangs in the air rather than
/// standing on it. The origin is the float's centre.
pub fn drift(b:*Builder,g:species.Genome,seed:u64,variant:u32)Allocator.Error!void{
  // the stream the neck, filaments and their strays draw from
  var rng=Rng.init(seed);
  // the float's radius
  const floatR=g.bloomR*0.62;
  // the float: a comb-jelly lantern, a spore held inside it
  try lantern(b,g,floatR,seed);
  try ellipsoid(b,.{
    .center=m.v3(0,-floatR*0.05,0),.radii=m.v3(floatR*0.26,floatR*0.36,floatR*0.26),
    .col=color.rgb(1.0,0.92,0.62).toRgba8(255),.part=.stem,.rings=6,.segs=8,.t=0.95,
  });
  // the neck and the catcher dish: two whorls opening wide and shallow
  // where the neck ends, a little astray, and its control points
  const neck=m.v3(rng.range(-0.02,0.02),floatR*0.95+g.stemH,rng.range(-0.02,0.02));
  var nc:[4]V3=undefined;
  growthPath(.{.start=m.v3(0,floatR*0.75,0),.direction=m.norm(neck-m.v3(0,floatR*0.75,0)),.length=m.dist(neck,m.v3(0,floatR*0.75,0)),.wobble=g.wobble,.seed=seed^0x57E4},&nc);
  // the neck's smooth path, then per point when it forms and its radius
  var np:[8]V3=undefined;
  m.splineResample(&nc,&np);
  var nt:[8]f32=undefined;
  var nr:[8]f32=undefined;
  for(&nt,&nr,0..)|*t,*r,i|{
    // how far up the neck this point is (0..1)
    const k=m.ratio(i,7);
    t.*=m.lerp(0.55,0.9,k);
    r.*=g.stemR*m.lerp(1.3,0.8,k);
  }
  try b.tubeR(&np,&nt,&nr,g.stemCol.toRgba8(255),.stem,6);
  // how many petals stand in the dish's inner whorl
  const inner=@max(g.petals/2,3);
  for(0..g.petals+inner)|i|{
    // whether this petal is in the broad outer whorl
    const outer=i<g.petals;
    // its bearing round the neck's tip
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
  // its yield: beads of starlight gathered in the dish's heart, among
  // its stamens, over the cup of its inner whorl
  for(0..g.pods)|k|{
    // the way out to this bead, and where it rests
    const ang=lib.meshgen.pods.bearing(k,variant);
    const at=np[7]+m.v3(@cos(ang),0,@sin(ang))*m.splat3(g.bloomR*0.12)+m.v3(0,g.bloomR*0.22,0);
    try lib.meshgen.pods.bead(b,g,k,at,g.podR,0.9);
  }
  // offshoots: slender stalks leaning out of the neck beneath the dish,
  // each lifting a bud or a small bloom of its own to the sky
  // a separate stream for the offshoots, so they leave the rest unchanged
  var srng=Rng.init(seed^0x0FF5);
  // how many offshoots this drift puts out
  const shoots=shootCount(g,&srng);
  for(0..shoots)|i|{
    // how far up the neck it leaves, its bearing and its length
    const k=srng.range(0.05,0.45);
    const ang=m.ratio(i,@max(shoots,1))*m.tau+0.5+m.f(variant)*1.1+srng.range(-0.4,0.4);
    const len=g.bloomR*srng.range(1.0,1.5);
    // the offshoot's tip, where its bloom or bud sits
    const tip=try offshoot(b,&np,k,m.lerp(0.55,0.9,k),ang,len,g.stemR*0.6,srng.range(0.15,0.45),g.stemCol.toRgba8(255),.stem,seed+%i*211);
    // where the bloom's vertices begin, to fold them with the stalk
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
    // this filament's bearing round the mouth, a little astray
    const a=m.ratio(i,g.tendrils)*m.tau+rng.range(-0.25,0.25);
    // the way out it leans, level
    const out=m.v3(@cos(a),0,@sin(a));
    // where it leaves the lantern's mouth
    const from=out*m.splat3(floatR*0.22)+m.v3(0,-floatR*0.55,0);
    // every other one shorter, so they hang in two lengths
    const len=if(i%2==0)rng.range(0.75,1.05)else rng.range(0.45,0.7);
    // where its free tip hangs
    const to=from+out*m.splat3(rng.range(0.06,0.14))+m.v3(0,-len,0);
    // the way it falls, and the way across its waving plane
    const dir=m.norm(to-from);
    const across=m.norm(m.cross(dir,out));
    // how many waves run down it, and where in a wave it starts
    const waves=rng.range(2.2,3.4);
    const ph=rng.range(0,m.tau);
    // its control points, mouth to tip
    var fc:[14]V3=undefined;
    for(&fc,0..)|*c,j|{
      // how far down the filament this point is (0..1)
      const k=m.ratio(j,fc.len-1);
      // how far it swings here: still at the mouth, widening toward the tip
      const amp=tendrilWave*m.smooth(@min(1,k*3))*(0.5+0.5*k);
      // where in its wave this point is
      const w=k*waves*m.tau+ph;
      c.*=from+(to-from)*m.splat3(k)+out*m.splat3(@sin(w)*amp)+across*m.splat3(@sin(w*0.5+1.3)*amp*0.45);
    }
    grow(&fc,.{.start=from,.direction=dir,.length=m.dist(to,from),.wobble=g.tendrilWobble,.seed=seed+%i*31});
    // its smooth path, then per point when it forms and its radius
    var fp:[40]V3=undefined;
    m.splineResample(&fc,&fp);
    var ft:[40]f32=undefined;
    var fr:[40]f32=undefined;
    for(&ft,&fr,0..)|*t,*r,j|{
      // how far down the filament this point is (0..1)
      const k=m.ratio(j,fp.len-1);
      // tu.x rises toward the tips so they sway most, like a pendulum
      t.*=m.lerp(0.3,1,k);
      r.*=tendrilR*(1-k)*(0.4+0.6*(1-k));
    }
    try b.tubeR(&fp,&ft,&fr,g.leafCol.toRgba8(255),.tendril,4);
  }
}
/// a driftwisp filament's thickness at the mouth (its radius)
const tendrilR:f32=0.0075;
/// how far a driftwisp filament's waves swing out at their widest
const tendrilWave:f32=0.045;
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
fn lantern(b:*Builder,g:species.Genome,radius:f32,seed:u64)Allocator.Error!void{
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
    const film=color.rgb(0.5+0.5*@cos(m.tau*x),0.5+0.5*@cos(m.tau*(x+0.33)),0.5+0.5*@cos(m.tau*(x+0.67))).toRgba8(255);
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
fn lanternAt(radius:f32,s:f32,ph:f32)V3{
  // the height, held to the lantern (0..1)
  const k=m.clamp01(s);
  // the radius here: an egg, broadest low, ribbed by the combs
  // (the sine held off below zero: at the top it rounds a hair under, and
  // its power would be no number)
  const r=radius*m.pow(f32,@max(@sin(k*m.pi),0),0.7)*(1.08-0.22*k)*(1+lanternRib*lanternCrest(k,ph));
  return m.v3(@cos(ph)*r,radius*m.lerp(-0.85,1.0,k),@sin(ph)*r);
}
