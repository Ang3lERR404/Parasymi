//! mesh: PLUCK BURST. what bursts out where a plant's yield comes loose in
//! the paws: beads of its essence lying round a point a unit out, the
//! fewer above it motes of light that drift up, the rest drops of sap
//! that arc down. part.vert's burst placement flings each out the way it
//! lies and shrinks it away over the burst's life; the instance tints it
//! as the yield.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, angles
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// colour conversions: the beads are white under the yield's tint
const color=engine.core.color;
/// the engine's deterministic random stream: how the beads lie
const Rng=engine.core.rng.Rng;
/// makes a vector from three numbers
const v3=m.v3;
/// how many beads it flings
const beads=18;
/// each bead's radius (part.vert `BURST_BEAD`)
pub const beadR:f32=0.11;
/// every third bead is a mote of light; the rest are drops of sap
const moteEvery=3;
/// builds the burst: beads of white essence round the origin a unit out,
/// each tagged (tu.y) a mote (below 0.5) or a drop, and its own pace
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the burst's own random stream, and the beads' white
  var rng=Rng.init(0xB025);
  const white=color.rgb(1,1,1).toRgba8(255);
  for(0..beads)|i|{
    // whether it is a mote, the way out it lies (motes upward, drops
    // round about and a little up), and where its vertices begin
    const mote=i%moteEvery==0;
    const a=m.f(i)*m.goldenAngle+rng.range(-0.3,0.3);
    const up=if(mote)rng.range(0.5,1.0)else rng.range(-0.15,0.45);
    const dir=m.norm(v3(@cos(a),up,@sin(a)));
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=dir,.radii=m.splat3(beadR),.col=white,.part=.essence,.rings=4,.segs=6,.t=-1});
    // its kind and its pace
    const tag=(if(mote)@as(f32,0)else 0.5)+rng.range(0,0.49);
    for(b.v.items[s..])|*v|v.tu[1]=tag;
  }
}
