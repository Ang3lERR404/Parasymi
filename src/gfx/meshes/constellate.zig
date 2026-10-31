//! a rough sketch of the constellate lineage (tier 4), for the gardener to
//! check we see the same thing (`--samples=`): small solid points of light
//! drifting free, a thin line of light joining any two near enough (the
//! plexus web), and a pane filling every three that are all joined. As the
//! points drift, lines and panes form between those coming together and
//! break between those parting. The web's heart beats, and every beat runs
//! out through it as a wave, lightening the blue it passes. One cluster
//! shown at three reaches, the lines reaching further each time: loose,
//! forming, crystalline.
//!
//! All of it is the GPU's (part.vert, part.frag `PART_PLEXUS`): where each
//! point rests and how it drifts, which lines and panes show, the beat. So
//! every vertex here carries only what it belongs to: colour r, g, b the
//! ids of its points (one for a point, two for a line, three for a pane),
//! alpha what it is (`Kind`); pos.x the cluster's reach; and for a point
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
};
/// one vertex of the web: what it belongs to and where on it
const Vert=struct{
  /// the ids of its points (repeated where it has fewer than three)
  ids:[3]u8,
  /// what it is
  kind:Kind,
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
  try b.v.append(b.gpa,.{.pos=v.at,.nrm=v.out,.col=color.Rgba8.of(.{v.ids[0],v.ids[1],v.ids[2],@intFromEnum(v.kind)}),.tu=v.tu,.part=@intFromEnum(lib.vertex.Part.plexus)});
}
/// one cluster: every point, every line that could join two, every pane
/// that could fill three; a line shows within `reach`
fn cluster(b:*mg.Builder,reach:f32)Allocator.Error!void{
  // each point: a pair of lights circling each other, two balls, their
  // vertices keeping only their direction out and which of the pair
  // (pos.y: 1 the first, -1 its companion)
  for(0..count)|i|for([_]f32{1,-1})|twin|{
    // where its vertices begin, and its id
    const s=b.mark();
    const id:u8=@intCast(i);
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(1,1,1),.col=color.Rgba8.of(.{0,0,0,0}),.part=.plexus,.rings=6,.segs=8});
    for(b.v.items[s..])|*v|{
      v.nrm=m.norm(v.pos);
      v.pos=v3(reach,twin,0);
      v.col=color.Rgba8.of(.{id,id,id,@intFromEnum(Kind.point)});
      v.tu=.{0,0};
    }
  };
  // each layer of the web: 0 joining the first lights, 1 the companions
  for([_]f32{0,1})|layer|try web(b,reach,layer);
}
/// one layer of the web (`layer` 0 the first lights', 1 the companions'):
/// every line that could join two of its lights, every pane that could fill
/// three
fn web(b:*mg.Builder,reach:f32,layer:f32)Allocator.Error!void{
  // the reach and layer every vertex carries
  const at=v3(reach,0,layer);
  // each line: a ribbon cut along its length, turned to the eye on the GPU
  for(0..count)|i|for(i+1..count)|j|{
    // its two points
    const ids=[3]u8{@intCast(i),@intCast(j),@intCast(j)};
    for(0..lineSteps)|k|{
      // where this piece begins and ends along it
      const s0=m.ratio(k,lineSteps);
      const s1=m.ratio(k+1,lineSteps);
      for([_][2]f32{.{s0,-1},.{s1,-1},.{s1,1},.{s0,-1},.{s1,1},.{s0,1}})|c|try put(b,.{.ids=ids,.kind=.line,.at=at,.tu=c});
    }
  };
  // each pane: two faces, wound opposite ways so one faces either side
  for(0..count)|i|for(i+1..count)|j|for(j+1..count)|k|{
    // its three points
    const ids=[3]u8{@intCast(i),@intCast(j),@intCast(k)};
    // its corners' weights: all of the first, all of the second, all of the third
    const a=[2]f32{1,0};
    const bb=[2]f32{0,1};
    const c=[2]f32{0,0};
    for([_][2]f32{a,bb,c})|w|try put(b,.{.ids=ids,.kind=.pane,.at=v3(reach,1,layer),.tu=w});
    for([_][2]f32{a,c,bb})|w|try put(b,.{.ids=ids,.kind=.pane,.at=v3(reach,-1,layer),.tu=w});
  };
}
/// mesh: CONSTELLATE, LOOSE. the points drifting, few of them joined
pub const loose=struct{
  /// builds the cluster, lines short
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,0.26);}
};
/// mesh: CONSTELLATE, FORMING. more joined, the first panes filling in
pub const forming=struct{
  /// builds the cluster, lines longer
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,0.38);}
};
/// mesh: CONSTELLATE, CRYSTALLINE. joined through, panes across most of it
pub const crystalline=struct{
  /// builds the cluster, lines long
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,0.5);}
};
