//! structures tested: messages, partners, outputs, growing, parents and children.
const lib=@import("../../../lib.zig");
const std=lib.std;
const testing=std.testing;
const ck=lib.ck;
const World=lib.world.World;
const Plants=lib.plants.Plants;
const prog=lib.progression;
const record=lib.record;
const Ctx=lib.structures.structure.Ctx;
const Ref=lib.structures.Ref;
const Reply=lib.structures.messages.Reply;
const Structure=lib.structures.structure.Structure;
const Structures=lib.structures.list.Structures;
const blank=lib.structures.structure.blank;
const choose=lib.structures.hooks.choose;
const defs=lib.structures.defs;
const freshState=lib.structures.structure.freshState;
const handOff=lib.structures.handoff.handOff;
const kindByName=lib.structures.structure.kindByName;
const kinds=lib.structures.kinds;
const recipes=lib.structures.hooks.recipes;
const reg=lib.structures.reg;
test"every kind's structure is stored as a record and read back the same"{
  const gpa=testing.allocator;
  inline for(reg.ids)|k|{
    var s=blank(k);
    s.x=3;
    s.y=-2;
    s.grown=0.5;
    _=s.inv.add(.grit,4);
    s.partners[0]=.{.x=1,.y=1,.floating=true};
    var a:std.ArrayList(u8)=.empty;
    defer a.deinit(gpa);
    try record.write(Structure,gpa,&a,&s);
    var back=blank(kindByName(record.nameHash(@tagName(k))).?);
    defer back.deinit(gpa);
    try record.read(Structure,gpa,a.items,&back);
    var b:std.ArrayList(u8)=.empty;
    defer b.deinit(gpa);
    try record.write(Structure,gpa,&b,&back);
    try testing.expectEqualSlices(u8,a.items,b.items);
    try testing.expectEqual(k,back.kind());
    try testing.expectEqual(@as(u32,4),back.inv.count(.grit));
  }
}
test"a message is taken by its hook, else by its default"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  const c=w.chunkOfTile(0,0).?;
  for(0..4)|x|{c.kind[x]=.soil;c.height[x]=1;c.res[x]=0;}
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  const ctx:Ctx=.{.gpa=gpa,.w=&w,.plants=&plants,.g=&g,.ss=&ss};
  try testing.expect(try ss.place(gpa,&w,0,0,.sapCache,0,0));
  try testing.expect(try ss.place(gpa,&w,1,0,.diamond,0,0));
  try testing.expect(try ss.place(gpa,&w,2,0,.loomfern,0,0));
  const cache=ss.at(&w,0,0).?;
  const dia=ss.at(&w,1,0).?;
  const fern=ss.at(&w,2,0).?;
  try testing.expectEqual(Reply{.took=3},ss.send(ctx,cache,.{.arrived=.{.item=.grit,.n=3}}));
  try testing.expectEqual(@as(u32,3),ss.get(cache).inv.count(.grit));
  // taken only as far as it wants
  try testing.expectEqual(Reply{.took=0},ss.send(ctx,fern,.{.arrived=.{.item=.grit,.n=3}}));
  try testing.expectEqual(Reply.ignored,ss.send(ctx,cache,.lit));
  try testing.expectEqual(Reply.done,ss.send(ctx,dia,.lit));
  for(ss.get(dia).state.diamond.light)|l|try testing.expectEqual(@as(f32,1),l);
}
/// a kind's file name: its camelCase name with each capital turned to `_` and lower case
fn snakeOf(comptime name:[]const u8)[]const u8{
  comptime var out:[]const u8="";
  inline for(name)|c|{
    out=out++if(std.ascii.isUpper(c))"_"++[_]u8{std.ascii.toLower(c)} else [_]u8{c};
  }
  return out;
}
test"no kind reads or writes another kind's state outside its tests"{
  @setEvalBranchQuota(2_000_000);
  inline for(comptime std.meta.declarations(kinds))|d|{
    const src=@embedFile("../"++comptime snakeOf(d.name)++".zig");
    const body=comptime src[0..std.mem.indexOf(u8,src,"\ntest\"") orelse src.len];
    inline for(comptime std.meta.declarations(kinds))|o|{
      if(comptime!std.mem.eql(u8,o.name,d.name)){
        if(comptime std.mem.indexOf(u8,body,".state."++o.name)!=null)
          @compileError(d.name++" reaches into "++o.name++"'s state: send it a `Msg` or read a hook");
      }
    }
  }
}
test"several partners: each once, oldest first, the oldest let go past `most`"{
  var s:Structure=.{.x=0,.y=0,.seed=0,.state=freshState(.driftbraid)};
  const r=[_]Ref{.{.x=1,.y=0,.floating=false},.{.x=2,.y=0,.floating=false},.{.x=3,.y=0,.floating=false}};
  try testing.expect(s.addPartner(r[0],2)==null);
  try testing.expect(s.addPartner(r[0],2)==null);
  try testing.expect(s.addPartner(r[1],2)==null);
  try testing.expectEqual(@as(usize,2),s.partnerCount());
  try testing.expect(s.addPartner(r[2],2).?.eql(r[0]));
  try testing.expect(s.partner().?.eql(r[1]) and s.pairedWith(r[2])and!s.pairedWith(r[0]));
  try testing.expect(s.dropPartner(r[1])and!s.dropPartner(r[1]));
  try testing.expect(s.partner().?.eql(r[2]) and s.partnerCount()==1);
}
test"several outputs: what a neighbour wants goes, even when it is not the first"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  const c=w.chunkOfTile(0,0).?;
  for(0..4)|x|{c.kind[x]=.soil;c.height[x]=1;c.res[x]=0;}
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  const ctx:Ctx=.{.gpa=gpa,.w=&w,.plants=&plants,.g=&g,.ss=&ss};
  try testing.expect(try ss.place(gpa,&w,0,0,.sapCache,0,0));
  try testing.expect(try ss.place(gpa,&w,1,0,.loomfern,0,0));
  const cache=ss.at(&w,0,0).?;
  _=ss.get(cache).inv.add(.essence,2);
  _=ss.get(cache).inv.add(.fibre,3);
  // the newest stack first, then the rest it gives
  var out=ss.outputs(cache);
  try testing.expect(out.next()==.fibre and out.next()==.essence and out.next()==null);
  // a loomfern takes no fibre, only essence
  try testing.expect(handOff(ctx,cache));
  try testing.expectEqual(@as(u32,1),ss.get(ss.at(&w,1,0).?).inv.count(.essence));
  try testing.expectEqual(@as(u32,3),ss.get(cache).inv.count(.fibre));
}
test"a structure put down grows before it works"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  const c=w.chunkOfTile(0,0).?;
  for(0..2)|x|for(0..2)|y|{const t=y*ck.sizeTiles+x;c.kind[t]=.soil;c.height[t]=1;c.res[t]=0;};
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.germinator,0,0));
  const id=ss.at(&w,0,0).?;
  ss.sprout(id);
  try testing.expectEqual(@as(f32,0),ss.get(id).grown);
  const secs=defs.get(.germinator).grow;
  var t:f32=0;
  while(t<secs*0.5):(t+=0.05)try ss.tick(gpa,&w,&plants,&g,0.05);
  try testing.expect(ss.get(id).grown>0.4 and ss.get(id).grown<0.6);
  try testing.expect(ss.get(id).activity<0.01);
  while(t<secs+0.1):(t+=0.05)try ss.tick(gpa,&w,&plants,&g,0.05);
  try testing.expectEqual(@as(f32,1),ss.get(id).grown);
}
test"a germinator weaves structure bulbs as well as seeds, and lets go only what it wove"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  const c=w.chunkOfTile(0,0).?;
  for(0..2)|x|for(0..2)|y|{const t=y*ck.sizeTiles+x;c.kind[t]=.soil;c.height[t]=1;c.res[t]=0;};
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.germinator,0,0));
  const id=ss.at(&w,0,0).?;
  const craft=lib.craft;
  // every weave is on offer, the bulbs too, but the advanced tier, which
  // only a monfris weaves
  try testing.expectEqual(craft.hand.len-craft.advanced.len,recipes(.germinator).len);
  for(recipes(.monfris))|r|try testing.expect(craft.hand[r].advanced);
  const conduit=for(recipes(.germinator))|r|{
    if(craft.hand[r].out==.conduit)break r;
  }else unreachable;
  choose(ss.get(id),&g,conduit);
  try testing.expectEqual(@as(u16,5),ss.insert(&g,id,.fibre,5));
  try testing.expectEqual(@as(u16,2),ss.insert(&g,id,.grit,2));
  // what it weaves from never leaves it
  try testing.expect(ss.output(id)==null);
  for(0..400)|_|try ss.tick(gpa,&w,&plants,&g,0.05);
  try testing.expectEqual(@as(u32,4),ss.get(id).inv.count(.conduit));
  try testing.expectEqual(@as(u32,1),ss.get(id).inv.count(.fibre));
  try testing.expect(ss.output(id)==.conduit);
}
test"parents and children: spawned, adopted, found again after a shift, cut loose when the parent goes"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  const c=w.chunkOfTile(0,0).?;
  for(0..8)|x|for(0..8)|y|{const t=y*ck.sizeTiles+x;c.kind[t]=.soil;c.height[t]=1;c.res[t]=0;};
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  try testing.expect(try ss.place(gpa,&w,0,0,.sapCache,0,0));
  try testing.expect(try ss.place(gpa,&w,4,4,.monfris,0,0));
  const loom=ss.at(&w,4,4).?;
  // a child put down by its parent, over the parent's own tile
  const v0=(try ss.spawnChild(gpa,&w,loom,.{.x=4,.y=4,.kind=.vultrixi})).?;
  try testing.expectEqual(loom,ss.getParent(v0).?);
  try testing.expect(try ss.spawnChild(gpa,&w,loom,.{.x=4,.y=4,.kind=.vultrixi})==null);
  // adopted: only what the parent takes on (`adopts`), never in a loop
  try testing.expect(try ss.place(gpa,&w,1,1,.vultrixi,0,0));
  const v1=ss.floaterAt(1,1).?;
  const cache=ss.at(&w,0,0).?;
  try testing.expect(!ss.dependOn(v1,cache));
  try testing.expect(!ss.dependOn(loom,v1));
  try testing.expect(!ss.dependOn(v1,v1));
  try testing.expect(ss.dependOn(v1,loom));
  try testing.expectEqual(@as(u32,2),ss.childCount(loom));
  try testing.expectEqual(v0,ss.getChild(loom,0).?);
  try testing.expectEqual(v1,ss.getChild(loom,1).?);
  try testing.expect(ss.getChild(loom,2)==null);
  try testing.expectEqual(@as(u32,0),ss.childCount(cache));
  // uprooting the cache shifts the others' ids; they still find each other
  _=ss.remove(&w,cache);
  const loom2=w.occAt(4,4).asStructure().?;
  try testing.expectEqual(@as(u32,2),ss.childCount(loom2));
  try testing.expectEqual(loom2,ss.getParent(ss.floaterAt(1,1).?).?);
  ss.detach(ss.floaterAt(1,1).?);
  try testing.expectEqual(@as(u32,1),ss.childCount(loom2));
  // uprooting the parent cuts its children loose
  _=ss.remove(&w,loom2);
  try testing.expect(ss.get(ss.floaterAt(4,4).?).parent==null);
}
test"partners: one way or both ways, re-pairing leaves the old one, uprooting cuts it"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  const c=w.chunkOfTile(0,0).?;
  for(0..8)|x|{c.kind[x]=.soil;c.height[x]=1;c.res[x]=0;}
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  for(0..3)|x|try testing.expect(try ss.place(gpa,&w,@intCast(x),0,.driftbraid,0,0));
  try testing.expect(try ss.place(gpa,&w,4,0,.sporecaster,0,0));
  try testing.expect(try ss.place(gpa,&w,5,0,.sapCache,0,0));
  const a=ss.at(&w,0,0).?;
  const b=ss.at(&w,1,0).?;
  const d=ss.at(&w,2,0).?;
  // only with its own kind, never with itself, never what does not pair
  try testing.expect(!ss.pairWith(a,ss.at(&w,4,0).?));
  try testing.expect(!ss.pairWith(a,a));
  try testing.expect(!ss.pairWith(ss.at(&w,5,0).?,a));
  try testing.expect(ss.pairWith(a,b));
  try testing.expectEqual(a,ss.getPartner(b).?);
  // both ways: d pairing with b leaves a alone
  try testing.expect(ss.pairWith(d,b));
  try testing.expect(ss.get(a).partner()==null);
  try testing.expectEqual(d,ss.getPartner(b).?);
  _=ss.remove(&w,b);
  try testing.expect(ss.get(ss.at(&w,2,0).?).partner()==null);
}
