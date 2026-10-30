//! parents and children: a child depends on its parent.
const lib=@import("../../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type putting a child down may fail with
const Allocator=std.mem.Allocator;
/// the garden's world of chunks
const World=lib.world.World;
/// a placed structure's slot in the list
const Id=lib.structures.Id;
/// a structure as another holds on to it: by tile
const Ref=lib.structures.Ref;
/// what `spawnChild` puts down
const Spawn=lib.structures.Spawn;
/// the garden's list of structures
const Structures=lib.structures.list.Structures;
/// the structures registry: which kinds adopt
const reg=lib.structures.reg;
// ---- parents and children: a child depends on its parent ----
/// the structure `r` names, if one still stands there
pub fn find(ss:*const Structures,r:Ref)?Id{return ss.where.get(r);}
/// `child` now depends on `parent` (or on nothing), leaving whatever it
/// depended on before
pub fn setParent(ss:*Structures,child:Id,parent:?Id)void{
  if(ss.getParent(child))|old|ss.leave(child,old);
  ss.get(child).parent=if(parent)|p|ss.get(p).ref()else null;
  if(parent)|p|ss.join(child,p);
}
/// put `c` among `p`'s children, in list order
pub fn join(ss:*Structures,c:Id,p:Id)void{
  // every structure's links to its first child and next sibling
  const kin=ss.kin.items;
  // the link `c` is threaded in at, walked along until past it in list order
  var slot:*?Id=&kin[p.idx()].first;
  while(slot.*)|o|{
    if(o.idx()>c.idx())break;
    slot=&kin[o.idx()].next;
  }
  kin[c.idx()].next=slot.*;
  slot.*=c;
}
/// take `c` out of `p`'s children
pub fn leave(ss:*Structures,c:Id,p:Id)void{
  // every structure's links to its first child and next sibling
  const kin=ss.kin.items;
  // the link being looked at, walked along until it points at `c`
  var slot:*?Id=&kin[p.idx()].first;
  while(slot.*)|o|{
    if(o==c){
      slot.*=kin[c.idx()].next;
      kin[c.idx()].next=null;
      return;
    }
    slot=&kin[o.idx()].next;
  }
}
/// put a structure down already depending on `parent` (its parent
/// chooses to: no `adopts` is asked). Returns it, or null if there is
/// no room.
pub fn spawnChild(ss:*Structures,gpa:Allocator,w:*World,parent:Id,sp:Spawn)Allocator.Error!?Id{
  // the parent, held by tile (its id may shift as the list grows)
  const up=ss.get(parent).ref();
  if(!try ss.place(gpa,w,sp.x,sp.y,sp.kind,sp.dir,sp.seed))return null;
  // the new child: the last in the list
  const id=Id.of(ss.list.items.len-1);
  ss.get(id).parent=up;
  ss.join(id,parent);
  return id;
}
/// make `child` depend on `parent`, leaving whatever it depended on
/// before, if the parent takes it on (`adopts`) and it is not the
/// parent's own ancestor. Returns whether it depends on it now.
pub fn dependOn(ss:*Structures,child:Id,parent:Id)bool{
  if(child==parent)return false;
  if(ss.getParent(child)==parent)return true;
  // no loops: the child may not be among the parent's ancestors
  var up=ss.getParent(parent);
  while(up)|a|{
    if(a==child)return false;
    up=ss.getParent(a);
  }
  // the parent, how many children it has, and the would-be child's kind
  const p=ss.get(parent);
  const have=ss.childCount(parent);
  const k=ss.get(child).kind();
  // whether the parent takes on one more of that kind
  const ok=switch(p.kind()){
    inline else=>|t|if(comptime reg.has(t,"adopts"))reg.module(t).adopts(p,k,have)else false,
  };
  if(ok)ss.setParent(child,parent);
  return ok;
}
/// cut `child` loose from its parent.
pub fn detach(ss:*Structures,child:Id)void{ss.setParent(child,null);}
/// the structure `child` depends on, or null if none (or it is gone)
pub fn getParent(ss:*const Structures,child:Id)?Id{
  // where its parent stood, if it has one
  const r=ss.list.items[child.idx()].parent orelse return null;
  return ss.find(r);
}
/// every structure depending on `parent`, in list order.
pub fn getChildren(ss:*const Structures,parent:Id)Children{
  return.{.ss=ss,.at=ss.kin.items[parent.idx()].first};
}
/// the `n`th of `parent`'s children (in list order).
pub fn getChild(ss:*const Structures,parent:Id,n:usize)?Id{
  // the walk over its children, and how many have been passed
  var it=ss.getChildren(parent);
  var k:usize=0;
  while(it.next())|c|:(k+=1)if(k==n)return c;
  return null;
}
/// how many structures depend on `parent`
pub fn childCount(ss:*const Structures,parent:Id)u32{
  // the walk over its children, and the count so far
  var it=ss.getChildren(parent);
  var n:u32=0;
  while(it.next())|_|n+=1;
  return n;
}
/// walks a structure's children (`kin`)
pub const Children=struct{
  /// the list they stand in
  ss:*const Structures,
  /// the child to hand out next (null: the walk is over)
  at:?Id,
  /// the next child, or null once all are walked
  pub fn next(it:*Children)?Id{
    // the child handed out now
    const c=it.at orelse return null;
    it.at=it.ss.kin.items[c.idx()].next;
    return c;
  }
};
