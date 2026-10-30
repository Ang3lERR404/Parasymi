//! DRIFTBRAID: a braided conduit and a sporecaster grown into one, that
//! trades both ways. Paired with another driftbraid (the configure key on
//! it, then on the other), each turns what it is fed into spore carriers
//! drifting, however far, into the other's pore, and takes in what the
//! other sends. What came by spore is kept apart from what it was fed: it
//! sends on only what it was fed, and lets go (to its neighbours, or to
//! conduits pulling) only what came by spore, so nothing is sent straight
//! back. Spores behave as a sporecaster's: one whose driftbraid is gone
//! turns home, one whose driftbraid is full hangs over it.
// decision: what came by spore is a count per kind over the one inventory
// (`kept`), not slots of its own: items leave a structure through its
// inventory alone. A count it has lost track of (the gardener lifting it
// out by hand, a conduit pulling) is trimmed to what is there each tick.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// an array with one entry per item kind
const EnumArray=std.enums.EnumArray;
/// the test allocator and expectations
const testing=std.testing;
/// all the maths: vectors, matrices, the four ways
const m=lib.engine.core.math;
/// colour conversions, for tinting a spore by what it carries
const color=lib.engine.core.color;
/// the chunks: tile layout and ground kinds
const ck=lib.ck;
/// the garden's world of chunks
const World=lib.world.World;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// every plant in the garden, for the tests
const Plants=lib.plants.Plants;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// the shared test bench: a patch of ground and its clock
const bench=st.bench;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the scene's list of moving parts its spores and lumps are added to
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// its mesh: where its pore and sac are
const mesh=lib.driftbraid;
/// the sporecaster it grew from: its spores, their flight and timing
const caster=lib.sporecasterStructure;
/// a point or direction in the world
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.bellyLump,.sporeCarrier};
/// paired both ways: each trades with the other
pub const pairs:st.Pairs=.{.way=.bothWays};
/// what a driftbraid is: one tile, keeping what it holds in slots,
/// growing in over 7 s, swaying gently; its spores are drawn however far
/// they drift (`far`)
pub const def:st.Def=.{.item=.driftbraid,.size=1,.mesh=.driftbraid,.store=true,.grow=7,.sway=0.4,.tall=0.9,.sap=0.3,.far=true};
/// the most it holds, fed and received together
pub const holdTime=40;
/// how many of one kind a spore carries, as a sporecaster's
const load=caster.load;
/// seconds between one spore and the next
const launch=caster.launch;
/// how many of its spores may be in the air at once
const airHeight=caster.airHeight;
/// tiles a second a spore drifts
const speed=caster.speed;
/// how see-through a spore is
const sporeFade:f32=0.35;
/// how brightly a spore glows
const sporeGlow:f32=0.6;
/// a spore's size, of its mesh
const sporeSize:f32=1.7;
/// a spore waiting over a full driftbraid hangs this high over its pore
const hangDepth:f32=0.35;
/// what it holds hangs in its sac, in a ring: how far out, as a share of
/// the sac's radius
const ringRadius:f32=0.45;
/// the size of a lump holding a single thing
const lumpR:f32=0.02;
/// how much larger a lump grows as its stack fills toward `holdTime`
const lumpGrow:f32=0.02;
/// how far each lump bobs up and down
const bobAmount:f32=0.01;
/// how fast the ring of lumps turns round the sac (radians a second)
const turnRate:f32=0.25;
/// how brightly the lumps glow in the sac
const glow:f32=0.2;
/// what a driftbraid remembers: its spores aloft, its launch clock, and
/// how much of what it holds came by spore
pub const State=struct{
  /// its spores in the air, each slot empty or one in flight
  spores:[airHeight]?caster.Spore=@splat(null),
  /// seconds since its last spore left
  t:f32=0,
  /// how many of each kind it holds came by spore
  kept:EnumArray(items.Item,u16)=.initFill(0),
};
/// the driftbraid standing at tile `at`, or null if none does
fn braidAt(ss:*st.Structures,w:*const World,at:[2]i32)?st.Id{
  // what stands there
  const j=ss.at(w,at[0],at[1]) orelse return null;
  return if(ss.get(j).kind()==.driftbraid)j else null;
}
/// pair it (`pairStep`): the first configured waits, the next trades with
/// it, both ways (each leaving whatever it traded with before). Configured
/// twice over, it stops trading.
pub fn configure(ss:*st.Structures,id:st.Id,g:*prog.Progression)void{
  switch(ss.pairStep(id)){
    .waiting=>g.say(txt.s.msg.braidChoose,.{}),
    .cut=>g.say(txt.s.msg.braidStill,.{}),
    .paired=>g.say(txt.s.msg.braidPaired,.{}),
  }
}
/// what it holds of `item` that it was fed (and may send)
fn fed(s:*const st.Structure,item:items.Item)u32{return s.inv.count(item)-|s.state.driftbraid.kept.get(item);}
/// hand one of what came by spore to a neighbour that wants it
fn handReceived(ctx:st.Ctx,i:st.Id)void{
  // the driftbraid, and the first thing it holds that came by spore
  const self=ctx.ss.get(i);
  const item=output(self) orelse return;
  for(m.dirs)|d|{
    // the step that way, and the structure standing there
    const v=m.dirVec(d);
    const j=ctx.ss.at(ctx.w,self.x+v.x,self.y+v.z) orelse continue;
    if(j==i or ctx.ss.get(j).def().carrier)continue;
    if(ctx.ss.insert(ctx.g,j,item,1)==1){
      _=self.inv.take(item,1);
      self.state.driftbraid.kept.getPtr(item).*-=1;
      return;
    }
  }
}
/// trims its spore counts to what it holds, hands on what came by spore,
/// flies its spores (landing, or turning home), and, paired, launches a
/// load of what it was fed most of. Returns whether anything is aloft or
/// left this tick.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  {
    // the driftbraid, and each count of what came by spore
    const self=ctx.ss.get(i);
    var it=self.state.driftbraid.kept.iterator();
    while(it.next())|e|e.value.*=@min(e.value.*,self.inv.count(e.key));
  }
  handReceived(ctx,i);
  // the driftbraid again (handing on may have changed it), its state, and
  // whether anything is aloft
  const self=ctx.ss.get(i);
  const db=&self.state.driftbraid;
  var busy=false;
  for(&db.spores)|*slot|{
    // the spore in this slot (an empty one is passed over)
    const sp=&(slot.* orelse continue);
    busy=true;
    // how far its flight is, in tiles (at least one)
    const far=@max(m.len(m.v3(m.f(sp.to[0]-self.x),0,m.f(sp.to[1]-self.y))),1);
    if(sp.home){
      sp.t-=dt*speed/far;
      if(sp.t>0)continue;
      // back home it is what it was fed again
      _=self.inv.add(sp.item,sp.n);
      slot.*=null;
      continue;
    }
    if(sp.t<1){
      sp.t=@min(1,sp.t+dt*speed/far);
      continue;
    }
    // the driftbraid it flies to; gone, it turns home
    const j=braidAt(ctx.ss,ctx.w,sp.to)orelse{
      sp.home=true;
      continue;
    };
    // how many it took of what the spore carries
    const took=switch(ctx.ss.send(ctx,j,.{.arrived=.{.item=sp.item,.n=sp.n}})){
      .took=>|k|k,
      .ignored,.done=>0,
    };
    sp.n-=@intCast(took);
    if(sp.n==0)slot.*=null;
  }
  if(ctx.ss.getPartner(i)==null)return busy;
  // the tile of the one it trades with
  const to=self.partner().?.tile();
  // launching: once `launch` seconds have passed, one spore if a slot is free
  sc:{
    db.t+=dt;
    if(db.t<launch)break:sc;
    // the kind it was fed most of, a load of it
    var best:?items.Item=null;
    var most:u32=0;
    for(self.inv.slot)|s|if(s)|it|{
      // how many of this kind it was fed
      const n=fed(self,it.item);
      if(n>most){
        most=n;
        best=it.item;
      }
    };
    // the kind sent (nothing fed: nothing to send)
    const item=best orelse break:sc;
    for(&db.spores)|*slot|{
      if(slot.*!=null)continue;
      // how many go in this spore: a load, or all it has
      const n:u8=@intCast(@min(most,load));
      _=self.inv.take(item,n);
      slot.*=.{.item=item,.n=n,.to=to,.toH=caster.groundAt(ctx.w,to)};
      db.t=0;
      busy=true;
      break;
    }
  }
  return busy;
}
/// uprooted: what its spores carry comes back into its slots with them.
pub fn release(s:*st.Structure)?items.Item{
  for(&s.state.driftbraid.spores)|*slot|if(slot.*)|sp|{
    _=s.inv.add(sp.item,sp.n);
    slot.*=null;
  };
  return null;
}
/// anything, while it has room.
pub fn wants(s:*const st.Structure,_:*const prog.Progression,_:items.Item)u32{return holdTime-|s.inv.total();}
/// `arrived`: what came by spore is taken in and kept apart (`kept`), to be
/// let go rather than sent back
pub fn message(ctx:st.Ctx,i:st.Id,msg:st.Msg)st.Reply{
  switch(msg){
    .arrived=>|a|{
      // how many it took in
      const took=ctx.ss.insert(ctx.g,i,a.item,a.n);
      ctx.ss.get(i).state.driftbraid.kept.getPtr(a.item).*+=took;
      return.{.took=took};
    },
    .lit=>return.ignored,
  }
}
/// the first thing it holds that came by spore.
pub fn output(s:*const st.Structure)?items.Item{
  for(s.inv.slot)|slot|if(slot)|it|if(s.state.driftbraid.kept.get(it.item)>0)return it.item;
  return null;
}
/// it gives only what came by spore, while it still holds some
pub fn gives(s:*const st.Structure,item:items.Item)bool{return s.state.driftbraid.kept.get(item)>0 and s.inv.count(item)>0;}
/// its spores drifting over (or home), and what it holds hanging in its sac.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its state, its frame in the world, and its pore there
  const db=&s.state.driftbraid;
  const base=s.place(ctr);
  const pore=m.mulPoint(base,mesh.poreAt);
  for(db.spores,0..)|slot,k|{
    // the spore in this slot (an empty one is passed over)
    const sp=slot orelse continue;
    // where it flies to (the other's pore), and its own phase
    const dest=m.footprintCentre(sp.to[0],sp.to[1],1,sp.toH)+mesh.poreAt;
    const ph=s.seed+m.f(k)*0.37;
    // where it is on its flight, and a little further along
    const at=caster.flight(pore,dest,sp.t,ph,tf);
    const ahead=caster.flight(pore,dest,if(sp.home)sp.t-0.02 else sp.t+0.02,ph,tf);
    // a spore waiting over a full driftbraid hangs there, bobbing
    const hang=if(!sp.home and sp.t>=1)v3(0,hangDepth+0.05*@sin(tf*2+m.f(k)),0)else v3(0,0,0);
    // the way its tip leads, and the colour of what it carries
    const dir=if(m.len(ahead-at)>m.eps)m.norm(ahead-at)else v3(0,1,0);
    const col=color.Rgba8.of(sp.item.info().col).toF4();
    try out.emit(.sporeCarrier,m.chain(&.{m.translate(at+hang),m.alignY(dir),m.scale3(m.splat3(sporeSize))}),.{
      .glow=sporeGlow,.phase=ph,.fade=sporeFade,.tint=.{col[0],col[1],col[2],0},.flutter=0.5,
    });
  }
  if(s.grown<1)return;
  // how many stacks it holds, and which of them is being drawn
  const n=s.inv.used();
  var j:usize=0;
  for(s.inv.slot)|slot|{
    // the stack in this slot (empty slots are passed over)
    const it=slot orelse continue;
    // the stack's place on the ring: its angle, the ring's reach, and where
    const a=m.ratio(j,n)*m.tau+tf*turnRate+s.seed*6;
    const ring=if(n==1)0 else mesh.sacR[0]*ringRadius;
    const at=mesh.sacAt+v3(@cos(a)*ring,bobAmount*@sin(tf*1.2+m.f(j)*2),@sin(a)*ring);
    // its size: larger the fuller it is
    const r=lumpR+lumpGrow*m.ratio(it.n,holdTime);
    try s.emitLump(out,base,at,r,it.item,glow);
    j+=1;
  }
}
/// its line in the panel: whom it trades with (how far off), how many
/// spores are aloft, and how much it holds fed and received; or, unpaired,
/// only how full it is
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // its state, and how many spores it has aloft
  const db=&s.state.driftbraid;
  var air:u32=0;
  for(db.spores)|sp|{if(sp!=null)air+=1;}
  // how many of what it holds came by spore
  var got:u32=0;
  for(db.kept.values)|n|got+=n;
  if(s.partner())|p|{
    // the tile of the one it trades with
    const to=p.tile();
    _=try d.print(x,y,style.textBody,style.white,txt.s.describe.trades,.{to[0]-s.x,to[1]-s.y,air,s.inv.total()-|got,got,holdTime});
  }else{
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.untraded,.{s.inv.total(),holdTime});
  }
}
/// its bulb: a twined stalk out of the seed holding a sac, spores drifting
/// off it one way and back into it the other (it trades both ways).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  for([_]f32{1,-1},[_]Color{iconGreen,iconPale})|way,c|{
    try ic.stem(.{.{-0.1,iconKit.topAt},.{-0.1+0.08*way,0.25},.{-0.1-0.08*way,0.45},.{-0.1,0.58}},0.07,c);
  }
  try ic.glow(.{-0.1,0.72},0.25,iconSacGlow);
  try ic.bud(.{-0.1,0.72},0.17,iconSac,0.4);
  for([_]f32{-1,1})|sx|try ic.stem(.{.{-0.1,0.86},.{-0.1+0.18*sx,0.98},.{-0.1+0.3*sx,0.9},.{-0.1+0.28*sx,0.78}},0.04,iconFrond);
  // the curve spores drift off along, and the one they come back by
  const out=[4]iconKit.P{.{-0.1,0.9},.{0.2,1.1},.{0.6,0.9},.{0.75,0.3}};
  const back=[4]iconKit.P{.{0.8,0.2},.{0.75,0.75},.{0.35,0.7},.{0,0.78}};
  for(0..2)|k|{
    // how far along its curve this pair of spores has drifted (0..1)
    const t=@mod(ic.t*0.5+ic.phase+m.f(k)/2,1);
    try ic.bud(iconKit.curve(out,t),0.055,iconSpore,@sin(t*m.pi));
    try ic.bud(iconKit.curve(back,t),0.05,iconSporeBack,@sin(t*m.pi));
  }
  try ic.coat(col);
}
/// the green strand of its twined stalk
const iconGreen:Color=.{80,150,95,255};
/// the pale strand twined with it
const iconPale:Color=.{185,180,205,255};
/// the lilac of the fronds over its sac
const iconFrond:Color=.{175,160,210,255};
/// the warm, half-clear sac
const iconSac:Color=.{220,150,110,210};
/// the soft violet glow round the sac
const iconSacGlow:Color=.{170,140,230,70};
/// the pale spores drifting off
const iconSpore:Color=.{235,225,255,255};
/// the warm spores drifting back
const iconSporeBack:Color=.{245,200,140,255};
// ---- tests ----
/// one beat of the bench's clock
const testDt=bench.testDt;
test"driftbraids pair both ways and trade what each is fed, never sending it back"{
  // the test allocator, and the world it grows on
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=30,.depth=2});
  // the plants, the structures and what is understood
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.driftbraid,0,0));
  try testing.expect(try ss.place(gpa,&w,26,1,.driftbraid,0,0));
  // the two driftbraids, far apart
  const a=ss.at(&w,0,0).?;
  const b=ss.at(&w,26,1).?;
  st.configure(&ss,a,&g);
  st.configure(&ss,b,&g);
  try testing.expectEqual(b,ss.getPartner(a).?);
  try testing.expectEqual(a,ss.getPartner(b).?);
  _=ss.insert(&g,a,.essence,12);
  _=ss.insert(&g,b,.grit,9);
  // nothing fed may leave by conduit
  try testing.expect(ss.output(a)==null and !ss.gives(a,.essence));
  try bench.run(&ss,&w,&plants,&g,30);
  try testing.expectEqual(@as(u32,12),ss.get(b).inv.count(.essence));
  try testing.expectEqual(@as(u32,9),ss.get(a).inv.count(.grit));
  try testing.expectEqual(@as(u32,0),ss.get(a).inv.count(.essence));
  try testing.expectEqual(@as(u32,0),ss.get(b).inv.count(.grit));
  // what came by spore is what it lets go
  try testing.expect(ss.output(a)==.grit and ss.gives(b,.essence));
  // configured twice over, both stop trading
  st.configure(&ss,a,&g);
  st.configure(&ss,a,&g);
  try testing.expect(ss.get(a).partner()==null and ss.get(b).partner()==null);
}
test"what a driftbraid received is handed on to its neighbours"{
  // the test allocator, and the world it grows on
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=30,.depth=2});
  // the plants, the structures and what is understood
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.driftbraid,0,0));
  try testing.expect(try ss.place(gpa,&w,20,0,.driftbraid,0,0));
  try testing.expect(try ss.place(gpa,&w,21,0,.sapCache,0,0));
  st.configure(&ss,ss.at(&w,0,0).?,&g);
  st.configure(&ss,ss.at(&w,20,0).?,&g);
  _=ss.insert(&g,ss.at(&w,0,0).?,.fibre,10);
  try bench.run(&ss,&w,&plants,&g,30);
  try testing.expectEqual(@as(u32,10),ss.get(ss.at(&w,21,0).?).inv.count(.fibre));
}
