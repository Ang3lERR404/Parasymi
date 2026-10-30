//! mesh: BLOOM THREAD. soft rays sent between two celestial blooms: a flat
//! ribbon, its length running up +Y over 0..1 (tu.x), its width across x
//! from -1 to 1 (tu.y). part.vert (curve mode) carries it from one bloom's
//! core to the other's as a spindle and turns its width to face the eye,
//! so it reads from every side, never a wire; part.frag fills it with a
//! faint haze, soft streaks swelling from sender to receiver and tiny
//! drifting motes, the rainbow running from one end to the other. Part
//! `.thread`. Listed last: it blends over everything.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// the plant-piece mesher: the builder this ribbon is put into
const mg=lib.meshgen;
/// colour conversions, for the ribbon's warm base
const color=engine.core.color;
/// a point in space, made from three numbers
const v3=m.v3;
/// builds the ribbon: a flat strip 48 steps long up +Y (0..1) and two cells
/// wide across x (-1..1), every vertex carrying its place as (along, across)
/// for the shader, all warm white and drawn as `.thread`
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the warm white every vertex starts as; the shader paints the rainbow over it
  const warm=color.rgb(1.0,0.9,0.7).toRgba8(255);
  // how many steps run along the ribbon's length
  const n=48;
  // the three lines across the ribbon: one edge, the middle, the other edge
  const across=[_]f32{-1,0,1};
  for(0..n-1)|i|for(0..across.len-1)|j|{
    // where this cell starts and ends along the length (0..1)
    const k0=m.ratio(i,n-1);
    const k1=m.ratio(i+1,n-1);
    // the cell's four corners as (along, across), wound round the quad
    const q=[4][2]f32{.{k0,across[j]},.{k0,across[j+1]},.{k1,across[j+1]},.{k1,across[j]}};
    for([_]usize{0,1,2,0,2,3})|c|try b.put(v3(q[c][1],q[c][0],0),v3(0,0,1),warm,q[c][0],q[c][1],.thread);
  };
}
