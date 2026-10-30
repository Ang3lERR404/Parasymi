//! one structure as stored, and the context its hooks run in.
const lib=@import("../../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const activeTag=std.meta.activeTag;
const engine=lib.engine;
const m=engine.core.math;
/// colours: an item's colour turned to the four floats a part is tinted by
const color=engine.core.color;
/// the scene's parts list, and how one part looks
const Parts=lib.parts.Parts;
const Look=lib.parts.Look;
const ck=lib.ck;
const World=lib.world.World;
const items=lib.items;
const Plants=lib.plants.Plants;
const Events=lib.ecology.Events;
const Player=lib.player.Player;
const Sky=lib.sky.Sky;
const prog=lib.progression;
const turn=lib.turn;
const record=lib.record;
const Def=lib.structures.Def;
const Id=lib.structures.Id;
const Kind=lib.structures.Kind;
const partnerSlots=lib.structures.messages.partnerSlots;
const Ref=lib.structures.Ref;
const slots=lib.structures.slots;
const State=lib.structures.State;
const Structures=lib.structures.list.Structures;
const defs=lib.structures.defs;
const reg=lib.structures.reg;
pub const Structure=struct{
  x:i32,
  y:i32,
  dir:m.Dir=0,
  seed:f32,
  inv:items.Inventory(slots)=.{},
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
  pub fn size(s:*const Structure)f32{
    return switch(s.kind()){
      inline else=>|k|if(comptime reg.has(k,"size"))reg.module(k).size(s)else 1,
    };
  }
  pub fn def(s:*const Structure)Def{return defs.get(s.kind());}
  pub fn ref(s:*const Structure)Ref{return.{.x=s.x,.y=s.y,.floating=s.def().floating};}
  /// the first it was paired with, if any
  pub fn partner(s:*const Structure)?Ref{return s.partners[0];}
  pub fn partnerCount(s:*const Structure)usize{
    for(s.partners,0..)|p,k|if(p==null)return k;
    return partnerSlots;
  }
  pub fn pairedWith(s:*const Structure,r:Ref)bool{
    for(s.partners)|p|if(p)|q|if(q.eql(r))return true;
    return false;
  }
  /// pair it with `r` (once), letting go of the oldest when it already has
  /// `most`; returns the one let go
  pub fn addPartner(s:*Structure,r:Ref,most:u8)?Ref{
    if(s.pairedWith(r))return null;
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
  w:*World,
  plants:*Plants,
  g:*prog.Progression,
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
pub fn freshState(k:Kind)State{
  return switch(k){
    inline else=>|t|blk:{
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
pub fn anyTile(_:ck.Kind)bool{return true;}
/// empty tiles between two structures' footprints (0: touching)
pub fn gap(a:*const Structure,b:*const Structure)i32{
  const sa:i32=a.def().size;
  const sb:i32=b.def().size;
  const dx=@max(b.x-(a.x+sa),a.x-(b.x+sb),-1);
  const dy=@max(b.y-(a.y+sa),a.y-(b.y+sb),-1);
  return@max(dx,dy,0);
}
/// `o` once the slot at `gone` is taken out of the list
pub fn slotDown(o:?Id,gone:usize)?Id{
  const i=o orelse return null;
  return if(i.idx()>gone)Id.of(i.idx()-1)else i;
}
/// a hook result that may be an error union, as one
pub fn orFail(r:anytype)Allocator.Error!bool{return r;}
