//! the lineages mixed: what grows where symbiote and parasite have become
//! one body, shared by the confluence (a plant, grown through keys) and
//! the convergent structures (grown on their growth splines, gfx/growth.zig:
//! the `*On` pieces). Not one laid over the other (a braid below, a cage above) but
//! woven through each other at every scale, so neither is ever seen alone:
//! - a stalk (`weave`) is the parasites' lattice with every other strand a
//!   symbiote's: green strands wound one way, each wandering a little off
//!   its course as a living thing does, pale strands wound the other way,
//!   exact; where it parts into a cage the two cross, and where they cross
//!   they fuse into a violet knot, neither one's colour. The core they
//!   share is banded with both saps;
//! - its sap (`sac`) is both at once, never stirred smooth: the
//!   symbiotes' amber and the parasites' pale blue swirl round each other
//!   in arms, violet where they mingle;
//! - its counts are the parasites' exact fives (`fold`), turned evenly
//!   and grown alike, but what each of the five carries is a symbiote's,
//!   each a little different from the next: a frond of the lineage's
//!   lilac bearing green leaflets (`frond`), a calyx of five pale
//!   frondlets holding warm living petals (`bloom`);
//! - it roots both ways (`foot`): a pale bulb half sunk in the soil, its
//!   five exact pale roots between the green braided roots of a symbiote.
//! A cage's strands carry how far they have parted in tu.y, as the
//! parasites' do. The confluence is grown through keys (sizes passed in,
//! never counts, so every key keeps one vertex layout).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// checks that a weave's arrays agree in length
const assert=std.debug.assert;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, rng, the builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, splines
const m=engine.core.math;
/// the plant-piece mesher: braids, petals, blades, stamens, the builder itself
const mg=lib.meshgen;
/// colour conversions, for mixing the two lineages' colours
const color=engine.core.color;
/// the vertex layout, whose part roles name how a piece is shaded
const vertex=lib.vertex;
/// the species registry, whose genome sizes a confluence
const species=lib.species;
/// the garden's growth timing: the splines structures grow along
const growth=lib.growth;
/// the seeded random stream that makes each symbiote's piece its own
const Rng=engine.core.rng.Rng;
/// the garden's palette: the symbiotes' vine, leaves, sap and sapwood
const pal=lib.palette;
/// the parasite kit: lattices, sections, fronds, nodules and its colours
const pk=lib.parasiteKit;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// a vertex colour: four bytes, red, green, blue and alpha
const Rgba8=color.Rgba8;
/// one cross-section of a lattice stalk: its core, how tight, how open
const Section=pk.Section;
/// the symbiotes' half: their green strands
pub const green=pal.vine;
/// the symbiotes' dark leaf green, at a leaf's foot
pub const leafDark=pal.leafDark;
/// the symbiotes' light leaf green, toward a leaf's tip
pub const leafLite=pal.leafLite;
/// the symbiotes' amber resin sap
pub const amber=pal.sap;
/// the parasites' half: their pale skin
pub const pale=pk.skin;
/// the parasites' pearl, where their skin swells toward the light
pub const pearl=pk.pearl;
/// the parasites' lilac, their fronds' colour
pub const lilac=pk.lilac;
/// the parasites' thin pale-blue sap
pub const blue=pk.sac;
/// where they meet: neither one's colour
pub const violet=color.rgb(0.58,0.36,0.9).toRgba8(255);
/// a knot where a strand of each crosses and fuses
pub const knot=color.rgb(0.8,0.68,0.98).toRgba8(255);
/// a living petal's warm amber foot
pub const petalBase=color.rgb(0.96,0.56,0.24).toRgba8(255);
/// the violet a living petal blushes toward at its tip
pub const petalTip=color.rgb(0.76,0.44,0.98).toRgba8(255);
/// the core they share, banded with both: the symbiotes' dark sapwood
const coreSym=pal.sapwoodDark;
/// the core's other band: the parasites' own core colour
const corePar=pk.core;
/// how many of everything: the parasites' count, exactly
pub const fold=pk.fold;
/// the most points a weave may have along it
const max=m.maxSpline;
// ---- the weave ----
/// how a weave of both is wound: its strands, their twist and wander, its
/// knots, its core's bands, and the part it is drawn as
pub const Weave=struct{
  /// strands each way: as many green as pale
  n:u32=fold,
  /// how far the strands wind round along the whole weave (radians)
  twist:f32=pk.twist,
  /// how many sides each strand's tube has
  sides:u32=4,
  /// how far a green strand wanders off its exact course (a pale one
  /// never does)
  wobble:f32=0.08,
  /// a knot where two cross, a multiple of a strand's radius, only where
  /// parted at least `knotFrom`
  knot:f32=1.55,
  /// how far parted (0..1) the cage must be before strands knot where they cross
  knotFrom:f32=0.3,
  /// bands of the two saps up the core
  bands:f32=5,
  /// the green strands' own seed, so each weave wanders its own way
  seed:u64=0,
  /// the part role the whole weave is drawn as
  part:vertex.Part=.stem,
};
/// a strand's angle round the weave `u` along it: the green (`way` 1)
/// wandering a little, the pale (`way` -1) exact
fn strandAngle(w:Weave,si:usize,way:f32,u:f32)f32{
  // its exact angle: spaced evenly round, wound on with the twist
  const a=m.ratio(si,w.n)*m.tau+way*w.twist*u;
  return if(way>0)a+mg.strandTurn(w.seed+%si*mg.strandSalt,u,w.wobble)else a;
}
/// a strand's distance from the weave's axis where the cage is `open`: the
/// green swelling a little as it wanders, the pale exactly `open`
fn strandRadius(w:Weave,si:usize,way:f32,u:f32,open:f32)f32{
  return if(way>0)open*mg.strandSwell(w.seed+%si*mg.strandSalt,u,w.wobble)else open;
}
/// the point `r` out from `at` at angle `a` round the frame `nv`, `bv`
fn round(at:V3,nv:V3,bv:V3,a:f32,r:f32)V3{return at+(nv*m.splat3(@cos(a))+bv*m.splat3(@sin(a)))*m.splat3(r);}
/// the weave along `spine` (tu.x `ts`, cross-sections `sec` as a
/// parasite's lattice): a core banded with both saps, `w.n` green strands
/// wound one way and as many pale ones the other, lifting off the core into
/// a cage where parted (tu.y how far, so plant.vert parts it as it grows),
/// and a violet knot wherever a green and a pale strand cross, parted.
pub fn weave(b:*mg.Builder,spine:[]const V3,ts:[]const f32,sec:[]const Section,w:Weave)Allocator.Error!void{
  // how many points run along the spine
  const n=spine.len;
  assert(n>=2 and n<=max and ts.len==n and sec.len==n);
  // a twist-free frame along the spine: its normal and its binormal
  var frameNormal:[max]V3=undefined;
  var fb:[max]V3=undefined;
  mg.transport(spine,frameNormal[0..n],fb[0..n]);
  // each point's radius and colour, used first for the core, then for each strand
  var rs:[max]f32=undefined;
  var cs:[max]Rgba8=undefined;
  for(rs[0..n],cs[0..n],sec,0..)|*r,*c,s,i|{
    r.*=s.core;
    c.*=color.mix(coreSym,corePar,0.5+0.5*@sin(m.ratio(i,n-1)*w.bands*m.tau));
  }
  try b.tubeC(spine,ts,rs[0..n],cs[0..n],null,w.part,8);
  // how far each strand has parted at each point (its tu.y)
  var us:[max]f32=undefined;
  // one strand's path along the weave
  var path:[max]V3=undefined;
  for([_]f32{1,-1})|way|for(0..w.n)|si|{
    for(path[0..n],rs[0..n],us[0..n],cs[0..n],sec,0..)|*p,*r,*u,*c,s,i|{
      // how far along the weave this point is (0..1)
      const k=m.ratio(i,n-1);
      p.*=round(spine[i],frameNormal[i],fb[i],strandAngle(w,si,way,k),strandRadius(w,si,way,k,s.open));
      r.*=s.strand;
      u.*=pk.parting(s);
      // each paler where it is parted, as young growth is
      c.*=if(way>0)color.mix(green,leafLite,u.* * 0.45)else color.mix(pale,pearl,u.* * 0.6);
    }
    try b.tubeC(path[0..n],ts,rs[0..n],cs[0..n],us[0..n],w.part,w.sides);
  };
  // decision: knots are left out at the coarsest level of detail, where
  // they are under a pixel
  if(w.knot<=0 or b.lod+1>=mg.lods)return;
  // pale strand j meets green strand j - k every pi / (n twist) along it
  const every=m.pi/(m.f(w.n)*w.twist);
  // which green strand the pale ones meet: `k` places back round the weave
  var k:u32=1;
  while(m.f(k)*every<1):(k+=1){
    // where along the weave this crossing lies (0..1)
    const u=m.f(k)*every;
    // that place as a fractional point index
    const x=u*m.f(n-1);
    // the points just before and after it, and how far between
    const lo=m.floorTo(usize,x);
    // the point just after it
    const hi=@min(lo+1,n-1);
    // how far between the two it lies (0..1)
    const f=x-m.f(lo);
    // the weave's section there, lerped between the two
    const s:Section=.{
      .core=m.lerp(sec[lo].core,sec[hi].core,f),.tight=m.lerp(sec[lo].tight,sec[hi].tight,f),
      .open=m.lerp(sec[lo].open,sec[hi].open,f),.strand=m.lerp(sec[lo].strand,sec[hi].strand,f),
    };
    // how far parted it is there; too little and no knot is tied
    const pt=pk.parting(s);
    if(pt<w.knotFrom)continue;
    // the spine's point there, and its frame
    const at=m.lerpV(spine[lo],spine[hi],f);
    // the frame's normal there
    const nv=m.norm(m.lerpV(frameNormal[lo],frameNormal[hi],f));
    // the frame's binormal there
    const bv=m.norm(m.lerpV(fb[lo],fb[hi],f));
    for(0..w.n)|j|{
      // the green strand pale strand `j` crosses here
      const i=(j+w.n-k%w.n)%w.n;
      // where the pale strand lies here
      const pPale=round(at,nv,bv,strandAngle(w,j,-1,u),strandRadius(w,j,-1,u,s.open));
      // where the green strand lies here
      const pGreen=round(at,nv,bv,strandAngle(w,i,1,u),strandRadius(w,i,1,u,s.open));
      // where the knot's vertices begin, so its parting can be set on them
      const mk=b.mark();
      // fused where they cross: drawn out a little along both
      try mg.ellipsoid(b,.{
        .center=(pPale+pGreen)*m.splat3(0.5),.radii=m.splat3(s.strand*w.knot),
        .col=knot,.part=w.part,.rings=4,.segs=6,.t=m.lerp(ts[lo],ts[hi],f),
      });
      for(b.v.items[mk..])|*vx|vx.tu[1]=pt;
    }
  }
}
/// a stalk's sections (as the parasites': woven at its foot, parting into a
/// cage over `s.from..s.to`, gathering again), one per point of `out`
pub fn sections(s:pk.Stalk,out:[]Section)void{
  for(out,0..)|*c,i|c.*=pk.section(s,m.ratio(i,out.len-1));
}
// ---- sap ----
/// how a sac of both saps is shaped and swirled
pub const Sac=struct{
  /// its centre
  center:V3,
  /// its half-sizes along x, y and z
  radii:V3,
  /// its growth tu.x, when it forms
  t:f32,
  /// how many arms of each sap swirl round it
  /// (the same for each sap, the two alternating round it)
  arms:u32=2,
  /// how many turns the arms make from its foot to its crown
  swirl:f32=0.9,
  /// turns the swirl about its axis (so no two sacs swirl alike)
  phase:f32=0,
  /// how many rings its ellipsoid has, crown to foot
  rings:u32=10,
  /// how many segments go round its ellipsoid
  segs:u32=14,
};
/// a sac of both saps (part `.bloom`: see-through, its hue its colour):
/// amber and pale blue swirling round each other in arms from its foot to
/// its crown, violet between them where they mingle; never one colour
pub fn sac(b:*mg.Builder,s:Sac)Allocator.Error!void{
  // where the sac's vertices begin, so only they are marbled
  const mk=b.mark();
  try mg.ellipsoid(b,.{.center=s.center,.radii=s.radii,.col=violet,.part=.bloom,.rings=s.rings,.segs=s.segs,.t=s.t});
  for(b.v.items[mk..])|*vx|vx.col=marbled(s,vx.pos);
}
/// a sac's colour at `p`: a smooth field of position, so its shared
/// vertices agree
fn marbled(s:Sac,p:V3)Rgba8{
  // the point in the sac's own unit space
  const d=(p-s.center)/s.radii;
  // its angle round the sac's axis (radians)
  const ph=m.atan2(d[2],d[0]);
  // which arm it falls in: -1 deep in one sap .. 1 deep in the other
  const band=@sin(m.f(s.arms)*ph+s.swirl*m.tau*d[1]+s.phase);
  // that turned to 0..1, amber at 0, violet at 0.5, blue at 1
  const k=m.clamp01(0.5+band*0.9);
  return if(k<0.5)color.mix(amber,violet,m.smooth(k*2))else color.mix(violet,blue,m.smooth(k*2-1));
}
// ---- fronds ----
/// how a frond of both is laid: where it springs, which way, how long and
/// thick, its leaflets, its crozier, its timing and its seeds
pub const Frond=struct{
  /// where it springs from
  from:V3,
  /// the way it leans out (horizontal, unit)
  out:V3,
  /// how far it reaches out
  len:f32,
  /// its stem's radius at the foot
  r:f32,
  /// how high it rises as it arches
  rise:f32=1.1,
  /// how far its tip curls back down
  curl:f32=3.0,
  /// green leaflet pairs along it, each pair a little different
  pairs:u32,
  /// a leaflet's length at its longest
  leafLen:f32,
  /// a leaflet's width
  leafW:f32,
  /// it ends rolled up in a crozier this many turns (a fern's young tip)
  coil:f32=1.2,
  /// its tu.x at its foot
  t0:f32,
  /// its tu.x at its tip
  t1:f32,
  /// one seed for a crown's fronds makes them alike (the parasites'
  /// exactness); `leafSeed` differs per frond (the symbiotes' leaflets)
  seed:u64,
  /// the leaflets' own seed, so each frond's are its own
  leafSeed:u64,
};
/// how many control points a frond's arc has
const arc=8;
/// how many control points its crozier's coil has
const coil=6;
/// how many points a frond is resampled to
const frondRes=30;
/// a frond: a lilac stem arching out of `from`, exact as the parasites'
/// are, greening toward its tip where it rolls up into a crozier as a
/// fern's does, with pairs of green leaflets along it, longest near its
/// foot, each pair its own; furled nubs on the coil
pub fn frond(b:*mg.Builder,f:Frond)Allocator.Error!void{
  // the frond's control points
  var c:[arc+coil]V3=undefined;
  frondCtrl(f,&c);
  try frondAlong(b,f,&c,null);
}
/// a frond grown on its own spline off `parent` at `u` (`o` when), its
/// leaflets unfolding as the front passes them; returns its spline
pub fn frondOn(b:*mg.Builder,k:*growth.Skeleton,parent:growth.Id,u:f32,f:Frond,o:growth.Branch)Allocator.Error!growth.Id{
  // the frond's control points
  var c:[arc+coil]V3=undefined;
  frondCtrl(f,&c);
  // the frond's own spline off its parent
  const id=k.branch(parent,u,&c,o);
  try frondAlong(b,f,&c,.{.k=k,.id=id});
  return id;
}
/// a growth skeleton and the spline on it a frond grows along
const On=struct{k:*growth.Skeleton,id:growth.Id};
/// a frond's control points: its arc, then the coil of its crozier
fn frondCtrl(f:Frond,c:*[arc+coil]V3)void{
  pk.frondPath(f.from,f.out,f.len,f.rise,f.curl,f.seed,c[0..arc]);
  // the crozier: the heading turns on, ever tighter, about the frond's side
  // the frond's side, the way across it, flat
  const side=m.norm(m.cross(v3(0,1,0),f.out));
  // the heading the arc ends on, turned on step by step through the coil
  var d=m.norm(c[arc-1]-c[arc-2]);
  // the way the coil turns toward, square to the heading and the side
  const up=m.cross(d,side);
  // how far each coil step goes, shrinking as it tightens
  var step=m.dist(c[arc-1],c[arc-2])*0.8;
  for(0..coil)|j|{
    // how far round the coil this step has turned (radians)
    const a=m.ratio(j+1,coil)*f.coil*m.tau;
    d=m.norm(m.norm(c[arc-1]-c[arc-2])*m.splat3(@cos(a))-up*m.splat3(@sin(a)));
    c[arc+j]=c[arc+j-1]+d*m.splat3(step);
    step*=0.72;
  }
}
/// builds a frond from its control points: the stem greening toward its
/// tip, leaflet pairs along the arc and furled nubs on the coil, each
/// grown on `on`'s spline as the front passes when given
fn frondAlong(b:*mg.Builder,f:Frond,c:*const[arc+coil]V3,on:?On)Allocator.Error!void{
  // the frond resampled smooth
  var p:[frondRes]V3=undefined;
  m.splineResample(c,&p);
  // where the stem's vertices begin, so it grows along the spline
  const stem=b.mark();
  // the stem's growth timing, radius and colour, point by point
  var ts:[frondRes]f32=undefined;
  var rs:[frondRes]f32=undefined;
  var cs:[frondRes]Rgba8=undefined;
  for(&ts,&rs,&cs,0..)|*t,*r,*cl,j|{
    // how far along the frond this point is (0..1)
    const k=m.ratio(j,frondRes-1);
    t.*=m.lerp(f.t0,f.t1,k);
    r.*=f.r*m.lerp(1,0.18,k);
    cl.*=color.mix(lilac,leafLite,m.smooth(m.unlerp(0.45,0.95,k)));
  }
  try b.tubeC(&p,&ts,&rs,&cs,null,.tendril,5);
  if(on)|o|try o.k.along(b,stem,o.id);
  // where the arc ends and the coil begins along the resampled frond
  const arcEnd:f32=0.7;
  // the frond's leaflet seed, so its leaflets are its own
  var rng=Rng.init(f.leafSeed);
  for(0..f.pairs)|j|{
    // how far along the frond this pair sits (0..1)
    const k=m.lerp(0.2,arcEnd,m.ratio(j,@max(f.pairs,2)-1));
    // the frond's point there
    const at=m.alongPath(&p,k);
    // the frond's direction there
    const tan=m.norm(m.alongPath(&p,@min(k+0.02,1))-m.alongPath(&p,@max(k-0.02,0)));
    // the way out to the frond's side
    const sd=m.norm(m.cross(tan,v3(0,1,0)));
    // the pair's length: shorter toward the tip
    const len=f.leafLen*(1-0.6*m.smooth(m.ratio(j,@max(f.pairs,2)-1)));
    // where the pair's vertices begin, so it unfolds in its turn
    const pair=b.mark();
    for([_]f32{1,-1})|sgn|{
      // which way this leaflet points: out to its side, swept on, lifted, jittered
      const dir=m.norm(sd*m.splat3(sgn)+tan*m.splat3(0.5+rng.range(-0.12,0.12))+v3(0,rng.range(0.05,0.25),0));
      try mg.natural(b,at,dir,len*rng.range(0.85,1.12),f.leafW*rng.range(0.85,1.1),0.4,leafDark,leafLite,m.lerp(f.t0,f.t1,k),.sessile);
    }
    if(on)|o|try o.k.on(b,pair,o.id,o.k.nearest(o.id,at),.{.from=at});
  }
  // decision: furled nubs only at full detail; past the first level of
  // detail (`b.lod>0`) they are under a pixel
  if(b.lod>0)return;
  // the frond's side, the way across it, flat
  const side=m.norm(m.cross(v3(0,1,0),f.out));
  for(0..4)|j|{
    // how far along the coil this pair of nubs sits (0..1)
    const k=m.lerp(arcEnd+0.04,0.95,m.ratio(j,3));
    // the frond's point there
    const at=m.alongPath(&p,k);
    // the frond's girth there, which the nubs are sized by
    const r=f.r*m.lerp(1,0.18,k);
    // where the nubs' vertices begin, so they swell in their turn
    const nubs=b.mark();
    for([_]f32{1,-1})|sgn|{
      try mg.ellipsoid(b,.{.center=at+side*m.splat3(sgn*r*1.2),.radii=m.splat3(r*0.85),.col=leafLite,.part=.leaf,.rings=3,.segs=5,.t=m.lerp(f.t0,f.t1,k)});
    }
    if(on)|o|try o.k.on(b,nubs,o.id,o.k.nearest(o.id,at),.{.from=at});
  }
}
// ---- flowers ----
/// how a flower of both is shaped: its heart, size, timing, how open, its
/// turn, its petals and their colours, and its seed
pub const Bloom=struct{
  /// where its heart sits
  heart:V3,
  /// a petal's length (the flower's size)
  len:f32,
  /// its growth tu.x, when it forms
  t:f32=1,
  /// 0 a closed bud .. 1 open
  open:f32=1,
  /// how far it is turned about its axis (radians)
  spin:f32=0,
  /// how many living petals it opens
  petals:u32=fold,
  /// the colour at a petal's foot
  base:Rgba8=petalBase,
  /// the colour at a petal's tip
  tip:Rgba8=petalTip,
  /// its own seed, so its petals each lean their own way
  seed:u64,
};
/// a flower of both: a calyx of `fold` pale frondlets turned exactly evenly
/// and curling out alike, each tipped with a pearl, and between them living
/// petals cupped round a bead of both saps, each petal its own size and
/// lean; pearl filaments carrying the symbiotes' gold pollen stand in it.
/// Every size follows `open` (counts never do), so it keeps one layout.
pub fn bloom(b:*mg.Builder,f:Bloom)Allocator.Error!void{
  // how open it is (0 a bud .. 1 open)
  const op=f.open;
  try sac(b,.{
    .center=f.heart+v3(0,f.len*0.12,0),.radii=v3(f.len*0.2,f.len*0.24,f.len*0.2),
    .t=f.t,.phase=f.spin*3,.rings=6,.segs=9,
  });
  // the calyx: exact, alike
  for(0..fold)|i|{
    // this frondlet's heading round the heart (radians)
    const a=f.spin+m.ratio(i,fold)*m.tau;
    // the frondlet's control points
    var c:[6]V3=undefined;
    pk.frondPath(f.heart,v3(@cos(a),0,@sin(a)),f.len*0.75,m.lerp(1.35,0.2,op),m.lerp(-0.4,2.4,op),f.seed^0xCA1,&c);
    // the frondlet resampled smooth
    var p:[12]V3=undefined;
    m.splineResample(&c,&p);
    try taper(b,&p,f.len*0.04,0.25,f.t,f.t,lilac,.tendril,4);
    try mg.ellipsoid(b,.{.center=p[11],.radii=m.splat3(f.len*0.045),.col=pearl,.part=.tendril,.rings=4,.segs=5,.t=f.t});
  }
  // the petals: living, each a little different
  // the flower's own seeded rng, so its petals are its own
  var rng=Rng.init(f.seed^0xB10);
  for(0..f.petals)|i|{
    // this petal's heading: evenly spread, jittered a little (radians)
    const a=f.spin+(m.f(i)+0.5)/m.f(f.petals)*m.tau+rng.range(-0.15,0.15);
    // its size, each its own
    const sc=rng.range(0.85,1.12);
    try mg.petal(b,.{
      .base=f.heart,.out=v3(@cos(a),0,@sin(a)),
      .len=f.len*sc*m.lerp(0.45,1,op),.width=f.len*0.4*sc*m.lerp(0.45,1,op),
      .rise=m.lerp(1.45,0.8,op)+rng.range(-0.1,0.1),.flare=m.lerp(-0.35,0.85,op),.cup=0.45,
      .col=f.base,.tip=f.tip,.t=f.t,.part=.leaf,
    });
  }
  try mg.stamens(b,.{
    .heart=f.heart+v3(0,f.len*0.08,0),.axis=v3(0,1,0),.n=fold,
    .len=f.len*m.lerp(0.25,0.6,op),.r=f.len*0.022,.anther=f.len*m.lerp(0.06,0.13,op),
    .lean=m.lerp(0.05,0.4,op),.arch=m.lerp(0.1,0.55,op),.col=pearl,.t=f.t,.spin=f.spin,.seed=f.seed^0x57A,
  });
}
// ---- rooting ----
/// how a foot rooted both ways is laid: where, how big, how far its roots
/// reach, how thick they are, its timing and its seed
pub const Foot=struct{
  /// where the bulb sits
  at:V3=v3(0,0,0),
  /// the bulb's radius across
  r:f32,
  /// how far its roots reach out
  reach:f32,
  /// a root's radius at the bulb
  rootR:f32,
  /// its growth tu.x, when it forms
  t:f32=0,
  /// its own seed, so its green roots each run their own way
  seed:u64,
};
/// rooted both ways: a pale bulb half sunk in the soil, pearl where it
/// swells toward the light; `FOLD` pale roots out of it, exactly even and
/// alike, and between each two a symbiote's green braided root, each its
/// own length and course, all reaching low over the ground and sinking in
pub fn foot(b:*mg.Builder,f:Foot)Allocator.Error!void{
  try pk.nodule(b,f.at+v3(0,f.r*0.12,0),v3(f.r,f.r*0.5,f.r),f.t,pale,corePar,pearl);
  // the foot's own seeded rng, so its green roots are its own
  var rng=Rng.init(f.seed);
  for(0..fold)|i|{
    // pale: exact
    {
      // this pale root's heading: exactly even (radians)
      const a=m.ratio(i,fold)*m.tau;
      // its control points
      var c:[6]V3=undefined;
      rootPath(f.at,a,f.r*0.6,f.reach,0.25,f.seed^0x9A1E,&c);
      // its control points resampled smooth
      var p:[12]V3=undefined;
      m.splineResample(&c,&p);
      try taper(b,&p,f.rootR*0.75,0.04,f.t,f.t+0.03,pearl,.stem,5);
    }
    // green: each its own
    {
      // this green root's heading: between two pale ones, jittered (radians)
      const a=(m.f(i)+0.5+rng.range(-0.18,0.18))/m.f(fold)*m.tau;
      // its control points
      var c:[6]V3=undefined;
      rootPath(f.at,a,f.r*0.5,f.reach*rng.range(0.8,1.1),0.3,f.seed+%i*41,&c);
      // its control points resampled smooth
      var p:[12]V3=undefined;
      m.splineResample(&c,&p);
      // its growth timing and radius, point by point
      var ts:[12]f32=undefined;
      var rs:[12]f32=undefined;
      for(&ts,&rs,0..)|*t,*r,j|{
        // how far along the root this point is (0..1)
        const k=m.ratio(j,11);
        t.*=f.t+0.03*(1-k);
        r.*=f.rootR*1.3*m.lerp(1,0.3,k);
      }
      try mg.braid(b,&p,&ts,&rs,3,2.2,pal.strandWobble,f.seed+%i*7,pal.core,green);
    }
  }
}
/// `foot` on a structure: the bulb swelling out of spline `id`'s start,
/// every root a branch growing with it
pub fn footOn(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,f:Foot)Allocator.Error!void{
  // where the bulb's vertices begin, so it swells out of the spline's start
  const bulb=b.mark();
  try pk.nodule(b,f.at+v3(0,f.r*0.12,0),v3(f.r,f.r*0.5,f.r),f.t,pale,corePar,pearl);
  try k.on(b,bulb,id,0,.{.from=f.at,.span=k.get(id).time*0.3});
  // the foot's own seeded rng, so its green roots are its own
  var rng=Rng.init(f.seed);
  for(0..fold)|i|{
    // one root's control points, reused for the pale and then the green
    var c:[6]V3=undefined;
    rootPath(f.at,m.ratio(i,fold)*m.tau,f.r*0.6,f.reach,0.25,f.seed^0x9A1E,&c);
    // the pale root's own branch, growing with the spline
    const paleRoot=k.branch(id,0,&c,.{.after=.with});
    try k.tube(b,paleRoot,.{.r0=f.rootR*0.75,.tip=0.04,.col=pearl,.sides=5,.t0=f.t,.t1=f.t+0.03});
    rootPath(f.at,(m.f(i)+0.5+rng.range(-0.18,0.18))/m.f(fold)*m.tau,f.r*0.5,f.reach*rng.range(0.8,1.1),0.3,f.seed+%i*41,&c);
    // the green root's own branch, growing with the spline
    const greenRoot=k.branch(id,0,&c,.{.after=.with});
    try k.braid(b,greenRoot,.{.girth=f.rootR*1.3,.tip=0.3,.wobble=pal.strandWobble,.seed=f.seed+%i*7,.core=pal.core,.strand=green,.t0=f.t+0.03,.t1=f.t});
  }
}
/// a weave grown along spline `id` (its tu.x `t0`..`t1`), sections from
/// `s`; returns where on it each section lies, for what rides inside
pub fn weaveOn(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,s:pk.Stalk,w:Weave,t0:f32,t1:f32,sp:*[growth.res]V3,sec:*[growth.res]Section)Allocator.Error!void{
  // the weave's tu.x, point by point
  var ts:[growth.res]f32=undefined;
  k.path(id,0,1,sp);
  for(&ts,0..)|*t,i|t.*=m.lerp(t0,t1,m.ratio(i,growth.res-1));
  sections(s,sec);
  // where the weave's vertices begin, so it grows along the spline
  const mk=b.mark();
  try weave(b,sp,&ts,sec,w);
  try k.along(b,mk,id);
}
/// a root from `at` toward bearing `a`: out of the bulb at `from`, low over
/// the ground to `reach`, then down into it
pub fn rootPath(at:V3,a:f32,from:f32,reach:f32,wobble:f32,seed:u64,c:*[6]V3)void{
  // the way out along the bearing, flat
  const out=v3(@cos(a),0,@sin(a));
  // where the root leaves the bulb, just above the ground
  const s=at+out*m.splat3(from)+v3(0,0.02,0);
  for(c,0..)|*p,j|{
    // how far along the root this point is (0..1)
    const k=m.ratio(j,5);
    p.*=s+out*m.splat3((reach-from)*k)+v3(0,0.02*@sin(m.pi*k*0.8)-0.1*k*k*reach,0);
  }
  mg.grow(c,.{.start=s,.direction=out,.length=reach-from,.wobble=wobble,.seed=seed});
}
/// a tube along `p`, `r` at its root tapering to `tip` of it, tu.x
/// `t0`..`t1`, never thinner than a tube keeps its caps at
pub fn taper(b:*mg.Builder,p:[]const V3,r:f32,tip:f32,t0:f32,t1:f32,col:Rgba8,part:vertex.Part,sides:u32)Allocator.Error!void{
  // the tube's tu.x and radius, point by point
  var ts:[max]f32=undefined;
  var rs:[max]f32=undefined;
  for(ts[0..p.len],rs[0..p.len],0..)|*t,*q,j|{
    // how far along the tube this point is (0..1)
    const k=m.ratio(j,p.len-1);
    t.*=m.lerp(t0,t1,k);
    q.*=@max(r*m.lerp(1,tip,k),2e-4);
  }
  try b.tubeR(p,ts[0..p.len],rs[0..p.len],col,part,sides);
}
// ---- the confluence (grown through keys) ----
/// tu.x where the two trunks have fused into one
/// (a share of the whole confluence, 0..1)
const fuseT:f32=0.42;
/// tu.x where the fused weave gives onto its canopy
const canopyT:f32=0.78;
/// how each part of a confluence has come along at `growth` (0..1)
const Grown=struct{
  /// the trunks' height and girth
  rise:f32,
  /// the boughs' reach
  reach:f32,
  /// its flowers opening
  bloom:f32,
  /// how far each part has come along at growth `gr` (0..1), each eased in
  /// over its own stretch of it
  fn at(gr:f32)Grown{
    return.{
      .rise=m.lerp(0.3,1,m.smooth(m.clamp01(gr/0.5))),
      .reach=m.lerp(0.05,1,m.smooth(m.unlerp(0.2,0.75,gr))),
      .bloom=m.smooth(m.unlerp(0.7,1,gr)),
    };
  }
};
/// the confluence at `growth` (0..1): where the lineages first met, so the
/// meeting is told from the ground up. Out of opposite corners of its
/// ground rise a symbiote's braided trunk, leafy, on green braided roots,
/// and a parasite's lattice stalk, sacs hanging in its cage, on a pale
/// bulb and exact roots; they wind round each other, closing in as they
/// climb, and fuse into one weave of both (green and pale strands, violet
/// knots) that opens into five boughs, each a frond of both lineages
/// ending in a flower of both, round a great sac of both saps crowned by a
/// flower of its own. Nothing appears or vanishes with growth (what is not
/// yet grown is small), so every key keeps one vertex layout.
pub fn confluence(b:*mg.Builder,g:species.Genome,seed:u64,gr:f32)Allocator.Error!void{
  // how far each part has come along
  const gw=Grown.at(gr);
  // the confluence's own seeded rng
  var rng=Rng.init(seed);
  // how tall its trunks stand by now
  const h=g.stemH*gw.rise;
  // where the trunks fuse
  const fuseH=h*0.42;
  // where the canopy starts
  const topH=h*0.78;
  // the trunks' girth by now
  const radius=g.stemR*m.lerp(0.55,1,gw.rise);
  // where the trunks stand apart, at the foot, and the turn they make
  const apart:f32=0.42*gw.rise;
  const turn:f32=1.15*m.pi;
  // where the first trunk stands round the axis (radians)
  const a0=rng.range(0,m.tau);
  // how many points run up each trunk
  const steps=25;
  for([_]f32{0,1})|side|{
    // whether this is the symbiote's trunk (or the parasite's)
    const sym=side==0;
    // the trunk's path and its growth timing
    var sp:[steps]V3=undefined;
    var ts:[steps]f32=undefined;
    for(&sp,&ts,0..)|*q,*t,i|{
      // how far up the trunk this point is (0..1)
      const u=m.ratio(i,steps-1);
      // closing in as they climb, eased so they meet tangent to the axis;
      // the last stretch runs on up inside the fused weave
      const close=1-m.smooth(m.clamp01(u/0.92));
      // its angle round the axis, the two opposite, winding as they climb
      const a=a0+side*m.pi+turn*u;
      q.*=v3(@cos(a)*apart*close,fuseH*1.12*u,@sin(a)*apart*close);
      t.*=fuseT*1.12*u;
    }
    // the trunk's foot, where its roots spread from
    const base=sp[0];
    if(sym){
      // the braided trunk's radius, flared at its foot
      var rs:[steps]f32=undefined;
      for(&rs,0..)|*r,i|{
        // how far up the trunk this point is (0..1)
        const u=m.ratio(i,steps-1);
        r.*=radius*0.62*(1+0.7*m.pow(f32,1-u,5))*m.lerp(1,0.55,u);
      }
      try mg.braid(b,&sp,&ts,&rs,6,2.6,pal.strandWobble*1.5,seed^0x5B,pal.core,green);
      try mg.leavesAlong(b,&sp,7,radius*1.6*gw.reach+0.01,radius*0.55*gw.reach+0.004,0.25,0.85,ts[0],ts[steps-1],leafDark,leafLite,seed^0x1EF);
      // green braided roots splaying out of its foot, each its own
      for(0..4)|i|{
        // this root's heading: fanned round the trunk's outer side, jittered
        const a=a0+(m.f(i)-1.5)*0.7+rng.range(-0.2,0.2);
        // its control points
        var c:[6]V3=undefined;
        rootPath(base,a,radius*0.3,radius*2.6*rng.range(0.85,1.1)+0.05,0.25,seed+%i*53,&c);
        // its control points resampled smooth
        var p:[12]V3=undefined;
        m.splineResample(&c,&p);
        // its growth timing and radius, point by point
        var rt:[12]f32=undefined;
        var rr:[12]f32=undefined;
        for(&rt,&rr,0..)|*t,*r,j|{
          // how far along the root this point is (0..1)
          const k=m.ratio(j,11);
          t.*=0.04*(1-k);
          r.*=radius*0.3*m.lerp(1,0.35,k);
        }
        try mg.braid(b,&p,&rt,&rr,3,2.2,pal.strandWobble,seed+%i*7,pal.core,green);
      }
    }else{
      // the lattice stalk's shape: parting into a cage over most of it
      const st:pk.Stalk=.{.girth=radius*0.6,.part=1.9,.from=0.15,.to=0.78,.foot=0.8};
      // its sections, point by point
      var sec:[steps]Section=undefined;
      sections(st,&sec);
      try pk.lattice(b,&sp,&ts,&sec,.{});
      // its sacs, on the core inside the cage
      for(0..3)|i|{
        // how far up the cage this sac hangs (0..1)
        const u=m.lerp(st.from,st.to,(m.f(i)+0.5)/3);
        // the stalk's section there
        const c=pk.section(st,u);
        // the sac's radius: whatever room the cage leaves round the core
        const r=@max((c.open-c.strand)*0.6,1e-3);
        try mg.ellipsoid(b,.{.center=m.alongPath(&sp,u),.radii=v3(r,r*1.15,r),.col=blue,.part=.bloom,.rings=6,.segs=9,.t=u*fuseT});
      }
      try pk.nodule(b,base+v3(0,radius*0.15,0),v3(radius*1.05,radius*0.5,radius*1.05),0,pale,corePar,pearl);
      for(0..fold)|i|{
        // this pale root's heading: fanned round the trunk's outer side, exact
        const a=a0+m.pi+(m.ratio(i,fold)-0.5)*2.2;
        // its control points
        var c:[6]V3=undefined;
        rootPath(base,a,radius*0.7,radius*3.4+0.05,0.2,seed^0x9A1E,&c);
        // its control points resampled smooth
        var p:[12]V3=undefined;
        m.splineResample(&c,&p);
        try taper(b,&p,radius*0.16,0.04,0,0.04,pearl,.stem,5);
      }
    }
  }
  // the fused weave: out of where they meet up to the canopy
  {
    // the weave's path and its growth timing
    var sp:[steps]V3=undefined;
    var ts:[steps]f32=undefined;
    // its control points: straight up, wandering a little higher up
    var c:[5]V3=undefined;
    for(&c,0..)|*q,i|{
      // how far up the weave this point is (0..1)
      const u=m.ratio(i,4);
      q.*=v3(rng.range(-0.03,0.03)*u,m.lerp(fuseH*0.85,topH,u),rng.range(-0.03,0.03)*u);
    }
    m.splineResample(&c,&sp);
    for(&ts,0..)|*t,i|t.*=m.lerp(fuseT*0.85,canopyT,m.ratio(i,steps-1));
    // the weave's stalk shape: parting into a cage over most of it
    const st:pk.Stalk=.{.girth=radius*0.85,.part=2.1,.from=0.2,.to=0.85,.foot=0.5};
    // its sections, point by point
    var sec:[steps]Section=undefined;
    sections(st,&sec);
    try weave(b,&sp,&ts,&sec,.{.seed=seed^0xC0F});
    // its yield: pods of both saps hanging from the weave just over where
    // the trunks fuse, small while it is young (every key has them all)
    // how far up the weave they hang, when they form there, and the genome sized to this key
    const pu:f32=0.38;
    const pt=m.lerp(fuseT*0.85,canopyT,pu);
    var pg=g;
    pg.podR=g.podR*m.lerp(0.3,1,gw.rise);
    // how far out the weave's parted strands lie there
    const ps=pk.section(st,pu);
    for(0..g.pods)|k|{
      // this pod's bearing, the way out to it and where its stalk leaves the weave
      const ang=a0+m.ratio(k,g.pods)*m.tau+0.4;
      const out=v3(@cos(ang),0,@sin(ang));
      const root=m.alongPath(&sp,pu)+out*m.splat3(ps.open+ps.strand*0.5);
      _=try mg.pods.hanging(b,pg,k,root,out,pg.podR*0.6,green,pt);
    }
  }
  // the canopy: a great sac of both saps at the top, a flower of both on
  // it, and five boughs arching out round it, alike, each its own leaves
  // and a flower of both at its tip
  // the canopy's foot, at the top of the weave
  const top=v3(0,topH,0);
  // the great sac's radius, swelling as the boughs reach
  const sr=g.bloomR*0.55*m.lerp(0.35,1,gw.reach);
  // the great sac's heart
  const heart=top+v3(0,sr*0.9,0);
  try sac(b,.{.center=heart,.radii=v3(sr,sr*1.15,sr),.t=canopyT+0.04,.arms=3,.swirl=1.1,.phase=a0});
  // how the boughs are turned round the axis (radians)
  const spin=a0+0.3;
  for(0..fold)|i|{
    // this bough's heading round the axis (radians)
    const a=spin+m.ratio(i,fold)*m.tau;
    // the bough's control points (only its arc is laid)
    var c:[arc+coil]V3=undefined;
    pk.frondPath(top+v3(0,sr*0.2,0),v3(@cos(a),0,@sin(a)),g.stemH*0.4*gw.reach,0.75,1.9,seed^0xB0F,c[0..10]);
    // the bough resampled smooth
    var p:[24]V3=undefined;
    m.splineResample(c[0..10],&p);
    try taper(b,&p,radius*0.32,0.4,canopyT,0.97,lilac,.tendril,6);
    try mg.leavesAlong(b,&p,7,radius*1.5*gw.reach+0.01,radius*0.5*gw.reach+0.004,0.2,0.8,canopyT,0.97,leafDark,leafLite,seed+%i*211);
    try bloom(b,.{.heart=p[23],.len=g.bloomR*0.5*m.lerp(0.3,1,gw.reach),.t=1,.open=gw.bloom,.spin=a,.petals=fold,.seed=seed^0xB1});
  }
  // the crowning flower lifts clear of the sac as it opens
  try bloom(b,.{.heart=heart+v3(0,sr*(1.05+0.3*gw.bloom),0),.len=g.bloomR*m.lerp(0.3,1,gw.reach),.t=1,.open=gw.bloom,.spin=spin,.petals=g.petals,.seed=seed^0xB2});
}
