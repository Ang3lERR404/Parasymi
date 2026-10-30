//! grown structures: the first steps from hand work toward automation.
//!
//! Each kind is its own module under `structures/` declaring:
//!   def:Def                     name, bulb item, footprint, mesh   (required)
//!   State                       per-kind data (optional, see `State` union)
//!   tick(ctx, id, dt) [!]bool   advance; returns whether it is active
//!                               (`Ctx`: the garden, and in the game the
//!                               wolf, the sky and this tick's events)
//!   link(ctx, id)               notice its neighbours, every tick, grown or not
//!   wants(s, g, item) u32       how many of `item` it will still take in
//!   output(s) ?Item             what may leave it first (pulled by conduits)
//!   gives(s, item) bool         whether `item` may leave it (default: it is
//!                               its `output`); a braided conduit's lanes
//!                               pull a different item each. `outputs` walks
//!                               all that may leave (`handOff` offers each)
//!   receive(s, g, item, edge) bool  a carrier taking an item handed in at
//!                               `edge` (counted from the way it faces)
//!   release(s) ?Item            hand back anything it holds outside `inv`
//!   message(ctx, id, msg) Reply what it makes of a `Msg` another sends it
//!                               (`Structures.send`; `.ignored`: the
//!                               message's default)
//!   configure(ss, id, g)        the player's "C" interaction (it may reach
//!                               another structure: `Structures.pairing`)
//!   recipes() []const u8        what its panel offers to weave (indices into
//!                               `craft.hand`); `chosen(s)` is the one it
//!                               weaves, `choose(s, g, r)` sets it
//!   emit(s, out, ctr, tf)       extra visuals beyond its mesh (placed as it is:
//!                               `place(s, ctr)`)
//!   describe(s, d, g, x, y)     one line of hover text
//!   ground(kind) bool           which tiles it may stand on (default: any tile)
//!   field(s) ?Field             a field of celestial energy it holds
//!   hold(s, x, y) ?Hold         how it draws the floater at a tile toward itself
//!   size(s) f32                 how much larger than its mesh it has grown
//!                               (by research), its growing in aside
//!   icon(ic, col)               its bulb in the HUD: the seed (`ic.coat`) and a
//!                               sprout or two showing what it does (`icon.zig`)
//!   meets:Meeting               the other lineage's structure that, grown
//!                               beside it, is a discovery (`Structures.meetings`)
//!   adopts(s, kind, have) bool  whether it takes on one more child of `kind`
//!                               beyond the `have` it has (`dependOn`;
//!                               default: none). A child depends on its
//!                               parent: `getParent`, `getChildren`,
//!                               `getChild`; `spawnChild` puts one down
//!                               already its child (no `adopts` asked)
//!   pairs:Pairs                 how it pairs with partners (`.most` at once),
//!                               one way (it sends there) or both ways
//!                               (`pairWith`, `pairStep`, `getPartner`,
//!                               `getPartners`, `pairedTo`, `unpair`;
//!                               default: never)
//!   meshes                      the library meshes it draws beyond `mesh` and
//!                               `preview` (a tuple: `.{ .item_pod, ... }`);
//!                               `--structure` builds only these (tested)
//! Missing hooks fall back to doing nothing. A new structure is one new file
//! plus one line in `kinds`.
const lib=@import("../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const registry=engine.core.registry;
const ck=lib.ck;
const items=lib.items;
const meshlib=lib.meshlib;
const prog=lib.progression;
pub const messages=@import("structures/core/messages.zig");
pub const structure=@import("structures/core/structure.zig");
pub const list=@import("structures/core/list.zig");
pub const partners=@import("structures/core/partners.zig");
pub const kin=@import("structures/core/kin.zig");
pub const dispatch=@import("structures/core/dispatch.zig");
pub const handoff=@import("structures/core/handoff.zig");
pub const hooks=@import("structures/core/hooks.zig");
pub const testsFlow=@import("structures/core/tests_flow.zig");
pub const testsKin=@import("structures/core/tests_kin.zig");
pub const bench=@import("structures/core/bench.zig");
pub const Msg=messages.Msg;
pub const Reply=messages.Reply;
pub const Pairs=messages.Pairs;
pub const partnerSlots=messages.partnerSlots;
pub const Way=messages.Way;
pub const PairStep=messages.PairStep;
pub const Structure=structure.Structure;
pub const Ctx=structure.Ctx;
pub const kindByName=structure.kindByName;
pub const blank=structure.blank;
pub const Structures=list.Structures;
pub const HandOff=handoff.HandOff;
pub const firstGround=handoff.firstGround;
pub const handOff=handoff.handOff;
pub const handOffWith=handoff.handOffWith;
pub const Hold=hooks.Hold;
pub const fields=hooks.fields;
pub const hold=hooks.hold;
pub const release=hooks.release;
pub const configurable=hooks.configurable;
pub const configure=hooks.configure;
pub const recipes=hooks.recipes;
pub const chosen=hooks.chosen;
pub const choose=hooks.choose;
pub const emit=hooks.emit;
pub const describe=hooks.describe;
pub const icon=hooks.icon;
pub const harvestOne=hooks.harvestOne;
pub const kinds=struct{
  pub const conduit=@import("structures/conduit.zig");
  pub const sapCache=@import("structures/sap_cache.zig");
  pub const germinator=@import("structures/germinator.zig");
  pub const arsthraxia=@import("structures/arsthraxia.zig");
  pub const rootDigger=@import("structures/root_digger.zig");
  pub const polyp=@import("structures/polyp.zig");
  pub const diamond=@import("structures/diamond.zig");
  pub const loomfern=@import("structures/loomfern.zig");
  pub const lithophage=@import("structures/lithophage.zig");
  pub const braidedConduit=@import("structures/braided_conduit.zig");
  pub const ganglion=@import("structures/ganglion.zig");
  pub const gatheringCrown=@import("structures/gathering_crown.zig");
  pub const sporecaster=@import("structures/sporecaster.zig");
  pub const weftstone=@import("structures/weftstone.zig");
  pub const driftbraid=@import("structures/driftbraid.zig");
  pub const monfris=@import("structures/monfris.zig");
  pub const vultrixi=@import("structures/vultrixi.zig");
};
pub const reg=registry.Registry(kinds);
pub const Occ=ck.Occ;
pub const PlantId=ck.PlantId;
pub const Kind=reg.Id;
/// a placed structure's slot in `Structures.list`.
pub const Id=ck.StructId;
pub const Def=struct{
  item:items.Item,
  size:u8,
  mesh:meshlib.Id,
  /// how see-through its sap (resin pods, sap beads) is at its thinnest;
  /// like the wolf's, it has no light of its own
  sap:f32=sap,
  /// grown structures that stand up move like plants: how far they bend in
  /// the wind (0 rigid) and over what height
  sway:f32=0,
  tall:f32=1,
  /// seconds it takes to grow from a sprout once the gardener puts it down
  /// (0: there at once); it does no work until grown. Its mesh is built
  /// along growth splines (gfx/growth.zig) and grows along them on the
  /// GPU, branch after branch (`PartInstance` `grown`)
  grow:f32=0,
  /// carries items tile to tile the way it faces (R turns it): carriers
  /// chain into one line, and producers leave them to pull through `output`
  carrier:bool=false,
  /// keeps items in its slots: a click on it opens its panel, where they
  /// are lifted and put down as in the belly (hud/structure.zig)
  store:bool=false,
  /// floats over its tile, `hover` over the ground, instead of standing on
  /// it: it takes no room there, so it may float over a structure or a
  /// plant (never over another floating one)
  floating:bool=false,
  hover:f32=0,
  /// its mesh is drawn by its own `emit` (a diamond: it forms on the GPU),
  /// not breathing and growing in as the others do; `mesh` is its preview
  bare:bool=false,
  /// does not breathe: what it emits hangs on its mesh and must stay put
  /// on it (a germinator's cups and core)
  still:bool=false,
  /// what the gardener sees before putting it down, if not `mesh` (a
  /// germinator's emitted pieces at rest with it)
  preview:?meshlib.Id=null,
  /// what it emits travels far from it (a sporecaster's spores): it is
  /// emitted however far it stands from the view
  far:bool=false,
  /// a parasite's: the roots it turns on (R) are pale, not bark
  pale:bool=false,
};
pub const defs=reg.table(Def,"def");
/// a structure of the other lineage that, both grown within `MEET` tiles of
/// each other, is witnessed as `found`
pub const Meeting=struct{kind:Kind,found:prog.Discovery};
/// tiles apart (between footprints) that still count as side by side
pub const meetCount=3;
/// per-kind state; the active tag is the structure's kind.
pub const State=reg.Union("State");
/// every library mesh kind `k` draws: its mesh, its preview and what it
/// emits (its `meshes`)
pub fn meshes(k:Kind)[]const meshlib.Id{
  return switch(k){
    inline else=>|t|comptime blk:{
      const d:Def=reg.module(t).def;
      const extra=if(reg.has(t,"meshes"))reg.module(t).meshes else.{};
      const own:usize=if(d.preview!=null)2 else 1;
      var out:[own+extra.len]meshlib.Id=undefined;
      out[0]=d.mesh;
      if(d.preview)|p|out[1]=p;
      for(extra,own..)|e,i|out[i]=e;
      const all=out;
      break:blk&all;
    },
  };
}
pub fn kindOf(item:items.Item)?Kind{
  inline for(reg.ids)|k|if(defs.get(k).item==item)return k;
  return null;
}
pub const slots=16;
/// how quickly a structure's activity glow eases toward its target
pub const activityEase:f32=3;
/// how see-through structures' sap is at its thinnest, unless a def says otherwise
pub const sap:f32=0.78;
/// a structure as another holds on to it: by tile (an `Id` shifts when
/// another is uprooted) and whether it floats (a floater and what it
/// floats over share a tile)
pub const Ref=struct{
  x:i32,
  y:i32,
  floating:bool,
  pub fn eql(a:Ref,b:Ref)bool{return a.x==b.x and a.y==b.y and a.floating==b.floating;}
  pub fn tile(r:Ref)[2]i32{return.{r.x,r.y};}
};
/// what `spawnChild` puts down
pub const Spawn=struct{x:i32,y:i32,kind:Kind,dir:m.Dir=0,seed:f32=0};
test{
  _=messages;
  _=structure;
  _=list;
  _=partners;
  _=kin;
  _=dispatch;
  _=handoff;
  _=hooks;
  _=testsFlow;
  _=testsKin;
}
