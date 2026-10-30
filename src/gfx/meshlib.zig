//! catalogue of rigid procedural part meshes, one module (or a companion
//! struct inside its owner's module) each under
//! `meshes/` exposing `build(b)`. Each is built once at startup in its own
//! local space; anything "made of parts" (the player, resource nodes, motes,
//! structures) draws instances of these with a per-instance transform, so
//! procedural animation is just transform math.
//!
//! A new mesh is one new file (or struct) plus one line in `parts`.
const lib=@import("../lib.zig");
const std=lib.std;
const assert=std.debug.assert;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const mg=lib.meshgen;
const registry=engine.core.registry;
const parts=struct{
  // drawn first: a flat soft patch on the ground under floaters
  pub const shadow=@import("meshes/shadow.zig");
  // the vine-wolf: one skinned body, then what is see-through over it
  pub const wolfBody=@import("meshes/wolf_body.zig");
  pub const wolfEars=@import("meshes/wolf_ears.zig");
  // drawn before the belly so the translucent sac blends over them
  pub const bellyLump=@import("meshes/belly_lump.zig");
  pub const wolfBelly=@import("meshes/wolf_belly.zig");
  pub const wolfPecL=@import("meshes/wolf_pec.zig").left;
  pub const wolfPecR=@import("meshes/wolf_pec.zig").right;
  pub const wolfRumpL=@import("meshes/wolf_rump.zig").left;
  pub const wolfRumpR=@import("meshes/wolf_rump.zig").right;
  pub const pawPad=@import("meshes/paw_pad.zig");
  pub const pawBean=@import("meshes/paw_pad.zig").bean;
  // the world
  pub const nodeGrit=@import("meshes/node_grit.zig");
  pub const nodeFibre=@import("meshes/node_fibre.zig");
  pub const nodeLey=@import("meshes/node_ley.zig");
  pub const mote=@import("meshes/mote.zig");
  // structures
  pub const conduit=@import("meshes/conduit.zig");
  pub const conduitLeft=@import("meshes/conduit.zig").left;
  pub const conduitRight=@import("meshes/conduit.zig").right;
  pub const conduitTap=@import("meshes/conduit.zig").tap;
  pub const braidedConduit=@import("meshes/braided_conduit.zig");
  pub const braidWrap=@import("meshes/braided_conduit.zig").wrap;
  pub const braidWrapLeft=@import("meshes/braided_conduit.zig").wrapLeft;
  pub const braidWrapRight=@import("meshes/braided_conduit.zig").wrapRight;
  pub const braidLane0=@import("meshes/braided_conduit.zig").Lane(0,0);
  pub const braidLane1=@import("meshes/braided_conduit.zig").Lane(0,1);
  pub const braidLane2=@import("meshes/braided_conduit.zig").Lane(0,2);
  pub const braidLane3=@import("meshes/braided_conduit.zig").Lane(0,3);
  pub const braidLane0Left=@import("meshes/braided_conduit.zig").Lane(1,0);
  pub const braidLane1Left=@import("meshes/braided_conduit.zig").Lane(1,1);
  pub const braidLane2Left=@import("meshes/braided_conduit.zig").Lane(1,2);
  pub const braidLane3Left=@import("meshes/braided_conduit.zig").Lane(1,3);
  pub const braidLane0Right=@import("meshes/braided_conduit.zig").Lane(-1,0);
  pub const braidLane1Right=@import("meshes/braided_conduit.zig").Lane(-1,1);
  pub const braidLane2Right=@import("meshes/braided_conduit.zig").Lane(-1,2);
  pub const braidLane3Right=@import("meshes/braided_conduit.zig").Lane(-1,3);
  pub const sapCacheLid=@import("meshes/sap_cache.zig").lid;
  pub const sapCache=@import("meshes/sap_cache.zig");
  pub const germinator=@import("meshes/germinator.zig");
  pub const germinatorWhole=@import("meshes/germinator.zig").whole;
  pub const germinatorCup=@import("meshes/germinator.zig").cup;
  pub const germinatorPool=@import("meshes/germinator.zig").pool;
  pub const germinatorPour=@import("meshes/germinator.zig").pour;
  pub const germinatorVortex=@import("meshes/germinator.zig").vortex;
  pub const germinatorThread=@import("meshes/germinator.zig").thread;
  pub const germinatorSeed=@import("meshes/germinator.zig").seed;
  pub const germinatorWinding=@import("meshes/germinator.zig").winding;
  // (see-through: blends over what spins inside it)
  pub const germinatorCore=@import("meshes/germinator.zig").core;
  pub const arsthraxia=@import("meshes/arsthraxia.zig");
  pub const arsthraxiaWhole=@import("meshes/arsthraxia.zig").whole;
  pub const arsthraxiaWhorl=@import("meshes/arsthraxia.zig").whorl;
  pub const arsthraxiaCup=@import("meshes/arsthraxia.zig").cup;
  pub const arsthraxiaVines=@import("meshes/arsthraxia.zig").vines;
  pub const arsthraxiaShoot=@import("meshes/arsthraxia.zig").shoot;
  pub const arsthraxiaSatellite=@import("meshes/arsthraxia.zig").satellite;
  // (light: blends over the satellites spinning round it)
  pub const arsthraxiaCore=@import("meshes/arsthraxia.zig").core;
  pub const arsthraxiaWisp=@import("meshes/arsthraxia.zig").wisp;
  pub const itemPod=@import("meshes/item_pod.zig");
  pub const rootDigger=@import("meshes/root_digger.zig");
  pub const diggerRoot=@import("meshes/root_digger.zig").root;
  pub const diggerClod=@import("meshes/root_digger.zig").clod;
  pub const loomfern=@import("meshes/loomfern.zig");
  pub const loomfernSheaf=@import("meshes/loomfern.zig").sheaf;
  pub const loomfernThread=@import("meshes/loomfern.zig").thread;
  pub const crownRoot1=@import("meshes/gathering_crown.zig").Root(0);
  pub const crownRoot2=@import("meshes/gathering_crown.zig").Root(1);
  pub const crownRoot3=@import("meshes/gathering_crown.zig").Root(2);
  pub const crownRoot4=@import("meshes/gathering_crown.zig").Root(3);
  pub const crownRoot5=@import("meshes/gathering_crown.zig").Root(4);
  pub const gatheringCrown=@import("meshes/gathering_crown.zig");
  pub const lithophage=@import("meshes/lithophage.zig");
  pub const lithophageCrystal=@import("meshes/lithophage.zig").crystal;
  pub const lithophageRoot=@import("meshes/lithophage.zig").root;
  pub const lithophageRootFar=@import("meshes/lithophage.zig").rootFar;
  // what a rooted thing walks on while it turns (R)
  pub const turnRoot=@import("meshes/turn_root.zig");
  pub const turnRootPale=@import("meshes/turn_root.zig").pale;
  pub const ganglionNerve=@import("meshes/ganglion.zig").nerve;
  // (see-through: blends over what hangs inside it)
  pub const ganglion=@import("meshes/ganglion.zig");
  // (see-through: blends over what hangs inside it)
  pub const sporecaster=@import("meshes/sporecaster.zig");
  pub const sporeCarrier=@import("meshes/sporecaster.zig").carrier;
  // the convergent structures (see-through: blend over what hangs inside)
  pub const weftstoneTendril=@import("meshes/weftstone.zig").tendril;
  pub const monfrisTether=@import("meshes/monfris.zig").tether;
  pub const driftbraid=@import("meshes/driftbraid.zig");
  pub const monfris=@import("meshes/monfris.zig");
  pub const vultrixi=@import("meshes/vultrixi.zig");
  pub const weftstone=@import("meshes/weftstone.zig");
  // the halo: its polyp and the diamond it forms
  pub const polyp=@import("meshes/polyp.zig");
  pub const haloDiamond=@import("meshes/halo.zig").diamond;
  // translucent, over everything
  pub const haloProjection=@import("meshes/halo.zig").projection;
  pub const haloRing=@import("meshes/halo.zig").ring;
  pub const haloFlash=@import("meshes/halo.zig").flash;
  pub const bloomThread=@import("meshes/bloom_thread.zig");
};
const reg=registry.Registry(parts);
pub const Id=reg.Id;
pub const count=reg.count;
pub const ids=reg.ids;
/// every library mesh at each level of detail (one slot per mesh and level,
/// see `slot`).
pub const slots=count*mg.lods;
/// where a mesh at a level of detail sits in per-slot tables.
pub fn slot(id:Id,lod:u32)usize{return@as(usize,@intFromEnum(id))*mg.lods+lod;}
/// build one mesh at one level of detail into `b` (leaving `b.lod` there),
/// recording its (first vertex, count).
pub fn buildOne(b:*mg.Builder,id:Id,lod:u32,ranges:*[slots][2]u32)Allocator.Error!void{
  b.lod=lod;
  const first=b.mark();
  switch(id){
    inline else=>|k|try reg.module(k).build(b),
  }
  // a skeleton left unfinished leaves its times past one (never grown)
  if(b.grow.items.len>first)for(b.grow.items[first..])|g|assert(g.at[0]+g.at[1]<=1+1e-4);
  ranges[slot(id,lod)]=.{@intCast(first),@intCast(b.mark()-first)};
}
