//! meshes: UNFORM SHARD, TRAIL and STAR. a shard of a radiant plant as it
//! shatters, flying up to where the unforming gathers its seed (radiant_kit
//! `cut`): a small sliver of cut crystal, tinted its plant's colour; the
//! ribbon of light it trails; and the web of light the seed gathers in. The
//! event places, spins and shrinks them (game/unforming.zig).
const lib=@import("../../lib.zig");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=lib.engine.core.math;
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the mesh builder
const mg=lib.meshgen;
/// the radiant kit: its cut crystals
const rk=lib.radiantKit;
/// the shared swatches, and the per-mesh random stream
const pal=lib.palette;
/// colour conversions
const color=lib.engine.core.color;
/// the shard's rows, foot to tip: height, radius, twist
const rows=[_]m.Vice(f32,3){.{-0.03,0,0},.{-0.005,0.018,0},.{0.03,0,0.5}};
/// builds the shard about the origin
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // its own random stream, the same every build
  var rng=pal.rngFor("unformShard");
  try rk.cut(b,.{.rows=&rows,.deepRows=1,.deep=color.rgb(0.6,0.5,0.9).toRgba8(255),.lite=color.rgb(0.95,0.96,1).toRgba8(255)},&rng);
}
/// mesh: UNFORM TRAIL. the trail of light a shard leaves as it flies up to
/// the seed, and the seed's as it falls: a strip straight up +Y over 0..1
/// (tu.x how far along, 0 its tail .. 1 its head), x across it -1..1, drawn
/// as `.trail`; part.vert lays it along the way the shard came, turned to
/// the eye, and part.frag lights it in the colour it carries
pub const trail=struct{
  /// how many pieces it is cut into along its length (so it bends smoothly)
  const steps=32;
  /// builds the strip, two triangles a piece
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // white: the trail takes the colour it carries
    const col=color.rgb(1,1,1).toRgba8(255);
    for(0..steps)|k|{
      // where this piece begins and ends along it
      const s0=m.ratio(k,steps);
      const s1=m.ratio(k+1,steps);
      for([_]m.Vice(f32,2){.{-1,s0},.{1,s1},.{1,s0},.{-1,s0},.{-1,s1},.{1,s1}})|c|try b.put(m.v3(c[0],c[1],0),m.v3(0,0,1),col,c[1],c[0],.trail);
    }
  }
};
/// mesh: UNFORM STAR. the star of gathered light the strange seed forms
/// in, a web of the constellate's light (as the sky's plexus): points of
/// light on two shells round its middle (radius 1 and an inner one), each
/// joined by threads of light to its nearest; all drawn as `.trail` light
/// (tu.x how lit along, tu.y across a thread -1..1, 0 a point), the colour
/// the event gives it. The event turns it, swells it as the shards arrive
/// and flares it with each.
pub const star=struct{
  /// points on the outer shell, and on the inner
  const outer=34;
  /// (on the inner)
  const inner=12;
  /// how far in the inner shell lies
  const innerR:f32=0.45;
  /// how many of its nearest each point is joined to
  const joins=3;
  /// a point's size, and a thread's half width
  const pointR:f32=0.03;
  /// (a thread's half width)
  const threadW:f32=0.012;
  /// how lit the web is along (part.frag's trail: full short of its tip)
  const lit:f32=0.9;
  /// builds the web: its points, then its threads
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // white: the web takes the colour it carries
    const col=color.rgb(1,1,1).toRgba8(255);
    // where every point lies, the outer shell's spread evenly (a golden spiral)
    var at:[outer+inner]m.V3=undefined;
    for(&at,0..)|*p,i|{
      // which shell, and where on it
      const n:usize=if(i<outer)outer else inner;
      const k=if(i<outer)i else i-outer;
      const y=1-2*(m.f(k)+0.5)/m.f(n);
      const r=@sqrt(@max(1-y*y,0));
      const a=m.f(k)*m.goldenAngle+(if(i<outer)@as(f32,0)else 1.1);
      p.*=m.v3(@cos(a)*r,y,@sin(a)*r)*m.splat3(if(i<outer)@as(f32,1)else innerR);
    }
    // each point: a small octahedron of light
    for(at)|p|{
      // its six corners
      const c=[6]m.V3{m.v3(pointR,0,0),m.v3(-pointR,0,0),m.v3(0,pointR,0),m.v3(0,-pointR,0),m.v3(0,0,pointR),m.v3(0,0,-pointR)};
      for([8][3]u8{.{0,2,4},.{2,1,4},.{1,3,4},.{3,0,4},.{2,0,5},.{1,2,5},.{3,1,5},.{0,3,5}})|f|for(f)|v|try b.put(p+c[v],m.norm(c[v]),col,lit,0,.trail);
    }
    // each point joined to its nearest, every thread once
    for(at,0..)|p,i|{
      // its nearest, found by a short insertion
      var near:[joins]usize=@splat(0);
      var nearD:[joins]f32=@splat(1e9);
      for(at,0..)|q,j|{
        if(j==i)continue;
        // how far, and where it goes among the nearest
        const d=m.dist(p,q);
        var s:usize=joins;
        while(s>0 and d<nearD[s-1]):(s-=1){
          if(s<joins){
            nearD[s]=nearD[s-1];
            near[s]=near[s-1];
          }
        }
        if(s<joins){
          nearD[s]=d;
          near[s]=j;
        }
      }
      for(near)|j|{
        if(j<i)continue;
        try thread(b,p,at[j],col);
      }
    }
  }
  /// one thread of light from `a` to `z`: two strips crossed along it, so
  /// it shows from every side
  fn thread(b:*mg.Builder,a:m.V3,z:m.V3,col:color.Rgba8)Allocator.Error!void{
    // along it, and two ways across it
    const d=m.norm(z-a);
    const u=m.norm(m.cross(d,if(@abs(d[1])<0.9)m.v3(0,1,0)else m.v3(1,0,0)));
    const v=m.cross(d,u);
    for([_]m.V3{u,v})|w|{
      // the strip's corners: (end, side)
      for([_]m.Vice(f32,2){.{0,-1},.{1,1},.{1,-1},.{0,-1},.{0,1},.{1,1}})|c|{
        const p=m.lerpV(a,z,c[0])+w*m.splat3(c[1]*threadW);
        try b.put(p,m.cross(w,d),col,lit,c[1],.trail);
      }
    }
  }
};
