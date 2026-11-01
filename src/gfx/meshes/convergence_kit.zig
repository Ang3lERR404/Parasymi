//! the lineages mixed: what grows where symbiote and parasite have become
//! one body, shared by the confluence (a plant, grown through keys) and
//! the convergent structures (grown on their growth splines, gfx/growth.zig:
//! the `*On` pieces). Not one laid over the other but grown into each
//! other, so neither is ever seen alone:
//! - a stalk (`weave`) rises out of the soil as two stems, a symbiote's
//!   green braided one, wandering and leafy, and a parasite's pale smooth
//!   one swelling at its exact nodes; they wind round each other, are grown
//!   together in a smooth callus wherever they touch (green one side, pale
//!   the other, a violet seam between, neither one's colour) and fuse into
//!   one soft see-through body: green strands and amber lanes winding up
//!   inside it, a pale vein up its middle, five pale ribs exact on its
//!   skin. A limb off another is the body alone (`Form`);
//! - its sap (`sac`) is both at once, never stirred smooth: the
//!   symbiotes' amber and the parasites' pale blue swirl round each other
//!   in arms, violet where they mingle;
//! - its counts are the parasites' exact fives (`fold`), turned evenly
//!   and grown alike, but what each of the five carries is a symbiote's,
//!   each a little different from the next: a frond of the lineage's
//!   lilac bearing green leaflets (`frond`), a calyx of five pale
//!   frondlets holding warm living petals (`bloom`);
//! - it roots both ways (`foot`), no bulb: under the stems' gentle flare,
//!   five exact pale roots between the green braided roots of a symbiote.
//! The confluence is grown through keys (sizes passed in, never counts,
//! so every key keeps one vertex layout).
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
/// how many of everything: the parasites' count, exactly
pub const fold=pk.fold;
/// the most points a weave may have along it
const max=m.maxSpline;
// ---- the weave ----
/// what a weave of both grows as
pub const Form=enum{
  /// out of the soil: two stems, a symbiote's green braided one and a
  /// parasite's pale smooth one, winding round each other, grown together
  /// at their grafts and fused at `Weave.fuse` into one soft body
  rooted,
  /// off another weave: the soft body alone
  limb,
  /// the two stems the whole way, fused at its end into what it meets
  stems,
};
/// how a weave of both grows: from the soil or off another, where its stems
/// fuse into its body, how many leaves its green stem carries, its seed
pub const Weave=struct{
  /// what it grows as
  form:Form=.rooted,
  /// how far along it (0..1) the stems fuse into the body, when rooted
  fuse:f32=0.38,
  /// leaves on the green stem, each on its own stalk
  leaves:u32=5,
  /// its own seed, so each weave's green stem wanders and leafs its own way
  seed:u64=0,
  /// the body's skin at its foot and higher up (a plant's glass draws them
  /// stronger, so the confluence passes paler)
  skin:m.Vice(Rgba8,2)=.{tissueLow,tissue},
};
/// the soft body of both: the parasites' pale skin flushed with violet,
/// see-through
pub const tissue=color.rgb(0.66,0.46,0.95).toRgba8(255);
/// the body's foot, warmed by the amber rising in it
pub const tissueLow=color.rgb(0.92,0.6,0.38).toRgba8(255);
/// where two stems have grown into each other: violet
const scar=violet;
/// how many points a stem or body is built of, fine, so its swellings are smooth
const fine=48;
/// a weave's section `u` along it (0..1), eased between its points
fn sectionAt(sec:[]const Section,u:f32)Section{
  // where it falls between the points, and how far between
  const x=m.clamp01(u)*m.f(sec.len-1);
  const lo=@min(m.floorTo(usize,x),sec.len-1);
  const hi=@min(lo+1,sec.len-1);
  const f=x-m.f(lo);
  return.{
    .core=m.lerp(sec[lo].core,sec[hi].core,f),.tight=m.lerp(sec[lo].tight,sec[hi].tight,f),
    .open=m.lerp(sec[lo].open,sec[hi].open,f),.strand=m.lerp(sec[lo].strand,sec[hi].strand,f),
  };
}
/// a value of `xs` `u` along them (0..1), eased between its points
fn valueAt(xs:[]const f32,u:f32)f32{
  const x=m.clamp01(u)*m.f(xs.len-1);
  const lo=@min(m.floorTo(usize,x),xs.len-1);
  const hi=@min(lo+1,xs.len-1);
  return m.lerp(xs[lo],xs[hi],x-m.f(lo));
}
/// how far out a section reaches: its cage's outside
fn outside(s:Section)f32{return s.open+s.strand;}
/// the weave along `spine` (tu.x `ts`, cross-sections `sec` as a
/// parasite's lattice, whose outside it fills): rooted, two stems grafted
/// into one body; a limb, the body alone; or the stems the whole way
pub fn weave(b:*mg.Builder,spine:[]const V3,ts:[]const f32,sec:[]const Section,w:Weave)Allocator.Error!void{
  assert(spine.len>=2 and spine.len<=max and ts.len==spine.len and sec.len==spine.len);
  switch(w.form){
    .rooted=>{
      try stems(b,spine,ts,sec,w.fuse,w);
      try body(b,spine,ts,sec,w.fuse*0.9,.rising,w.skin);
    },
    .limb=>try body(b,spine,ts,sec,0,.flush,w.skin),
    .stems=>try stems(b,spine,ts,sec,1,w),
  }
}
/// where the green (`side` 1) or pale (`side` -1) stem lies off the
/// middle `v` up their climb (0..1), `r` the reach there: opposite each
/// other, winding loosely, apart most between the grafts, touching at
/// each, close at the soil and meeting at the top; the green wandering a
/// little, the pale exact. Returns its angle round and distance out.
fn stemOff(side:f32,v:f32,r:f32,seed:u64)m.Vice(f32,2){
  const a=0.4+(if(side>0)@as(f32,0)else m.pi)+2.1*v;
  const s=@sin(m.pi*(2*v+0.5));
  const sep=r*(0.22+0.78*s*s)*m.lerp(0.35,1,m.smooth(m.clamp01(v/0.12)))*(1-m.smooth(m.clamp01((v-0.86)/0.14)));
  const wd:f32=if(side>0)r*0.09*@sin(v*9+m.f(seed%7))else 0;
  return.{a,sep+wd};
}
/// where the stems have grown together (shares of their climb), before
/// they fuse for good at its top
const grafts=[_]f32{0.25,0.75,0.97};
/// the two stems along the first `upTo` of `spine`, winding round it: the
/// green braided, leafy; the pale smooth, swelling at its exact nodes; a
/// callus wherever they have grown together. Each as thick as about half
/// the stalk's reach there, so they flare into the soil as it does.
fn stems(b:*mg.Builder,spine:[]const V3,ts:[]const f32,sec:[]const Section,upTo:f32,w:Weave)Allocator.Error!void{
  // the stretch of the middle they climb, its tu.x and its reach, point by point
  var mid:[fine]V3=undefined;
  var tt:[fine]f32=undefined;
  var reaches:[fine]f32=undefined;
  for(&mid,&tt,&reaches,0..)|*p,*t,*r,i|{
    const u=upTo*m.ratio(i,fine-1);
    p.*=m.alongPath(spine,u);
    t.*=valueAt(ts,u);
    // how thick the stalk is woven shut there (its parting left out)
    const s=sectionAt(sec,u);
    r.*=s.tight+s.strand;
  }
  // decision: the stalk swells hard into the soil (a lattice's foot); two
  // stems doing so read as a bulb, so theirs flare gently instead, a root
  // flare under which the roots leave
  {
    const above=valueAt(&reaches,0.35);
    for(&reaches,0..)|*r,i|r.*=@min(r.*,above*(1+0.4*(1-m.smooth(m.clamp01(m.ratio(i,fine-1)/0.12)))));
  }
  // a twist-free frame up it
  var nv:[fine]V3=undefined;
  var bv:[fine]V3=undefined;
  mg.transport(&mid,&nv,&bv);
  // each stem's course and radius
  var gp:[fine]V3=undefined;
  var pp:[fine]V3=undefined;
  var rs:[fine]f32=undefined;
  for(&gp,&pp,&rs,0..)|*g,*p,*r,i|{
    const v=m.ratio(i,fine-1);
    const go=stemOff(1,v,reaches[i]*1.1,w.seed);
    const po=stemOff(-1,v,reaches[i]*1.1,w.seed);
    g.*=round(mid[i],nv[i],bv[i],go[0],go[1]);
    p.*=round(mid[i],nv[i],bv[i],po[0],po[1]);
    r.*=reaches[i]*0.5;
  }
  // the green: braided, wandering
  {
    var gr:[fine]f32=undefined;
    for(&gr,rs)|*q,r|q.*=r*1.05;
    try mg.braid(b,&gp,&tt,&gr,4,2.4,pal.strandWobble*1.4,w.seed,pal.core,green);
  }
  // the pale: smooth, swelling at its exact nodes between the grafts, its
  // own skin thickening and paling to pearl into each, lilac at the
  // middle, and out again
  {
    var pr:[fine]f32=undefined;
    var pc:[fine]Rgba8=undefined;
    for(&pr,&pc,rs,0..)|*q,*c,r,i|{
      const v=m.ratio(i,fine-1);
      // how far into a node this point is (0 between, 1 at its middle)
      var node:f32=0;
      for([_]f32{0.12,0.45,0.58})|nu|node=@max(node,m.smooth(m.clamp01(1-@abs(v-nu)/0.045)));
      q.*=r*(1+0.32*node);
      c.*=color.mix(color.mix(pale,pearl,node),lilac,m.smooth(m.clamp01((node-0.75)/0.25))*0.6);
    }
    try b.tubeC(&pp,&tt,&pr,&pc,null,.stem,8);
  }
  // a callus wherever they have grown together, the last (where they fuse
  // for good) the longest, none longer than a share of their climb
  var climb:f32=0;
  for(1..fine)|i|climb+=m.dist(mid[i],mid[i-1]);
  for(grafts,0..)|v,j|{
    const r=valueAt(&rs,v);
    const g=m.alongPath(&gp,v);
    const p=m.alongPath(&pp,v);
    const last=j==grafts.len-1;
    try graftUnion(b,.{
      .at=m.lerpV(g,p,0.5)+(if(last)m.norm(m.alongPath(&mid,1)-m.alongPath(&mid,0.9))*m.splat3(r*1.1)else v3(0,0,0)),
      .green=g,.pale=p,.r=r*(if(last)@as(f32,1.2)else 0.9),.h=@min(r*(if(last)@as(f32,4.3)else 2.9),climb*(if(last)@as(f32,0.16)else 0.12)),
      .t=valueAt(&tt,v),.phase=m.f(j)*2.1+m.f(w.seed%5),
    });
  }
  // the green stem's leaves, each on its own stalk, out from the middle
  var rng=Rng.init(w.seed^0x1EAF);
  for(0..w.leaves)|i|{
    const v=m.lerp(0.18,0.9,(m.f(i)+rng.range(0.2,0.8))/m.f(@max(w.leaves,1)));
    const at=m.alongPath(&gp,v);
    const r=valueAt(&rs,v);
    const c=m.alongPath(&mid,v);
    const away=v3(at[0]-c[0],0,at[2]-c[2]);
    const out=if(m.len(away)>1e-5)m.norm(away)else v3(1,0,0);
    const len=@min(r*3.2,0.12);
    try mg.natural(b,at+out*m.splat3(r*0.8),m.norm(out+v3(0,rng.range(0.2,0.6),0)),len,len*0.38,0.4,leafDark,leafLite,valueAt(&tt,v),.stalked);
  }
}
/// where two stems have grown together, and how big the callus round it is
const Union=struct{
  /// its middle
  at:V3,
  /// the green stem's middle there
  green:V3,
  /// the pale stem's middle there
  pale:V3,
  /// how far it swells past the stems' middles, and how deep it is square to them
  r:f32,
  /// half its length up the stems
  h:f32,
  /// its growth tu.x
  t:f32,
  /// turns its seam's wander, so no two seams run alike
  phase:f32,
};
/// a graft's union: one smooth callus round where the two stems have grown
/// together, long up them and wide across the join, its ends sinking into
/// both; green on the green stem's side, pale on the pale one's, and
/// between them a violet seam wandering up it, lit lilac along its middle
fn graftUnion(b:*mg.Builder,u:Union)Allocator.Error!void{
  // the way across the join (flat, pale to green), square to it, and half the join's width
  const d0=v3(u.green[0]-u.pale[0],0,u.green[2]-u.pale[2]);
  const across=if(m.len(d0)>1e-4)m.norm(d0)else v3(1,0,0);
  const side=m.cross(v3(0,1,0),across);
  const half=m.len(d0)*0.5;
  // built round the origin in its own frame, then turned onto the join
  const mk=b.mark();
  try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(half+u.r,u.h,u.r*0.9),.col=scar,.part=.stem,.rings=14,.segs=18,.t=u.t});
  for(b.v.items[mk..])|*vx|{
    // its place and facing in its own frame
    const q:V3=vx.pos;
    const n:V3=vx.nrm;
    vx.pos=u.at+across*m.splat3(q[0])+v3(0,q[1],0)+side*m.splat3(q[2]);
    vx.nrm=across*m.splat3(n[0])+v3(0,n[1],0)+side*m.splat3(n[2]);
    // how far to either side of the seam: -1 the pale's, 1 the green's,
    // the seam wandering as it climbs
    const s=q[0]/(half+u.r)+0.2*@sin(q[1]/u.h*4.2+u.phase)+0.08*@sin(q[2]/u.r*3+u.phase*2);
    // how far into its own side, past the seam's width
    const w=m.smooth(m.clamp01((@abs(s)-0.06)/0.3));
    const seam=color.mix(knot,scar,m.smooth(m.clamp01(@abs(s)/0.06)));
    vx.col=color.mix(seam,if(s>0)green else pale,w);
  }
}
/// how a body begins: rising thin out of the callus its stems fuse in, or
/// as full as the weave it grows off
const Start=enum{
  /// thin out of the fusing callus, swelling as it rises
  rising,
  /// full from its foot
  flush,
};
/// the soft body along `spine` from `from` to its end, as full as the
/// stalk's reach: two see-through skins, pale flushed violet, warmed amber
/// at the foot; inside three green strands winding up, two amber lanes the
/// other way and a pale vein up the middle; outside five pale ribs, exact
fn body(b:*mg.Builder,spine:[]const V3,ts:[]const f32,sec:[]const Section,from:f32,start:Start,skin:m.Vice(Rgba8,2))Allocator.Error!void{
  // its points, tu.x, radius and skin colour
  var p:[fine]V3=undefined;
  var tt:[fine]f32=undefined;
  var rs:[fine]f32=undefined;
  var cs:[fine]Rgba8=undefined;
  for(&p,&tt,&rs,&cs,0..)|*q,*t,*r,*c,i|{
    const v=m.ratio(i,fine-1);
    const u=m.lerp(from,1,v);
    q.*=m.alongPath(spine,u);
    t.*=valueAt(ts,u);
    r.*=@max(outside(sectionAt(sec,u)),sectionAt(sec,u).core*1.4)*(switch(start){.rising=>m.lerp(0.55,1,m.smooth(m.clamp01(v/0.14))),.flush=>1});
    c.*=color.mix(skin[0],skin[1],m.smooth(m.clamp01(v*1.6)));
  }
  try b.tubeC(&p,&tt,&rs,&cs,null,.bloom,14);
  // a second skin just inside the first, so the flesh reads as a body and
  // not a pane: its rim doubled, its middle clouded
  var inner:[fine]f32=undefined;
  for(&inner,rs)|*q,r|q.*=r*0.88;
  try b.tubeC(&p,&tt,&inner,&cs,null,.bloom,12);
  // a twist-free frame up it
  var nv:[fine]V3=undefined;
  var bv:[fine]V3=undefined;
  mg.transport(&p,&nv,&bv);
  // one run of strands: how many, how far out and how thick (shares of
  // the body's radius), how many turns, its colour, its turn at the foot
  const Run=struct{n:usize,out:f32,turns:f32,r:f32,col:Rgba8,from:f32};
  const runs=[_]Run{
    .{.n=3,.out=0.5,.turns=1.6,.r=0.09,.col=green,.from=0},
    .{.n=2,.out=0.3,.turns=-1.1,.r=0.07,.col=amber,.from=0.9},
    .{.n=1,.out=0,.turns=0,.r=0.11,.col=color.mix(pale,lilac,0.5),.from=0},
    .{.n=fold,.out=1.005,.turns=0,.r=0.042,.col=pale,.from=0.3},
  };
  for(runs)|run|for(0..run.n)|j|{
    var q:[fine]V3=undefined;
    var rr:[fine]f32=undefined;
    for(&q,&rr,0..)|*x,*r,i|{
      const v=m.ratio(i,fine-1);
      const a=m.ratio(j,run.n)*m.tau+run.from+run.turns*m.tau*v+(if(run.n==3)0.15*@sin(v*8+m.f(j))else 0);
      x.*=round(p[i],nv[i],bv[i],a,rs[i]*run.out);
      r.*=rs[i]*run.r*(if(run.out>1)m.lerp(0.6,1.2,m.smooth(@sin(m.pi*v)))else 1);
    }
    try b.tubeR(&q,&tt,&rr,run.col,.stem,if(run.out>1)4 else 5);
  };
}
/// the point `r` out from `at` at angle `a` round the frame `nv`, `bv`
fn round(at:V3,nv:V3,bv:V3,a:f32,r:f32)V3{return at+(nv*m.splat3(@cos(a))+bv*m.splat3(@sin(a)))*m.splat3(r);}
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
  /// where the weave rises out of the soil
  at:V3=v3(0,0,0),
  /// how wide its root crown spreads (its roots leave a third of it out)
  r:f32,
  /// how far its roots reach out
  reach:f32,
  /// a root's radius where it leaves the crown
  rootR:f32,
  /// its growth tu.x, when it forms
  t:f32=0,
  /// its own seed, so its green roots each run their own way
  seed:u64,
};
/// rooted both ways, no bulb: out of the crown where the weave's two stems
/// flare into the soil, `fold` pale roots, exactly even and alike, and
/// between each two a symbiote's green braided root, each its own length
/// and course, all reaching low over the ground and sinking in
pub fn foot(b:*mg.Builder,f:Foot)Allocator.Error!void{
  // the foot's own seeded rng, so its green roots are its own
  var rng=Rng.init(f.seed);
  for(0..fold)|i|{
    // pale: exact
    {
      // this pale root's heading: exactly even (radians)
      const a=m.ratio(i,fold)*m.tau;
      // its control points
      var c:[6]V3=undefined;
      rootPath(f.at,a,f.r*crownOut,f.reach,0.25,f.seed^0x9A1E,&c);
      // its control points resampled smooth
      var p:[12]V3=undefined;
      m.splineResample(&c,&p);
      try taper(b,&p,f.rootR,0.04,f.t,f.t+0.03,pearl,.stem,5);
    }
    // green: each its own
    {
      // this green root's heading: between two pale ones, jittered (radians)
      const a=(m.f(i)+0.5+rng.range(-0.18,0.18))/m.f(fold)*m.tau;
      // its control points
      var c:[6]V3=undefined;
      rootPath(f.at,a,f.r*crownOut,f.reach*rng.range(0.8,1.1),0.3,f.seed+%i*41,&c);
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
/// how far out of the crown its roots leave (a share of `Foot.r`): under
/// the stems' flared feet, so they read as one root flare
const crownOut:f32=0.3;
/// `foot` on a structure: every root a branch growing with spline `id`
/// out of its start
pub fn footOn(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,f:Foot)Allocator.Error!void{
  // the foot's own seeded rng, so its green roots are its own
  var rng=Rng.init(f.seed);
  for(0..fold)|i|{
    // one root's control points, reused for the pale and then the green
    var c:[6]V3=undefined;
    rootPath(f.at,m.ratio(i,fold)*m.tau,f.r*crownOut,f.reach,0.25,f.seed^0x9A1E,&c);
    // the pale root's own branch, growing with the spline
    const paleRoot=k.branch(id,0,&c,.{.after=.with});
    try k.tube(b,paleRoot,.{.r0=f.rootR,.tip=0.04,.col=pearl,.sides=5,.t0=f.t,.t1=f.t+0.03});
    rootPath(f.at,(m.f(i)+0.5+rng.range(-0.18,0.18))/m.f(fold)*m.tau,f.r*crownOut,f.reach*rng.range(0.8,1.1),0.3,f.seed+%i*41,&c);
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
      for(0..fold)|i|{
        // this pale root's heading: fanned round the trunk's outer side, exact
        const a=a0+m.pi+(m.ratio(i,fold)-0.5)*2.2;
        // its control points
        var c:[6]V3=undefined;
        rootPath(base,a,radius*0.35,radius*3.4+0.05,0.2,seed^0x9A1E,&c);
        // its control points resampled smooth
        var p:[12]V3=undefined;
        m.splineResample(&c,&p);
        try taper(b,&p,radius*0.22,0.04,0,0.04,pearl,.stem,5);
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
    try weave(b,&sp,&ts,&sec,.{.form=.limb,.seed=seed^0xC0F,.skin=.{color.mix(tissueLow,pearl,0.65),color.mix(tissue,pearl,0.65)}});
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
