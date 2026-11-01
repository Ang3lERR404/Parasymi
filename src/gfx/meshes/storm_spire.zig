//! mesh: the storm spire (structures/storm_spire.zig), a kin of the
//! weftstone (convergence kit) that charges the air and strikes the rain
//! clouds into storms. A woven spire on a rooted foot, a chamber of both
//! saps caged at its crown, rings of vanes fanned round it (each two pale
//! ribs and a bar strung with fine green threads, as the weftstone's), five
//! short offshoots out of it, and from the tip of each a fine thread rising
//! to a lantern (woven strands round a small glowing sac) floating up where
//! the rain cloud gathers. The gardener chose this look of three (the
//! others' kites, round sacs and diamonds of membrane, are still `Kite`s
//! here). Grown along one skeleton: foot and spire, the vane rings fanning
//! out as the front passes them, the offshoots, the threads rising and the
//! lanterns last. `bolt` is a bolt of its lightning.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors and lerps
const m=engine.core.math;
/// the garden's meshgen: builder, laminae, ellipsoids
const mg=lib.meshgen;
/// colour types
const color=engine.core.color;
/// growth splines: the skeleton the spire grows along
const growth=lib.growth;
/// the parasite kit: the woven stalk's shape, nodules
const pk=lib.parasiteKit;
/// the convergence kit: its foot, weave, sac and colours
const kit=lib.convergenceKit;
/// a point or direction in 3D
const V3=m.V3;
/// builds a point or direction
const v3=m.v3;
/// what a kite is
const Kite=enum{
  /// a round sac of both saps, see-through
  sac,
  /// a diamond of see-through membrane stretched on a cross of spars
  diamond,
  /// a lantern: woven strands round a small glowing sac
  lantern,
};
/// one look: its spire, its vane rings, its offshoots and their kites
const Look=struct{
  /// how tall the spire stands (m)
  tall:f32,
  /// its woven stalk's shape
  stalk:pk.Stalk,
  /// how far up the spire each vane ring fans out (shares of it)
  rings:[]const f32,
  /// how far a vane reaches out, at the lowest ring (higher rings smaller)
  reach:f32,
  /// half a vane's spread round the ring (radians)
  half:f32,
  /// vanes in each ring
  vanes:usize,
  /// how far up the spire the offshoots leave it (shares of it)
  shoots:[]const f32,
  /// how far an offshoot reaches
  shootLen:f32,
  /// how high the kites float (m), the lowest and the highest
  kiteH:m.Vice(f32,2),
  /// how big a kite is
  kiteR:f32,
  /// what its kites are
  kite:Kite,
  /// a caged chamber at its crown (as the weftstone's)
  chamber:bool=false,
  /// its own seed
  seed:u64,
};
/// threads strung across each vane
const threads=4;
/// how far a vane rises toward its edge, and how far it is pitched (as the weftstone's)
const vaneRise:f32=0.05;
/// (how far pitched)
const vanePitch:f32=0.03;
/// the thread's colour: lilac, the charge running up it
const threadCol=kit.lilac;
/// a diamond kite's membrane: both saps thinned to a pale violet, see-through
const membrane=color.rgb(0.8,0.7,1.0).toRgba8(150);
/// the storm spire's look (the gardener's pick of three: the caged one,
/// lantern kites): a woven chamber at its crown, three vane rings, five
/// offshoots, their lanterns floating where the rain cloud gathers
pub const look:Look=.{
  .tall=2.0,.stalk=.{.girth=0.08,.part=2.2,.from=0.2,.to=0.85},
  .rings=&.{0.38,0.56,0.72},.reach=0.55,.half=0.3,.vanes=kit.fold,
  .shoots=&.{0.22,0.32,0.42,0.52,0.62},.shootLen=0.3,.kiteH=.{4.4,5.0},.kiteR=0.1,.kite=.lantern,.chamber=true,.seed=0x5703,
};
/// builds the storm spire whole
pub fn build(b:*mg.Builder)Allocator.Error!void{try spire(b,look);}
/// its crown's knot (structures/storm_spire.zig: where a strike leaves it)
pub fn topAt()V3{return v3(0.03,look.tall,-0.02);}
/// the spire's spline as the skeleton lays it: control points resampled
fn trunkPts()[growth.res]V3{
  // the top, the control points, and their resampled points
  const top=topAt();
  const c=[_]V3{v3(0,-0.1,0),v3(0,0.3,0),v3(top[0]*0.3,look.tall*0.4,top[2]*0.3),v3(top[0]*0.7,look.tall*0.75,top[2]*0.7),top};
  var pts:[growth.res]V3=undefined;
  m.splineResample(&c,&pts);
  return pts;
}
/// offshoot `i`'s bearing round the spire
fn shootBearing(i:usize)f32{return m.f(i)*2.39996+0.7;}
/// the tip of offshoot `i`, where its thread leaves
pub fn tipAt(i:usize)V3{
  // the way out, and where it leaves the spire
  const out=v3(@cos(shootBearing(i)),0,@sin(shootBearing(i)));
  const pts=trunkPts();
  const from=m.alongPath(&pts,look.shoots[i]);
  return from+out*m.splat3(look.shootLen)+v3(0,look.shootLen*0.45,0);
}
/// where kite `i` floats, its thread's end under it
pub fn kiteAt(i:usize)V3{
  // the offshoot's tip, the way out, and how high this kite floats
  const tip=tipAt(i);
  const out=v3(@cos(shootBearing(i)),0,@sin(shootBearing(i)));
  const h=m.lerp(look.kiteH[0],look.kiteH[1],m.ratio(i,@max(look.shoots.len,2)-1));
  return v3(tip[0]+out[0]*look.tall*0.25,h,tip[2]+out[2]*look.tall*0.25);
}
/// how many offshoots fly kites
pub const kites=look.shoots.len;
/// a storm spire of look `l`, its foot at the origin
fn spire(b:*mg.Builder,l:Look)Allocator.Error!void{
  // the skeleton every part is timed along
  var k=growth.Skeleton.begin(b);
  // the spire: up out of the soil, leaning a little, to its top
  const top=v3(0.03,l.tall,-0.02);
  const c=[_]V3{v3(0,-0.1,0),v3(0,0.3,0),v3(top[0]*0.3,l.tall*0.4,top[2]*0.3),v3(top[0]*0.7,l.tall*0.75,top[2]*0.7),top};
  const trunk=k.trunk(&c,.{.pace=1.3});
  var sp:[growth.res]V3=undefined;
  var sec:[growth.res]pk.Section=undefined;
  try kit.weaveOn(b,&k,trunk,l.stalk,.{.seed=l.seed},0,0.5,&sp,&sec);
  try kit.footOn(b,&k,trunk,.{.r=l.stalk.girth*1.8,.reach=l.tall*0.35,.rootR=l.stalk.girth*0.3,.seed=l.seed^0xF007});
  // a knot of pale skin crowning it
  const crown=b.mark();
  try pk.nodule(b,top,v3(l.stalk.girth*0.6,l.stalk.girth*0.5,l.stalk.girth*0.6),0.6,kit.pale,kit.lilac,kit.pearl);
  try k.on(b,crown,trunk,1,.{.from=top});
  if(l.chamber)try chamber(b,&k,trunk,top);
  // the vane rings, smaller the higher, each turned off the one under
  for(l.rings,0..)|u,r|{
    // how much smaller this ring is than the lowest
    const shrink=m.lerp(1,0.6,m.ratio(r,@max(l.rings.len,2)-1));
    try ring(b,&k,trunk,u,l.reach*shrink,l.half,l.vanes,0.2+m.f(r)*0.6);
  }
  // the offshoots, each flying a kite on its thread
  for(l.shoots,0..)|u,i|{
    // its bearing, the way out, and where it leaves the spire
    const a=shootBearing(i);
    const out=v3(@cos(a),0,@sin(a));
    const from=k.point(trunk,u);
    // the offshoot: out and up a little, ending in a knot
    const tip=from+out*m.splat3(l.shootLen)+v3(0,l.shootLen*0.45,0);
    const sh=k.branch(trunk,u,&.{from,from+out*m.splat3(l.shootLen*0.5)+v3(0,l.shootLen*0.05,0),tip},.{.after=.passing,.delay=0.1});
    try k.braid(b,sh,.{.girth=l.stalk.girth*0.35,.tip=0.6,.strands=3,.twist=2,.wobble=0.15,.seed=l.seed+%i*31,.core=kit.pale,.strand=kit.green,.t0=0.5,.t1=0.7});
    const knot=b.mark();
    try pk.nodule(b,tip,m.splat3(l.stalk.girth*0.32),0.7,kit.pale,kit.lilac,kit.pearl);
    try k.on(b,knot,sh,1,.{.from=tip});
    // (its thread and lantern fly free of it: `thread`, `lantern`, flown
    // by structures/storm_spire.zig)
  }
  k.finish(b);
}
/// a ring of `n` vanes fanned out of the spire at `u` along it, each `reach`
/// long, spread `half` either way, turned `turn` round: two pale ribs out
/// from the spire, sweeping up toward their edge, a bar across their ends,
/// fine green threads strung rib to rib (as the weftstone's vanes)
fn ring(b:*mg.Builder,k:*growth.Skeleton,trunk:growth.Id,u:f32,reach:f32,half:f32,n:usize,turn:f32)Allocator.Error!void{
  // where it fans out
  const at=k.point(trunk,u);
  for(0..n)|i|{
    // this vane's bearing, and its ribs, leading and trailing
    const a=turn+m.ratio(i,n)*m.tau;
    var ribs:[2]growth.Id=undefined;
    for(&ribs,[_]f32{-1,1})|*rb,s|{
      // the rib's guide points: low and level out of the spire, sweeping up at its edge
      var c:[6]V3=undefined;
      for(&c,0..)|*q,j|{
        // how far out the rib, its bearing narrowing in toward the spire
        const w=m.ratio(j,5);
        const ba=a+s*half*m.smooth(@min(1,w*1.6));
        const y=vaneRise*reach/0.3*w*w+(if(s<0)vanePitch*w else -vanePitch*0.5*w);
        q.*=at+v3(@cos(ba)*reach*w,y,@sin(ba)*reach*w);
      }
      rb.*=k.branch(trunk,u,&c,.{.after=.passing,.delay=0.03*m.f(i)});
      try k.tube(b,rb.*,.{.r0=0.007,.tip=0.6,.col=kit.pale,.sides=5,.t0=0.5,.t1=0.9});
    }
    // the bar across its edge, bowing out, grown out of the leading rib's
    // end (a piece, not a spline: a skeleton holds only `growth.max`)
    const e0=k.point(ribs[0],1);
    const e1=k.point(ribs[1],1);
    const mid=m.lerpV(e0,e1,0.5);
    const bow=m.norm(v3(mid[0]-at[0],0,mid[2]-at[2]))*m.splat3(reach*0.1);
    const bc=[_]V3{e0,m.lerpV(e0,e1,0.25)+bow*m.splat3(0.8),mid+bow,m.lerpV(e0,e1,0.75)+bow*m.splat3(0.8),e1};
    var bp:[12]V3=undefined;
    m.splineResample(&bc,&bp);
    const barMk=b.mark();
    try kit.taper(b,&bp,0.0058,0.9,0.9,0.95,kit.pale,.stem,5);
    for([_]V3{e0,e1})|e|try pk.nodule(b,e,m.splat3(0.009),0.95,kit.pearl,kit.lilac,kit.pearl);
    try k.on(b,barMk,ribs[0],1,.{.from=e0});
    // the threads strung across, rib to rib, sagging a little
    for(0..threads)|j|{
      // how far out it is strung, and its ends
      const w=m.lerp(0.25,0.95,m.ratio(j,threads-1));
      const p0=k.point(ribs[0],w);
      const p1=k.point(ribs[1],w);
      const c:[3]V3=.{p0,m.lerpV(p0,p1,0.5)-v3(0,0.006*w,0),p1};
      var p:[8]V3=undefined;
      m.splineResample(&c,&p);
      const mk=b.mark();
      try kit.taper(b,&p,0.0015,1,0.9,0.92,if(j%2==0)kit.green else kit.leafLite,.tendril,4);
      try k.on(b,mk,ribs[0],1,.{.from=p0,.delay=0.03*m.f(j)});
    }
  }
}
/// a chamber caged at the spire's crown, as the weftstone's: a sac of both
/// saps in a net of pale and green strands wound round it
fn chamber(b:*mg.Builder,k:*growth.Skeleton,trunk:growth.Id,top:V3)Allocator.Error!void{
  // the chamber's middle and size, just under the crown
  const r=v3(0.13,0.16,0.13);
  const mid=top-v3(0,r[1]*1.15,0);
  const sac=b.mark();
  try kit.sac(b,.{.center=mid,.radii=r,.t=0.6,.arms=2,.swirl=1.1});
  try k.on(b,sac,trunk,0.9,.{.from=mid});
  for([_]f32{-1,1})|way|for(0..kit.fold)|i|{
    // this strand's bearing, and its points round the chamber, bottom to top
    const a0=m.ratio(i,kit.fold)*m.tau+(if(way<0)@as(f32,0.6)else 0);
    var c:[10]V3=undefined;
    for(&c,0..)|*q,j|{
      // how far up the strand, its height round the net and its bearing
      const w=m.ratio(j,9);
      const th=m.pi*(1-w);
      const ph=a0+way*1.3*w;
      q.*=mid+v3(@sin(th)*@cos(ph)*r[0]*1.25,@cos(th)*r[1]*1.2,@sin(th)*@sin(ph)*r[2]*1.25);
    }
    const id=k.branch(trunk,0.88,&c,.{.after=.passing,.pace=0.8});
    try k.tube(b,id,.{.r0=0.006,.tip=0.6,.col=if(way<0)kit.pale else kit.green,.sides=5,.t0=0.55,.t1=0.65});
  };
}
/// kite of look `l` at `at`, turned to bearing `a`
fn kiteOf(b:*mg.Builder,l:Look,at:V3,a:f32)Allocator.Error!void{
  const r=l.kiteR;
  switch(l.kite){
    .sac=>try kit.sac(b,.{.center=at,.radii=v3(r,r*1.15,r),.t=0.97,.arms=2,.swirl=0.9,.phase=a}),
    .diamond=>{
      // the way it faces (out from the spire), across it, and up
      const face=v3(@cos(a),0,@sin(a));
      const side=m.norm(m.cross(v3(0,1,0),face));
      // the membrane: a diamond, widest two fifths up, rows bottom to top
      var sp:[9]V3=undefined;
      var sd:[9]V3=undefined;
      var fc:[9]V3=undefined;
      var wd:[9]f32=undefined;
      var ds:[9]f32=undefined;
      var cs:[9]color.Rgba8=undefined;
      for(0..9)|j|{
        // how far up the kite
        const s=m.ratio(j,8);
        sp[j]=at+v3(0,(s-0.4)*r*2.2,0);
        sd[j]=side;
        fc[j]=face;
        wd[j]=r*0.85*(if(s<0.4)s/0.4 else(1-s)/0.6);
        ds[j]=r*0.12;
        cs[j]=membrane;
      }
      try mg.lamina(b,.{.spine=&sp,.side=&sd,.face=&fc,.width=&wd,.dish=&ds,.broad=r*0.3,.col=&cs,.t=0.97,.part=.bloom});
      // its spars: one up its length, one across its widest
      const up=[_]V3{at-v3(0,r*0.9,0),at,at+v3(0,r*1.35,0)};
      const across=[_]V3{at-side*m.splat3(r*0.85),at,at+side*m.splat3(r*0.85)};
      for([_][3]V3{up,across})|c|{
        var p:[8]V3=undefined;
        m.splineResample(&c,&p);
        try kit.taper(b,&p,0.005,0.6,0.97,0.98,kit.pale,.stem,5);
      }
    },
    .lantern=>{
      // a small glowing sac, and woven strands round it, knotted top and bottom
      try kit.sac(b,.{.center=at,.radii=m.splat3(r*0.7),.t=0.97,.arms=2,.swirl=1.2,.phase=a});
      for(0..kit.fold)|i|{
        // this strand's bearing, and its points round the sac
        const ba=m.ratio(i,kit.fold)*m.tau+a;
        var c:[6]V3=undefined;
        for(&c,0..)|*q,j|{
          // how far round, bottom to top
          const th=m.pi*(1-m.ratio(j,5));
          q.*=at+v3(@sin(th)*@cos(ba)*r,@cos(th)*r*1.2,@sin(th)*@sin(ba)*r);
        }
        var p:[12]V3=undefined;
        m.splineResample(&c,&p);
        try kit.taper(b,&p,0.0045,0.6,0.97,0.98,if(i%2==0)kit.pale else kit.green,.stem,4);
      }
      for([_]f32{-1,1})|s|try pk.nodule(b,at+v3(0,s*r*1.2,0),m.splat3(r*0.15),0.97,kit.pale,kit.lilac,kit.pearl);
    },
  }
}
/// mesh: one bolt of lightning, built straight up +Y over 0..1 (bent on
/// the GPU along the curve it strikes, `Parts.emitCurve`): a jagged thread
/// of light kinked at uneven steps, a fork off its middle, pointed at both
/// ends (part `.spark`: white-hot at its core, violet at its edge, lighting
/// the air round it); far thicker than a weftstone's spark, for it spans
/// metres
pub const bolt=struct{
  /// lays the bolt up 0..1
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // how many kinks it runs through, and each one's place, stamp and radius
    const n=17;
    var p:[n]V3=undefined;
    var ts:[n]f32=undefined;
    var rs:[n]f32=undefined;
    var rng=engine.core.rng.Rng.init(0xB017);
    for(&p,&ts,&rs,0..)|*q,*t,*r,i|{
      // how far along it this kink is (the ends fixed), and how far it kinks off its line
      const f=if(i==0 or i==n-1)m.ratio(i,n-1)else m.ratio(i,n-1)+rng.range(-0.02,0.02);
      const off:f32=if(i==0 or i==n-1)0 else 0.035;
      q.*=v3(rng.range(-1,1)*off,f,rng.range(-1,1)*off);
      t.*=f;
      r.*=@max(0.012*@sqrt(@sin(m.pi*f)),2e-4);
    }
    try b.tubeR(&p,&ts,&rs,kit.pearl,.spark,5);
    // forks off its middle and lower third, dying out
    for([_]usize{6,11},[_]f32{1,-1})|at,s|{
      var fp:[6]V3=undefined;
      var ft:[6]f32=undefined;
      var fr:[6]f32=undefined;
      for(&fp,&ft,&fr,0..)|*q,*t,*r,j|{
        // how far along the fork
        const f=m.ratio(j,5);
        q.*=p[at]+v3(s*0.09*f+rng.range(-0.01,0.01)*f,-0.12*f,0.03*f);
        t.*=ts[at];
        r.*=@max(0.007*(1-f),2e-4);
      }
      try b.tubeR(&fp,&ft,&fr,kit.pearl,.spark,4);
    }
  }
};
/// mesh: one of its lanterns, flown free of the spire on its thread
/// (structures/storm_spire.zig places it, drifting): woven strands round a
/// small glowing sac, knotted top and bottom, round its origin
pub const lantern=struct{
  /// builds it
  pub fn build(b:*mg.Builder)Allocator.Error!void{try kiteOf(b,look,v3(0,0,0),0);}
};
/// mesh: a lantern's thread, built straight up +Y over 0..1 (bent on the GPU
/// along the curve it hangs in, `Parts.emitCurve`): a fine lilac strand,
/// the charge running up it
pub const thread=struct{
  /// lays it up 0..1
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // its points, their stamps and radii
    var p:[16]V3=undefined;
    var ts:[16]f32=undefined;
    var rs:[16]f32=undefined;
    for(&p,&ts,&rs,0..)|*q,*t,*r,i|{
      // how far up it
      const f=m.ratio(i,15);
      q.*=v3(0,f,0);
      t.*=f;
      r.*=@max(0.004*m.lerp(1,0.7,f),2e-4);
    }
    try b.tubeR(&p,&ts,&rs,threadCol,.tendril,4);
  }
};
