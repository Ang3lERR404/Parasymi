//! mesh: GANGLION. a parasite's brain: a bulbous foot half sunk in the
//! soil, a short stalk of the lineage's lattice parting round a sac on its
//! core, and on it a folded pale knot: two halves side by side, furrows
//! cut into each in fives, exactly alike, sculpted as one seamless surface
//! (engine gfx/sculpt.zig) of milky see-through cortex (part
//! `.cortex`, tu.y how deep in a furrow) where what it holds travels,
//! glowing (emitted: `held` beads and their `trail`s along `route`). Its
//! nerves out to the neighbours it feeds are its own (`nerve`, emitted per
//! side), branching as a neuron's, and pulses run out along them.
//! It grows on a hidden stalk (gfx/growth.zig): the foot swells and its
//! roots spread with it, the stalk rises and the knot's stem with it, then
//! both halves of the knot swell out of the stem's top together, alike,
//! furrows and all.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the test harness: expectations
const testing=std.testing;
/// the engine package: maths, colours, the sculptor, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// colour types: the held bead's white
const color=engine.core.color;
/// the sculptor: forms melted into one seamless surface
const sculpt=engine.gfx.sculpt;
/// the plant-piece mesher: braids, grown paths, the builder itself
const mg=lib.meshgen;
/// the garden's growth timing: the hidden stalk everything grows along
const growth=lib.growth;
/// the parasite kit: feet, roots, lattice stalks, bladders and its palette
const pk=lib.parasiteKit;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// the stalk's top, where the knot's stem rises from
const neck=v3(0,0.2,0);
/// how the lattice stalk is shaped: its girth, how far its strands part and
/// over which stretch of it (0..1) they open round the sac
const stalkShape:pk.Stalk=.{.girth=0.03,.part=2.0,.from=0.25,.to=0.88};
/// the knot's middle, where the folded brain sits on its stem
pub const brainAt=v3(0,0.335,0);
/// each half's half-sizes: across, up, and front to back
pub const halfR=v3(0.074,0.09,0.135);
/// how far each half's middle lies off the parting between them
const halfOff:f32=0.056;
/// how many long furrows run over each half, front to back, and how many
/// short ones branch off each: the lineage's fivefold, and three
const furrows=pk.fold;
/// (how many branch off each)
const spurs=3;
/// where round each half its first long furrow lies (radians from the top;
/// below zero toward the parting), and the step from one to the next down its side
const furrowFrom:f32=-0.5;
/// (the step)
const furrowStep:f32=0.56;
/// how far toward each pole the long furrows run (radians off the long
/// axis), every other one stopping this much short at its front or its back
const furrowEnd:f32=0.52;
/// (stopping short)
const furrowShort:f32=0.15;
/// how far a furrow wanders off its line, in its two waves (radians)
const wander=m.Vice(f32,2){0.13,0.05};
/// how many times each wave wanders over a long furrow's length
const waves=m.Vice(f32,2){5,12};
/// how far round a branching furrow reaches (radians), and how far it curls toward the back
const spurReach:f32=0.42;
/// (how far it curls)
const spurCurl:f32=0.12;
/// how far off each pole the two furrows curving round it lie (radians),
/// and how far each wanders toward it and away
const poleAt=m.Vice(f32,2){0.2,0.42};
/// (how far each wanders)
const poleWander=m.Vice(f32,2){0.04,0.08};
/// a furrow's girth, how far below the surface its middle runs, and how
/// deep a vertex lies on its floor (tu.y 1)
const furrowR:f32=0.0065;
/// (how far below)
const furrowSink:f32=0.0035;
/// (how deep its floor)
const furrowDeep:f32=0.008;
/// how many segments a long furrow, a branching one and a pole's are laid through
const segs=m.Vice(usize,3){24,6,12};
/// how softly the furrows are cut, so the folds between them swell round
const cutMelt:f32=0.006;
/// how far the two halves melt into one another, leaving the parting between them
const melt:f32=0.012;
/// how far the knot's stem melts into it
const stemMelt:f32=0.03;
/// the cell size the knot is meshed at, at full detail (doubling each coarser level)
const cell:f32=0.003;
/// the knot's pale tissue: the lineage's pearl
const tissue=pk.pearl;
/// how long the knot's halves take to swell, as a share of the stalk's growing
const swellTime:f32=1.4;
/// where the halves swell out of: this far below their middles, as a share of their height
const swellFrom:f32=0.6;
/// a vertex lying further than this above the knot's two cores is its
/// stem's, grown along the stalk (metres)
const stemOff:f32=0.012;
/// where on half `side` (-1 or 1) a point at `th` round it (radians from
/// its top) and `ph` along it (radians off the long axis, 0 its front) lies,
/// `sink` below its surface
fn onHalf(side:f32,th:f32,ph:f32,sink:f32)V3{
  // the half's middle, and the point on its surface
  const c=brainAt+v3(side*halfOff,0,0);
  const p=c+halfR*v3(side*@sin(th)*@sin(ph),@cos(th)*@sin(ph),@cos(ph));
  return p-m.norm(p-c)*m.splat3(sink);
}
/// the span along the long axis (radians, front to back) long furrow `i` runs
fn span(i:usize)m.Vice(f32,2){
  return.{furrowEnd+furrowShort*m.f(i%2),m.pi-furrowEnd-furrowShort*m.f((i+1)%2)};
}
/// how far round its half long furrow `i` lies at `ph` along it: wandering
/// off its line in two waves, each furrow exactly as the last, two fifths
/// of the way further through its waves (the lineage's even turn)
fn furrowTh(i:usize,ph:f32)f32{
  // its turn through the waves
  const turn=m.ratio(i,furrows)*m.tau*2;
  return furrowFrom+furrowStep*m.f(i)+wander[0]*@sin(waves[0]*ph+turn)+wander[1]*@sin(waves[1]*ph+turn*1.3);
}
/// long furrow `i` on half `side`, `sink` below the surface, front to back; fills `pts`
fn furrowPath(side:f32,i:usize,sink:f32,pts:[]V3)void{
  // the span it runs
  const sp=span(i);
  for(pts,0..)|*p,j|{
    // how far along it this point is (radians off the long axis)
    const ph=m.lerp(sp[0],sp[1],m.ratio(j,pts.len-1));
    p.*=onHalf(side,furrowTh(i,ph),ph,sink);
  }
}
/// branching furrow `j` off long furrow `i` on half `side`: out of it round
/// the half, up or down by turns, curling a little toward the back; fills `pts`
fn spurPath(side:f32,i:usize,j:usize,pts:[]V3)void{
  // where along the long furrow it leaves, and which way round it heads
  const sp=span(i);
  const ph0=m.lerp(sp[0],sp[1],(m.f(j)+0.5+0.15*m.f(i%2))/(spurs+0.3));
  const way:f32=if((i+j)%2==0)1 else-1;
  for(pts,0..)|*p,k|{
    // how far out along it this point is (0..1)
    const f=m.ratio(k,pts.len-1);
    const ph=ph0+spurCurl*f*f;
    p.*=onHalf(side,furrowTh(i,ph0)+way*spurReach*f,ph,furrowSink);
  }
}
/// furrow `ring` (0 the nearer) curving round half `side`'s pole (`pole`
/// -1 its front, 1 its back), `sink` below the surface, from beside the
/// parting down its side; fills `pts`
fn polePath(side:f32,pole:f32,ring:usize,sink:f32,pts:[]V3)void{
  for(pts,0..)|*p,j|{
    // how far round the half this point is (radians from its top)
    const th=m.lerp(furrowFrom+0.06,furrowFrom+furrowStep*(furrows-1)+0.15,m.ratio(j,pts.len-1));
    // how far off the pole: wandering toward it and away
    const off=poleAt[ring]+poleWander[ring]*@sin((4+2*m.f(ring))*th+m.f(ring));
    p.*=onHalf(side,th,if(pole<0)off else m.pi-off,sink);
  }
}
/// how far a point lies above the knot's two cores (metres; below zero inside them)
fn aboveCores(p:V3)f32{
  // the least height above either half found yet
  var h:f32=m.inf(f32);
  for([_]f32{-1,1})|side|{
    // the point from this half's middle, in the half's own unit sphere
    const d=p-(brainAt+v3(side*halfOff,0,0));
    const e=m.len(d/halfR);
    h=@min(h,(e-1)*m.len(d)/@max(e,1e-5));
  }
  return h;
}
/// the sculpt's one bone, which hangs from nothing
const noParent=[_]?u8{null};
/// builds the knot: the foot and roots, the lattice stalk and its sac, then
/// the folded brain sculpted from its forms; all hung on one growth
/// skeleton in that order
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the growth skeleton everything below is hung on
  var k=growth.Skeleton.begin(b);
  // the hidden stalk: from just under the ground up to the neck
  const stalk=k.trunk(&.{v3(0,-0.03,0),v3(0.012,0.08,-0.008),neck},.{.pace=1.6});
  try pk.foot(b,&k,stalk,v3(0,-0.01,0),v3(0.11,0.07,0.11));
  try pk.roots(b,&k,stalk,pk.fold,0.22,0.014,0x6A7);
  try pk.stalk(b,&k,stalk,stalkShape);
  try pk.organs(b,&k,stalk,stalkShape,1,0.6);
  try brain(b,&k,stalk);
  k.finish(b);
}
/// cuts a furrow through `pts` into the sculpt, narrowing toward its ends
fn cut(sc:*sculpt.Sculpt,pts:[]const V3)Allocator.Error!void{
  // the chain laid through its points
  var ch:sculpt.Chain=.{.n=@intCast(pts.len-1)};
  for(pts,0..)|p,j|{
    ch.pts[j]=p;
    ch.r[j]=furrowR*m.lerp(0.55,1,@sin(m.pi*m.ratio(j,pts.len-1)));
  }
  try sc.add(.{.shape=.{.chain=ch},.bone=0,.col=tissue,.k=cutMelt,.carve=true});
}
/// the folded knot on the stalk's top: two halves side by side, its
/// furrows cut into each (five long ones front to back, three branching
/// off each, one curving round each pole) so the folds between them swell
/// round, on the stem it sits on, meshed as one surface. The stem grows
/// out along the stalk; the halves then swell as one piece out of a line
/// low through their middles (as the kit's sacs and nodules swell out of a
/// point), both at once
fn brain(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id)Allocator.Error!void{
  // the sculpt, one bone holding every form
  var sc:sculpt.Sculpt=.{.gpa=b.gpa,.parents=&noParent,.io=b.io};
  defer sc.deinit();
  for([_]f32{-1,1})|side|try sc.add(.{.shape=.{.ellipsoid=.{.c=brainAt+v3(side*halfOff,0,0),.r=halfR}},.bone=0,.col=tissue,.k=melt});
  // the stem it sits on, flowing up out of the neck into its underside
  try sc.add(.{.shape=.{.cone=.{.a=neck-v3(0,0.015,0),.b=brainAt-v3(0,halfR[1]*0.45,0),.ra=0.026,.rb=0.05}},.bone=0,.col=pk.skin,.k=stemMelt});
  for([_]f32{-1,1})|side|{
    for(0..furrows)|i|{
      // the furrow's line under the surface
      var low:[segs[0]+1]V3=undefined;
      furrowPath(side,i,furrowSink,&low);
      try cut(&sc,&low);
      for(0..spurs)|j|{
        // a furrow branching off it
        var sp:[segs[1]+1]V3=undefined;
        spurPath(side,i,j,&sp);
        try cut(&sc,&sp);
      }
    }
    for([_]f32{-1,1})|pole|for(0..2)|ring|{
      // this furrow round the pole, under the surface
      var low:[segs[2]+1]V3=undefined;
      polePath(side,pole,ring,furrowSink,&low);
      try cut(&sc,&low);
    };
  }
  // where the knot's vertices begin
  const s=b.mark();
  try sc.mesh(mg.gen,b,cell*m.f(@as(u32,1)<<@intCast(b.lod)),0.5,.cortex);
  for(b.v.items[s..])|*vx|{
    // how deep in a furrow it lies: 0 on a fold's crown .. 1 on a furrow's floor
    vx.tu[1]=m.clamp01(-aboveCores(vx.pos)/furrowDeep);
  }
  // the stalk, when the halves begin to swell (once it is done) and how long they take
  const sp=k.get(stalk);
  const t0=k.done(stalk);
  const swell=sp.time*swellTime;
  for(b.v.items[s..],try b.growOf(s))|vx,*g|{
    if(aboveCores(vx.pos)>stemOff){
      // the stem: out of its nearest point on the stalk as the front passes
      const u=k.nearest(stalk,vx.pos);
      g.*=.{.from=k.point(stalk,u),.at=.{k.when(stalk,u),sp.time*sp.front,sp.start,t0}};
    }else{
      // a half: out of the line low through both middles (each half's
      // middle, the parting between them), so the two swell as one
      g.*=.{.from=brainAt+v3(m.clamp(vx.pos[0],-halfOff,halfOff),-halfR[1]*swellFrom,0),.at=.{t0,swell,0,0}};
    }
  }
}
/// how far round the knot's inner path the shapes it holds travel each
/// second (a share of the whole path)
pub const travel:f32=0.09;
/// the half-reach of that path: across, up and down, front to back
const routeR=v3(0.07,0.018,0.17);
/// where along the knot's inner path (`u`, 0..1 once round) what it holds
/// travels, in the knot's own space: a figure of eight through both halves,
/// crossing between them at the middle, rising there and dipping in each
pub fn route(u:f32)V3{
  // the angle round it
  const a=u*m.tau;
  return brainAt+v3(routeR[0]*@sin(a),routeR[1]*@cos(2*a),routeR[2]*@sin(a)*@cos(a));
}
/// mesh: GANGLION HELD. one thing the knot holds, travelling inside it: a
/// unit bead of light (`.bloom`), white so it takes its item's colour as
/// its tint, glowing; listed before the knot so its cortex blends over it
pub const held=struct{
  /// builds the bead: one unit sphere, scaled to size where it is placed
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(1,1,1),.col=heldCol,.part=.bloom,.rings=8,.segs=12,.t=0.5});
  }
  /// its colour before its tint: near white
  const heldCol=color.rgb(0.95,0.93,0.9).toRgba8(255);
};
/// mesh: GANGLION NERVE. a nerve from inside the knot out along +X to the
/// tile's edge, branching as a neuron's: a sheathed axon out of the knot's
/// underside arching low, parting in two, each part in two again, the four
/// fine twigs diving into the ground at the edge toward the neighbour it
/// feeds; its core (part `.core`, tu.x 0 in the knot .. 1 at every twig's
/// tip) carries a pulse of what it hands on (part.vert). It grows out
/// along its splines as it reaches (emitted with that as `grown`).
pub const nerve=struct{
  /// the axon, from inside the knot to where it parts
  const axon=[_]V3{v3(0.03,0.31,0),v3(0.09,0.285,0),v3(0.15,0.24,0),v3(0.21,0.18,0),v3(0.27,0.13,0),v3(0.31,0.105,0)};
  /// a part's way on from there (its first point moved onto the axon's
  /// end), on side `s` (-1 or 1) of the axon's line
  fn limb(s:f32)[4]V3{return.{v3(0.31,0.105,0),v3(0.35,0.085,0.03*s),v3(0.39,0.065,0.062*s),v3(0.42,0.05,0.078*s)};}
  /// a twig's way on from a part's end at `z`, on side `s` of it, into the ground
  fn twig(z:f32,s:f32)[4]V3{return.{v3(0.42,0.05,z),v3(0.46,0.03,z+0.03*s),v3(0.5,0.006,z+0.05*s),v3(0.54,-0.03,z+0.058*s)};}
  /// the axon's girth at its root, a part's, a twig's (each tapering to
  /// the next, a twig to a fine point)
  const girth=m.Vice(f32,3){0.014,0.0085,0.0055};
  /// whether a stretch is wrapped in a sheath of two pale strands (the axon) or bare
  const Sheath=enum{
    /// bare: a part or a twig
    bare,
    /// wrapped: the axon
    sheathed,
  };
  /// builds the nerve: the axon (sheathed in two pale strands), its two
  /// parts and four twigs, each its own branch flaring out of the last,
  /// every core lilac and tu.x running 0..1 from the knot to the tips
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the growth skeleton the nerve is hung on
    var k=growth.Skeleton.begin(b);
    // the axon's spline
    const id=k.trunk(&axon,.{});
    // each limb's spline, and each twig's off it
    var limbs:[2]growth.Id=undefined;
    var twigs:[4]growth.Id=undefined;
    for([_]f32{-1,1},0..)|s,i|{
      limbs[i]=k.branch(id,1,&limb(s),.{});
      for([_]f32{-1,1},0..)|t,j|twigs[i*2+j]=k.branch(limbs[i],1,&twig(0.078*s,t),.{});
    }
    // the whole run from the knot to a twig's tip
    const whole=k.get(id).len+k.get(limbs[0]).len+k.get(twigs[0]).len;
    // tu.x where each stretch begins and ends
    const at0=k.get(id).len/whole;
    const at1=at0+k.get(limbs[0]).len/whole;
    try core(b,&k,id,.{0,at0},.{girth[0],girth[1]},.sheathed);
    for(limbs)|l|try core(b,&k,l,.{at0,at1},.{girth[1],girth[2]},.bare);
    for(twigs)|t|try core(b,&k,t,.{at1,1},.{girth[2],girth[2]*0.25},.bare);
    k.finish(b);
  }
  /// one stretch of the nerve along spline `id`: its lilac core tapering
  /// over `r` (root, tip), tu.x running over `t`, flaring into the
  /// stretch it leaves; the axon (`sheath` sheathed) wrapped in two pale strands
  fn core(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,t:m.Vice(f32,2),r:m.Vice(f32,2),sheath:Sheath)Allocator.Error!void{
    // its path, its tu.x along it and its radius
    var sp:[growth.res]V3=undefined;
    var ts:[growth.res]f32=undefined;
    var rs:[growth.res]f32=undefined;
    k.path(id,0,1,&sp);
    for(&ts,&rs,0..)|*a,*rr,j|{
      // how far along this stretch the point is (0..1)
      const u=m.ratio(j,growth.res-1);
      a.*=m.lerp(t[0],t[1],u);
      rr.*=m.lerp(r[0],r[1],u)*switch(sheath){.sheathed=>1,.bare=>mg.collar(u)};
    }
    // where its vertices begin, so it all grows out along its spline
    const s=b.mark();
    try b.tubeR(&sp,&ts,&rs,pk.lilac,.core,6);
    if(sheath==.sheathed){
      // the sheath's radius: just wider than the core it wraps
      var wrap:[growth.res]f32=undefined;
      for(&wrap,rs)|*a,r0|a.*=r0*1.15;
      try mg.braid(b,&sp,&ts,&wrap,2,3.2,pk.wobble,0x6C1,pk.core,pk.pearl);
    }
    try k.along(b,s,id);
  }
};
test"the knot's furrows lie on its cores, its route inside them"{
  for([_]f32{-1,1})|side|for(0..furrows)|i|{
    // the furrow's line on the surface
    var pts:[segs[0]+1]V3=undefined;
    furrowPath(side,i,0,&pts);
    for(pts)|p|try testing.expect(aboveCores(p)<0.002);
  };
  for(0..64)|j|try testing.expect(aboveCores(route(m.ratio(j,64)))<-0.01);
}
