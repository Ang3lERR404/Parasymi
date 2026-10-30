//! meshes: the HALO. What a polyp's four blooms become (game/structures/
//! halo.zig): the diamond, the radiant lineage's crystal, gathered from its
//! shards (radiant_kit: never grown), and the light it throws, its ring,
//! the projection that makes it and the flash it forms with. The light is
//! the halo's own and forms on the GPU as it does.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// the plant-piece mesher: the builder these meshes are put into
const mg=lib.meshgen;
/// the garden's palette: named colours and the seeded rng each mesh draws from
const pal=lib.palette;
/// colour conversions, for the light's whites
const color=engine.core.color;
/// the radiant lineage's kit: crystal cuts and shards, gathered, never grown
const radiant=lib.radiantKit;
/// a point in space, made from three numbers
const v3=m.v3;
/// mesh: HALO FLASH. the light thrown out where a halo's blooms became one:
/// a flat disc of radius 1 (tu.x its radius 0..1), fine near its rim where
/// the light is a thin ring. part.vert spreads it with its age; part.frag
/// lights it.
pub const flash=struct{
  /// builds the flash: rings of quads round the centre, tightly spaced near the
  /// rim, each vertex carrying its radius (0..1) for the shader, drawn as `.flash`
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the warm white the light starts from
    const col=color.rgb(1.0,0.97,0.9).toRgba8(255);
    // how many slices go round the disc
    const n=48;
    // the radii the rings are laid at, crowding toward the rim where the light is thin
    const radii=[_]f32{0,0.4,0.7,0.82,0.88,0.92,0.96,1.0};
    for(0..n)|i|for(0..radii.len-1)|j|{
      // the slice's two edges, as angles (radians)
      const a0=m.ratio(i,n)*m.tau;
      const a1=m.ratio(i+1,n)*m.tau;
      // the cell's four corners as (angle, radius), wound round the quad
      const q=[4][2]f32{.{a0,radii[j]},.{a1,radii[j]},.{a1,radii[j+1]},.{a0,radii[j+1]}};
      for([_]usize{0,2,1,0,3,2})|c|try b.put(v3(@cos(q[c][0])*q[c][1],0,@sin(q[c][0])*q[c][1]),v3(0,1,0),col,q[c][1],0,.flash);
    };
  }
};
/// mesh: HALO DIAMOND. where the four blooms became one: a cut crystal
/// (`radiant.cut`), eight-sided, its girdle bevelled into a crown and a
/// pavilion of staggered triangular facets running up to a long point and
/// down to a shorter one, three small crystals grown out at its foot
/// (`radiant.shards`). It has no light of its own; part.frag lays a warm
/// iridescent film over its facets, so it only catches light. Centred on
/// its girdle. part.vert gathers it in from its shards as the halo forms,
/// facet by facet from its foot up, the radiant way.
pub const diamond=struct{
  /// how much larger it is built than the rows below give it
  const enlarge:f32=1.6;
  /// the crystal's cut: its rows of facets and the two colours of its film
  const cut:radiant.Cut=.{
    // rows from the bottom point to the top one: height, radius, twist (in
    // half sides), each staggered from the next
    .rows=&.{
      .{-0.24,0,0},
      .{-0.09,0.085,1},
      .{0,0.125,0},
      .{0.07,0.09,1},
      .{0.13,0.05,0},
      .{0.28,0,1},
    },
    .deepRows=2,
    .deep=color.rgb(0.95,0.84,0.76).toRgba8(255),
    .lite=color.rgb(1.0,0.97,0.92).toRgba8(255),
  };
  /// builds the diamond: cuts the crystal, grows three shards at its foot, then
  /// scales the whole gathered form up by `enlarge`
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // where the diamond's vertices begin, so only they are scaled
    const start=b.mark();
    // the diamond's own seeded rng, so every halo's crystal is cut alike
    var rng=pal.rngFor("halo_diamond");
    try radiant.cut(b,cut,&rng);
    try radiant.shards(b,3,-0.12,cut,&rng);
    b.xform(start,m.scale3(m.splat3(enlarge)));
  }
};
/// mesh: HALO RING. the ring of fragmented light a diamond projects: a flat
/// band around a circle of radius 1 in xz (scaled out to the halo's
/// radius), tu.x its angle as a share of a turn from +x toward +z, tu.y
/// across it from its inner edge (-1) to its outer (1), finely, so the
/// spectrum part.frag splits across it stays smooth.
pub const ring=struct{
  /// half the band's width, as a share of the radius
  const half:f32=0.065;
  /// builds the ring: a band 160 steps round and six cells across, each vertex
  /// carrying (share of a turn, -1..1 across) for the shader, drawn as `.halo`
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // plain white: the shader splits the spectrum over it
    const col=color.rgb(1.0,1.0,1.0).toRgba8(255);
    // how many steps go round the ring
    const n=160;
    // the lines across the band, from inner edge (-1) to outer (1)
    const across=[_]f32{-1,-0.7,-0.4,-0.1,0.2,0.6,1};
    for(0..n)|i|for(0..across.len-1)|j|{
      // the cell's four corners as (share of a turn, across), wound round the quad
      const q=[4][2]f32{.{m.ratio(i,n),across[j]},.{m.ratio(i+1,n),across[j]},.{m.ratio(i+1,n),across[j+1]},.{m.ratio(i,n),across[j+1]}};
      for([_]usize{0,2,1,0,3,2})|c|{
        // this corner's angle (radians) and its distance from the centre
        const a=q[c][0]*m.tau;
        const r=1+q[c][1]*half;
        try b.put(v3(@cos(a)*r,0,@sin(a)*r),v3(0,1,0),col,q[c][0],q[c][1],.halo);
      }
    };
  }
};
/// mesh: HALO PROJECTION. the light a diamond throws out to make its ring:
/// a cone from its apex at the crystal (origin) opening up to a circle of
/// radius 1 one unit above (scaled to reach the ring), tu.x along it from
/// the crystal (0) to the ring (1), tu.y its angle as a share of a turn.
/// part.frag fills it with fine rays of split light.
pub const projection=struct{
  /// builds the projection: a cone 96 slices round and 12 rings up, normals
  /// facing out and down, each vertex carrying (along 0..1, share of a turn),
  /// drawn as `.projection`
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // plain white: the shader lays the split rays over it
    const col=color.rgb(1.0,1.0,1.0).toRgba8(255);
    // how many slices go round the cone, and how many rings run up it
    const n=96;
    const l=12;
    for(0..n)|i|for(0..l)|j|{
      // the cell's four corners as (share of a turn, along), wound round the quad
      const q=[4][2]f32{.{m.ratio(i,n),m.ratio(j,l)},.{m.ratio(i+1,n),m.ratio(j,l)},.{m.ratio(i+1,n),m.ratio(j+1,l)},.{m.ratio(i,n),m.ratio(j+1,l)}};
      for([_]usize{0,2,1,0,3,2})|c|{
        // this corner's angle (radians) and how far up the cone it sits (0..1)
        const a=q[c][0]*m.tau;
        const k=q[c][1];
        try b.put(v3(@cos(a)*k,k,@sin(a)*k),m.norm(v3(@cos(a),-1,@sin(a))),col,k,q[c][0],.projection);
      }
    };
  }
};
