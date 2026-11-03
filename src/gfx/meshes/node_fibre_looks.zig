//! mesh: three looks for the fibre node, laid side by side (`--samples=`) for
//! the gardener to choose from. Each is drawn to read from above against
//! moss and its grass: a golden flax starburst (`flax`), a fan of bronze
//! strap leaves fraying into fibre at their tips (`harakeke`), and a twisted
//! rope of stalk bursting into a fountain of pale fibre (`sheaf`). Tile
//! space, centred on the tile; each sways as the node does.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, splines, easing
const m=engine.core.math;
/// the mesh builder, its primitives and leaves
const mg=lib.meshgen;
/// the shared swatches, and the per-mesh random stream
const pal=lib.palette;
/// colour conversions and mixing, for the ramps along stalks and fibres
const color=engine.core.color;
/// the structure kit, for the root mat at a clump's foot
const kit=lib.structureKit;
/// a seeded random stream
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// how many points a stalk or fibre is resampled to along its spline
const pts=14;
/// one stalk's or fibre's shape: its control points, its radius at the root
/// and at the tip (a share of the root's), its colour at the root and tip,
/// where along it the colour turns, and the growth stamps it spans
const Strand=struct{
  /// its control points, root first
  ctrl:[]const V3,
  /// its radius at the root
  r0:f32,
  /// its tip's radius, a share of the root's
  tip:f32=0.08,
  /// its colour at the root
  c0:color.Rgba8,
  /// its colour at the tip
  c1:color.Rgba8,
  /// how far along the colour has fully turned (0..1)
  turn:f32=1,
  /// its growth stamp at the root
  t0:f32=0,
  /// its growth stamp at the tip
  t1:f32=1,
  /// how many sides its tube has round
  sides:u32=4,
};
/// lays one strand: its spline resampled smooth, tapering root to tip and
/// fading colour, a tube closed at both ends. Returns its resampled points.
fn strand(b:*mg.Builder,s:Strand)Allocator.Error![pts]V3{
  // the strand resampled along its spline
  var p:[pts]V3=undefined;
  m.splineResample(s.ctrl,&p);
  // each point's growth stamp, radius and colour
  var ts:[pts]f32=undefined;
  var rs:[pts]f32=undefined;
  var cs:[pts]color.Rgba8=undefined;
  for(&ts,&rs,&cs,0..)|*t,*r,*c,j|{
    // how far along the strand, 0 root .. 1 tip
    const k=m.ratio(j,pts-1);
    t.*=m.lerp(s.t0,s.t1,k);
    r.*=@max(s.r0*m.lerp(1,s.tip,k),0.0006);
    c.*=color.mix(s.c0,s.c1,m.smooth(m.clamp01(k/s.turn)));
  }
  try b.tubeC(&p,&ts,&rs,&cs,null,.stem,s.sides);
  return p;
}
/// the flat way out at bearing `a`
fn bearing(a:f32)V3{return v3(@cos(a),0,@sin(a));}
/// flax: a tight tuft of many slender stems, twice the grass's height,
/// bowing out into a starburst, green at the foot ripening to gold, narrow
/// leaves up their lower half, each crowned by a cluster of round golden
/// seed bolls on short stalks. From above, a gold star dotted with bolls.
pub const flax=struct{
  /// builds the tuft: a root mat, then its stems, leaves and bolls
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the tuft's own random stream, the same every build
    var rng=pal.rngFor("node_fibre_flax");
    try kit.rootMat(b,6,0.3,0.04,0xF1A8,null);
    try stems(b,&rng,30,.bolls);
  }
};
/// what crowns each flax stem
const Crown=enum{
  /// a cluster of round seed bolls on short stalks
  bolls,
  /// nothing: the stem tapers to a bare golden point
  bare,
};
/// `n` slender flax stems from a tight tuft, bowing out into a starburst,
/// green at the foot ripening to gold, narrow leaves up their lower half,
/// each crowned as `crown` says
fn stems(b:*mg.Builder,rng:*Rng,n:u32,crown:Crown)Allocator.Error!void{
  // the living green at the foot, the ripe gold of the stems, the bolls' gold
  const green=color.rgb(0.30,0.50,0.22).toRgba8(255);
  const gold=color.rgb(0.86,0.68,0.30).toRgba8(255);
  const boll=color.rgb(0.80,0.58,0.22).toRgba8(255);
  for(0..n)|i|{
    // this stem's bearing, how far it bows out, and how tall it stands
    const a=m.ratio(i,n)*m.tau*2.39996+rng.range(-0.2,0.2);
    const out=bearing(a);
    const lean=rng.range(0.12,0.55);
    const len=rng.range(0.75,1.05);
    // the stem's control points: out of the tuft, bowing over as it rises
    var c:[6]V3=undefined;
    mg.growthPath(.{.start=out*m.splat3(rng.range(0.01,0.05)),.direction=m.norm(out*m.splat3(lean*0.6)+v3(0,1,0)),.length=len,.wobble=0.12,.curl=0,.seed=0xF1A0+%i},&c);
    for(c[1..],1..)|*p,j|{
      // how far up the stem this point lies, 0..1
      const k=m.ratio(j,5);
      p.*+=out*m.splat3(0.22*k*k*lean)-v3(0,0.1*k*k*k*lean,0);
    }
    const p=try strand(b,.{.ctrl=&c,.r0=0.007,.tip=0.35,.c0=green,.c1=gold,.turn=0.45});
    // narrow leaves up its lower half
    for(0..3)|l|{
      // how far up the stem this leaf sits, and the way it reaches
      const k=0.12+0.12*m.f(l);
      const at=p[@intFromFloat(k*(pts-1))];
      const dir=m.norm(bearing(a+rng.range(-1.4,1.4))+v3(0,0.9,0));
      try mg.natural(b,at,dir,rng.range(0.06,0.1),0.011,0.3,pal.leafDark,color.mix(pal.leafLite,gold,0.5),0.2+k*0.6,.sessile);
    }
    // the bolls: a few short stalks off the top, each a round capsule
    if(crown==.bare)continue;
    const top=p[pts-1];
    const up=m.norm(p[pts-1]-p[pts-3]);
    const nb=2+rng.below(2);
    for(0..nb)|q|{
      // this boll's way off the top, and where it hangs
      const d=m.norm(up+bearing(a+m.f(q)*2.1+rng.range(0,1))*m.splat3(0.9));
      const at=top+d*m.splat3(rng.range(0.03,0.05));
      var sc=[3]V3{top,m.lerpV(top,at,0.5)+v3(0,0.005,0),at};
      _=try strand(b,.{.ctrl=&sc,.r0=0.0035,.tip=0.6,.c0=gold,.c1=gold,.t0=0.85,.t1=0.95,.sides=3});
      const r=rng.range(0.018,0.026);
      try mg.ellipsoid(b,.{.center=at+d*m.splat3(r*0.8),.radii=v3(r,r*1.15,r),.col=boll,.part=.leaf,.rings=8,.segs=10,.t=1});
    }
  }
}
/// harakeke: three fans of long, broad strap leaves rising from a root
/// mat, bronze with a darker base, arching over under their weight; the
/// outer leaves' tips split and fray into loose pale fibres trailing to the
/// ground. From above, a large bronze star frayed at its points.
pub const harakeke=struct{
  /// builds the clump: a root mat, then its fans of leaves and their frayed tips
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the clump's own random stream, the same every build
    var rng=pal.rngFor("node_fibre_harakeke");
    try kit.rootMat(b,6,0.32,0.045,0xF1B8,null);
    try fans(b,&rng);
  }
};
/// harakeke and flax together: the bronze fans of strap leaves fraying at
/// their tips, and between them a sheaf of slender golden flax stems rising
/// past the leaves, crowned with their seed bolls. From above, a bronze
/// star shot through with gold.
pub const blend=struct{
  /// builds the clump: a root mat, its fans of leaves, then the flax stems
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the clump's own random stream, the same every build
    var rng=pal.rngFor("node_fibre_blend");
    try kit.rootMat(b,6,0.32,0.045,0xF1D8,null);
    try fans(b,&rng);
    try stems(b,&rng,20,.bolls);
  }
};
/// three fans of long bronze strap leaves, the outer ones arching over and
/// fraying at their tips into loose pale fibres trailing to the ground
fn fans(b:*mg.Builder,rng:*Rng)Allocator.Error!void{
  // the dark base, the bronze blade, the warm tip, and the loose fibre
  const base=color.rgb(0.30,0.16,0.10).toRgba8(255);
  const bronze=color.rgb(0.62,0.32,0.18).toRgba8(255);
  const tipCol=color.rgb(0.78,0.52,0.30).toRgba8(255);
  const fibre=color.rgb(0.90,0.80,0.58).toRgba8(255);
  for(0..3)|f|{
    // this fan's bearing: its leaves lie in its plane, outer ones lower
    const fa=m.ratio(f,3)*m.tau+rng.range(-0.3,0.3);
    const from=bearing(fa+m.halfPi)*m.splat3(0.04);
    for(0..5)|i|{
      // where in the fan this leaf stands (-1 .. 1), and its lean
      const s=m.ratio(i,4)*2-1;
      const lean=0.15+0.75*@abs(s);
      const side:f32=if(s<0)-1 else 1;
      // which half of the fan it leans into (the middle leaf stands near upright)
      const half:f32=if(side<0)m.pi else 0;
      const a=fa+(if(@abs(s)<0.01)rng.range(-0.3,0.3)else half)+rng.range(-0.25,0.25);
      const len=rng.range(0.7,1.0)*(1.1-0.25*@abs(s));
      const dir=m.norm(bearing(a)*m.splat3(lean)+v3(0,1.1-lean*0.6,0));
      try mg.leaf(b,.{
        .at=from+bearing(a)*m.splat3(0.03),.dir=dir,.len=len,.width=0.055,
        .droop=0.25+0.55*lean,.curl=0.1,.twist=rng.range(-0.5,0.5),.wave=0.04,
        .col=color.mix(base,bronze,0.35),.tip=tipCol,.stalkCol=base,.t=0.2+0.3*@abs(s),
      });
      // the outer leaves fray at their tips into loose fibres
      if(@abs(s)<0.5)continue;
      // where the blade's tip lands: as the leaf's midrib reaches it
      const tip=from+dir*m.splat3(len)+v3(0,len*(0.35-(0.25+0.55*lean)-0.1),0);
      const out=bearing(a);
      for(0..5)|q|{
        // this fibre's spread and how far it trails toward the ground
        const sp=bearing(a+(m.ratio(q,4)-0.5)*0.9);
        const fl=rng.range(0.18,0.32);
        var c=[4]V3{tip-out*m.splat3(0.05),tip+sp*m.splat3(fl*0.35),tip+sp*m.splat3(fl*0.7)-v3(0,fl*0.3,0),tip+sp*m.splat3(fl)-v3(0,fl*0.75,0)};
        _=try strand(b,.{.ctrl=&c,.r0=0.004,.tip=0.3,.c0=tipCol,.c1=fibre,.turn=0.4,.t0=0.85,.t1=1,.sides=3});
      }
    }
  }
}
/// sheaf: a stout stalk of six strands twisted together like rope, rising
/// to knee height from a rosette of leaves, unravelling at its top into a
/// fountain of fine pale fibres that arch out and fall back to the ground.
/// From above, a wide cream fountain round a dark knot.
pub const sheaf=struct{
  /// builds the sheaf: a root mat and rosette, the twisted stalk, the fountain
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the sheaf's own random stream, the same every build
    var rng=pal.rngFor("node_fibre_sheaf");
    try kit.rootMat(b,5,0.26,0.04,0xF1C8,null);
    // the green stalk, the straw it dries to, and the fibre's pale cream
    const green=color.rgb(0.32,0.48,0.22).toRgba8(255);
    const straw=color.rgb(0.70,0.58,0.34).toRgba8(255);
    const cream=color.rgb(0.95,0.90,0.74).toRgba8(255);
    // the rosette at its foot
    for(0..7)|i|{
      // this leaf's bearing
      const a=m.ratio(i,7)*m.tau+rng.range(-0.2,0.2);
      try mg.natural(b,bearing(a)*m.splat3(0.03)+v3(0,0.01,0),m.norm(bearing(a)+v3(0,0.25,0)),rng.range(0.16,0.22),0.05,0.45,pal.leafDark,pal.leafLite,0.1,.stalked);
    }
    // the stalk's height, and how far its strands wind round it
    const h=0.5;
    const turns=1.6;
    for(0..6)|i|{
      // this strand's place round the rope
      const a0=m.ratio(i,6)*m.tau;
      var c:[8]V3=undefined;
      for(&c,0..)|*p,j|{
        // how far up the rope, and how far round this strand has wound
        const k=m.ratio(j,7);
        const a=a0+k*turns*m.tau;
        p.*=bearing(a)*m.splat3(0.028*(1+0.3*k))+v3(0,h*k,0);
      }
      _=try strand(b,.{.ctrl=&c,.r0=0.016,.tip=0.7,.c0=green,.c1=straw,.t1=0.5,.sides=5});
    }
    // the fountain: fine fibres springing from the top, arching out and falling
    for(0..48)|i|{
      // this fibre's bearing, how far it reaches, how high it arches first
      const a=m.ratio(i,48)*m.tau*2.39996+rng.range(-0.15,0.15);
      const out=bearing(a);
      const reach=rng.range(0.35,0.62);
      const rise=rng.range(0.06,0.18);
      const top=v3(0,h,0)+out*m.splat3(0.03);
      var c=[5]V3{
        top-v3(0,0.04,0),
        top+out*m.splat3(reach*0.2)+v3(0,rise,0),
        top+out*m.splat3(reach*0.55)+v3(0,rise*0.6,0),
        top+out*m.splat3(reach*0.85)-v3(0,h*0.35,0),
        top+out*m.splat3(reach)-v3(0,h*rng.range(0.6,0.85),0),
      };
      _=try strand(b,.{.ctrl=&c,.r0=0.0045,.tip=0.25,.c0=straw,.c1=cream,.turn=0.3,.t0=0.5,.t1=1,.sides=3});
    }
  }
};
