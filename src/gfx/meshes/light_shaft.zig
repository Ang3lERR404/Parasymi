//! meshes: LIGHT BEAM and LIGHT STRIP. the light grid's shafts of light:
//! a solcyriphon's night beam falling straight down from its lens onto
//! what is under it, and a heliocyra's strip, a band of light a tile wide
//! laid just over the ground the way it faces. Each a flat ribbon, its
//! length running up +Y over 0..1 (tu.x), its width across x from -1 to 1
//! (tu.y); tu.z says which (0 falling, 1 laid). part.vert (curve mode)
//! bends it from where it leaves to where it ends, a beam turned to the eye
//! from every side, `flutter` metres either side of its middle, a strip
//! laid flat facing the sky a tile wide (its `flutter` its whole length,
//! its `fade` how far along it this piece begins, as it is laid tile by
//! tile over the ground); part.frag fills it with light (part
//! `.shaft`, light itself: it lights the fog round it). Listed last: it
//! blends over everything.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, ratios
const m=engine.core.math;
/// the plant-piece mesher: the builder the ribbons are put into
const mg=lib.meshgen;
/// colour conversions, for the ribbons' white
const color=engine.core.color;
/// how many steps run along a shaft's length (so it bends and swells smoothly)
const steps=48;
/// the lines across a shaft: one edge, the middle, the other edge (so its
/// core runs true down the middle)
const across=[_]f32{-1,-0.5,0,0.5,1};
/// a ribbon `steps` long up +Y (0..1) and across x (-1..1), every vertex
/// carrying its place as (along, across) and `laid` (tu.z), white (the
/// shader gives it its light), drawn as `.shaft`
fn ribbon(b:*mg.Builder,laid:f32)Allocator.Error!void{
  // the white every vertex starts as, and where its vertices begin
  const white=color.rgb(1,1,1).toRgba8(255);
  const s=b.mark();
  for(0..steps)|i|for(0..across.len-1)|j|{
    // where this cell starts and ends along the length (0..1)
    const k0=m.ratio(i,steps);
    const k1=m.ratio(i+1,steps);
    // the cell's four corners as (along, across), wound round the quad
    const q=[4]m.Vice(f32,2){.{k0,across[j]},.{k0,across[j+1]},.{k1,across[j+1]},.{k1,across[j]}};
    for([_]usize{0,1,2,0,2,3})|c|try b.put(m.v3(q[c][1],q[c][0],0),m.v3(0,0,1),white,q[c][0],q[c][1],.shaft);
  };
  for(b.v.items[s..])|*v|v.tu[2]=laid;
}
/// mesh: LIGHT BEAM. a solcyriphon's night beam, falling
pub const beam=struct{
  /// builds the ribbon, marked falling
  pub fn build(b:*mg.Builder)Allocator.Error!void{try ribbon(b,0);}
};
/// mesh: LIGHT STRIP. a heliocyra's strip, laid over the ground
pub const strip=struct{
  /// builds the ribbon, marked laid
  pub fn build(b:*mg.Builder)Allocator.Error!void{try ribbon(b,1);}
};
