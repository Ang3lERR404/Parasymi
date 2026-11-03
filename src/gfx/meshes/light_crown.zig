//! meshes: the HALO CROWNS. The sign a structure wears in light
//! (docs/radiant-plants.md, game/light_crown.zig): a crown of radiant
//! fragments gathered over it while it is powered, come apart in the dark.
//! A few set designs, each built only of the radiant kit's pieces (petals,
//! threads, beads, rings, cut and grown crystals), never grown: every piece
//! a rigid fragment with its order, ring and bearing, drawn as `.crown`
//! (pearl with a soap-bubble film, light held in it). part.vert gathers
//! them by the structure's light, turns their rings slowly and bobs them.
//! Built round the crown's middle (origin), about a unit across its ring.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, angles, ratios
const m=engine.core.math;
/// the plant-piece mesher: the builder these meshes are put into
const mg=lib.meshgen;
/// the garden's palette: the seeded rng each crown draws from
const pal=lib.palette;
/// colour conversions, for the pearl's whites
const color=engine.core.color;
/// the vertex layout: the crown's part role
const vertex=lib.vertex;
/// the radiant lineage's kit: fragments, threads, whorls, rings, cuts
const radiant=lib.radiantKit;
/// the mineral kit: small grown crystals
const mineral=lib.mineralKit;
/// the engine's deterministic random stream
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// a vertex colour
const Rgba8=color.Rgba8;
/// the pearl a crown's pieces are, at their feet
const pearl=color.rgb(0.93,0.93,0.98).toRgba8(255);
/// paling to near white at their tips, a breath of ley violet in it
const pale=color.rgb(0.98,0.97,1.0).toRgba8(255);
/// a little warmer: beads and hearts, where the light gathers
const warm=color.rgb(1.0,0.95,0.86).toRgba8(255);
/// the thread of light rings and tethers are spun of
const lite=color.rgb(0.96,0.95,1.0).toRgba8(255);
/// every vertex built since `start` drawn as a crown's fragment (keeping
/// the order, ring and bearing the kit marked it with)
fn asCrown(b:*mg.Builder,start:usize)void{
  for(b.v.items[start..])|*v|v.part=@intFromEnum(vertex.Part.crown);
}
/// a bead of light at `at`, `r` across: a fragment of its own
fn bead(b:*mg.Builder,at:V3,r:f32,f:radiant.Fragment)Allocator.Error!void{
  // where its vertices begin
  const s=b.mark();
  try mg.ellipsoid(b,.{.center=at,.radii=m.splat3(r),.col=warm,.part=.bloom,.rings=4,.segs=6});
  radiant.fragment(b,s,f);
}
/// a ring of light `r` out, `thick` its radius, tilted `tilt` about x then
/// turned `yaw` about up: a fragment of its own on `ring`
fn hoop(b:*mg.Builder,r:f32,thick:f32,tilt:f32,yaw:f32,order:f32,ring:radiant.Ring)Allocator.Error!void{
  // where its vertices begin
  const s=b.mark();
  try radiant.halo(b,r,thick,tilt,order,lite);
  for(b.v.items[s..])|*v|{
    v.pos=turnY(v.pos,yaw);
    v.nrm=turnY(v.nrm,yaw);
  }
  radiant.fragment(b,s,.{.order=order,.ring=ring,.bearing=yaw});
}
/// `p` turned `a` radians about the up axis
fn turnY(p:m.Vice(f32,3),a:f32)m.Vice(f32,3){
  return.{p[0]*@cos(a)-p[2]*@sin(a),p[1],p[0]*@sin(a)+p[2]*@cos(a)};
}
/// the point on a ring `r` out, tilted `tilt` about x and turned `yaw`
/// about up, `a` radians round it
fn onHoop(r:f32,tilt:f32,yaw:f32,a:f32)V3{
  // the point before the tilt, then tilted
  const q=v3(@cos(a)*r,0,@sin(a)*r);
  const t=m.Vice(f32,3){q[0],q[1]*@cos(tilt)-q[2]*@sin(tilt),q[1]*@sin(tilt)+q[2]*@cos(tilt)};
  const w=turnY(t,yaw);
  return v3(w[0],w[1],w[2]);
}
/// mesh: CROWN DIADEM. a circlet of tall slender pearl petals standing on
/// a ring of light, alternately long and short, leaning a little out at
/// their tips like a coronet's points, a bead of light between each pair.
/// The petals settle first, round the ring, then the beads, the ring last.
pub const diadem=struct{
  /// how many petals stand round it
  const n=9;
  /// builds the diadem
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // its seeded stream, and where its vertices begin
    var rng=pal.rngFor("light_crown_diadem");
    const start=b.mark();
    for(0..n)|i|{
      // this petal's bearing, the flat way out along it, and whether it is a long one
      const a=m.ratio(i,n)*m.tau;
      const out=v3(@cos(a),0,@sin(a));
      const long=i%2==0;
      // where its vertices begin
      const s=b.mark();
      try mg.petal(b,.{
        .base=out*m.splat3(0.95),.out=out,
        .len=(if(long)@as(f32,0.78)else 0.5)*rng.range(0.95,1.05),.width=if(long)0.15 else 0.12,
        .rise=1.38,.flare=0.45,.cup=0.55,.col=pearl,.tip=pale,.part=.leaf,
      });
      radiant.fragment(b,s,.{.order=0.05+0.55*m.ratio(i,n),.ring=.inner,.bearing=a});
      // a bead between it and the next
      const ab=a+m.pi/m.f(n);
      try bead(b,v3(@cos(ab),0,@sin(ab))*m.splat3(0.97)+v3(0,0.06,0),0.055,.{.order=0.6+0.25*m.ratio(i,n),.ring=.inner,.bearing=ab});
    }
    try hoop(b,0.96,0.022,0,0,0.92,.inner);
    try hoop(b,1.12,0.012,0.12,0.6,1,.middle);
    asCrown(b,start);
  }
};
/// mesh: CROWN CIRCLET. a ring of starglass points: clear crystals standing
/// round a ring of light, tall and short in turn, leaning out a little,
/// with a second, wider ring tilted round them and motes floating over
/// their tips. Crystals first, foot to point round the ring, then the
/// rings, the motes last.
pub const circlet=struct{
  /// how many crystals stand round it
  const n=7;
  /// builds the circlet
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // its seeded stream, and where its vertices begin
    var rng=pal.rngFor("light_crown_circlet");
    const start=b.mark();
    for(0..n)|i|{
      // this crystal's bearing, the flat way out along it, and whether it is a tall one
      const a=m.ratio(i,n)*m.tau;
      const out=v3(@cos(a),0,@sin(a));
      const tall=i%2==0;
      // where its vertices begin
      const s=b.mark();
      try mineral.crystal(b,.{
        .base=out*m.splat3(0.9)+v3(0,-0.04,0),.dir=m.norm(out*m.splat3(0.22)+v3(0,1,0)),
        .len=(if(tall)@as(f32,0.72)else 0.42)*rng.range(0.92,1.08),.r=if(tall)0.1 else 0.08,.sides=6,.col=pearl,.tip=pale,
      },&rng);
      radiant.fragment(b,s,.{.order=0.04+0.5*m.ratio(i,n),.ring=.inner,.bearing=a});
    }
    try hoop(b,0.92,0.02,0,0,0.6,.inner);
    try hoop(b,1.18,0.014,0.22,1.1,0.72,.middle);
    for(0..n)|i|{
      // this mote's bearing, over the gap between two crystals
      const a=(m.f(i)+0.5)/n*m.tau;
      try bead(b,v3(@cos(a),0,@sin(a))*m.splat3(0.78)+v3(0,0.62+0.08*rng.range(-1,1),0),0.045,.{.order=0.78+0.22*m.ratio(i,n),.ring=.motes,.bearing=a});
    }
    asCrown(b,start);
  }
};
/// mesh: CROWN ORRERY. a small cut crystal heart held in two rings of light
/// crossed at a slant, beads of light riding each, and a flat ring of motes
/// round its waist: like an armillary sphere. The heart first, facet by
/// facet, then the rings and their beads, the motes last.
pub const orrery=struct{
  /// the heart's cut: rows from its bottom point to its top one
  const cut:radiant.Cut=.{
    .rows=&.{
      .{-0.42,0,0},
      .{-0.11,0.22,1},
      .{0.07,0.25,0},
      .{0.42,0,1},
    },
    .deepRows=1,
    .deep=warm,
    .lite=pale,
    .part=.crown,
  };
  /// how far one ring is tilted from flat (radians)
  const tilt:f32=0.75;
  /// builds the orrery
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // its seeded stream, and where its vertices begin
    var rng=pal.rngFor("light_crown_orrery");
    const start=b.mark();
    // the heart's facets gather in the first share of the order
    const heart=b.mark();
    try radiant.cut(b,cut,&rng);
    for(b.v.items[heart..])|*v|v.tu[0]*=0.35;
    // the two rings, crossed, each with its beads riding it
    for([_]f32{0,m.pi/2.0},[_]radiant.Ring{.inner,.middle},0..)|yaw,ring,k|{
      // the ring's tilt, this way or that
      const tl=if(k==0)tilt else -tilt;
      try hoop(b,0.85,0.018,tl,yaw,0.4+0.1*m.f(k),ring);
      for(0..3)|j|{
        // where round its ring the bead rides
        const a=(m.f(j)+0.25*m.f(k))/3.0*m.tau;
        try bead(b,onHoop(0.85,tl,yaw,a),0.06,.{.order=0.6+0.05*m.f(j)+0.1*m.f(k),.ring=ring,.bearing=a+yaw});
      }
    }
    // the motes round its waist
    for(0..8)|i|{
      // this mote's bearing
      const a=m.ratio(i,8)*m.tau+rng.range(-0.1,0.1);
      try bead(b,v3(@cos(a),0,@sin(a))*m.splat3(1.15),0.035,.{.order=0.82+0.18*m.ratio(i,8),.ring=.outer,.bearing=a});
    }
    asCrown(b,start);
  }
};
/// mesh: CROWN LOTUS. a little celestial bloom hanging over it: a luminous
/// heart with its crown of stamens, an upright cup of petals round it and a
/// wider whorl opening out and down, each petal floating free on its
/// thread of light, motes round it all. The heart first, the cup, the
/// open whorl, the motes last.
pub const lotus=struct{
  /// the bloom's radius, everything sized by it
  const r:f32=0.48;
  /// builds the lotus
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // its seeded stream, and where its vertices begin
    var rng=pal.rngFor("light_crown_lotus");
    const start=b.mark();
    try radiant.core(b,.{.r=r,.body=pearl,.lite=warm,.stamens=6,.seed=0x10705},&rng);
    try radiant.whorl(b,r,.{.n=5,.ring=.inner,.at=0.6,.y=0,.len=1.05,.w=0.32,.rise=1.25,.flare=0.45,.cup=0.7,.order=.{0.12,0.35},.col=pearl,.tip=pale},lite,0x10706,&rng);
    try radiant.whorl(b,r,.{.n=8,.ring=.middle,.at=1.1,.y=-0.12,.len=1.45,.w=0.3,.rise=0.4,.flare=0.65,.cup=0.5,.order=.{0.38,0.75},.offset=true,.col=pearl,.tip=pale},lite,0x10707,&rng);
    // the motes round it, each its own fragment
    for(0..7)|i|{
      // this mote's bearing
      const a=m.ratio(i,7)*m.tau+rng.range(-0.2,0.2);
      try bead(b,v3(@cos(a),0,@sin(a))*m.splat3(1.15)+v3(0,0.12*rng.range(-1,1),0),0.035,.{.order=0.8+0.2*m.ratio(i,7),.ring=.motes,.bearing=a});
    }
    asCrown(b,start);
  }
};
test"every crown is wholly gathered fragments drawn as a crown, on no growth spline"{
  inline for(.{diadem,circlet,orrery,lotus})|d|{
    // a builder for it
    var b:mg.Builder=.{.gpa=std.testing.allocator};
    defer b.deinit();
    try d.build(&b);
    try std.testing.expect(b.v.items.len>0);
    for(b.v.items)|v|{
      try std.testing.expectEqual(@as(u32,@intFromEnum(vertex.Part.crown)),v.part);
      try std.testing.expect(v.tu[0]>=0 and v.tu[0]<=1);
      for(0..3)|i|try std.testing.expect(v.pos[i]==v.pos[i] and v.nrm[i]==v.nrm[i]);
    }
    try std.testing.expect(b.grow.items.len==0);
  }
}
