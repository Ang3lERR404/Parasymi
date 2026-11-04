//! every structure in the garden: the list, its tile index, placing and uprooting.
const lib=@import("../../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// a check that what must hold does (a bug if not)
const assert=std.debug.assert;
/// the allocator type placing a structure may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: here, the way a structure faces
const m=engine.core.math;
/// the garden's world of chunks, whose tiles a footprint marks
const World=lib.world.World;
/// a placed structure's slot in the list
const Id=lib.structures.Id;
/// which kind of structure
const Kind=lib.structures.Kind;
/// what fills a tile, as a footprint marks it
const Occ=lib.structures.Occ;
/// a structure as another holds on to it: by tile
const Ref=lib.structures.Ref;
/// one placed structure
const Structure=lib.structures.structure.Structure;
/// the default `ground`: any tile will do
const anyTile=lib.structures.structure.anyTile;
/// every kind's `def`
const defs=lib.structures.defs;
/// a kind's state, fresh
const freshState=lib.structures.structure.freshState;
/// the structures registry: which kinds have which hooks
const reg=lib.structures.reg;
/// an id once a slot before it is taken out
const slotDown=lib.structures.structure.slotDown;
/// how close two floating structures may hang, centre to centre (m): as
/// close as on neighbouring tiles
pub const floatGap=1.0;
/// how near a cursor ray must pass a floating structure to touch it (m)
pub const floatTouch=0.7;
/// every structure standing in the garden, in the order put down (the
/// order they tick in), with the indexes kept beside it
pub const Structures=struct{
  /// the structures themselves; an `Id` is a place in this list
  list:std.ArrayList(Structure)=.empty,
  /// a structure waiting to be paired with another (a sporecaster
  /// choosing where it sends): the next one configured
  pairing:?Ref=null,
  /// every structure by where it stands (`find`, `floaterAt`), kept on
  /// `place`/`remove`
  where:std.AutoHashMapUnmanaged(Ref,Id)=.empty,
  /// beside `list`: each structure's first child and next sibling, in list
  /// order (`getChildren`); never saved, `relink` rebuilds it
  kin:std.ArrayList(Kin)=.empty,
  /// one structure's place among kin: its `first` child and the `next`
  /// sibling after it (null: none)
  pub const Kin=struct{first:?Id=null,next:?Id=null};
  /// frees every structure's state and the lists and index themselves
  pub fn deinit(ss:*Structures,gpa:Allocator)void{
    for(ss.list.items)|*s|s.deinit(gpa);
    ss.list.deinit(gpa);
    ss.where.deinit(gpa);
    ss.kin.deinit(gpa);
  }
  /// the structure at slot `id`, to read or change in place
  pub fn get(ss:*Structures,id:Id)*Structure{return&ss.list.items[id.idx()];}
  /// whether a structure of kind `k` may go down at tile `wx`,`wy`: a
  /// floater at the tile's centre, anything else on a footprint free and of
  /// ground it may stand on
  pub fn canPlace(ss:*const Structures,w:*const World,wx:i32,wy:i32,k:Kind)bool{
    if(defs.get(k).floating)return ss.canFloat(w,m.tileCentre(wx,wy,0));
    return switch(k){
      inline else=>|t|w.footprintFree(wx,wy,defs.get(t).size,if(comptime reg.has(t,"ground"))reg.module(t).ground else anyTile),
    };
  }
  /// whether a structure of kind `k` may go down at ground point `pt`: a
  /// floater right there, anything else on the footprint centred nearest it
  pub fn canPlaceNear(ss:*const Structures,w:*const World,pt:m.V3,k:Kind)bool{
    if(defs.get(k).floating)return ss.canFloat(w,pt);
    // the footprint's top-left tile
    const t=anchor(pt,k);
    return ss.canPlace(w,t[0],t[1],k);
  }
  /// the anchor tile a structure of kind `k` takes for ground point `pt`:
  /// the tile under a floater, else the top-left of the footprint centred nearest it
  fn anchor(pt:m.V3,k:Kind)m.Vice(i32,2){
    // how far its footprint's centre is from its top-left tile's
    const half=if(defs.get(k).floating)0 else m.f(defs.get(k).size-1)*0.5;
    return m.tileAt(pt-m.v3(half,0,half));
  }
  /// whether a floating structure may hang at ground point `pt`: over a
  /// streamed tile, whatever stands on it, no nearer another floating
  /// structure than `floatGap`, and not over the same tile as one (each is
  /// found, and held by a `Ref`, by the tile under it)
  fn canFloat(ss:*const Structures,w:*const World,pt:m.V3)bool{
    // the tile under the point
    const t=m.tileAt(pt);
    _=w.chunkOfTile(t[0],t[1]) orelse return false;
    if(ss.floaterAt(t[0],t[1])!=null)return false;
    for(ss.list.items)|*s|if(s.def().floating){
      // the way to that one, flat on the ground
      const d=(s.at-pt)*m.v3(1,0,1);
      if(m.dot(d,d)<floatGap*floatGap)return false;
    };
    return true;
  }
  /// where a structure of kind `k` stands when put down from the cursor,
  /// over tile `t` at ground point `pt`: a floater right at `pt`, off the
  /// grid; anything else on the footprint whose top-left is `t`
  pub fn spot(k:Kind,t:m.Vice(i32,2),pt:m.V3)m.V3{
    return if(defs.get(k).floating)m.v3(pt[0],0,pt[2])else m.footprintCentre(t[0],t[1],defs.get(k).size,0);
  }
  /// put a fresh structure of kind `k` down at `wx`,`wy` (a floater at the
  /// tile's centre), facing `dir`, marking its footprint (unless it floats)
  /// and indexing it. Returns false, changing nothing, if it may not go there.
  pub fn place(ss:*Structures,gpa:Allocator,w:*World,wx:i32,wy:i32,k:Kind,dir:m.Dir,seed:f32)Allocator.Error!bool{
    return ss.placeNear(gpa,w,spot(k,.{wx,wy},m.tileCentre(wx,wy,0)),k,dir,seed);
  }
  /// put a fresh structure of kind `k` down at ground point `pt`: a floater
  /// hangs right there, anything else takes the footprint centred nearest
  /// `pt`; as `place`.
  pub fn placeNear(ss:*Structures,gpa:Allocator,w:*World,pt:m.V3,k:Kind,dir:m.Dir,seed:f32)Allocator.Error!bool{
    if(!ss.canPlaceNear(w,pt,k))return false;
    // its anchor tile, where it stands, and the slot it will take: the end of the list
    const def=defs.get(k);
    const t=anchor(pt,k);
    const stands=if(def.floating)m.v3(pt[0],0,pt[2])else m.footprintCentre(t[0],t[1],def.size,0);
    const idx=Id.of(ss.list.items.len);
    try ss.list.ensureUnusedCapacity(gpa,1);
    try ss.kin.ensureUnusedCapacity(gpa,1);
    try ss.where.ensureUnusedCapacity(gpa,1);
    ss.list.appendAssumeCapacity(.{.x=t[0],.y=t[1],.at=stands,.dir=dir,.seed=seed,.state=freshState(k)});
    ss.kin.appendAssumeCapacity(.{});
    ss.where.putAssumeCapacityNoClobber(ss.get(idx).ref(),idx);
    if(!def.floating)w.setFootprint(t[0],t[1],def.size,Occ.structure(idx));
    return true;
  }
  /// the floating structure a ray from `o` along unit `d` passes nearest
  /// its start, within `floatTouch` of where it hangs (its point, `hover`
  /// over the ground `groundOf` gives), and how far along the ray that is
  pub fn floaterOnRay(ss:*const Structures,o:m.V3,d:m.V3,comptime Ground:type,ground:Ground)?Touch{
    // the nearest so far
    var best:?Touch=null;
    for(ss.list.items,0..)|*s,i|if(s.def().floating){
      // where it hangs, how far along the ray it lies, and how far off it
      const c=s.at+m.v3(0,@max(ground.at(s.x,s.y),0)+s.def().hover,0);
      const t=m.dot(c-o,d);
      if(t<=0)continue;
      if(best)|b|if(t>=b.t)continue;
      const off=c-(o+d*m.splat3(t));
      if(m.dot(off,off)>floatTouch*floatTouch)continue;
      best=.{.id=Id.of(i),.t=t};
    };
    return best;
  }
  /// a floating structure a ray touches, and how far along it
  pub const Touch=struct{
    /// the structure
    id:Id,
    /// how far along the ray (m)
    t:f32,
  };
  /// put a saved structure back as it was (inventory, state, whom it
  /// depends on), owning what its state holds; once all are back,
  /// `relink`. Returns whether it fit (if not, `s` is still the caller's).
  pub fn restore(ss:*Structures,gpa:Allocator,w:*World,s:Structure)Allocator.Error!bool{
    // where it stood: a floater's own point if it lies over its tile (a
    // garden saved before floaters left the grid has none), else its tile's
    const own=s.def().floating and m.tileAt(s.at)[0]==s.x and m.tileAt(s.at)[1]==s.y;
    if(!try ss.placeNear(gpa,w,if(own)s.at else spot(s.kind(),.{s.x,s.y},m.tileCentre(s.x,s.y,0)),s.kind(),s.dir,s.seed))return false;
    // the fresh one just put down, overwritten by the saved one
    const put=&ss.list.items[ss.list.items.len-1];
    put.deinit(gpa);
    // (keeping where it was put)
    const stands=put.at;
    put.*=s;
    put.at=stands;
    return true;
  }
  /// rebuild who is whose child from each structure's `parent`
  pub fn relink(ss:*Structures)void{
    @memset(ss.kin.items,.{});
    for(0..ss.list.items.len)|i|if(ss.getParent(Id.of(i)))|p|ss.join(Id.of(i),p);
  }
  /// structure `id` becomes one of kind `k` where it stands, its state
  /// fresh, keeping its place, its inventory and its kin (a stem whose
  /// fourth bud fastens becomes the heart). Both kinds must be the same
  /// size and both stand on the ground or both float.
  pub fn become(ss:*Structures,gpa:Allocator,id:Id,k:Kind)void{
    // the structure
    const s=ss.get(id);
    assert(defs.get(k).size==s.def().size and defs.get(k).floating==s.def().floating);
    s.deinit(gpa);
    s.state=freshState(k);
  }
  /// a structure the gardener has just put down starts as a sprout.
  pub fn sprout(ss:*Structures,id:Id)void{
    // the one just put down
    const s=ss.get(id);
    if(s.def().grow>0)s.grown=0;
  }
  /// what stands at a tile: what floats over it first (it is drawn over
  /// whatever is under it), else what stands on it.
  pub fn at(ss:*const Structures,w:*const World,wx:i32,wy:i32)?Id{
    return ss.floaterAt(wx,wy) orelse w.occAt(wx,wy).asStructure();
  }
  /// what the gardener reaches at a tile: the structure standing there, else
  /// the one floating over it
  pub fn touched(ss:*const Structures,w:*const World,wx:i32,wy:i32)?Id{
    return ss.at(w,wx,wy) orelse ss.floaterAt(wx,wy);
  }
  /// the floating structure over a tile
  pub fn floaterAt(ss:*const Structures,wx:i32,wy:i32)?Id{
    return ss.where.get(.{.x=wx,.y=wy,.floating=true});
  }
  /// ordered remove: the others keep the order they were put down in (the
  /// order they tick in), each after it one slot down. Returns the removed
  /// structure so its contents can be refunded; the caller `deinit`s it.
  /// note to CLAUDE, I changed the code, it is bad to do repeated get calls.
  pub fn remove(ss:*Structures,w:*World,id:Id)Structure{
    // a copy of the one uprooted, handed back at the end
    const s=ss.get(id).*;
    // calls should always be at the top;
    // its kind's def (footprint, floating), and its slot in the list
    const stct=s.def();
    const idx=id.idx();
    // it leaves its parent, and what depended on it is cut loose
    ss.setParent(id,null);
    // the child being cut loose, walked along the sibling links
    var c=ss.kin.items[idx].first;
    while(c)|k|{
      c=ss.kin.items[k.idx()].next;
      ss.kin.items[k.idx()].next=null;
      ss.get(k).parent=null;
    }
    ss.kin.items[idx].first=null;
    if(!stct.floating)w.setFootprint(s.x,s.y,stct.size,.none);
    _=ss.where.remove(s.ref());
    _=ss.list.orderedRemove(idx);
    _=ss.kin.orderedRemove(idx);
    // each after it is one slot down: its tiles, where it is found, and the
    // child lists naming it (still in list order, as all move alike)
    for(ss.list.items[idx..],idx..)|*l,k|{
      // the def of the one moving down
      const lstct=l.def();
      if(!lstct.floating)w.moveFootprint(l.x,l.y,lstct.size,Occ.structure(Id.of(k)));
      ss.where.getPtr(l.ref()).?.*=Id.of(k);
    }
    for(ss.kin.items)|*e|{
      e.first=slotDown(e.first,idx);
      e.next=slotDown(e.next,idx);
    }
    // what was paired with it is cut loose
    const gone=s.ref();
    for(ss.list.items)|*o|_=o.dropPartner(gone);
    if(ss.pairing)|p|if(p.eql(gone)){ss.pairing=null;};
    return s;
  }
  /// pair one structure with another as its kind pairs
  pub const pairWith=lib.structures.partners.pairWith;
  /// cut the structure at a tile from one partner
  pub const letGo=lib.structures.partners.letGo;
  /// cut a structure from all its partners
  pub const unpair=lib.structures.partners.unpair;
  /// the configure handshake of a structure that pairs
  pub const pairStep=lib.structures.partners.pairStep;
  /// the first a structure was paired with
  pub const getPartner=lib.structures.partners.getPartner;
  /// every structure one is paired with, oldest first
  pub const getPartners=lib.structures.partners.getPartners;
  /// every structure paired with one
  pub const pairedTo=lib.structures.partners.pairedTo;
  /// the walk over a structure's partners
  pub const Partners=lib.structures.partners.Partners;
  /// the walk over those paired with a structure
  pub const Paired=lib.structures.partners.Paired;
  /// the structure a `Ref` names, if it still stands
  pub const find=lib.structures.kin.find;
  /// make one structure depend on another, or on nothing
  pub const setParent=lib.structures.kin.setParent;
  /// thread a child into its parent's children
  pub const join=lib.structures.kin.join;
  /// take a child out of its parent's children
  pub const leave=lib.structures.kin.leave;
  /// put a structure down already a child
  pub const spawnChild=lib.structures.kin.spawnChild;
  /// make one depend on another, if the parent adopts it
  pub const dependOn=lib.structures.kin.dependOn;
  /// cut a child loose from its parent
  pub const detach=lib.structures.kin.detach;
  /// the structure one depends on
  pub const getParent=lib.structures.kin.getParent;
  /// every structure depending on one
  pub const getChildren=lib.structures.kin.getChildren;
  /// the `n`th child of one
  pub const getChild=lib.structures.kin.getChild;
  /// how many depend on one
  pub const childCount=lib.structures.kin.childCount;
  /// the walk over a structure's children
  pub const Children=lib.structures.kin.Children;
  /// how many of an item a structure will still take
  pub const wants=lib.structures.dispatch.wants;
  /// what may leave a structure first
  pub const output=lib.structures.dispatch.output;
  /// hand one item into a structure at an edge
  pub const handIn=lib.structures.dispatch.handIn;
  /// tell a structure something
  pub const send=lib.structures.dispatch.send;
  /// everything that may leave a structure
  pub const outputs=lib.structures.dispatch.outputs;
  /// the walk over what may leave a structure
  pub const Outputs=lib.structures.dispatch.Outputs;
  /// whether an item may leave a structure
  pub const gives=lib.structures.dispatch.gives;
  /// put items into a structure, as many as it wants
  pub const insert=lib.structures.dispatch.insert;
  /// witness the lineages' meetings
  pub const meetings=lib.structures.dispatch.meetings;
  /// pairs side by side growing together into their convergent kin
  pub const growTogether=lib.structures.dispatch.growTogether;
  /// every structure notices its neighbours
  pub const link=lib.structures.dispatch.link;
  /// `link` with the game's whole context
  pub const linkWith=lib.structures.dispatch.linkWith;
  /// a tick with only the garden
  pub const tick=lib.structures.dispatch.tick;
  /// a tick with the game's whole context
  pub const tickWith=lib.structures.dispatch.tickWith;
};
