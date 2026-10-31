//! a rough sketch of the constellate lineage (tier 4), for the gardener to
//! check we see the same thing (`--samples=`): small solid points of light
//! drifting free, a thin line of light joining any two near enough (the
//! plexus web), and a pane filling every three that are all joined. As the
//! points drift, lines and panes form between those coming together and
//! break between those parting. The web's heart beats, and every beat runs
//! out through it as a wave, lightening the blue it passes. One cluster
//! shown at three reaches, the lines reaching further each time: loose,
//! forming, crystalline. Beside it, the plant parts a gardener builds a
//! constellate plant from, each a web holding a shape (`Shape`): a petal,
//! a leaf, a bud, an open flower head. And the first thing built from
//! them: a yielder, five petals snapped to a flower head, which becomes
//! its core, bonded to every petal's base; it yields motes of light and new
//! fragments, rising from it.
//!
//! All of it is the GPU's (part.vert, part.frag `PART_PLEXUS`): where each
//! point rests and how it drifts, which lines and panes show, the beat. So
//! every vertex here carries only what it belongs to: colour r, g, b the
//! ids of its points (one for a point, two for a line, three for a pane),
//! alpha what it is (`Kind`) and what shape the web holds (`Shape`, four
//! times over); pos.x the cluster's reach; and for a point
//! which of its pair of lights (pos.y) and
//! its direction out from its middle (the normal), for a line how far along
//! it and which side (tu), for a pane its corner's weights (tu) and which
//! face (pos.y). The web is two layers (pos.z): one joining the pairs' first
//! lights, one joining only their companions. Every line and pane that
//! could ever form is built in both, collapsed to nothing while its lights
//! are apart.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, ratios
const m=engine.core.math;
/// the mesh builder and its balls
const mg=lib.meshgen;
/// the vertex colours the ids ride in
const color=engine.core.color;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// how many points float in the cluster (part.vert `PLEXUS_POINTS`)
const count=30;
/// how many pieces a line is cut into along its length
const lineSteps=8;
/// what a piece of the web is (colour alpha): part.vert places each its
/// own way, part.frag draws each its own way
const Kind=enum(u8){
  /// a solid point of light
  point,
  /// a line of light between two points
  line,
  /// a pane across three
  pane,
  /// a yielder's bond: a line from its core to the base of one of its
  /// petals (ids: the core's point, the petal's, which petal)
  bond,
};
/// what shape a web holds (part.vert `PLEXUS_CLUSTER`…): where on the GPU
/// each point rests, and which is its heart
const Shape=enum(u8){
  /// a loose spindle of points drifting wide
  cluster,
  /// a petal: rows from a narrow base out to its round tip, cupped, no
  /// midrib
  petal,
  /// a leaf: a stalk running on as a midrib, two edges, folded a little
  /// up from the midrib, pointed
  leaf,
  /// a closed bud: a teardrop of points in a golden spiral
  bud,
  /// an open flower head: a domed disc and five petals round it
  flower,
  /// a yielder's core: the flower head its petals were snapped to
  yieldCore,
  /// the first of a yielder's five petals, the rest following it
  /// (`yieldPetal`+k for petal k)
  yieldPetal,
  /// the fragments a yielder yields, three points each, rising from it
  yieldFragment=11,
  /// the motes of light a yielder yields, rising quicker
  yieldLight,
  /// the one point a yielder's shut petals gather light and fragments in
  yieldGathering,
  /// a stem: rings wound up its length, a joint every third where other
  /// stems and leaves fasten
  stem,
  /// a sprig's stem, the others fastened to its joints
  sprigStem,
  /// a sprig's branch stem, fastened at its stem's middle joint
  sprigBranch,
  /// a sprig's leaf at its stem's lowest joint
  sprigLeaf,
  /// a sprig's leaf at its stem's highest joint
  sprigLeafHigh,
  /// the heart's stem, becoming its grand flower
  heartStem,
  /// the first of the heart's four buds, the rest following it
  /// (`heartBud`+k for bud k)
  heartBud,
  /// the heart's filaments, three of eight points each, dripping from its
  /// foot
  heartFilament=24,
  /// the first of the petlets on the heart's blooms, four to a bloom, the
  /// rest following it (`heartPetlet`+4*bloom+petlet)
  heartPetlet=25,
  /// the first of the heart's five grand petals, the rest following it
  heartGrand=41,
  /// the fragments the heart's done blooms let go, three points each,
  /// sixteen for each bloom built, each becoming three points of a petlet
  heartSeed=46,
  /// the fragments that burst from the heart's blooms as they break free,
  /// six of three points from each
  heartBurst,
  /// the currents of energy flowing up into a settled heart's base, seven
  /// of ten points
  heartCurrent,
  /// the petals of the rose the heart's stem becomes, three rings of five,
  /// ten points each
  heartRose,
  /// a part the settled heart makes out of energy, a different one each
  /// time round
  heartMade,
  /// the glowing spot the settled heart gathers energy in to make a part
  heartMadeGlow,
  /// the yielder's other petals, by number
  _,
};
/// one vertex of the web: what it belongs to and where on it
const Vert=struct{
  /// the ids of its points (repeated where it has fewer than three)
  ids:[3]u8,
  /// what it is
  kind:Kind,
  /// what shape its web holds
  shape:Shape,
  /// the cluster's reach, for a pane which face, for a line or pane which
  /// layer (pos)
  at:V3,
  /// a point's direction out from its middle (else unused)
  out:V3=v3(0,1,0),
  /// along a line and across it, or a pane corner's weights
  tu:[2]f32=.{0,0},
};
/// put one vertex of the web, as `Vert` describes it
fn put(b:*mg.Builder,v:Vert)Allocator.Error!void{
  try b.v.append(b.gpa,.{.pos=v.at,.nrm=v.out,.col=color.Rgba8.of(.{v.ids[0],v.ids[1],v.ids[2],@intFromEnum(v.kind)+4*@intFromEnum(v.shape)}),.tu=.{v.tu[0],v.tu[1],0},.part=@intFromEnum(lib.vertex.Part.plexus)});
}
/// one web: which shape it holds, how far its lines reach, how many points,
/// and in how many points at a time they keep to themselves
const Web=struct{
  /// the shape it holds
  shape:Shape,
  /// a line shows within this
  reach:f32,
  /// how many points it has
  n:usize=count,
  /// its points join only within runs of this many (0: all of them)
  group:usize=0,
  /// whether points `i` and `j` may join
  fn together(w:Web,i:usize,j:usize)bool{return w.group==0 or i/w.group==j/w.group;}
};
/// one web's points, each a pair of lights circling each other: two balls,
/// their vertices keeping only their direction out and which of the pair
/// (pos.y: 1 the first, -1 its companion)
fn points(b:*mg.Builder,w:Web)Allocator.Error!void{
  for(0..w.n)|i|for([_]f32{1,-1})|twin|{
    // where its vertices begin, and its id
    const s=b.mark();
    const id:u8=@intCast(i);
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(1,1,1),.col=color.Rgba8.of(.{0,0,0,0}),.part=.plexus,.rings=6,.segs=8});
    for(b.v.items[s..])|*v|{
      v.nrm=m.norm(v.pos);
      v.pos=v3(w.reach,twin,0);
      v.col=color.Rgba8.of(.{id,id,id,@intFromEnum(Kind.point)+4*@intFromEnum(w.shape)});
      v.tu=.{0,0,0};
    }
  };
}
/// one web whole: its points, then each layer of it (0 joining the first
/// lights, 1 the companions)
fn cluster(b:*mg.Builder,w:Web)Allocator.Error!void{
  try points(b,w);
  for([_]f32{0,1})|layer|try web(b,w,layer);
}
/// one ribbon of line, cut along its length and turned to the eye on the
/// GPU, between the points `ids` name
fn ribbon(b:*mg.Builder,ids:[3]u8,kind:Kind,shape:Shape,at:V3)Allocator.Error!void{
  for(0..lineSteps)|k|{
    // where this piece begins and ends along it
    const s0=m.ratio(k,lineSteps);
    const s1=m.ratio(k+1,lineSteps);
    for([_][2]f32{.{s0,-1},.{s1,-1},.{s1,1},.{s0,-1},.{s1,1},.{s0,1}})|c|try put(b,.{.ids=ids,.kind=kind,.shape=shape,.at=at,.tu=c});
  }
}
/// one layer of the web (`layer` 0 the first lights', 1 the companions'):
/// every line that could join two of its lights, every pane that could fill
/// three
fn web(b:*mg.Builder,w:Web,layer:f32)Allocator.Error!void{
  // the reach and layer every vertex carries
  const at=v3(w.reach,0,layer);
  // each line
  for(0..w.n)|i|for(i+1..w.n)|j|{
    if(!w.together(i,j))continue;
    try ribbon(b,.{@intCast(i),@intCast(j),@intCast(j)},.line,w.shape,at);
  };
  // each pane: two faces, wound opposite ways so one faces either side
  for(0..w.n)|i|for(i+1..w.n)|j|for(j+1..w.n)|k|{
    if(!w.together(i,j) or !w.together(j,k))continue;
    // its three points
    const ids=[3]u8{@intCast(i),@intCast(j),@intCast(k)};
    // its corners' weights: all of the first, all of the second, all of the third
    const a=[2]f32{1,0};
    const bb=[2]f32{0,1};
    const c=[2]f32{0,0};
    for([_][2]f32{a,bb,c})|q|try put(b,.{.ids=ids,.kind=.pane,.shape=w.shape,.at=v3(w.reach,1,layer),.tu=q});
    for([_][2]f32{a,c,bb})|q|try put(b,.{.ids=ids,.kind=.pane,.shape=w.shape,.at=v3(w.reach,-1,layer),.tu=q});
  };
}
/// a yielder: five petals snapped to a flower head, which becomes its core,
/// turning slowly round it; bonds join the core's heart to each petal's
/// base. Over and over its petals shut, their tips gathering air and energy
/// into one point of light, threads of light running to it from each tip,
/// and when it is full it is let go as a mote of light and a new fragment
fn yielder(b:*mg.Builder)Allocator.Error!void{
  try cluster(b,.{.shape=.yieldCore,.reach=0.21});
  for(0..5)|k|try cluster(b,.{.shape=@enumFromInt(@intFromEnum(Shape.yieldPetal)+k),.reach=0.17});
  for(0..5)|k|for([_]f32{0,1})|layer|{
    // the core's heart to both points of petal k's base, the gathered
    // point to both of its tip
    // which petal's web
    const petalWeb:u8=@intCast(@intFromEnum(Shape.yieldPetal)+k);
    for([_]u8{0,1})|to|try ribbon(b,.{0,to,petalWeb},.bond,.yieldCore,v3(1,0,layer));
    for([_]u8{28,29})|to|try ribbon(b,.{0,to,petalWeb},.bond,.yieldGathering,v3(1,0,layer));
  };
  try cluster(b,.{.shape=.yieldFragment,.reach=0.3,.n=9,.group=3});
  try points(b,.{.shape=.yieldLight,.reach=0,.n=2});
  try points(b,.{.shape=.yieldGathering,.reach=0,.n=1});
}
/// a sprig: a stem, a branch stem fastened at its middle joint, a leaf at
/// its lowest joint and another at its highest, bonds from each joint's
/// ring to the foot of what fastens there
fn sprig(b:*mg.Builder)Allocator.Error!void{
  try cluster(b,.{.shape=.sprigStem,.reach=0.17});
  try cluster(b,.{.shape=.sprigBranch,.reach=0.17});
  try cluster(b,.{.shape=.sprigLeaf,.reach=0.22});
  try cluster(b,.{.shape=.sprigLeafHigh,.reach=0.22});
  for([_]f32{0,1})|layer|{
    // the branch's foot ring to the middle joint's, point for point
    for(0..3)|c|try ribbon(b,.{@intCast(18+c),@intCast(c),@intFromEnum(Shape.sprigBranch)},.bond,.sprigStem,v3(1,0,layer));
    // each leaf's stalk foot to its joint's ring
    for(0..3)|c|try ribbon(b,.{@intCast(9+c),0,@intFromEnum(Shape.sprigLeaf)},.bond,.sprigStem,v3(1,0,layer));
    for(0..3)|c|try ribbon(b,.{@intCast(27+c),0,@intFromEnum(Shape.sprigLeafHigh)},.bond,.sprigStem,v3(1,0,layer));
  }
}
/// the heart's chain reaction: the heart blooming (stage 3), with the
/// petlets its blooms are built (four to each), its grand petals, and the
/// fragments on their way between blooms
fn chain(b:*mg.Builder)Allocator.Error!void{
  try grown(b,3);
  try cluster(b,.{.shape=.heartSeed,.reach=3.2,.n=144,.group=3});
}
/// the heart at `stage` with all its blooms' petlets and its grand petals
fn grown(b:*mg.Builder,stage:f32)Allocator.Error!void{
  try heart(b,stage);
  for(0..16)|k|try cluster(b,.{.shape=@enumFromInt(@intFromEnum(Shape.heartPetlet)+k),.reach=stage+0.3*0.4*0.7,.n=12});
  for(0..5)|p|try cluster(b,.{.shape=@enumFromInt(@intFromEnum(Shape.heartGrand)+p),.reach=stage+0.17*1.6*0.7});
}
/// the heart settling into a builder (stage 4): its blooms bursting free
/// in a puff of fragments and drifting down to the ground, the heart
/// coming down near it, currents of energy flowing up into its base
fn builder(b:*mg.Builder)Allocator.Error!void{
  try grown(b,4);
  try settling(b,4);
}
/// what bursts from the heart's blooms and flows into it as it settles, at
/// `stage`
fn settling(b:*mg.Builder,stage:f32)Allocator.Error!void{
  try cluster(b,.{.shape=.heartBurst,.reach=stage+0.2,.n=72,.group=3});
  try cluster(b,.{.shape=.heartCurrent,.reach=stage+0.22,.n=70,.group=10});
  // the part it makes (its reach set on the GPU by which part), and the
  // spot it gathers the energy in
  try cluster(b,.{.shape=.heartMade,.reach=stage+0.2});
  try points(b,.{.shape=.heartMadeGlow,.reach=stage,.n=1});
}
/// the heart's whole story in one (stage 5): every web any stage has, the
/// GPU telling which stage it is at by its clock
fn story(b:*mg.Builder)Allocator.Error!void{
  try grown(b,5);
  try cluster(b,.{.shape=.heartSeed,.reach=5.2,.n=144,.group=3});
  try settling(b,5);
}
/// the heart at `stage` (0 bound, 1 rising, 2 blooming, 3 its chain
/// reaction, 4 settling into a builder, 5 all of them in turn; it rides
/// in every
/// vertex's reach, whole part): a stem with four buds fastened at its
/// joints, bonded, and the filaments that drip from its foot once it rises;
/// each web's reach shrunk with the part, so its lines join only what they
/// did at full size
fn heart(b:*mg.Builder,stage:f32)Allocator.Error!void{
  // how much the whole shrinks once it rises
  const shrink:f32=if(stage==0)1 else 0.7;
  try cluster(b,.{.shape=.heartStem,.reach=stage+0.17*shrink});
  try cluster(b,.{.shape=.heartRose,.reach=stage+0.28*shrink,.n=150,.group=10});
  for(0..4)|k|try cluster(b,.{.shape=@enumFromInt(@intFromEnum(Shape.heartBud)+k),.reach=stage+0.2*0.6*shrink});
  try cluster(b,.{.shape=.heartFilament,.reach=stage+0.12,.n=24,.group=8});
  for(0..4)|k|for([_]f32{0,1})|layer|{
    // bud k's joint ring, and the bud's web
    const joint=[4]u8{9,18,27,27};
    const budWeb:u8=@intCast(@intFromEnum(Shape.heartBud)+k);
    for(0..3)|c|try ribbon(b,.{@intCast(joint[k]+c),0,budWeb},.bond,.heartStem,v3(stage+0.5,0,layer));
  };
}
/// mesh: CONSTELLATE, LOOSE. the points drifting, few of them joined
pub const loose=struct{
  /// builds the cluster, lines short
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,.{.shape=.cluster,.reach=0.26});}
};
/// mesh: CONSTELLATE, FORMING. more joined, the first panes filling in
pub const forming=struct{
  /// builds the cluster, lines longer
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,.{.shape=.cluster,.reach=0.38});}
};
/// mesh: CONSTELLATE, CRYSTALLINE. joined through, panes across most of it
pub const crystalline=struct{
  /// builds the cluster, lines long
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,.{.shape=.cluster,.reach=0.5});}
};
/// mesh: CONSTELLATE PETAL. a petal of light, a part to build with
pub const petal=struct{
  /// builds the petal's web
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,.{.shape=.petal,.reach=0.17});}
};
/// mesh: CONSTELLATE LEAF. a leaf of light, a part to build with
pub const leaf=struct{
  /// builds the leaf's web
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,.{.shape=.leaf,.reach=0.22});}
};
/// mesh: CONSTELLATE BUD. a closed bud of light, a part to build with
pub const bud=struct{
  /// builds the bud's web
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,.{.shape=.bud,.reach=0.2});}
};
/// mesh: CONSTELLATE FLOWER HEAD. an open flower head of light, a part to
/// build with
pub const flower=struct{
  /// builds the flower head's web
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,.{.shape=.flower,.reach=0.21});}
};
/// mesh: CONSTELLATE YIELDER. five petals snapped to a flower head, now
/// its core, bonded to every petal's base; it yields light and fragments
pub const yield=struct{
  /// builds the yielder
  pub fn build(b:*mg.Builder)Allocator.Error!void{try yielder(b);}
};
/// mesh: CONSTELLATE STEM. a stem of light, the part others fasten to
pub const stem=struct{
  /// builds the stem's web
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,.{.shape=.stem,.reach=0.17});}
};
/// mesh: CONSTELLATE SPRIG. a stem with a branch stem and two leaves
/// fastened to its joints
pub const sprigMesh=struct{
  /// builds the sprig
  pub fn build(b:*mg.Builder)Allocator.Error!void{try sprig(b);}
};
/// mesh: CONSTELLATE HEART, BOUND. four buds fastened to a stem
pub const heartBound=struct{
  /// builds the heart, bound
  pub fn build(b:*mg.Builder)Allocator.Error!void{try heart(b,0);}
};
/// mesh: CONSTELLATE HEART, RISING. lifted, shrunk, filaments dripping
pub const heartRising=struct{
  /// builds the heart, rising
  pub fn build(b:*mg.Builder)Allocator.Error!void{try heart(b,1);}
};
/// mesh: CONSTELLATE HEART, BLOOMING. buds blooming one by one, the stem
/// becoming a grand flower
pub const heartBlooming=struct{
  /// builds the heart, blooming
  pub fn build(b:*mg.Builder)Allocator.Error!void{try heart(b,2);}
};
/// mesh: CONSTELLATE HEART, CHAIN. four petlets snapped to one bloom set off
/// a chain reaction: its fragments build the next bloom's petlets one
/// fragment at a time, each bloom done joining in on the next, the heart
/// swelling, and once all are done it grows and grand petals open
pub const heartChain=struct{
  /// builds the heart's chain reaction
  pub fn build(b:*mg.Builder)Allocator.Error!void{try chain(b);}
};
/// mesh: CONSTELLATE HEART, BUILDER. its blooms burst free and drift down
/// to lie as parts; the heart settles near the ground, currents of energy
/// rising into its base, and builds: a whole part forms out of the energy
/// before it, and a bundle of its tendrils draws it away to the wolf
pub const heartBuilder=struct{
  /// builds the heart settling into a builder
  pub fn build(b:*mg.Builder)Allocator.Error!void{try builder(b);}
};
/// mesh: CONSTELLATE HEART. its whole story in one: bound, rising,
/// blooming, its chain reaction, settling into a builder, then beginning
/// again
pub const heartWhole=struct{
  /// builds the heart's whole story
  pub fn build(b:*mg.Builder)Allocator.Error!void{try story(b);}
};
