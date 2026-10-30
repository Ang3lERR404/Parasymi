//! partners: structures paired one way or both ways (`pairs`).
const lib=@import("../../../lib.zig");
const Id=lib.structures.Id;
const partnerSlots=lib.structures.messages.partnerSlots;
const PairStep=lib.structures.messages.PairStep;
const Ref=lib.structures.Ref;
const Structures=lib.structures.list.Structures;
const pairsOf=lib.structures.messages.pairsOf;
// ---- partners: paired one way or both ways (`pairs`) ----
/// pair `a` with `b` as `a`'s kind pairs (`pairs`): one way, `a` sends to
/// `b`; both ways, each is the other's. One already holding its `most`
/// lets go of its oldest. Returns whether they are paired now.
pub fn pairWith(ss:*Structures,a:Id,b:Id)bool{
  if(a==b)return false;
  const ka=ss.get(a).kind();
  const pa=pairsOf(ka) orelse return false;
  const kb=ss.get(b).kind();
  if(kb!=(pa.with orelse ka))return false;
  const ra=ss.get(a).ref();
  const rb=ss.get(b).ref();
  const old=ss.get(a).addPartner(rb,pa.most);
  if(pa.way==.bothWays){
    if(old)|o|ss.letGo(o,ra);
    const mb=if(pairsOf(kb))|pb|pb.most else pa.most;
    if(ss.get(b).addPartner(ra,mb))|o|ss.letGo(o,rb);
  }
  return true;
}
/// the structure at `r`, if one stands there, is cut from `from`
pub fn letGo(ss:*Structures,r:Ref,from:Ref)void{
  if(ss.find(r))|o|_=ss.get(o).dropPartner(from);
}
/// cut `id` from its partners; paired both ways, every pairing that
/// reaches it is cut too.
pub fn unpair(ss:*Structures,id:Id)void{
  const s=ss.get(id);
  s.partners=@splat(null);
  const p=pairsOf(s.kind()) orelse return;
  if(p.way!=.bothWays)return;
  const here=s.ref();
  for(ss.list.items)|*o|_=o.dropPartner(here);
}
/// the configure handshake of a structure that pairs: the first
/// configured waits, the next is paired with it (`pairWith`, from the
/// one waiting); configured twice over, it is cut loose (`unpair`).
pub fn pairStep(ss:*Structures,id:Id)PairStep{
  const here=ss.get(id).ref();
  if(ss.pairing)|p|{
    ss.pairing=null;
    if(p.eql(here)){
      ss.unpair(id);
      return.cut;
    }
    if(ss.find(p))|o|if(ss.pairWith(o,id))return.paired;
  }
  ss.pairing=here;
  return.waiting;
}
/// the first `id` was paired with
pub fn getPartner(ss:*const Structures,id:Id)?Id{
  const r=ss.list.items[id.idx()].partner() orelse return null;
  return ss.find(r);
}
/// every structure `id` is paired with, oldest first.
pub fn getPartners(ss:*const Structures,id:Id)Partners{
  return.{.ss=ss,.of=&ss.list.items[id.idx()].partners};
}
/// every structure paired with `id` (one of its partners is `id`), in
/// list order.
pub fn pairedTo(ss:*const Structures,id:Id)Paired{
  return.{.ss=ss,.of=ss.list.items[id.idx()].ref()};
}
/// walks a structure's partners (`partners`)
pub const Partners=struct{
  ss:*const Structures,
  of:*const[partnerSlots]?Ref,
  k:usize=0,
  pub fn next(it:*Partners)?Id{
    while(it.k<partnerSlots){
      const r=it.of[it.k] orelse return null;
      it.k+=1;
      if(it.ss.find(r))|id|return id;
    }
    return null;
  }
};
/// walks every structure one of whose partners is `of`
pub const Paired=struct{
  ss:*const Structures,
  of:Ref,
  i:usize=0,
  pub fn next(it:*Paired)?Id{
    while(it.i<it.ss.list.items.len){
      const i=it.i;
      it.i+=1;
      if(it.ss.list.items[i].pairedWith(it.of))return Id.of(i);
    }
    return null;
  }
};
