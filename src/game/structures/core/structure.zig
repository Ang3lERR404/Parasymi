//! one structure as stored, and the context its hooks run in.
const lib=@import("../../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type a structure's state is freed with
const Allocator=std.mem.Allocator;
/// which tag of a tagged union is live: a structure's kind is its state's
const activeTag=std.meta.activeTag;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, a structure's facing
const m=engine.core.math;
/// colours: an item's colour turned to the four floats a part is tinted by
const color=engine.core.color;
/// the scene's parts list, which a held lump is added to
const Parts=lib.parts.Parts;
/// how one part looks: its glow, tint, sway and growth
const Look=lib.parts.Look;
/// the chunks: tile kinds and the ids stored there
const ck=lib.ck;
/// the garden's world of chunks
const World=lib.world.World;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// every plant in the garden
const Plants=lib.plants.Plants;
/// what befell the garden this tick
const Events=lib.ecology.Events;
/// the wolf
const Player=lib.player.Player;
/// the sky: daylight and the time of day
const Sky=lib.sky.Sky;
/// what the gardener has understood
const prog=lib.progression;
/// how a structure turns smoothly to a new facing
const turn=lib.turn;
/// saved records, read by field name; here, a kind's name hash
const record=lib.record;
/// what a kind of structure is
const Def=lib.structures.Def;
/// a placed structure's slot in the list
const Id=lib.structures.Id;
/// which kind of structure
const Kind=lib.structures.Kind;
/// the most partners any structure keeps
const partnerSlots=lib.structures.messages.partnerSlots;
/// a structure as another holds on to it: by tile
const Ref=lib.structures.Ref;
/// how many stacks a structure holds
const slots=lib.structures.slots;
/// per-kind state; its tag is the kind
const State=lib.structures.State;
/// the garden's list of structures
const Structures=lib.structures.list.Structures;
/// every kind's `def`
const defs=lib.structures.defs;
/// the structures registry: which kinds have which hooks
const reg=lib.structures.reg;
/// one placed structure, as the list keeps it and a save stores it
pub const Structure=struct{
  /// its footprint's west column (tiles)
  x:i32,
  /// its footprint's north row (tiles)
  y:i32,
  /// the way it faces (R turns it)
  dir:m.Dir=0,
  /// its own seed: how it sways and varies from its neighbours
  seed:f32,
  /// what it holds, in its slots
  inv:items.Inventory(slots)=.{},
  /// its kind's own state; the live tag is its kind
  state:State,
  /// the structure it depends on (`dependOn`, `spawnChild`), if any
  parent:?Ref=null,
  /// the structures it is paired with (`pairWith`), oldest first, the
  /// empty slots last
  partners:[partnerSlots]?Ref=@splat(null),
  /// smoothed 0..1, drives glow and motion
  activity:f32=0,
  /// 0 a sprout .. 1 grown (see `Def.grow`)
  grown:f32=1,
  /// how it got to face `dir` (R turns it)
  turn:turn.Turn=.{},
  /// what kind it is: the live tag of its state
  pub fn kind(s:*const Structure)Kind{return activeTag(s.state);}
  /// free what its state holds (a `State` with a `deinit`: lists, ...);
  /// `Structures.remove` hands back one the caller frees
  pub fn deinit(s:*Structure,gpa:Allocator)void{
    switch(s.state){
      inline else=>|*v|if(comptime@typeInfo(@TypeOf(v.*))==.@"struct"and@hasDecl(@TypeOf(v.*),"deinit"))v.deinit(gpa),
    }
  }
  /// how big it is drawn: the size research has grown it to (`size`);
  /// growing in is its growth splines' alone
  pub fn grownScale(s:*const Structure)m.V3{return m.splat3(s.size());}
  /// how much larger than its mesh research has grown it (its kind's
  /// `size` hook; 1 if it has none)
  pub fn size(s:*const Structure)f32{
    return switch(s.kind()){
      inline else=>|k|if(comptime reg.has(k,"size"))reg.module(k).size(s)else 1,
    };
  }
  /// its kind's def
  pub fn def(s:*const Structure)Def{return defs.get(s.kind());}
  /// it as another holds on to it: its tile and whether it floats
  pub fn ref(s:*const Structure)Ref{return.{.x=s.x,.y=s.y,.floating=s.def().floating};}
  /// the first it was paired with, if any
  pub fn partner(s:*const Structure)?Ref{return s.partners[0];}
  /// how many partners it has (the filled slots before the first empty)
  pub fn partnerCount(s:*const Structure)usize{
    for(s.partners,0..)|p,k|if(p==null)return k;
    return partnerSlots;
  }
  /// whether `r` is among its partners
  pub fn pairedWith(s:*const Structure,r:Ref)bool{
    for(s.partners)|p|if(p)|q|if(q.eql(r))return true;
    return false;
  }
  /// pair it with `r` (once), letting go of the oldest when it already has
  /// `most`; returns the one let go
  pub fn addPartner(s:*Structure,r:Ref,most:u8)?Ref{
    if(s.pairedWith(r))return null;
    // the oldest let go to make room, if any
    var old:?Ref=null;
    if(s.partnerCount()>=most){
      old=s.partners[0];
      _=s.dropPartner(old.?);
    }
    s.partners[s.partnerCount()]=r;
    return old;
  }
  /// cut it from `r`, the later ones moving up; returns whether they were paired
  pub fn dropPartner(s:*Structure,r:Ref)bool{
    // how many partners it has
    const n=s.partnerCount();
    for(0..n)|k|if(s.partners[k].?.eql(r)){
      std.mem.copyForwards(?Ref,s.partners[k..n-1],s.partners[k+1..n]);
      s.partners[n-1]=null;
      return true;
    };
    return false;
  }
  /// where its mesh is drawn from, at its centre `ctr`: turned its way,
  /// at the size it has grown to (breathing aside)
  pub fn place(s:*const Structure,ctr:m.V3)m.M4{
    return m.chain(&.{m.translate(ctr),m.rotY(m.dirYaw(s.dir)),m.scale3(s.grownScale())});
  }
  /// the first thing it holds that `keep` lets go, oldest slot first: what
  /// an `output` hook hands down a conduit (null: nothing to give).
  pub fn firstHeld(s:*const Structure,comptime keep:fn(items.Item)bool)?items.Item{
    for(s.inv.slot)|slot|if(slot)|it|if(keep(it.item))return it.item;
    return null;
  }
  /// a `keep` for `firstHeld` that lets anything go.
  pub fn anything(_:items.Item)bool{return true;}
  /// one held thing shown as a lump of resin: drawn at `at` inside the
  /// structure's frame `base`, `r` across, tinted the item's colour and
  /// glowing `glow`, swaying with the structure that holds it.
  pub fn emitLump(s:*const Structure,out:*Parts,base:m.M4,at:m.V3,r:f32,item:items.Item,glow:f32)Allocator.Error!void{
    // the structure's kind: how far it sways, how tall it stands
    const d=s.def();
    try out.emit(.bellyLump,m.mul(base,m.chain(&.{m.translate(at),m.scale3(m.splat3(r))})),Look{
      .glow=glow,.phase=s.seed,.tint=color.Rgba8.of(item.info().col).toF4(),
      .sway=d.sway,.tall=d.tall,.drop=at[1],
    });
  }
};
/// everything a structure's behaviour may touch.
pub const Ctx=struct{
  /// for a structure that puts another down (a polyp, its diamond)
  gpa:Allocator,
  /// the garden's world: its tiles and what fills them
  w:*World,
  /// every plant in the garden
  plants:*Plants,
  /// what the gardener has understood (research, discoveries)
  g:*prog.Progression,
  /// every structure, this one among them
  ss:*Structures,
  // decision: the world beyond the garden is read-only to structures and
  // left out by headless callers (tests), so each is optional
  /// the wolf, for a structure that answers it coming near
  player:?*const Player=null,
  /// the time of day (`daylight`, `tod`), for one that works by day or night
  sky:?*const Sky=null,
  /// what befell the garden this tick (plants withered)
  events:Events=.{},
};
/// a fresh state for kind `k`: its `State` struct at its defaults, or
/// nothing for a kind that keeps none
pub fn freshState(k:Kind)State{
  return switch(k){
    inline else=>|t|blk:{
      // the kind's own state type
      const T=@FieldType(State,@tagName(t));
      break:blk@unionInit(State,@tagName(t),if(T==void){}else.{});
    },
  };
}
/// a kind by its name's hash (`record.nameHash`), as saves store it
pub fn kindByName(h:u32)?Kind{
  inline for(reg.ids)|k|if((comptime record.nameHash(@tagName(k)))==h)return k;
  return null;
}
/// a structure of kind `k` at the origin, its state fresh (what a saved
/// one is read over)
pub fn blank(k:Kind)Structure{return.{.x=0,.y=0,.seed=0,.state=freshState(k)};}
/// the default `ground`: a structure may stand on any tile
pub fn anyTile(_:ck.Kind)bool{return true;}
/// empty tiles between two structures' footprints (0: touching)
pub fn gap(a:*const Structure,b:*const Structure)i32{
  // each footprint's width in tiles
  const sa:i32=a.def().size;
  const sb:i32=b.def().size;
  // the gap across and down (-1 when they overlap that way)
  const dx=@max(b.x-(a.x+sa),a.x-(b.x+sb),-1);
  const dy=@max(b.y-(a.y+sa),a.y-(b.y+sb),-1);
  return@max(dx,dy,0);
}
/// `o` once the slot at `gone` is taken out of the list
pub fn slotDown(o:?Id,gone:usize)?Id{
  // the id, if there is one to move
  const i=o orelse return null;
  return if(i.idx()>gone)Id.of(i.idx()-1)else i;
}
/// a hook result that may be an error union, as one
pub fn orFail(r:anytype)Allocator.Error!bool{return r;}
