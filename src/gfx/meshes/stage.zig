//! meshes: the main menu's stage (game/title.zig). The mossy mound the
//! wolf sleeps on, and what drifts down out of the dark over him: single
//! petals, small whole flowers (stamens and all), winged seeds with their
//! fluff, and glowing grains of pollen. Each piece is built at its true
//! size round its own middle; part.vert drops, sways and tumbles it.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, angles
const m=engine.core.math;
/// the mesh builder, its primitives, petals and stamens
const mg=lib.meshgen;
/// colour conversions and mixing
const color=engine.core.color;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// the mound: a low, softly lumpy dome of moss and soil the stage's light
/// falls on, its moss giving way to bare soil and then to the dark at its
/// rim, where it sinks below the ground plane (so no edge is ever seen)
pub const mound=struct{
  /// how far across the mound reaches from its middle (metres)
  pub const r:f32=5.5;
  /// how high its middle stands over the ground plane (metres)
  pub const top:f32=0.02;
  /// how far below the ground plane its rim sinks (metres)
  const sink:f32=0.5;
  /// how many rings out from its middle, and points round each
  const rings=40;
  /// how many points round each ring (the last one the first again)
  const around=73;
  /// how high its lumps rise (metres)
  const lump:f32=0.025;
  /// its surface's height `d` out from the middle along bearing `a`: a
  /// smooth dome, softly lumpy
  pub fn height(d:f32,a:f32)f32{
    // how far out, 0 middle .. 1 rim
    const k=m.clamp01(d/r);
    const dome=top-(top+sink)*k*k*k;
    return dome+lump*(1-k)*(@sin(d*3.1+a*2)*@sin(a*5+d*1.7)*0.6+@sin(d*7.3-a*3)*0.4);
  }
  /// builds the dome as rings of points from its middle out, coloured moss
  /// to soil to the dark as they go
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the moss at the middle, the soil past it, the dark at the rim
    const moss=color.rgb(0.13,0.19,0.07).toRgba8(255);
    const soil=color.rgb(0.07,0.055,0.035).toRgba8(255);
    const dark=color.rgb(0.006,0.005,0.008).toRgba8(255);
    // the points, their normals, colours and how far out each is
    var pts:[rings*around]V3=undefined;
    var nrms:[rings*around]V3=undefined;
    var cols:[rings*around]color.Rgba8=undefined;
    var us:[rings*around]f32=undefined;
    // how far either side a normal's slope is measured (metres)
    const e:f32=0.01;
    for(0..rings)|i|for(0..around)|j|{
      // how far out this ring is, and the bearing round it
      const k=m.ratio(i,rings-1);
      const d=r*k;
      const a=m.ratio(j,around-1)*m.tau;
      const at=i*around+j;
      // the point (every ring's point at the middle is the one middle)
      const x=@cos(a)*d;
      const z=@sin(a)*d;
      pts[at]=v3(x,height(d,a),z);
      // its normal, from the slope either way across the ground
      const hx=height(m.len(v3(x+e,0,z)),angle(x+e,z))-height(m.len(v3(x-e,0,z)),angle(x-e,z));
      const hz=height(m.len(v3(x,0,z+e)),angle(x,z+e))-height(m.len(v3(x,0,z-e)),angle(x,z-e));
      nrms[at]=m.norm(v3(-hx,2*e,-hz));
      // moss in the middle, soil past it, dark at the rim
      cols[at]=if(k<0.22)color.mix(moss,soil,m.smooth(k/0.22))else color.mix(soil,dark,m.smooth(m.clamp01((k-0.22)/0.4)));
      us[at]=k;
    };
    try mg.patch(b,rings,around,&pts,&nrms,&cols,&us,1,.leaf);
  }
  /// the bearing of ground point (`x`, `z`) from the middle
  fn angle(x:f32,z:f32)f32{return m.atan2(z,x);}
};
/// a petal fallen loose: soft rose to a pale tip, cupped, its claw at the
/// middle
pub const petal=struct{
  /// builds one petal, centred on its own middle
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try mg.petal(b,.{.base=v3(-0.025,0,0),.out=v3(1,0,0),.len=0.05,.width=0.016,.rise=0.15,.flare=0.35,.cup=0.5,
      .col=color.rgb(0.86,0.42,0.6).toRgba8(255),.tip=color.rgb(0.98,0.8,0.88).toRgba8(255)});
  }
};
/// a small whole flower fallen from somewhere above: five petals round a
/// gold heart, its stamens standing in it
pub const flower=struct{
  /// how many petals it has
  const n=5;
  /// builds the flower, facing up, centred on its heart
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the petals' claw and tip colours: a violet bloom paling to its edge
    const col=color.rgb(0.55,0.42,0.9).toRgba8(255);
    const tip=color.rgb(0.86,0.8,1.0).toRgba8(255);
    for(0..n)|i|{
      // the way this petal opens out
      const a=m.ratio(i,n)*m.tau;
      try mg.petal(b,.{.base=v3(0,0,0),.out=v3(@cos(a),0,@sin(a)),.len=0.03,.width=0.013,.rise=0.5,.flare=0.6,.cup=0.35,.col=col,.tip=tip});
    }
    try mg.stamens(b,.{.heart=v3(0,0.002,0),.axis=v3(0,1,0),.n=6,.len=0.012,.r=0.0007,.anther=0.0025,.col=color.rgb(0.95,0.9,0.7).toRgba8(255),.seed=0x5F1A});
    try mg.ellipsoid(b,.{.center=v3(0,0.001,0),.radii=v3(0.004,0.003,0.004),.col=color.rgb(0.95,0.75,0.3).toRgba8(255),.part=.leaf,.rings=6,.segs=8,.t=1});
  }
};
/// a seed borne on its fluff: a slim seed, a fine beak up from it, and a
/// crown of feathery threads spread out over it like a small parasol
pub const seed=struct{
  /// how many threads its crown spreads
  const threads=14;
  /// how many points along each thread
  const pts=6;
  /// builds the seed, centred near its crown
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the seed's brown, the beak's pale green, the fluff's white
    const brown=color.rgb(0.42,0.3,0.18).toRgba8(255);
    const beak=color.rgb(0.75,0.82,0.62).toRgba8(255);
    const fluff=color.rgb(0.97,0.96,0.92).toRgba8(255);
    try mg.ellipsoid(b,.{.center=v3(0,-0.03,0),.radii=v3(0.0025,0.007,0.0025),.col=brown,.part=.leaf,.rings=6,.segs=8,.t=1});
    // the beak up to the crown
    var stalk=[_]V3{v3(0,-0.024,0),v3(0,-0.012,0),v3(0,0,0)};
    var st:[3]f32=@splat(1);
    try b.tube(&stalk,&st,0.0006,0.0004,beak,.stem,4);
    for(0..threads)|i|{
      // the way this thread spreads out, rising a little then drooping
      const a=m.ratio(i,threads)*m.tau;
      const out=v3(@cos(a),0,@sin(a));
      var path:[pts]V3=undefined;
      var ts:[pts]f32=undefined;
      for(&path,&ts,0..)|*p,*t,j|{
        // how far along the thread this point is
        const k=m.ratio(j,pts-1);
        p.*=out*m.splat3(0.022*k)+v3(0,0.006*k-0.004*k*k,0);
        t.*=1;
      }
      try b.tube(&path,&ts,0.0003,0.00015,fluff,.leaf,3);
    }
  }
};
/// a grain of pollen lit from within: a small soft bead that glows (the
/// instance's glow)
pub const pollen=struct{
  /// builds the bead, round its middle
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(0.006,0.006,0.006),.col=color.rgb(1,0.88,0.55).toRgba8(255),.part=.bloom,.rings=6,.segs=8,.t=1});
  }
};
