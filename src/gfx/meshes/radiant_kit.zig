//! the radiant (celestial) lineage's body, shared by its plants (`plant`,
//! the celestial bloom, the `radiant` form; `star`, the vesper, the `star`
//! form) and its structures (the diamond, `cut` + `shards`). A radiant thing is never grown: it is
//! gathered. It has no stem, no growth spline and nothing that swells or
//! scales up (a grounded one is held to its tile by a `root` of light,
//! struck down from its heart, never grown up from the soil); it is made of rigid fragments joined to nothing
//! (petals, threads, motes, facets), and each comes in from afar on its own
//! way, turning round the heart as it comes, and settles in its place in
//! its turn, the heart first, the last to close last. Once gathered it
//! hangs together by light alone (threads of it, `thread`), turning
//! slowly and drifting a little apart and back; it never bends from a root.
//!
//! Every vertex built here belongs to one fragment (`fragment`), which
//! carries to the shaders (common.glsl `fragmentOf`): tu.x its assembly
//! order (0 first .. 1 last), tu.y its `Ring` (a thread adds how far it is
//! from what it holds, `threadAmount`, so its heart end stays put), colour alpha
//! its bearing round the heart. The shaders gather it (common.glsl
//! `gatherAway`, `gatherIn`): plant.vert by the bloom's growth, part.vert
//! by how far its halo (or its own growing in) has come. A new radiant
//! thing is built from these pieces and gathered the same way, never with
//! the symbiotes' kits or the growth splines.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// checks a fragment's order and a cut's rows are in range
const assert=std.debug.assert;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, splines, angles
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// colour conversions, for paling petals toward white
const color=engine.core.color;
/// the vertex layout: the part role a cut is drawn as
const vertex=lib.vertex;
/// the species registry, whose genomes shape a bloom or a vesper
const species=lib.species;
/// the mineral kit: flat facets and small crystals for the diamond
const mineral=lib.mineralKit;
/// the engine's deterministic random stream
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// a vertex colour: four bytes, red, green, blue and alpha
const Rgba8=color.Rgba8;
/// what each fragment belongs to (tu.y): the shaders move each its own way
/// (plant.vert `SPIN` turns them by it). A radiant structure's body is its
/// `core`.
pub const Ring=enum(u8){
  /// the heart, and a radiant structure's whole body
  core,
  /// the innermost whorl of petals, an upright cup
  inner,
  /// the middle whorl (the vesper's star of rays)
  middle,
  /// the outer whorl, opening wide
  outer,
  /// the motes of light spiralling in
  motes,
  /// the thin ring of light round it all
  halo,
  /// living leaves floating beneath the heart
  leaves,
  /// beads of its yield held round the heart (part `.pod`, their bearing
  /// their place among its pods), swelling as it ripens
  yield,
  /// a grounded one's root of light, struck down from the heart into the
  /// soil: it never turns, and its soil end stays where it dug in
  root,
  /// cut crystal laid round a heart: a solcyriphon's flat lens of facets,
  /// a halcyra's crystal petals at its veil's edge
  facets,
  /// threads of light trailing loose beneath, as a jellyfish's (a
  /// solcyriphon's): drifting by day, drawn in under it by night
  trailing,
  /// a halcyra's see-through veil, hooding its flower like a jellyfish's bell
  veil,
  /// a halcyra's thread of light wound round the one plant it guards
  wound,
  /// the same thread opened into a net of light over the plants round it,
  /// when it stands alone
  net,
};
/// tu.y a thread adds at its heart end (0 at what it holds; common.glsl
/// `RADIANT_THREAD`)
pub const threadAmount:f32=0.9;
/// one rigid piece of a radiant thing: when it settles, which ring it
/// belongs to, and the way it comes in from
pub const Fragment=struct{
  /// when it settles among the rest: 0 the first .. 1 the last
  order:f32,
  /// which ring it belongs to, so the shaders move it with its kind
  ring:Ring,
  /// the way it lies from the heart (radians from +x toward +z), the way
  /// it comes in from
  bearing:f32=0,
  /// what its form tells the shaders of it besides (tu.z): which of an
  /// astrocyme's flowers it belongs to, how high a root strikes from
  aux:f32=0,
};
/// mark every vertex built since `start` as one fragment: tu.x takes its
/// order, tu.y its ring, tu.z its `aux`, colour alpha its bearing (0..255
/// round the heart)
pub fn fragment(b:*mg.Builder,start:usize,f:Fragment)void{
  assert(f.order>=0 and f.order<=1);
  // the bearing as a byte, a whole turn over 0..255
  const a:u8=@intFromFloat(@mod(f.bearing,m.tau)/m.tau*255);
  for(b.v.items[start..])|*v|{
    v.tu=.{f.order,m.f(@intFromEnum(f.ring)),f.aux};
    v.col.a=a;
  }
}
/// marks the vertices since `start` as held by a thread from `from` (its
/// heart end, which stays put) to `to` (what it holds): tu.y gains up to
/// `threadAmount`, most at `from`, none at `to`
fn holdAlong(b:*mg.Builder,start:usize,from:V3,to:V3)void{
  for(b.v.items[start..])|*v|{
    // how far along from the heart to what it holds this vertex lies, 0..1
    const along=m.clamp01(m.dot(v.pos-from,to-from)/m.dot(to-from,to-from));
    v.tu[1]+=(1-along)*threadAmount;
  }
}
/// a thread of light along a grown path, `r` at its thickest, tapering to a
/// point at both ends (not a fragment by itself: it belongs to what it
/// holds); returns its far end
pub fn thread(b:*mg.Builder,g:mg.Growth,r:f32,col:Rgba8)Allocator.Error!V3{
  // its control points, and the thread resampled smooth
  var ctrl:[6]V3=undefined;
  mg.growthPath(g,&ctrl);
  var path:[14]V3=undefined;
  m.splineResample(&ctrl,&path);
  try threadOn(b,&path,r,col);
  return path[13];
}
/// a thread of light along `path` (its points as they lie), `r` at its
/// thickest, tapering to a point at both ends
fn threadOn(b:*mg.Builder,path:[]const V3,r:f32,col:Rgba8)Allocator.Error!void{
  // each point's stamp and radius
  var ts:[m.maxSpline]f32=undefined;
  var radii:[m.maxSpline]f32=undefined;
  for(ts[0..path.len],radii[0..path.len],0..)|*t,*rr,j|{
    // how far along the thread, 0..1
    const k=m.ratio(j,path.len-1);
    t.*=k;
    // (sin pi is a hair below 0 in f32: clamp it, or the tip is NaN)
    rr.*=r*@sqrt(@max(0,@sin(m.pi*k)))+r*0.05;
  }
  try b.tubeR(path,ts[0..path.len],radii[0..path.len],col,.bloom,4);
}
/// a thread of light through the control points `ctrl` (a smooth curve
/// through them, resampled), `r` at its thickest, tapering at both ends
fn strand(b:*mg.Builder,ctrl:[]const V3,r:f32,col:Rgba8)Allocator.Error!void{
  // the curve, resampled smooth
  var path:[18]V3=undefined;
  m.splineResample(ctrl,&path);
  try threadOn(b,&path,r,col);
}
/// how the heart is made: its size, its colours, its stamens
pub const Core=struct{
  /// the bloom's radius (`Genome.bloomR`): everything is sized by it
  r:f32,
  /// the core's body colour
  body:Rgba8,
  /// the light of its nucleus, stamens and beads
  lite:Rgba8,
  /// stamens in its crown
  stamens:u32=7,
  /// the stamens' wander
  seed:u64,
};
/// the heart everything gathers to, the first fragment: a luminous core
/// and its nucleus, a little taller than wide, like a seed, with a crown of
/// stamens rising out of its top and arching out, each a thread of light
/// tipped with a bead of it (their roots sunk in the core)
pub fn core(b:*mg.Builder,c:Core,rng:*Rng)Allocator.Error!void{
  // the bloom's radius, and where the heart's vertices begin
  const radius=c.r;
  const s=b.mark();
  try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(radius*0.4,radius*0.48,radius*0.4),.col=c.body,.part=.bloom,.rings=6,.segs=8});
  try mg.ellipsoid(b,.{.center=v3(0,radius*0.04,0),.radii=m.splat3(radius*0.22),.col=c.lite,.part=.bloom,.rings=4,.segs=6});
  try stamens(b,.{.r=radius,.n=c.stamens,.lite=c.lite,.seed=c.seed},rng);
  fragment(b,s,.{.order=0,.ring=.core});
}
/// how a crown of stamens rises round a heart
pub const Stamens=struct{
  /// the heart's radius (a bloom's `bloomR`): they are sized by it
  r:f32,
  /// how many
  n:u32,
  /// their light
  lite:Rgba8,
  /// their wander
  seed:u64,
  /// how far out from the axis they root (a share of the radius)
  at:f32=0.12,
  /// how high they root (a share of the radius)
  y:f32=0.3,
  /// how long they are (a share of the radius): shortest and longest
  len:m.Vice(f32,2)=.{0.55,0.8},
  /// how far out they lean from upright (as a slope)
  lean:f32=0.55,
};
/// a crown of stamens rising out of a heart and arching out, each a thread
/// of light tipped with a bead of it (not a fragment: it belongs to the
/// heart it crowns)
pub fn stamens(b:*mg.Builder,c:Stamens,rng:*Rng)Allocator.Error!void{
  for(0..c.n)|i|{
    // this stamen's bearing, and the flat way out along it
    const a=m.ratio(i,c.n)*m.tau+rng.range(-0.2,0.2);
    const out=v3(@cos(a),0,@sin(a));
    // its root, sunk in the heart's top, and its length
    const from=out*m.splat3(c.r*c.at)+v3(0,c.r*c.y,0);
    const len=c.r*rng.range(c.len[0],c.len[1]);
    // the stamen's thread, and its far end where the bead sits
    const tip=try thread(b,.{.start=from,.direction=m.norm(out*m.splat3(c.lean)+v3(0,1,0)),.length=len,.wobble=0.3,.curl=0.08,.seed=c.seed+%i*13},c.r*0.03,c.lite);
    try mg.ellipsoid(b,.{.center=tip,.radii=m.splat3(c.r*0.06),.col=c.lite,.part=.bloom,.rings=3,.segs=5});
  }
}
/// how one whorl of floating petals is laid out round the heart
pub const Whorl=struct{
  /// how many petals
  n:u32,
  /// which ring its petals belong to
  ring:Ring,
  /// how far out from the heart its petals float (a share of the radius)
  at:f32,
  /// how high they float (a share of the radius; below the heart if negative)
  y:f32,
  /// a petal's length (a share of the radius)
  len:f32,
  /// a petal's width (a share of the radius)
  w:f32,
  /// how steeply a petal rises from its claw
  rise:f32,
  /// how far a petal flares back toward its tip
  flare:f32,
  /// how deeply a petal is cupped across
  cup:f32,
  /// the assembly orders its first and last petal settle at
  order:m.Vice(f32,2),
  /// turned half a petal on from the whorl inside it
  offset:bool=false,
  /// the petals' colour at their claws
  col:Rgba8,
  /// toward its tips, where the light inside it gathers
  tip:Rgba8,
};
/// a whorl of petals floating free round the heart, a gap off it, each its
/// own fragment held to the core by a thread of light from the core's
/// flank to its claw (`seed` its threads' wander)
pub fn whorl(b:*mg.Builder,radius:f32,wh:Whorl,lite:Rgba8,seed:u64,rng:*Rng)Allocator.Error!void{
  // the half-petal turn, if offset from the whorl inside
  const off=if(wh.offset)m.pi/m.f(wh.n)else 0;
  for(0..wh.n)|i|{
    // this petal's bearing, and the flat way out along it
    const a=m.ratio(i,wh.n)*m.tau+off+rng.range(-0.12,0.12);
    const out=v3(@cos(a),0,@sin(a));
    // its claw, floating free of the heart
    const base=out*m.splat3(radius*wh.at)+v3(0,radius*(wh.y+rng.range(-0.05,0.05)),0);
    // the fragment it is: its turn among the whorl's, its ring, its bearing
    const f:Fragment=.{.order=m.lerp(wh.order[0],wh.order[1],m.ratio(i,wh.n)),.ring=wh.ring,.bearing=a};
    // where its vertices begin
    const s=b.mark();
    try mg.petal(b,.{
      .base=base,.out=out,
      .len=radius*wh.len*rng.range(0.9,1.1),.width=radius*wh.w,
      .rise=wh.rise+rng.range(-0.1,0.1),.flare=wh.flare,.cup=wh.cup,
      .col=wh.col,.tip=wh.tip,.part=.leaf,
    });
    fragment(b,s,f);
    // the thread: from just inside the core's skin to just short of the claw
    try tether(b,out*m.splat3(radius*0.3)+v3(0,-radius*0.05,0),base-out*m.splat3(radius*0.04),radius*0.022,lite,seed+%i*7,f);
  }
}
/// a thread of light from the heart (`from`) to what it holds (`to`), part
/// of that fragment, its heart end marked to stay with the core: tu.y
/// gains up to `threadAmount`, most at the heart end, none at `to`
fn tether(b:*mg.Builder,from:V3,to:V3,r:f32,lite:Rgba8,seed:u64,f:Fragment)Allocator.Error!void{
  // where the thread's vertices begin
  const s=b.mark();
  _=try thread(b,.{.start=from,.direction=m.norm(to-from),.length=m.dist(to,from),.wobble=0.25,.curl=0.1,.seed=seed},r,lite);
  fragment(b,s,f);
  holdAlong(b,s,from,to);
}
/// how the leaves floating beneath the heart are laid out
pub const Leaves=struct{
  /// how many leaves
  n:u32,
  /// how far out from under the heart they float (a share of the radius)
  at:f32,
  /// how far below the heart they float (a share of the radius)
  y:f32,
  /// a leaf's length (as a blade's, not a share)
  len:f32,
  /// a leaf's half-width (as a blade's, not a share)
  w:f32,
  /// how far a leaf droops to its tip (as a blade's)
  droop:f32,
  /// the assembly orders its first and last leaf settle at
  order:m.Vice(f32,2),
  /// the leaves' colour at their bases
  col:Rgba8,
  /// the colour they turn to at their tips
  tip:Rgba8,
};
/// leaves floating free beneath the heart, each its own fragment, lifting
/// a little and drooping to their tips, held up to the core's underside by
/// a thread of light (a gathered thing may carry living leaves; nothing
/// roots them)
pub fn leaves(b:*mg.Builder,radius:f32,l:Leaves,lite:Rgba8,seed:u64,rng:*Rng)Allocator.Error!void{
  for(0..l.n)|i|{
    // this leaf's bearing, and the flat way out along it
    const a=m.ratio(i,l.n)*m.tau+rng.range(-0.15,0.15);
    const out=v3(@cos(a),0,@sin(a));
    // its base, floating under the heart
    const base=out*m.splat3(radius*l.at)+v3(0,-radius*(l.y+rng.range(-0.15,0.15)),0);
    // the fragment it is
    const f:Fragment=.{.order=m.lerp(l.order[0],l.order[1],m.ratio(i,l.n)),.ring=.leaves,.bearing=a};
    // where its vertices begin
    const s=b.mark();
    try mg.blade(b,base,m.norm(out+v3(0,0.3,0)),l.len*rng.range(0.85,1.1),l.w,l.droop,l.col,l.tip,1,.leaf);
    fragment(b,s,f);
    try tether(b,out*m.splat3(radius*0.12)+v3(0,-radius*0.4,0),base-out*m.splat3(radius*0.05),radius*0.018,lite,seed+%i*11,f);
  }
}
/// how a grounded radiant plant's root of light is laid out under its heart
pub const Root=struct{
  /// how many strands fan out round the taproot
  n:u32,
  /// how far below the heart the soil lies (its `stemH`)
  depth:f32,
  /// how far out the strands dig in (a share of the radius)
  spread:f32,
  /// how deep under the soil they reach
  sink:f32,
  /// the assembly orders its first and last strand settle at
  order:m.Vice(f32,2),
  /// the strands' light
  col:Rgba8,
  /// the shards where they dig in: at their foot, and paling to their point
  shard:Rgba8,
  /// toward the shards' points
  tip:Rgba8,
  /// how high over the soil it strikes down from as it gathers (m; 0: the
  /// vesper's height, plant.vert `ROOT_STRIKE`)
  strike:f32=0,
};
/// a root of light holding a grounded radiant plant to its tile: a taproot
/// straight down from the heart's underside into the soil and a fan of
/// strands round it, each a thread of light tapering to points, its heart
/// end staying with the core; where a strand digs in, a small shard of
/// crystal stands out of the soil, leaning away. Each strand (and its
/// shard) is its own fragment on ring `.root`: it strikes down out of the
/// heart as it gathers (plant.vert) and never turns once in
pub fn root(b:*mg.Builder,radius:f32,r:Root,seed:u64,rng:*Rng)Allocator.Error!void{
  // the heart's underside, where every strand leaves it
  const from=v3(0,-radius*0.4,0);
  for(0..r.n+1)|i|{
    // the taproot first (straight down), then the strands on their bearings
    const tap=i==0;
    const a=if(tap)0 else m.ratio(i-1,r.n)*m.tau+rng.range(-0.2,0.2);
    const out=v3(@cos(a),0,@sin(a));
    // where it digs in at the soil, and where it ends under it
    const at=if(tap)m.splat3(0)else out*m.splat3(radius*r.spread*rng.range(0.8,1.15));
    const to=at+out*m.splat3(if(tap)0 else radius*0.25)+v3(0,-r.depth-r.sink*(if(tap)1.4 else rng.range(0.8,1.1)),0);
    // the fragment it is: its turn striking down, its bearing
    const f:Fragment=.{.order=m.lerp(r.order[0],r.order[1],m.ratio(i,r.n)),.ring=.root,.bearing=a,.aux=r.strike};
    try tether(b,from,to,radius*(if(tap)0.05 else rng.range(0.028,0.038)),r.col,seed+%i*19,f);
    if(tap)continue;
    // a shard of crystal where it digs in, leaning out
    const s=b.mark();
    try mineral.crystal(b,.{
      .base=at+v3(0,-r.depth,0),.dir=m.norm(out*m.splat3(0.7)+v3(0,1,0)),
      .len=radius*rng.range(0.28,0.4),.r=radius*rng.range(0.06,0.08),.sides=5,.col=r.shard,.tip=r.tip,
    },rng);
    fragment(b,s,f);
  }
}
/// motes of light, each its own fragment on its own bearing, waiting to
/// spiral in to the heart (the shaders carry them in and fade them as they
/// are taken up, over and over)
pub fn motes(b:*mg.Builder,radius:f32,n:u32,col:Rgba8,rng:*Rng)Allocator.Error!void{
  for(0..n)|i|{
    // this mote's bearing, and where its vertices begin
    const a=m.ratio(i,n)*m.tau+rng.range(-0.3,0.3);
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=v3(@cos(a),0,@sin(a))*m.splat3(radius*0.5),.radii=m.splat3(radius*rng.range(0.04,0.07)),.col=col,.part=.bloom,.rings=3,.segs=4});
    fragment(b,s,.{.order=m.ratio(i,n),.ring=.motes,.bearing=a});
  }
}
/// a thin ring of light round it all, `r` out, `thick` its radius, tilted
/// `tilt` radians: the last to close (`order`)
pub fn halo(b:*mg.Builder,r:f32,thick:f32,tilt:f32,order:f32,col:Rgba8)Allocator.Error!void{
  // where the ring's vertices begin
  const s=b.mark();
  // its points and stamps
  var ring:[25]V3=undefined;
  var ts:[25]f32=undefined;
  for(&ring,&ts,0..)|*p,*t,j|{
    // the bearing round the ring, and the point there before the tilt
    const a=m.ratio(j,24)*m.tau;
    const q=v3(@cos(a)*r,0,@sin(a)*r);
    p.*=v3(q[0],q[1]*@cos(tilt)-q[2]*@sin(tilt),q[1]*@sin(tilt)+q[2]*@cos(tilt));
    t.*=1;
  }
  try b.tube(&ring,&ts,thick,thick,col,.bloom,4);
  fragment(b,s,.{.order=order,.ring=.halo});
}
/// sides of a `cut` crystal
pub const cutSides=8;
/// how a cut crystal is shaped: its rows, and its deep and lit colours
pub const Cut=struct{
  /// rows from its bottom point to its top one: height, radius, twist (in
  /// half sides; a row half a side on from the next staggers the facets
  /// between them); a point is a row of radius 0
  rows:[]const m.Vice(f32,3),
  /// rows below this are `deep`, the rest `lite`
  deepRows:usize,
  /// the colour of its deep lower rows
  deep:Rgba8,
  /// the colour of its lit upper rows
  lite:Rgba8,
  /// the part role it is drawn as: a prism by default
  part:vertex.Part=.prism,
};
/// a cut crystal: rows of points round its axis, faced flat between each
/// pair, each face a little uneven like a grown one. Every facet is a
/// fragment of its own, gathered from the bottom point up to the top one,
/// coming in from the way it faces; each row's facets in turn round it.
pub fn cut(b:*mg.Builder,c:Cut,rng:*Rng)Allocator.Error!void{
  // sides round each row
  const sides=cutSides;
  assert(c.rows.len>=2 and c.rows.len<=maxRows);
  // every row's points round the axis
  var pts:[maxRows][sides]V3=undefined;
  for(c.rows,pts[0..c.rows.len])|rg,*row|for(row,0..)|*p,i|{
    // this point's bearing (twisted by the row), and its uneven radius
    const a=(m.f(i)+rg[2]*0.5)/sides*m.tau;
    const r=rg[1]*rng.range(0.92,1.08);
    p.*=v3(@cos(a)*r,rg[0]+rng.range(-0.006,0.006)*@min(1,rg[1]*20),@sin(a)*r);
  };
  // a point inside, for facing the faces out, and the spans between rows
  const inside=v3(0,0.01,0);
  const spans=c.rows.len-1;
  for(0..spans)|k|{
    // this span's lower and upper rows
    const lo=pts[k];
    const hi=pts[k+1];
    // and their colours, deep or lit
    const cl=if(k<c.deepRows)c.deep else c.lite;
    const ch=if(k+1<c.deepRows)c.deep else c.lite;
    // a point is a ring of one place: the faces along it vanish
    const lo0=c.rows[k][1]==0;
    const hi0=c.rows[k+1][1]==0;
    for(0..sides)|i|{
      // the next point round
      const j=(i+1)%sides;
      // the fragment this facet pair is: its turn up the crystal, its bearing
      const f:Fragment=.{.order=cutShare*(m.f(k)+m.ratio(i,sides))/m.f(spans),.ring=.core,.bearing=(m.f(i)+0.5)/sides*m.tau};
      // where its vertices begin
      const s=b.mark();
      // the upper row sits half a side on: stagger between them
      if(c.rows[k+1][2]>c.rows[k][2]){
        if(!lo0)try mineral.facet(b,.{lo[i],lo[j],hi[i]},inside,.{cl,cl,ch},0,c.part);
        if(!hi0)try mineral.facet(b,.{hi[i],lo[j],hi[j]},inside,.{ch,cl,ch},0,c.part);
      }else{
        if(!hi0)try mineral.facet(b,.{lo[i],hi[j],hi[i]},inside,.{cl,ch,ch},0,c.part);
        if(!lo0)try mineral.facet(b,.{lo[i],lo[j],hi[j]},inside,.{cl,cl,ch},0,c.part);
      }
      fragment(b,s,f);
    }
  }
}
/// the most rows a cut may have
const maxRows=12;
/// the share of the assembly order a cut's own facets take; shards grown
/// out of it come after
const cutShare:f32=0.8;
/// `n` small crystals grown out of a cut one at its foot (`at` below its
/// heart), leaning away, in its colours, each a fragment settling after
/// its facets
pub fn shards(b:*mg.Builder,n:u32,at:f32,c:Cut,rng:*Rng)Allocator.Error!void{
  for(0..n)|i|{
    // this shard's bearing, and where its vertices begin
    const a=(m.f(i)+rng.range(-0.15,0.15))/m.f(n)*m.tau+0.4;
    const s=b.mark();
    try mineral.crystal(b,.{
      .base=v3(@cos(a)*0.05,at,@sin(a)*0.05),
      .dir=m.norm(v3(@cos(a)*0.9,0.6,@sin(a)*0.9)),
      .len=rng.range(0.12,0.17),.r=rng.range(0.022,0.03),.col=c.deep,.tip=c.lite,.part=c.part,
    },rng);
    fragment(b,s,.{.order=m.lerp(cutShare,1,m.ratio(i+1,n)),.ring=.core,.bearing=a});
  }
}
/// a celestial bloom (the `radiant` form): a flower whose petals are not
/// joined to it. Its `core` holds three whorls of petals floating free
/// round it (an upright inner cup, a middle whorl, an outer one opening
/// wide), each bound to it by a thread of light, and motes of light
/// spiralling in to it; a thin tilted `halo` rings it all. The origin is
/// the core.
pub fn plant(b:*mg.Builder,g:species.Genome,seed:u64,variant:u32)Allocator.Error!void{
  // the bloom's own random stream
  var rng=Rng.init(seed);
  // the body's colour, and the light it holds
  const body=g.stemCol.toRgba8(255);
  const lite=g.bloomCol.toRgba8(255);
  // petals pale toward their tips, where the light inside them gathers
  const pale=color.mix(lite,color.rgb(1,1,1).toRgba8(255),0.6);
  // the bloom's radius, which everything is sized by
  const radius=g.bloomR;
  try core(b,.{.r=radius,.body=body,.lite=lite,.seed=seed},&rng);
  // the whorls, innermost first, each turned half a petal on from the last
  const whorls=[_]Whorl{
    .{.n=5,.ring=.inner,.at=0.62,.y=-0.05,.len=1.0,.w=0.26,.rise=1.3,.flare=0.5,.cup=0.7,.order=.{0.12,0.3},.col=lite,.tip=pale},
    .{.n=6+variant%2,.ring=.middle,.at=1.1,.y=-0.2,.len=1.25,.w=0.3,.rise=0.95,.flare=0.6,.cup=0.6,.order=.{0.3,0.55},.offset=true,.col=body,.tip=pale},
    .{.n=8+variant%2,.ring=.outer,.at=1.6,.y=-0.4,.len=1.4,.w=0.28,.rise=0.6,.flare=0.7,.cup=0.5,.order=.{0.5,0.8},.col=body,.tip=pale},
  };
  for(whorls,0..)|wh,k|try whorl(b,radius,wh,lite,seed+%k*97,&rng);
  try motes(b,radius,9,lite,&rng);
  try halo(b,radius*1.55,radius*0.025,0.35,0.95,lite);
}
/// the vesper (the `star` form): an evening star's flower, the radiant body
/// brought down to hang `stemH` over its tile, held to it by a `root` of
/// light struck down into the soil. Its
/// `core` (dusk violet, gold light, five stamens) holds a small upright cup
/// of petals and, turned half a petal on, a star of long narrow rays lying
/// open round it; beneath, `leaves` float free (it was spliced from both
/// lineages' herbs). Motes come in to it; no halo (that is the sky
/// bloom's). The origin is its tile; plant.vert brings each piece down to
/// it out of the sky.
pub fn star(b:*mg.Builder,g:species.Genome,seed:u64,variant:u32)Allocator.Error!void{
  // the vesper's own random stream
  var rng=Rng.init(seed);
  // the body's dusk colour, its gold light, and the pale petal tips
  const body=g.stemCol.toRgba8(255);
  const lite=g.bloomCol.toRgba8(255);
  const pale=color.mix(lite,color.rgb(1,1,1).toRgba8(255),0.55);
  // the bloom's radius, and where its vertices begin (to lift them all)
  const radius=g.bloomR;
  const start=b.mark();
  try core(b,.{.r=radius,.body=body,.lite=lite,.stamens=5,.seed=seed},&rng);
  // the cup, then the star of rays
  const whorls=[_]Whorl{
    .{.n=g.petals,.ring=.inner,.at=0.55,.y=0.02,.len=0.85,.w=0.24,.rise=1.25,.flare=0.45,.cup=0.7,.order=.{0.1,0.24},.col=lite,.tip=pale},
    // the star: long narrow rays lying nearly open, paling to gold points
    .{.n=g.petals,.ring=.middle,.at=0.95,.y=-0.12,.len=2.3+0.25*m.f(variant%2),.w=0.17,.rise=0.3,.flare=0.15,.cup=0.35,.order=.{0.28,0.55},.offset=true,.col=body,.tip=lite},
  };
  for(whorls,0..)|wh,k|try whorl(b,radius,wh,lite,seed+%k*97,&rng);
  // the leaves' colour
  const lc=g.leafCol.toRgba8(255);
  try leaves(b,radius,.{
    .n=g.leaves,.at=1.0,.y=1.6,.len=g.leafLen,.w=g.leafW,.droop=g.leafDroop,
    .order=.{0.6,0.85},.col=lc,.tip=color.mix(lc,body,0.5),
  },lite,seed+%0x1EAF,&rng);
  try motes(b,radius,7,lite,&rng);
  // its root of light, struck down into its tile just after the heart lands
  try root(b,radius,.{
    .n=5,.depth=g.stemH,.spread=0.9,.sink=0.08,.order=.{0.03,0.09},
    .col=lite,.shard=body,.tip=pale,
  },seed+%0x5007,&rng);
  // its yield: beads of light held round its core, the last to settle
  for(0..g.pods)|k|{
    // this bead's bearing (its place among the pods, which the shaders
    // read back), and where its vertices begin
    const a=(m.f(k)+0.5)/m.f(g.pods)*m.tau;
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=v3(@cos(a),0.2,@sin(a))*m.splat3(radius*0.62),.radii=m.splat3(g.podR),.col=lite,.part=.pod,.rings=5,.segs=7});
    fragment(b,s,.{.order=m.lerp(0.88,0.98,m.ratio(k,@max(g.pods,1))),.ring=.yield,.bearing=a});
  }
  b.xform(start,m.translate(v3(0,g.stemH,0)));
}
/// how a flat ring of crystal facets lies round a heart
pub const Lens=struct{
  /// how many segments round it
  n:u32,
  /// where its inner edge lies out from the heart (a share of the radius)
  inner:f32,
  /// where its outer edge lies (a share of the radius)
  outer:f32,
  /// how far its ridge stands proud of it, above and below (a share of the radius)
  thick:f32,
  /// how high it lies (a share of the radius)
  y:f32,
  /// the assembly orders its first and last segment settle at
  order:m.Vice(f32,2),
  /// the colour along its inner edge, nearest the heart's light
  lite:Rgba8,
  /// the colour along its outer edge
  deep:Rgba8,
};
/// the share of each lens segment's arc left open before the next
const lensGap:f32=0.1;
/// a flat ring of crystal facets laid round the heart (a solcyriphon's
/// lens): `n` segments, each a flat gem cut to a ridge above and below,
/// floating a hair apart from the next, its own fragment (ring `.facets`)
/// held to the heart by a thread of light (`lite`)
pub fn lens(b:*mg.Builder,radius:f32,l:Lens,lite:Rgba8,seed:u64)Allocator.Error!void{
  // how far out its inner and outer edges lie, how high it lies, and where its ridge runs
  const ri=radius*l.inner;
  const ro=radius*l.outer;
  const y=radius*l.y;
  const rm=m.lerp(ri,ro,0.45);
  // each girdle corner's colour: the inner two lit, the outer two deep
  const cols=[4]Rgba8{l.lite,l.lite,l.deep,l.deep};
  for(0..l.n)|i|{
    // the segment's arc, and the bearing of its middle
    const a0=(m.f(i)+lensGap*0.5)/m.f(l.n)*m.tau;
    const a1=(m.f(i)+1-lensGap*0.5)/m.f(l.n)*m.tau;
    const mid=(m.f(i)+0.5)/m.f(l.n)*m.tau;
    // its corners round its girdle: inner two, then outer two
    const corner=[4]V3{
      v3(@cos(a0)*ri,y,@sin(a0)*ri),v3(@cos(a1)*ri,y,@sin(a1)*ri),
      v3(@cos(a1)*ro,y,@sin(a1)*ro),v3(@cos(a0)*ro,y,@sin(a0)*ro),
    };
    // its ridge's middle, and the two points over and under it it is cut to
    const ridge=v3(@cos(mid)*rm,y,@sin(mid)*rm);
    const apexes=[2]V3{ridge+v3(0,radius*l.thick,0),ridge-v3(0,radius*l.thick,0)};
    // the fragment it is, and where its vertices begin
    const f:Fragment=.{.order=m.lerp(l.order[0],l.order[1],m.ratio(i,l.n)),.ring=.facets,.bearing=mid};
    const s=b.mark();
    for(apexes)|apex|for(0..4)|k|{
      // the next corner round
      const j=(k+1)%4;
      try mineral.facet(b,.{corner[k],corner[j],apex},ridge,.{cols[k],cols[j],l.lite},0,.prism);
    };
    fragment(b,s,f);
    // the way out to it, and the thread holding it from the heart's flank to its inner edge
    const out=v3(@cos(mid),0,@sin(mid));
    try tether(b,out*m.splat3(radius*0.3),out*m.splat3(ri*0.97)+v3(0,y,0),radius*0.02,lite,seed+%i*23,f);
  }
}
/// how threads of light trail loose beneath a heart, as a jellyfish's
pub const Trail=struct{
  /// how many threads
  n:u32,
  /// how far out from under the heart they hang from (a share of the radius)
  at:f32,
  /// how far below the heart they leave it (a share of the radius)
  y:f32,
  /// their shortest and longest (shares of the radius)
  len:m.Vice(f32,2),
  /// a thread's thickest radius (a share of the radius)
  r:f32,
  /// beads of light strung down each
  beads:u32,
  /// the assembly orders the first and last thread settle at
  order:m.Vice(f32,2),
  /// their light
  col:Rgba8,
};
/// threads of light trailing loose beneath the heart, as a jellyfish's:
/// each leaves from under it and falls, wandering a little, beads of light
/// strung down it, smaller toward its tip; each its own fragment (ring
/// `.trailing`) held at its top (tu.y says how far down it a vertex lies)
pub fn trailing(b:*mg.Builder,radius:f32,tr:Trail,seed:u64,rng:*Rng)Allocator.Error!void{
  for(0..tr.n)|i|{
    // this thread's bearing and the flat way out along it, where it leaves the heart and how far it falls
    const a=m.ratio(i,tr.n)*m.tau+rng.range(-0.25,0.25);
    const out=v3(@cos(a),0,@sin(a));
    const from=out*m.splat3(radius*tr.at*rng.range(0.55,1.1))-v3(0,radius*tr.y,0);
    const len=radius*rng.range(tr.len[0],tr.len[1]);
    // its path, wandering down, resampled smooth
    var ctrl:[6]V3=undefined;
    mg.growthPath(.{.start=from,.direction=m.norm(out*m.splat3(0.12)-v3(0,1,0)),.length=len,.wobble=0.3,.curl=0.12,.seed=seed+%i*29},&ctrl);
    var path:[24]V3=undefined;
    m.splineResample(&ctrl,&path);
    // where its vertices begin
    const s=b.mark();
    try threadOn(b,&path,radius*tr.r,tr.col);
    for(0..tr.beads)|k|{
      // how far down it this bead hangs
      const along=(m.f(k)+0.6)/m.f(tr.beads+1);
      try mg.ellipsoid(b,.{.center=m.alongPath(&path,along),.radii=m.splat3(radius*tr.r*(2.6-1.4*along)),.col=tr.col,.part=.bloom,.rings=3,.segs=5});
    }
    fragment(b,s,.{.order=m.lerp(tr.order[0],tr.order[1],m.ratio(i,tr.n)),.ring=.trailing,.bearing=a});
    holdAlong(b,s,from,path[path.len-1]);
  }
}
/// how a broad crystal petal is cut
pub const CrystalPetal=struct{
  /// where its claw sits
  base:V3,
  /// the way it points from its claw (unit)
  dir:V3,
  /// the way its broad face looks (unit, square to `dir`)
  face:V3,
  /// claw to tip
  len:f32,
  /// its widest half-width
  w:f32,
  /// how far its ridge stands proud on either face
  thick:f32,
  /// its colour at the claw
  col:Rgba8,
  /// at its shoulders and tip, where the light gathers
  tip:Rgba8,
};
/// a broad crystal petal: a flat gem cut to a ridge on either face, a
/// lozenge from its claw through two shoulders (widest past its middle) to
/// its tip; eight flat facets, closed (part `.prism`; not a fragment by
/// itself)
pub fn crystalPetal(b:*mg.Builder,c:CrystalPetal)Allocator.Error!void{
  // the way across it
  const side=m.norm(m.cross(c.dir,c.face));
  // its claw, shoulders and tip round its girdle
  const girdle=[4]V3{
    c.base,c.base+c.dir*m.splat3(c.len*0.6)+side*m.splat3(c.w),
    c.base+c.dir*m.splat3(c.len),c.base+c.dir*m.splat3(c.len*0.6)-side*m.splat3(c.w),
  };
  // each girdle point's colour, and the middle its ridge rises over
  const cols=[4]Rgba8{c.col,c.tip,c.tip,c.tip};
  const mid=c.base+c.dir*m.splat3(c.len*0.55);
  for([2]f32{1,-1})|sd|for(0..4)|k|{
    // the next girdle point round
    const j=(k+1)%4;
    try mineral.facet(b,.{girdle[k],girdle[j],mid+c.face*m.splat3(c.thick*sd)},mid,.{cols[k],cols[j],c.tip},0,.prism);
  };
}
/// where a `petal` laid from `base` along `out` ends (its spine's tip),
/// `len` long, rising `rise` and flaring `flare` as meshgen lays it
fn petalTip(base:V3,out:V3,len:f32,rise:f32,flare:f32)V3{
  // the tip so far, walked row by row as the petal is
  var p=base;
  for(1..10)|i|{
    // the angle this row climbs at
    const h=rise-flare*m.pow(f32,m.ratio(i,9),2);
    p+=(out*m.splat3(@cos(h))+v3(0,@sin(h),0))*m.splat3(len/9);
  }
  return p;
}
/// how far a halcyra leans over the plant it guards (radians from upright,
/// about its foot; plant.vert `VEIL_LEAN`, must match)
pub const veilLean:f32=0.5;
/// where the plant a halcyra guards stands as its wound thread is built:
/// this far off along +x (m; plant.vert carries it on to where that plant
/// truly stands)
pub const veilReach:f32=1;
/// a halcyra's thread of light wound round the plant beside it: out of its
/// leaning heart (`heart`, mesh space) it arcs over to that plant (as
/// built, `veilReach` off along +x) and winds down round it, nearly to the
/// ground; one fragment (ring `.wound`), held at the heart
pub fn woundThread(b:*mg.Builder,heart:V3,lite:Rgba8,order:f32)Allocator.Error!void{
  // how high the winding starts and ends, how far round the plant it lies, and how many turns
  const top:f32=0.9;
  const low:f32=0.12;
  const r:f32=0.15;
  const turns:f32=2.6;
  // the arc's points, then the winding's
  const arc=10;
  const coil=44;
  var path:[arc+coil]V3=undefined;
  // where the winding begins (on the side toward the heart)
  const first=v3(veilReach-r,top,0);
  for(path[0..arc],0..)|*p,j|{
    // how far along the arc, and how high it bows over
    const k=m.ratio(j,arc);
    p.*=m.lerpV(heart,first,k)+v3(0,0.22*@sin(m.pi*k),0);
  }
  for(path[arc..],0..)|*p,j|{
    // how far down the winding, and its bearing round the plant
    const k=m.ratio(j,coil-1);
    const a=m.pi+k*turns*m.tau;
    p.*=v3(veilReach+@cos(a)*r,m.lerp(top,low,k),@sin(a)*r);
  }
  // where its vertices begin
  const s=b.mark();
  try threadOn(b,&path,0.012,lite);
  fragment(b,s,.{.order=order,.ring=.wound});
  holdAlong(b,s,heart,path[path.len-1]);
}
/// a lone halcyra's net: how far it reaches (m) and how high it hangs over
/// the ground (m) near its middle, sinking a little toward its rim
const netReach:f32=2.2;
/// (how high it hangs)
const netHigh:f32=1.1;
/// (how far its rim sinks below that)
const netSink:f32=0.2;
/// its threads out from the heart
const netSpokes=8;
/// its rings round, as shares of its reach
const netRings=[2]f32{0.5,0.96};
/// how high the net hangs `d` metres out from its middle
fn netAt(d:f32)f32{return netHigh-netSink*m.pow(f32,d/netReach,2);}
/// a halcyra's thread of light opened into a net over the plants round it
/// (when it guards no plant beside it): spokes rising out of its heart
/// (`heart`, mesh space) and spreading over them, rings of light strung
/// between, sagging a little, a bead where they cross; each thread its own
/// fragment (ring `.net`), settling over `order`
pub fn net(b:*mg.Builder,heart:V3,radius:f32,lite:Rgba8,order:m.Vice(f32,2))Allocator.Error!void{
  // threads in all, and the one being laid
  const total=netSpokes*(1+netRings.len);
  var n:usize=0;
  for(0..netSpokes)|k|{
    // this spoke's bearing, the flat way out along it, and where it ends
    const a=m.ratio(k,netSpokes)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    const end=out*m.splat3(netReach)+v3(0,netAt(netReach),0);
    // where its vertices begin
    const s=b.mark();
    try strand(b,&.{heart+v3(0,radius*0.5,0),out*m.splat3(0.3)+v3(0,netAt(0.3)-0.08,0),out*m.splat3(0.9)+v3(0,netAt(0.9),0),out*m.splat3(1.6)+v3(0,netAt(1.6),0),end},0.007,lite);
    fragment(b,s,.{.order=m.lerp(order[0],order[1],m.ratio(n,total)),.ring=.net,.bearing=a});
    holdAlong(b,s,heart,end);
    n+=1;
  }
  for(netRings)|share|for(0..netSpokes)|k|{
    // the two spokes it runs between, and how far out
    const a0=m.ratio(k,netSpokes)*m.tau;
    const a1=m.ratio(k+1,netSpokes)*m.tau;
    const d=netReach*share;
    // where it leaves the one spoke, sags between and meets the next
    const p0=v3(@cos(a0)*d,netAt(d),@sin(a0)*d);
    const p1=v3(@cos(a1)*d,netAt(d),@sin(a1)*d);
    const sag=m.lerpV(p0,p1,0.5)-v3(0,0.07,0);
    // where its vertices begin
    const s=b.mark();
    try strand(b,&.{p0,m.lerpV(p0,sag,0.55),sag,m.lerpV(p1,sag,0.55),p1},0.005,lite);
    try mg.ellipsoid(b,.{.center=p0,.radii=m.splat3(0.022),.col=lite,.part=.bloom,.rings=3,.segs=5});
    fragment(b,s,.{.order=m.lerp(order[0],order[1],m.ratio(n,total)),.ring=.net,.bearing=(a0+a1)*0.5});
    n+=1;
  };
}
/// the solcyriphon (the `lens` form): a lens, a flower facing up and a
/// touch of jellyfish, hung high. Its heart burns gold in a flat ring of
/// crystal facets (`lens`); two whorls of broad petals rise round the
/// lens, open to the sky; threads of light hung with beads trail loose
/// beneath (`trailing`), and motes of light are spread out round it.
/// plant.vert folds it by how dark it is: by night the petals close up
/// tight, the threads draw in under the lens and the heart burns smaller
/// and brighter (the beam it pours is the view's). The origin is the heart.
pub fn solcyriphon(b:*mg.Builder,g:species.Genome,seed:u64,variant:u32)Allocator.Error!void{
  // its own random stream
  var rng=Rng.init(seed);
  // its pearl, its paler petals, its gold light, and white
  const body=g.stemCol.toRgba8(255);
  const leaf=g.leafCol.toRgba8(255);
  const lite=g.bloomCol.toRgba8(255);
  const white=color.rgb(1,1,1).toRgba8(255);
  // petals and facets pale toward white where the light gathers
  const pale=color.mix(lite,white,0.6);
  // the bloom's radius, which everything is sized by
  const radius=g.bloomR;
  try core(b,.{.r=radius,.body=color.mix(body,lite,0.5),.lite=lite,.seed=seed},&rng);
  try lens(b,radius,.{.n=g.thorns,.inner=0.5,.outer=1.2,.thick=0.08,.y=-0.05,.order=.{0.08,0.26},.lite=pale,.deep=leaf},lite,seed+%0x1E25);
  // the petals: an inner whorl rising steeply, an outer one opening wider
  const whorls=[_]Whorl{
    .{.n=g.petals,.ring=.inner,.at=1.28,.y=0.02,.len=1.45,.w=0.4,.rise=1.4,.flare=0.6,.cup=0.55,.order=.{0.28,0.48},.col=leaf,.tip=pale},
    .{.n=g.petals+variant%2,.ring=.outer,.at=1.45,.y=-0.07,.len=1.85,.w=0.34,.rise=1.05,.flare=0.75,.cup=0.45,.order=.{0.46,0.66},.offset=true,.col=body,.tip=pale},
  };
  for(whorls,0..)|wh,k|try whorl(b,radius,wh,lite,seed+%k*97,&rng);
  try trailing(b,radius,.{.n=g.tendrils,.at=0.9,.y=0.2,.len=.{4.2,6.2},.r=0.03,.beads=4,.order=.{0.68,0.86},.col=lite},seed+%0x7A11,&rng);
  try motes(b,radius,16,lite,&rng);
}
/// the halyriphon's crown, all three of the gardener's drafts layered (the
/// gardener's pick): its facets' own soft aqua, its petals' own lilac, its halo's star-blue,
/// never white
const lumiFacet=color.rgb(0.32,0.62,0.78).toRgba8(255);
/// (its petals' tips)
const lumiPetal=color.rgb(0.62,0.48,0.86).toRgba8(255);
/// (its halo: a soft star-blue)
const lumiHalo=color.rgb(0.5,0.66,1.0).toRgba8(255);
/// the halyriphon's lantern: how many comb rows run up it (the old
/// lantern's eight), how far they turn round it mouth to top (turns, its
/// `lanternTwist`), how far off its skin they float (a share of its
/// radius) and how many beads of split light each strings
const lumiCombs=8;
/// (how far they turn)
const lumiTwist:f32=0.7;
/// (how far off the skin)
const lumiCombOff:f32=1.07;
/// (how many beads)
const lumiCombBeads=5;
/// its yield beads: how high over the heart they hang (m, its species' `pluck`)
/// and how far out round it (a share of the radius)
const lumiPodHigh:f32=0.31;
/// (how far out)
const lumiPodOut:f32=0.35;
/// the halyriphon (the `drift` form, turned radiant): a comb-jelly lantern
/// of light, gathered, never grown: its old sap lantern kept whole (the
/// gardener's heart of it), gathered in as one sheer pane of light round
/// its heart (`core`); its eight comb rows lifted off it as threads of
/// light floating a hair off its skin, each its own colour of the split
/// light, beads strung along it; beneath, its filaments (the other heart
/// of it) trailing as threads of light with beads strung down them; over
/// it its yield's beads and its crown: a ring of crystal facets close over
/// its top, an open whorl of floating petals above them, a thin halo tilted
/// round it all with motes spiralling in (the gardener's three, layered).
/// The origin is the heart.
pub fn lumi(b:*mg.Builder,g:species.Genome,seed:u64,variant:u32)Allocator.Error!void{
  // its own random stream
  var rng=Rng.init(seed);
  // the pale body, the light it holds, and white
  const body=g.stemCol.toRgba8(255);
  const lite=g.bloomCol.toRgba8(255);
  const white=color.rgb(1,1,1).toRgba8(255);
  // the lantern's radius, which everything is sized by
  const radius=g.bloomR*0.62;
  try core(b,.{.r=radius*0.8,.body=color.mix(body,lite,0.5),.lite=lite,.stamens=5,.seed=seed},&rng);
  // the lantern: its sap skin, the old comb-jelly egg kept whole, gathered
  // in as one pane of light, sheer
  const skin=b.mark();
  try mg.drifts.lantern(b,g,radius,seed);
  fragment(b,skin,.{.order=0.08,.ring=.veil});
  // where on the rainbow this lantern's split light begins
  const hue0=m.f(seed%97)/97+m.f(variant)*0.25;
  for(0..lumiCombs)|i|{
    // this comb row's own colour of the split light
    const x=hue0+m.ratio(i,lumiCombs);
    const film=color.rgb(0.5+0.5*@cos(m.tau*x),0.5+0.5*@cos(m.tau*(x+0.33)),0.5+0.5*@cos(m.tau*(x+0.67))).toRgba8(255);
    const col=color.mix(film,white,0.25);
    // its path: along the lantern's comb crest, a hair off the skin, mouth to top
    var path:[16]V3=undefined;
    for(&path,0..)|*p,j|{
      const s=m.lerp(0.1,0.9,m.ratio(j,path.len-1));
      const ph=(m.ratio(i,lumiCombs)-lumiTwist*s/m.f(lumiCombs))*m.tau;
      p.*=mg.drifts.lanternAt(radius*lumiCombOff,s,ph);
    }
    // the comb row and the beads of split light strung along it, one fragment
    const a=m.ratio(i,lumiCombs)*m.tau;
    const s0=b.mark();
    try threadOn(b,&path,radius*0.035,col);
    for(0..lumiCombBeads)|k|{
      try mg.ellipsoid(b,.{.center=m.alongPath(&path,(m.f(k)+0.5)/m.f(lumiCombBeads)),.radii=m.splat3(radius*0.045),.col=col,.part=.bloom,.rings=3,.segs=5});
    }
    fragment(b,s0,.{.order=m.lerp(0.14,0.4,m.ratio(i,lumiCombs)),.ring=.inner,.bearing=a});
  }
  // its filaments: threads of light trailing from under it, two lengths, beads strung down them
  try trailing(b,radius,.{.n=g.tendrils,.at=0.3,.y=0.62,.len=.{2.8,6.4},.r=0.022,.beads=3,.order=.{0.45,0.7},.col=g.leafCol.toRgba8(255)},seed+%0x7A12,&rng);
  // its yield: beads of starlight held over its crown, where the paws reach
  // for them (its species' `pluck`), the last to settle
  for(0..g.pods)|k|{
    // this bead's bearing (its place among the pods), and where its vertices begin
    const a=(m.f(k)+0.5)/m.f(g.pods)*m.tau;
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=v3(@cos(a)*radius*lumiPodOut,lumiPodHigh,@sin(a)*radius*lumiPodOut),.radii=m.splat3(g.podR),.col=lite,.part=.pod,.rings=5,.segs=7});
    fragment(b,s,.{.order=m.lerp(0.9,0.98,m.ratio(k,@max(g.pods,1))),.ring=.yield,.bearing=a});
  }
  // its crown, layered: facets close over its top, a whorl of petals
  // opening above them, a halo tilted round it all, motes coming in
  try lens(b,radius,.{.n=9,.inner=0.3,.outer=0.85,.thick=0.06,.y=1.08,.order=.{0.72,0.84},.lite=lumiFacet,.deep=body},lite,seed+%0x1E26);
  try whorl(b,radius,.{.n=g.petals,.ring=.outer,.at=0.55,.y=1.45,.len=1.4,.w=0.36,.rise=0.62,.flare=0.45,.cup=0.45,.order=.{0.82,0.93},.col=body,.tip=lumiPetal},lite,seed+%0x2B11,&rng);
  try motes(b,radius,10,lite,&rng);
  try halo(b,radius*2.1,radius*0.022,0.4,0.96,lumiHalo);
}
/// how many flowers an astrocyme's bouquet holds, one share of its store
/// each (its genome's `petals`; plant.vert `BOUQUET_FLOWERS`, must match)
pub const bouquetFlowers=6;
/// how high its highest flower hangs (its genome's `stemH`, m; plant.vert `BOUQUET_HIGH`)
pub const bouquetHigh:f32=1.1;
/// its lowest flower's height, as a share of the highest's (plant.vert `BOUQUET_LOW`)
pub const bouquetLow:f32=0.38;
/// how far round the thread each flower winds from the one below (radians; plant.vert `BOUQUET_TURN`)
pub const bouquetTurn:f32=2.2;
/// how far out from the thread its lowest flower hangs (m; plant.vert `BOUQUET_OUT`)
pub const bouquetOut:f32=0.24;
/// how much nearer the thread the highest hangs, a share of that (plant.vert `BOUQUET_TAPER`)
pub const bouquetTaper:f32=0.35;
/// how high over the soil the knot of light its flowers fan up from sits (m)
const bouquetKnot:f32=0.12;
/// where flower `k` of an astrocyme's bouquet hangs (mesh space, its foot
/// the origin): winding up round its thread, nearer it the higher it is
/// (plant.vert `bouquetAt`, the same)
pub fn bouquetAt(k:usize)V3{
  // how far up the spiral it is, its bearing round the thread, and how far out
  const s=m.ratio(k,bouquetFlowers-1);
  const a=m.f(k)*bouquetTurn;
  const r=bouquetOut*(1-bouquetTaper*s);
  return v3(@cos(a)*r,bouquetHigh*m.lerp(bouquetLow,1,s),@sin(a)*r);
}
/// the astrocyme (the `bouquet` form): a spiral bouquet. From a knot of
/// light just over its tile, held to it by a `root` of light, a thread of
/// light rises, and six flowers fan up from the knot on stalks of light,
/// winding round the thread at rising heights (`bouquetAt`), each a heart
/// of its own with a whorl of petals. Each flower is one share of what it
/// holds: every vertex of flower `k` carries `k + 1` in tu.z, and
/// plant.vert opens it as the store fills past it (bottom up; giving light
/// back, top down) and lets its petals drift loose round it when empty.
pub fn astrocyme(b:*mg.Builder,g:species.Genome,seed:u64,variant:u32)Allocator.Error!void{
  // its own random stream
  var rng=Rng.init(seed);
  // its violet, its pale petals, its gold light and the white its tips pale to
  const body=g.stemCol.toRgba8(255);
  const leaf=g.leafCol.toRgba8(255);
  const lite=g.bloomCol.toRgba8(255);
  const pale=color.mix(lite,color.rgb(1,1,1).toRgba8(255),0.55);
  // each flower's radius, the knot they fan up from, and where the next piece's vertices begin
  const radius=g.bloomR;
  const knot=v3(0,bouquetKnot,0);
  var s=b.mark();
  try mg.ellipsoid(b,.{.center=knot,.radii=m.splat3(radius*0.32),.col=lite,.part=.bloom,.rings=4,.segs=6});
  // the thread they wind round: from the knot up past the highest, twisting slowly
  const top=bouquetHigh+radius*1.6;
  var spine:[6]V3=undefined;
  for(&spine,0..)|*p,j|{
    // how far up it, and its twist round the axis there
    const k=m.ratio(j,5);
    const a=k*m.tau*0.8+m.f(variant)*0.7;
    p.*=v3(@cos(a)*0.025*k,m.lerp(bouquetKnot,top,k),@sin(a)*0.025*k);
  }
  try strand(b,&spine,radius*0.12,pale);
  fragment(b,s,.{.order=0,.ring=.core});
  for(0..bouquetFlowers)|k|{
    // where this flower hangs, its turn among them, which it is (tu.z) and its heart's underside
    const c=bouquetAt(k);
    const o=m.lerp(0.14,0.82,m.ratio(k,bouquetFlowers-1));
    const which=m.f(k+1);
    const under=c-v3(0,radius*0.4,0);
    // its stalk of light, fanning up from the knot
    s=b.mark();
    try strand(b,&.{knot,knot+v3(c[0]*0.15,(under[1]-knot[1])*0.35,c[2]*0.15),v3(c[0]*0.8,m.lerp(knot[1],under[1],0.75),c[2]*0.8),under},radius*0.07,lite);
    // its heart, built round the origin and hung in place
    const h=b.mark();
    try core(b,.{.r=radius,.body=body,.lite=lite,.stamens=5,.seed=seed+%k*31},&rng);
    b.xform(h,m.translate(c));
    fragment(b,s,.{.order=o,.ring=.core,.aux=which});
    // its petals, the same
    const pw=b.mark();
    try whorl(b,radius,.{.n=g.thorns,.ring=.inner,.at=0.62,.y=-0.02,.len=1.35,.w=0.34,.rise=0.85,.flare=0.6,.cup=0.55,.order=.{o+0.02,o+0.1},.col=leaf,.tip=pale},lite,seed+%k*97,&rng);
    b.xform(pw,m.translate(c));
    for(b.v.items[pw..])|*v|v.tu[2]=which;
  }
  // its root of light, struck down from the knot into its tile
  const lift=bouquetKnot+radius*0.4;
  s=b.mark();
  try root(b,radius,.{.n=4,.depth=lift,.spread=1.6,.sink=0.07,.order=.{0.03,0.08},.col=lite,.shard=body,.tip=pale,.strike=bouquetKnot},seed+%0x5007,&rng);
  b.xform(s,m.translate(v3(0,lift,0)));
}
/// how far a heliocyra's head looks up from level, facing the way it
/// casts its strip (radians)
const helioLift:f32=0.45;
/// the heliocyra (the `heliotrope` form): a heliotrope. A flower head on a
/// neck of light, held to its tile by a `root` of light: a cut crystal
/// heart crowned with stamens, a ring of short gold petals and a wheel of
/// ray petals round it, the whole head turned to face +x (the way it
/// casts its strip once turned, as a sunflower follows the sun) and
/// lifted a little toward the sky. Every vertex of the head carries how far
/// out from its heart it lies in tu.z (its rays flutter by it).
pub fn heliocyra(b:*mg.Builder,g:species.Genome,seed:u64,variant:u32)Allocator.Error!void{
  // its own random stream (each variant its own)
  var rng=Rng.init(seed+%variant);
  // its amber, its paler rays, its gold light and the white its tips pale to
  const body=g.stemCol.toRgba8(255);
  const leaf=g.leafCol.toRgba8(255);
  const lite=g.bloomCol.toRgba8(255);
  const pale=color.mix(lite,color.rgb(1,1,1).toRgba8(255),0.6);
  // the head's radius, the way it faces, where it hangs, and the knot its neck rises from
  const radius=g.bloomR;
  const face=v3(@cos(helioLift),@sin(helioLift),0);
  const head=v3(radius*0.5,g.stemH,0);
  const knot=v3(0,0.07,0);
  // its neck of light: up from the knot, bowing back a little, then over to the back of its head
  var s=b.mark();
  try strand(b,&.{knot,v3(-0.03,g.stemH*0.45,0),v3(-0.03,g.stemH*0.85,0),head-face*m.splat3(radius*0.5)},radius*0.1,lite);
  try mg.ellipsoid(b,.{.center=knot,.radii=m.splat3(radius*0.22),.col=lite,.part=.bloom,.rings=4,.segs=6});
  fragment(b,s,.{.order=0.02,.ring=.core});
  // the head, built facing up round the origin: first its cut crystal heart
  const h=b.mark();
  const rows=[_]m.Vice(f32,3){.{-radius*0.55,0,0},.{-radius*0.05,radius*0.42,0},.{radius*0.12,radius*0.42,1},.{radius*0.3,radius*0.22,0},.{radius*0.36,0,1}};
  try cut(b,.{.rows=&rows,.deepRows=2,.deep=body,.lite=pale},&rng);
  // (its facets gather early, just after the neck)
  for(b.v.items[h..])|*v|v.tu[0]=m.lerp(0.06,0.3,v.tu[0]/cutShare);
  // a crown of stamens round it
  s=b.mark();
  try stamens(b,.{.r=radius,.n=9,.lite=lite,.seed=seed,.at=0.4,.y=0.05,.len=.{0.45,0.6},.lean=0.9},&rng);
  fragment(b,s,.{.order=0.32,.ring=.core});
  // a ring of short gold petals, and the wheel of rays round them
  try whorl(b,radius,.{.n=9,.ring=.inner,.at=0.52,.y=0,.len=0.75,.w=0.22,.rise=0.85,.flare=0.5,.cup=0.6,.order=.{0.34,0.5},.col=lite,.tip=pale},lite,seed+%7,&rng);
  try whorl(b,radius,.{.n=g.petals,.ring=.outer,.at=0.72,.y=-0.04,.len=1.55,.w=0.2,.rise=0.18,.flare=0.28,.cup=0.35,.order=.{0.5,0.85},.offset=true,.col=leaf,.tip=pale},lite,seed+%11,&rng);
  // how far out from the heart each vertex of the head lies (tu.z), for its flutter
  for(b.v.items[h..])|*v|v.tu[2]=m.clamp01(m.len(v.pos*v3(1,0,1))/(radius*2.4));
  b.xform(h,m.chain(&.{m.translate(head),m.rotZ(helioLift-m.pi*0.5)}));
  // its root of light, struck down from the knot into its tile
  const lift=knot[1]+radius*0.4;
  s=b.mark();
  try root(b,radius,.{.n=4,.depth=lift,.spread=1.4,.sink=0.07,.order=.{0.03,0.08},.col=lite,.shard=body,.tip=pale,.strike=knot[1]},seed+%0x5007,&rng);
  b.xform(s,m.translate(v3(0,lift,0)));
}
/// the halcyra (the `veil` form): veil, shield and shepherd in one. A small
/// radiant flower (a heart and an upright cup of petals) hung `stemH` over
/// its tile on a `root` of light, hooded by a see-through veil of broad
/// petals curving down like a jellyfish's bell, broad crystal petals
/// hanging at the veil's edge between them (`crystalPetal`, ring
/// `.facets`), sparkling motes. Its thread of light is built both ways:
/// wound round a plant beside it (`woundThread`, built for the heart
/// leaning `veilLean` toward +x) and opened into a `net` over the plants
/// round it; plant.vert shows the one the halcyra's guarding calls for
/// (and leans it, and carries the winding to where the plant stands).
/// The origin is its tile.
pub fn halcyra(b:*mg.Builder,g:species.Genome,seed:u64,variant:u32)Allocator.Error!void{
  // its own random stream
  var rng=Rng.init(seed+%variant);
  // its pale blue, its veil's paler tissue, its white light, and paler still
  const body=g.stemCol.toRgba8(255);
  const leaf=g.leafCol.toRgba8(255);
  const lite=g.bloomCol.toRgba8(255);
  const pale=color.mix(lite,color.rgb(1,1,1).toRgba8(255),0.5);
  // the flower's radius, how high it hangs, and where its vertices begin (to lift them all)
  const radius=g.bloomR;
  const high=g.stemH;
  const start=b.mark();
  try core(b,.{.r=radius,.body=body,.lite=lite,.stamens=5,.seed=seed},&rng);
  try whorl(b,radius,.{.n=g.petals,.ring=.inner,.at=0.5,.y=0,.len=0.8,.w=0.26,.rise=1.15,.flare=0.5,.cup=0.7,.order=.{0.1,0.22},.col=lite,.tip=pale},lite,seed+%3,&rng);
  // the veil: broad gores curving down from over the heart, each its own fragment
  const Gore=struct{
    /// how far out from the axis a gore's claw sits, and how high (shares of the radius)
    const at:f32=0.1;
    /// (how high)
    const y:f32=1.15;
    /// its length and half-width (shares of the radius)
    const len:f32=2.0;
    /// (its half-width)
    const w:f32=0.62;
    /// how steeply it leaves its claw, and how far it curves down by its tip
    const rise:f32=0.3;
    /// (how far it curves down)
    const flare:f32=1.85;
  };
  for(0..g.thorns)|i|{
    // this gore's bearing, the flat way out along it, and its claw
    const a=m.ratio(i,g.thorns)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    const base=out*m.splat3(radius*Gore.at)+v3(0,radius*Gore.y,0);
    // the fragment it is, and where its vertices begin
    const f:Fragment=.{.order=m.lerp(0.28,0.46,m.ratio(i,g.thorns)),.ring=.veil,.bearing=a};
    const s=b.mark();
    try mg.petal(b,.{.base=base,.out=out,.len=radius*Gore.len,.width=radius*Gore.w,.rise=Gore.rise,.flare=Gore.flare,.cup=0.25,.col=leaf,.tip=pale,.part=.bloom});
    fragment(b,s,f);
    try tether(b,v3(0,radius*0.35,0),base,radius*0.02,lite,seed+%i*41,f);
  }
  // the crystal petals at its edge, between the gores, hanging out and down
  for(0..g.thorns)|i|{
    // this petal's bearing, the way out along it, and where the veil's edge lies there
    const a=(m.f(i)+0.5)/m.f(g.thorns)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    const rim=petalTip(out*m.splat3(radius*Gore.at)+v3(0,radius*Gore.y,0),out,radius*Gore.len*0.92,Gore.rise,Gore.flare);
    // the way it hangs, and the way its broad face looks
    const dir=m.norm(out*m.splat3(0.75)-v3(0,0.65,0));
    const face=m.norm(m.cross(m.cross(v3(0,1,0),out),dir));
    // where its vertices begin
    const s=b.mark();
    try crystalPetal(b,.{.base=rim-dir*m.splat3(radius*0.1),.dir=dir,.face=face,.len=radius*1.15,.w=radius*0.42,.thick=radius*0.07,.col=leaf,.tip=pale});
    fragment(b,s,.{.order=m.lerp(0.5,0.66,m.ratio(i,g.thorns)),.ring=.facets,.bearing=a});
  }
  // sparkles scattered off them
  try motes(b,radius,10,pale,&rng);
  // its root of light, struck down into its tile just after the heart lands
  try root(b,radius,.{.n=4,.depth=high,.spread=0.85,.sink=0.08,.order=.{0.03,0.09},.col=lite,.shard=body,.tip=pale,.strike=high-radius*0.4},seed+%0x5007,&rng);
  b.xform(start,m.translate(v3(0,high,0)));
  // its thread of light, both ways: wound from its leaning heart, and opened as a net
  try woundThread(b,v3(@sin(veilLean)*high,@cos(veilLean)*high,0),lite,0.9);
  try net(b,v3(0,high,0),radius,lite,.{0.84,0.98});
}
/// every vertex since `start` is gathered: a fragment with a valid order
/// and ring, on no growth spline
fn expectGathered(b:*const mg.Builder,start:usize)!void{
  try std.testing.expect(b.v.items.len>start);
  for(b.v.items[start..])|v|{
    try std.testing.expect(v.tu[0]>=0 and v.tu[0]<=1);
    // a real place and facing (nothing degenerate)
    for(0..3)|i|try std.testing.expect(v.pos[i]==v.pos[i] and v.nrm[i]==v.nrm[i]);
    // the ring it belongs to, with any thread's share dropped
    const ring=@floor(v.tu[1]+0.01);
    try std.testing.expect(ring>=0 and ring<=@intFromEnum(Ring.net));
  }
  // nothing of it is on a growth spline
  try std.testing.expect(b.grow.items.len<=start);
}
test"a celestial bloom, a vesper and a cut crystal are wholly gathered fragments"{
  // the builder the three are built into
  var b:mg.Builder=.{.gpa=std.testing.allocator};
  defer b.deinit();
  try plant(&b,species.get(.bloom).genome,7,0);
  try expectGathered(&b,0);
  // the vesper too, hanging over its tile: only its root reaches the
  // ground, and it does dig in
  const v=b.mark();
  try star(&b,species.get(.vesper).genome,7,1);
  try expectGathered(&b,v);
  // the lowest any of its root reaches
  var deepest:f32=1;
  for(b.v.items[v..])|x|{
    if(@floor(x.tu[1]+0.01)==@intFromEnum(Ring.root))deepest=@min(deepest,x.pos[1])else try std.testing.expect(x.pos[1]>0.05);
  }
  try std.testing.expect(deepest<0);
  // where the cut begins, and its random stream
  const s=b.mark();
  var rng=Rng.init(3);
  // a small cut: a point, a ring, a point
  const c:Cut=.{.rows=&.{.{-0.2,0,0},.{0,0.1,1},.{0.2,0,0}},.deepRows=1,.deep=color.rgb(1,1,1).toRgba8(255),.lite=color.rgb(1,1,1).toRgba8(255)};
  try cut(&b,c,&rng);
  try shards(&b,3,-0.1,c,&rng);
  try expectGathered(&b,s);
  // the cut's facets gather from its foot up
  try std.testing.expect(b.v.items[s].tu[0]<b.v.items[b.mark()-1].tu[0]);
}
test"the light grid's four are wholly gathered, grounded ones dig in, and the bouquet is as the shaders know it"{
  // the builder they are built into
  var b:mg.Builder=.{.gpa=std.testing.allocator};
  defer b.deinit();
  // the solcyriphon hangs from its heart: its threads trail well below it
  try solcyriphon(&b,species.get(.solcyriphon).genome,7,0);
  try expectGathered(&b,0);
  // the lowest of it
  var low:f32=0;
  for(b.v.items)|x|low=@min(low,x.pos[1]);
  try std.testing.expect(low < -1);
  // the three grounded ones each dig a root into their tile
  for([_]species.Id{.astrocyme,.heliocyra,.halcyra})|sp|{
    // where it begins, and the lowest its root reaches
    const s=b.mark();
    switch(species.get(sp).genome.form){
      .bouquet=>try astrocyme(&b,species.get(sp).genome,7,1),
      .heliotrope=>try heliocyra(&b,species.get(sp).genome,7,1),
      else=>try halcyra(&b,species.get(sp).genome,7,1),
    }
    try expectGathered(&b,s);
    var deepest:f32=1;
    for(b.v.items[s..])|x|if(@floor(x.tu[1]+0.01)==@intFromEnum(Ring.root)){deepest=@min(deepest,x.pos[1]);};
    try std.testing.expect(deepest<0);
  }
  // every variant of each, as the garden builds them, is whole (nothing degenerate)
  for(0..12)|vi|{
    // (each level of detail too)
    b.lod=@intCast(vi/4);
    // the variant, and where it begins
    const vr:u32=@intCast(vi%4);
    const s=b.mark();
    try solcyriphon(&b,species.get(.solcyriphon).genome,@as(u64,@intFromEnum(species.Id.solcyriphon))*977+77+vr*131,vr);
    try astrocyme(&b,species.get(.astrocyme).genome,@as(u64,@intFromEnum(species.Id.astrocyme))*977+77+vr*131,vr);
    try heliocyra(&b,species.get(.heliocyra).genome,@as(u64,@intFromEnum(species.Id.heliocyra))*977+77+vr*131,vr);
    try halcyra(&b,species.get(.halcyra).genome,@as(u64,@intFromEnum(species.Id.halcyra))*977+77+vr*131,vr);
    try expectGathered(&b,s);
  }
  // the astrocyme's genome holds what plant.vert takes its bouquet to be
  try std.testing.expectEqual(@as(u32,bouquetFlowers),species.get(.astrocyme).genome.petals);
  try std.testing.expectEqual(bouquetHigh,species.get(.astrocyme).genome.stemH);
  // and each flower's heart sits where `bouquetAt` says
  var c:mg.Builder=.{.gpa=std.testing.allocator};
  defer c.deinit();
  try astrocyme(&c,species.get(.astrocyme).genome,7,0);
  for(0..bouquetFlowers)|k|{
    // the nearest any of this flower's vertices comes to where its heart should be
    var near:f32=1;
    for(c.v.items)|x|if(x.tu[2]==m.f(k+1)){near=@min(near,m.dist(x.pos,bouquetAt(k)));};
    try std.testing.expect(near<species.get(.astrocyme).genome.bloomR*0.3);
  }
}
