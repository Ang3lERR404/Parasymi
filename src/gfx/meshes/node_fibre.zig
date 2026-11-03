//! mesh: NODE FIBRE. a clump of fibre plant, drawn to read from above against
//! moss and its grass: three fans of long bronze strap leaves arching over,
//! the outer ones fraying at their tips into loose pale fibres trailing to
//! the ground, and between them a sheaf of slender flax stems, green at the
//! foot ripening to gold, each crowned by round golden seed bolls. From
//! above, a bronze star shot through with gold. It sways like any plant
//! (the instance's sway). Tile space, centred on the tile.
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
/// the structure kit, for the root mat at the clump's foot
const kit=lib.structureKit;
/// a seeded random stream
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// how many points a stalk or fibre is resampled to along its spline
const pts=14;
/// how many flax stems rise between the fans
const stemCount=20;
/// builds the clump: a root mat, its fans of leaves, then the flax stems
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the clump's own random stream, the same every build (the stream the
  // approved sample was drawn from, so the clump is that one exactly)
  var rng=pal.rngFor("node_fibre_blend");
  try kit.rootMat(b,6,0.32,0.045,0xF1D8,null);
  try fans(b,&rng);
  try stems(b,&rng);
}
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
      // which half of the fan it leans into (the middle leaf stands near upright)
      const half:f32=if(s<0)m.pi else 0;
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
/// the slender flax stems from the clump's heart, bowing out into a
/// starburst past the leaves, green at the foot ripening to gold, narrow
/// leaves up their lower half, each crowned by a few round seed bolls
fn stems(b:*mg.Builder,rng:*Rng)Allocator.Error!void{
  // the living green at the foot, the ripe gold of the stems, the bolls' gold
  const green=color.rgb(0.30,0.50,0.22).toRgba8(255);
  const gold=color.rgb(0.86,0.68,0.30).toRgba8(255);
  const boll=color.rgb(0.80,0.58,0.22).toRgba8(255);
  for(0..stemCount)|i|{
    // this stem's bearing, how far it bows out, and how tall it stands
    const a=m.ratio(i,stemCount)*m.tau*2.39996+rng.range(-0.2,0.2);
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
    // the bolls: a few short stalks off the top, each a round capsule of
    // plant tissue (not `.pod`: that role is a plant's ripening yield, drawn
    // see-through and swollen by the plant's ripeness, and reads as a flat disc)
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
