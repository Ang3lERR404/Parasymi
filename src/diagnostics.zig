//! This module is built for the sole purpose of finding any bugs in the code
//! or silent errors that are hard to pin down.
//! any and all of these functions should not be touched unless it is absolutely necessary.
//! changing the behavior of these functions is prohibited unless stated otherwise.
//! changing the functionality will always result in erroneous bugs or confusing results.
//! these should be kept as is.
//! never optimize them.
//! never "clean" them.
//! only improve upon/add to them.
//! do not change any imports.
//! do not remove any imports.
//! do not do x
//! do not do y
//! simply, do not.
//! only use them.
//! STRICT RULE ENFORCED BY USER.
//! ANY VIOLATION WILL RESULT IN AN IMMEDIATE REPORT OR TERMINATION.
/// the import hub every game module is reached through
const lib=@import("lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type, for helpers that keep memory
const Allocator=std.mem.Allocator;
/// which tag of a tagged union is active
const activeTag=std.meta.activeTag;
/// the test helpers: expectations and the testing allocator
const testing=std.testing;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, footprints, limits
const m=engine.core.math;
/// the engine's registry helpers: kinds, hooks, dispatch
const registry=engine.core.registry;
/// the garden's chunk: tile heights, kinds and occupancy
const ck=lib.ck;
/// the streamed world of chunks
const World=lib.world.World;
/// what can be held: item kinds and stacks
const items=lib.items;
/// the plant species registry
const species=lib.species;
/// the store of every plant in the garden
const Plants=lib.plants.Plants;
/// the ley field the ecology draws mana from
const Field=lib.ecology.Field;
/// what the ecology tick reports: births, deaths, drains
const Events=lib.ecology.Events;
/// the vine-wolf the gardener plays
const Player=lib.player.Player;
/// the sky: time of day, sun and stars
const Sky=lib.sky.Sky;
/// the mesh library: every built mesh
const meshlib=lib.meshlib;
/// what the gardener has understood
const prog=lib.progression;
/// the scene's per-frame list of rigid parts
const Parts=lib.parts.Parts;
/// the UI's draw batch
const Draw=engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=engine.ui.draw.Color;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// turning what stands
const turn=lib.turn;
/// a value as a record of named fields
const record=lib.record;
/// the structures registry
const structures=lib.structures;
/// the store of every structure in the garden
const Structures=structures.Structures;
/// which kind a structure is
const Kind=structures.Kind;
/// each structure kind's definition: size, floating, mesh
const defs=structures.defs;
/// prints why a structure of kind `k` can't stand at tile (`wx`,`wy`):
/// for a floater whether the spot is taken, else the anchor's height and
/// each footprint tile's occupancy, kind and height, then `canPlace`'s answer
pub fn whyNot(ss:*const Structures,w:*const World,wx:i32,wy:i32,k:Kind)void{
  // the kind's definition
  const d=defs.get(k);
  if(d.floating){
    std.debug.print("floating {s}\n",.{if(ss.floaterAt(wx,wy)!=null)"occupied"else"ok"});
    return;
  }
  // the chunk under the anchor tile, and the anchor's height
  const c0=w.chunkOfTile(wx,wy)orelse{std.debug.print("chunk not loaded\n",.{});return;};
  const h0=c0.height[ck.localIndex(wx,wy)];
  std.debug.print("anchor h={d}\n",.{h0});
  // every tile the footprint covers
  var it=m.footprint(wx,wy,d.size);
  while(it.next())|p|{
    // the chunk this footprint tile is in, and its index in that chunk
    const c=w.chunkOfTile(p[0],p[1])orelse{std.debug.print("tile ({d},{d}) chunk missing\n",.{p[0],p[1]});continue;};
    const t=ck.localIndex(p[0],p[1]);
    std.debug.print("Tile ({d},{d}): occ={any} kind={any} h={d}\n",.{p[0],p[1],c.occ[t],c.kind[t],c.height[t]});
  }
  std.debug.print("canPlace={any}\n",.{ss.canPlace(w,wx,wy,k)});
}
