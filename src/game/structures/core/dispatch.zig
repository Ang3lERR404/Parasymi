//! the hook dispatch over every structure: one comptime switch each, no per-kind code.
const lib=@import("../../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type a tick may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: here, the edge a thing is handed in at
const m=engine.core.math;
/// the garden's world of chunks
const World=lib.world.World;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// every plant in the garden
const Plants=lib.plants.Plants;
/// what the gardener has understood
const prog=lib.progression;
/// how quickly a structure's activity glow eases toward its target
const activityEase=lib.structures.activityEase;
/// how fast a structure's shine follows its light
const shineEase=lib.structures.shineEase;
/// everything a structure's behaviour may touch
const Ctx=lib.structures.structure.Ctx;
/// a placed structure's slot in the list
const Id=lib.structures.Id;
/// tiles apart that still count as side by side, for a meeting
const meetCount=lib.structures.meetCount;
/// the kind a structure meets, and what that reveals
const Meeting=lib.structures.Meeting;
/// what one structure tells another
const Msg=lib.structures.messages.Msg;
/// what a structure makes of a message
const Reply=lib.structures.messages.Reply;
/// how many stacks a structure holds
const slots=lib.structures.slots;
/// the garden's list of structures
const Structures=lib.structures.list.Structures;
/// empty tiles between two structures' footprints
const gap=lib.structures.structure.gap;
/// a hook result that may or may not fail, as one that may
const orFail=lib.structures.structure.orFail;
/// the structures registry: which kinds have which hooks
const reg=lib.structures.reg;
// ---- hook dispatch: one comptime switch each, no per-kind code here ----
/// how many of `item` structure `id` will still take in (0 if it has no
/// `wants` hook: it takes nothing)
pub fn wants(ss:*Structures,g:*const prog.Progression,id:Id,item:items.Item)u32{
  // the structure asked
  const s=ss.get(id);
  return switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"wants"))reg.module(k).wants(s,g,item)else 0,
  };
}
/// what may leave structure `id` first, as its `output` hook says (null:
/// nothing, or it has no such hook)
pub fn output(ss:*Structures,id:Id)?items.Item{
  // the structure asked
  const s=ss.get(id);
  return switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"output"))reg.module(k).output(s)else null,
  };
}
/// hand one `item` to structure `id`, coming in at `edge` (counted from
/// the way it faces): a carrier takes it into its core or a lane
/// (`receive`), anything else as `insert` does. Returns whether it went.
pub fn handIn(ss:*Structures,g:*const prog.Progression,id:Id,item:items.Item,edge:m.Dir)bool{
  // the structure taking it
  const s=ss.get(id);
  return switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"receive"))reg.module(k).receive(s,g,item,edge)else ss.insert(g,id,item,1)==1,
  };
}
/// tell structure `to` something (`Msg`): its `message` hook takes it at
/// once, else the message's default does (`arrived`: `insert`)
pub fn send(ss:*Structures,ctx:Ctx,to:Id,msg:Msg)Reply{
  // what its own hook made of it, if it has one
  const r:Reply=switch(ss.get(to).kind()){
    inline else=>|k|if(comptime reg.has(k,"message"))reg.module(k).message(ctx,to,msg)else.ignored,
  };
  if(r!=.ignored)return r;
  return switch(msg){
    .lit,.unform,.graft,.petalComing,.petalSnapped,.fastenComing,.fastened=>.ignored,
    .arrived=>|a|.{.took=ss.insert(ctx.g,to,a.item,a.n)},
  };
}
/// everything that may leave structure `id`: its `output` first, then
/// each other kind it holds that it `gives`, in slot order
pub fn outputs(ss:*Structures,id:Id)Outputs{
  return.{.ss=ss,.id=id,.first=ss.output(id)};
}
/// a walk over what may leave one structure, each kind once (`outputs`)
pub const Outputs=struct{
  /// the list the structure stands in
  ss:*Structures,
  /// the structure walked
  id:Id,
  /// its `output`, given before anything else
  first:?items.Item,
  /// the next slot to look in; -1: `first` not yet given
  k:i32=-1,
  /// the next kind that may leave, or null once all have been named
  pub fn next(it:*Outputs)?items.Item{
    if(it.k<0){
      it.k=0;
      if(it.first)|f|return f;
    }
    // the structure's slots, looked through in order
    const slot=&it.ss.get(it.id).inv.slot;
    while(it.k<slots){
      // the slot being looked in
      const k:usize=@intCast(it.k);
      it.k+=1;
      // what that slot holds (empty slots are passed over)
      const item=(slot[k] orelse continue).item;
      if(item==it.first)continue;
      // once per kind: the first slot holding it
      const again=for(slot[0..k])|o|{
        if(o)|e|if(e.item==item)break true;
      }else false;
      if(!again and it.ss.gives(it.id,item))return item;
    }
    return null;
  }
};
/// whether `item` may leave structure `id`: its `gives` hook, or else
/// whether it is its `output`
pub fn gives(ss:*Structures,id:Id,item:items.Item)bool{
  // the structure asked
  const s=ss.get(id);
  return switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"gives"))reg.module(k).gives(s,item)else ss.output(id)==item,
  };
}
/// insert up to `n` of `item` (capped by what the structure still wants).
/// Returns how many were actually inserted.
pub fn insert(ss:*Structures,g:*const prog.Progression,id:Id,item:items.Item,n:u16)u16{
  // how many it will take: `n`, or fewer if it wants fewer
  const k:u16=@intCast(@min(n,ss.wants(g,id,item)));
  if(k==0)return 0;
  return ss.get(id).bag().add(item,k);
}
/// witness every pair of grown structures that `meets` the other (once
/// each: a discovery found is never looked for again)
pub fn meetings(ss:*const Structures,g:*prog.Progression)void{
  for(ss.list.items)|*a|{
    if(a.grown<1)continue;
    // whom this one meets, and what that meeting reveals
    const mt:Meeting=switch(a.kind()){
      inline else=>|k|if(comptime reg.has(k,"meets"))reg.module(k).meets else continue,
    };
    if(g.found.contains(mt.found))continue;
    for(ss.list.items)|*b|{
      if(b.kind()!=mt.kind or b.grown<1)continue;
      if(gap(a,b)<=meetCount){
        g.discover(mt.found);
        break;
      }
    }
  }
}
/// every structure notices its neighbours (`link`) without working
/// (`--structure` holding one still)
pub fn link(ss:*Structures,gpa:Allocator,w:*World,plants:*Plants,g:*prog.Progression)void{
  linkWith(.{.gpa=gpa,.w=w,.plants=plants,.g=g,.ss=ss});
}
/// `link`, with the whole of `ctx` (the wolf, the sky) as the game has it
pub fn linkWith(ctx:Ctx)void{
  // the structures being linked
  const ss=ctx.ss;
  for(0..ss.list.items.len)|idx|switch(ss.get(Id.of(idx)).kind()){
    inline else=>|k|if(comptime reg.has(k,"link"))reg.module(k).link(ctx,Id.of(idx)),
  };
}
/// a tick with only the garden: no wolf, no sky, nothing befallen
pub fn tick(ss:*Structures,gpa:Allocator,w:*World,plants:*Plants,g:*prog.Progression,dt:f32)Allocator.Error!void{
  return tickWith(.{.gpa=gpa,.w=w,.plants=plants,.g=g,.ss=ss},dt);
}
/// `tick`, with the whole of `ctx` (the wolf, the sky, this tick's
/// events) as the game has it: each structure links, then grows `dt`
/// seconds nearer grown or, grown, works; its activity glow eases after
pub fn tickWith(ctx:Ctx,dt:f32)Allocator.Error!void{
  // the structures being ticked
  const ss=ctx.ss;
  for(0..ss.list.items.len)|idx|{
    // the structure this turn of the loop ticks
    const id=Id.of(idx);
    switch(ss.get(id).kind()){
      inline else=>|k|if(comptime reg.has(k,"link"))reg.module(k).link(ctx,id),
    }
    // the structure, fetched after linking (a link may move the list)
    const g0=ss.get(id);
    // its shine follows its light, slowly (none once it takes none, or
    // while the unforming takes it): its crown and ley-blue follow that
    g0.shine=m.damp(g0.shine,if(g0.fade>0 or lib.structures.lightUse(g0)==.none)0 else g0.lit,shineEase,dt);
    // unforming, it works no more, and grows back down as it goes
    if(g0.fade>0){
      g0.grown=@min(g0.grown,1-g0.fade);
      g0.activity=0;
      continue;
    }
    // whether it worked this tick: a sprout only grows, never works (but
    // one whose life is all growing works as it grows)
    const growing=g0.grown<1;
    if(growing)g0.grown=@min(1,g0.grown+dt/g0.def().grow);
    // how much work it does this tick, by its light: boosted, or held
    // still when it needs light it has not got
    const work=if(growing)dt else lib.structures.workTime(g0,dt);
    const active=if((growing and !g0.def().worksGrowing) or work<=0)false else switch(g0.kind()){
      // a tick that may put something down can fail for room
      inline else=>|k|if(comptime reg.has(k,"tick"))try orFail(reg.module(k).tick(ctx,id,work))else false,
    };
    // fetched again: its own tick may have put another down and moved the list
    const s=ss.get(id);
    s.activity=m.damp(s.activity,if(active)1 else 0,activityEase,dt);
  }
  // what is gone (fully faded: a drift flower taken into an arsthraxia),
  // lifted out, walking down the list so removing one never skips another
  var k=ss.list.items.len;
  while(k>0){
    k-=1;
    if(ss.list.items[k].fade<1)continue;
    // the structure, lifted out and freed
    var gone=ss.remove(ctx.w,.of(k));
    gone.deinit(ctx.gpa);
  }
}
