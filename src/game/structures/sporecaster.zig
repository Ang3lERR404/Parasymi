//! SPORECASTER: a parasite that sends. Paired with another sporecaster (the
//! configure key on it, then on the one it should send to), it turns what
//! it is fed into spore carriers, a few of one kind to a spore, which rise
//! out of its pore and drift over everything, however far, straight down
//! into the pore of the one it is paired with. Spores cost nothing: a
//! fruiting body manifests them by the thousand. The caster they land in
//! hands what they bring to its neighbours, or conduits pull it away, or,
//! paired on itself, it sends it on again: the loop conduits cannot close.
//! A spore whose caster is gone turns home and gives back what it carried;
//! one whose caster is full hangs over it until there is room. It needs
//! the light grid's light at both ends: a dark caster casts no spores, and
//! a spore over a dark one hangs there until its light comes.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the test harness: allocator and expectations
const testing=std.testing;
/// all the maths: vectors, matrices, easing
const m=lib.engine.core.math;
/// colour conversions, for tinting a spore by what it carries
const color=lib.engine.core.color;
/// chunk layout: tiles and their heights
const ck=lib.ck;
/// the garden's tile world
const World=lib.world.World;
/// world generation, for the ground's height where no chunk is loaded
const gen=lib.gen;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// the garden's plants (the tests' bench needs a list of them)
const Plants=lib.plants.Plants;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// the shared structure test bench: ground, running ticks
const bench=st.bench;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the scene's list of moving parts this caster adds to each frame
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the sporecaster's mesh: where its pore and sac are
const mesh=lib.sporecaster;
/// a three-float vector
const V3=m.V3;
/// builds a three-float vector
const v3=m.v3;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.bellyLump,.sporeCarrier};
/// paired one way: its partner is the caster it sends to
pub const pairs:st.Pairs=.{};
/// what a sporecaster is: grown from its seed, one tile across, a pale
/// store that swaps sap and is drawn from afar
pub const def:st.Def=.{.item=.sporecaster,.lineage=.parasitic,.size=1,.mesh=.sporecaster,.store=true,.grow=5,.sway=0.45,.tall=0.65,.sap=0.3,.far=true,.light=.needs,.draws=2};
/// the most it holds
pub const holdMost=40;
/// how many of one kind a spore carries
pub const load=5;
/// seconds between one spore and the next
pub const launch:f32=0.25;
/// spores in the air at once from one caster
pub const airMost=24;
/// tiles a second a spore drifts
pub const speed:f32=2.5;
/// how high it rises over a crossing, as a share of how far it goes
const riseHeight:f32=0.22;
/// the least it rises, however short the crossing
const riseMin:f32=1.2;
/// it wanders off its line by this much, back and forth as it goes
const wanderAmount:f32=0.25;
/// how see-through a spore is
const sporeFade:f32=0.35;
/// how brightly a spore glows
const sporeGlow:f32=0.6;
/// a spore's size, of its mesh
const sporeSize:f32=1.7;
/// a spore waiting over a full caster hangs this high over its pore, bobbing
const hangDepth:f32=0.35;
/// what it holds hangs in its sac in a ring this far out, as a share of
/// the sac's radius
const ringRadius:f32=0.45;
/// the size of a held shape holding a single thing
const lumpR:f32=0.022;
/// how much larger a held shape grows as the sac fills
const lumpGrow:f32=0.02;
/// how far each held shape bobs up and down
const bobAmount:f32=0.01;
/// how fast the ring of held shapes turns (radians a second)
const turnRate:f32=0.25;
/// how brightly the held shapes glow
const glow:f32=0.2;
/// one spore in the air: what it carries and where it is bound
pub const Spore=struct{
  /// the kind it carries
  item:items.Item,
  /// how many of it
  n:u8,
  /// how far along it is (0 at the pore it left .. 1 at the one it seeks)
  t:f32=0,
  /// the tile of the caster it seeks
  to:m.Vice(i32,2),
  /// the ground height under that caster
  toH:f32,
  /// whether it has turned home, carrying back what it could not deliver
  home:bool=false,
};
/// what a sporecaster remembers: its spores in the air, and the time since
/// it sent the last
pub const State=struct{
  /// each spore in the air, or null for a free place
  spores:Air=@splat(null),
  /// seconds since it sent its last spore
  t:f32=0,
};
/// what a sporecaster or a driftbraid keeps aloft: each place a spore in
/// flight, or null for a free one
pub const Air=[airMost]?Spore;
/// the structure of `kind` on tile `at`, if one stands there
fn seekerAt(ss:*st.Structures,w:*const World,at:m.Vice(i32,2),kind:st.Kind)?st.Id{
  // whatever structure stands there
  const j=ss.at(w,at[0],at[1]) orelse return null;
  return if(ss.get(j).kind()==kind)j else null;
}
/// drifts each of `self`'s spores in `air` on: home (back into it), or
/// toward the `kind` it seeks, landing what fits there and turning home once
/// that one is gone. Returns whether any spore is in the air
pub fn drift(ctx:st.Ctx,self:*st.Structure,air:*Air,kind:st.Kind,dt:f32)bool{
  // whether any spore is in the air
  var busy=false;
  for(air)|*slot|{
    // the spore in this place
    const sp=&(slot.* orelse continue);
    busy=true;
    // how far its crossing is, tiles (at least one)
    const far=@max(m.len(m.v3(m.f(sp.to[0]-self.x),0,m.f(sp.to[1]-self.y))),1);
    if(sp.home){
      sp.t-=dt*speed/far;
      if(sp.t>0)continue;
      _=self.inv.add(sp.item,sp.n);
      slot.*=null;
      continue;
    }
    if(sp.t<1){
      sp.t=@min(1,sp.t+dt*speed/far);
      continue;
    }
    // over the one it seeks: in, if it is still there and has room
    const j=seekerAt(ctx.ss,ctx.w,sp.to,kind)orelse{
      sp.home=true;
      continue;
    };
    // a dark one takes nothing in: the spore hangs over it till it is lit
    if(lib.structures.lightUse(ctx.ss.get(j))!=.none and ctx.ss.get(j).lit<lib.light.needAt)continue;
    // how many the one below took in
    const took=switch(ctx.ss.send(ctx,j,.{.arrived=.{.item=sp.item,.n=sp.n}})){
      .took=>|k|k,
      .ignored,.done,.joint=>0,
    };
    sp.n-=@intCast(took);
    if(sp.n==0)slot.*=null;
  }
  return busy;
}
/// `n` of `item` taken out of `self` and sent off on the first free place in
/// `air` toward tile `to`; false, with nothing taken, while every one is aloft
pub fn launchSpore(self:*st.Structure,air:*Air,w:*const World,item:items.Item,n:u8,to:m.Vice(i32,2))bool{
  for(air)|*slot|{
    if(slot.*!=null)continue;
    _=self.inv.take(item,n);
    slot.*=.{.item=item,.n=n,.to=to,.toH=groundAt(w,to)};
    return true;
  }
  return false;
}
/// every spore in `air` back home at once, what it carries in `s`'s slots
pub fn bringHome(s:*st.Structure,air:*Air)void{
  for(air)|*slot|if(slot.*)|sp|{
    _=s.inv.add(sp.item,sp.n);
    slot.*=null;
  };
}
/// how many spores are in the air
pub fn aloft(air:*const Air)u32{
  // the count so far
  var n:u32=0;
  for(air)|sp|{if(sp!=null)n+=1;}
  return n;
}
/// the spores in `air` drifting from `pore` (in the world) to the pore each
/// seeks, `poreAt` over that one's tile (or home), each its tip leading and
/// a bead of what it carries inside; one waiting over a full one hangs there,
/// bobbing
pub fn emitSpores(s:*const st.Structure,out:*Parts,air:*const Air,pore:V3,poreAt:V3,tf:f32)Allocator.Error!void{
  for(air,0..)|slot,k|{
    // the spore in this place
    const sp=slot orelse continue;
    // the pore it seeks, and its own phase
    const dest=m.footprintCentre(sp.to[0],sp.to[1],1,sp.toH)+poreAt;
    const ph=s.seed+m.f(k)*0.37;
    // where it is now, and a little further along its way
    const at=flight(pore,dest,sp.t,ph,tf);
    const ahead=flight(pore,dest,if(sp.home)sp.t-0.02 else sp.t+0.02,ph,tf);
    // how far it hangs below its way while it waits
    const hang=if(!sp.home and sp.t>=1)v3(0,hangDepth+0.05*@sin(tf*2+m.f(k)),0)else v3(0,0,0);
    // the way its tip leads, and the colour of what it carries
    const dir=if(m.dist(ahead,at)>m.eps)m.norm(ahead-at)else v3(0,1,0);
    const col=color.Rgba8.of(sp.item.info().col).toF4();
    try out.emit(.sporeCarrier,m.chain(&.{m.translate(at+hang),m.alignY(dir),m.scale3(m.splat3(sporeSize))}),.{
      .glow=sporeGlow,.phase=ph,.fade=sporeFade,.tint=.{col[0],col[1],col[2],0},.flutter=0.5,
    });
  }
}
/// the ground's height at tile `at`: from its chunk if loaded, else as the
/// world would generate it
pub fn groundAt(w:*const World,at:m.Vice(i32,2))f32{
  if(w.chunkOfTile(at[0],at[1]))|c|return c.height[ck.localIndex(at[0],at[1])];
  return gen.heightAt(w.seed,at[0],at[1]);
}
/// pair it (`pairStep`): the first configured waits, the next is where the
/// first sends. Configured twice over, it stops sending.
pub fn configure(ss:*st.Structures,id:st.Id,g:*prog.Progression)void{
  switch(ss.pairStep(id)){
    .waiting=>g.say(txt.s.msg.sporesChoose,.{}),
    .cut=>g.say(txt.s.msg.sporesStill,.{}),
    .paired=>g.say(txt.s.msg.sporesPaired,.{}),
  }
}
/// drifts each spore on (home, or toward its caster, landing what fits
/// there), and while paired and holding anything sends a load of what it
/// holds most of every `launch` seconds. Returns true while busy.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the caster itself, and its remembered state
  const self=ctx.ss.get(i);
  const sc=&self.state.sporecaster;
  // a caster that sends hands nothing to its neighbours: it sends it all
  if(self.partner()==null)_=st.handOff(ctx,i);
  // whether any spore is in the air
  const busy=drift(ctx,self,&sc.spores,.sporecaster,dt);
  if(ctx.ss.getPartner(i)==null)return busy;
  // the tile of the caster it sends to
  const to=self.partner().?.tile();
  // dark, it casts nothing (what is aloft still drifts on)
  if(self.inv.total()==0 or self.lit<lib.light.needAt)return busy;
  sc.t+=dt;
  if(sc.t<launch)return true;
  // the kind it holds most of, a load of it
  var best:?items.Stack=null;
  for(self.inv.slot)|s|if(s)|it|if(best==null or it.n>best.?.n){
    best=it;
  };
  // that stack, and how many of it this spore carries
  const it=best orelse return true;
  if(launchSpore(self,&sc.spores,ctx.w,it.item,@intCast(@min(it.n,load)),to))sc.t=0;
  return true;
}
/// how its light paces it: never by the tick (its spores aloft drift on in
/// the dark); it casts only while lit and lands only in a lit caster, so it
/// still draws its light as one that needs it
pub fn lightUse(_:*const st.Structure)st.Use{return.looks;}
/// uprooted: what its spores carry comes back into its slots with them.
pub fn release(s:*st.Structure)?items.Item{
  bringHome(s,&s.state.sporecaster.spores);
  return null;
}
/// anything, while it has room (up to `holdMost` in all).
pub fn wants(s:*const st.Structure,_:*const prog.Progression,_:items.Item)u32{return holdMost-|s.inv.total();}
/// the oldest thing it holds (what a caster that sends nowhere lets go).
pub fn output(s:*const st.Structure)?items.Item{
  if(s.partner()!=null)return null;
  for(s.inv.slot)|slot|if(slot)|it|return it.item;
  return null;
}
/// it gives anything it holds, but only while it sends nowhere.
pub fn gives(s:*const st.Structure,item:items.Item)bool{return s.partner()==null and s.inv.count(item)>0;}
/// the spores it sent, drifting over to the caster they seek (or home),
/// each its tip leading and a bead of what it carries inside; and what it
/// holds hanging in its sac.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its remembered state, its frame in the world, and its pore there
  const sc=&s.state.sporecaster;
  const base=s.place(ctr);
  const pore=m.mulPoint(base,mesh.poreAt);
  try emitSpores(s,out,&sc.spores,pore,mesh.poreAt,tf);
  if(s.grown<1)return;
  // how many stacks it holds, and which of them is being drawn
  const n=s.inv.used();
  var j:usize=0;
  for(s.inv.slot)|slot|{
    // the stack in this slot
    const it=slot orelse continue;
    // the stack's place on the ring: its angle, the ring's reach, where it hangs
    const a=m.ratio(j,n)*m.tau+tf*turnRate+s.seed*6;
    const ring=if(n==1)0 else mesh.sacR[0]*ringRadius;
    const at=mesh.sacAt+v3(@cos(a)*ring,bobAmount*@sin(tf*1.2+m.f(j)*2),@sin(a)*ring);
    // its size: larger the fuller the sac
    const r=lumpR+lumpGrow*m.ratio(it.n,holdMost);
    try s.emitLump(out,base,at,r,it.item,glow);
    j+=1;
  }
}
/// where a spore is `t` along its drift from `from` to `to`: up out of the
/// pore, a long rise and fall over the ground, straight down into the
/// pore it seeks, wandering a little off its line as it goes
pub fn flight(from:V3,to:V3,t:f32,ph:f32,tf:f32)V3{
  // how far along (0..1), and the way from start to end
  const k=m.clamp01(t);
  const d=to-from;
  // that way laid level, and how far it runs
  const flat=v3(d[0],0,d[2]);
  const far=m.len(flat);
  // the level sideways it wanders along, and how high it rises
  const side=if(far>m.eps)m.norm(m.cross(flat,v3(0,1,0)))else v3(1,0,0);
  const rise=@max(riseMin,riseHeight*far);
  // eased along, so it leaves and arrives slowly
  const e=m.smooth(k);
  // how far off its line it has wandered now (none at either end)
  const wander=wanderAmount*@sin(m.pi*k)*@sin(k*9+ph*7+tf*0.7);
  return from+flat*m.splat3(e)+v3(0,d[1]*e+rise*@sin(m.pi*k),0)+side*m.splat3(wander);
}
/// its line in the panel: where it sends (as an offset), spores in the air
/// and how full it is; or, dim, that it is unpaired.
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // its remembered state
  const sc=&s.state.sporecaster;
  // how many spores are in the air
  const air=aloft(&sc.spores);
  if(s.partner())|p|{
    // the tile it sends to
    const to=p.tile();
    _=try d.print(x,y,style.textBody,style.white,txt.s.describe.sends,.{to[0]-s.x,to[1]-s.y,air,s.inv.total(),holdMost});
  }else{
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.unpaired,.{s.inv.total(),holdMost});
  }
}
/// its bulb: a tall pale stalk out of the seed holding a sac, spores rising
/// out of its pore and drifting off along an arc (it sends things far).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.stem(.{.{-0.1,iconKit.topAt},.{-0.05,0.3},.{-0.16,0.45},.{-0.1,0.58}},0.09,iconSkin);
  try ic.glow(.{-0.1,0.72},0.25,iconSacGlow);
  try ic.bud(.{-0.1,0.72},0.18,iconSac,0.3);
  for([_]f32{-1,1})|sx|try ic.stem(.{.{-0.1,0.86},.{-0.1+0.18*sx,0.98},.{-0.1+0.3*sx,0.9},.{-0.1+0.28*sx,0.78}},0.04,iconFrond);
  // the arc the spores drift along
  const arc=[4]iconKit.P{.{-0.1,0.9},.{0.2,1.1},.{0.6,0.9},.{0.75,0.3}};
  for(0..3)|k|{
    // how far along the arc this spore has drifted (0..1)
    const t=@mod(ic.t*0.5+ic.phase+m.f(k)/3,1);
    try ic.bud(iconKit.curve(arc,t),0.06,iconSpore,@sin(t*m.pi));
  }
  try ic.coat(col);
}
/// the pale lilac of its stalk in its bulb
const iconSkin:Color=.{190,182,205,255};
/// the violet of the fronds round its pore
const iconFrond:Color=.{175,160,210,255};
/// the translucent blue of its sac
const iconSac:Color=.{120,160,220,200};
/// the soft blue glow behind that sac
const iconSacGlow:Color=.{120,160,220,70};
/// the near-white of the drifting spores
const iconSpore:Color=.{235,225,255,255};
// ---- tests ----
test"sporecasters pair by configuring one, then the one it sends to"{
  // the allocator, the world and its ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=30,.depth=2});
  // the structures, and what the gardener understands
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.sporecaster,0,0));
  try testing.expect(try ss.place(gpa,&w,25,1,.sporecaster,0,0));
  // the two casters: the sender and the one it sends to
  const a=ss.at(&w,0,0).?;
  const b=ss.at(&w,25,1).?;
  st.configure(&ss,a,&g);
  try testing.expect(ss.pairing!=null);
  st.configure(&ss,b,&g);
  try testing.expectEqual(b,ss.getPartner(a).?);
  try testing.expect(ss.get(b).partner()==null and ss.pairing==null);
  // the casters paired to b
  var toB=ss.pairedTo(b);
  try testing.expectEqual(a,toB.next().?);
  try testing.expect(toB.next()==null);
  // configured twice over, it stops sending
  st.configure(&ss,a,&g);
  st.configure(&ss,a,&g);
  try testing.expect(ss.get(a).partner()==null);
}
test"spores carry what a caster is fed to the one it is paired with, however far"{
  // the allocator, the world and its ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=30,.depth=2});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.sporecaster,0,0));
  try testing.expect(try ss.place(gpa,&w,28,0,.sporecaster,0,0));
  // the sender
  const a=ss.at(&w,0,0).?;
  try testing.expect(ss.pairWith(a,ss.at(&w,28,0).?));
  // both in light (they cast and take in only lit)
  for(ss.list.items)|*c|c.lit=1;
  try testing.expectEqual(@as(u16,12),ss.insert(&g,a,.essence,12));
  try testing.expectEqual(@as(u16,7),ss.insert(&g,a,.grit,7));
  // a caster that sends lets nothing go to conduits
  try testing.expect(ss.output(a)==null);
  try bench.run(&ss,&w,&plants,&g,24);
  // the caster it sent to
  const b=ss.get(ss.at(&w,28,0).?);
  try testing.expectEqual(@as(u32,12),b.inv.count(.essence));
  try testing.expectEqual(@as(u32,7),b.inv.count(.grit));
  try testing.expectEqual(@as(u32,0),ss.get(a).inv.total());
  // the one it lands in, sending nowhere, lets it go
  try testing.expect(ss.output(ss.at(&w,28,0).?)!=null);
}
test"spores whose caster is uprooted turn home with what they carry"{
  // the allocator, the world and its ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=30,.depth=2});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.sporecaster,0,0));
  try testing.expect(try ss.place(gpa,&w,28,0,.sporecaster,0,0));
  // the sender
  const a=ss.at(&w,0,0).?;
  try testing.expect(ss.pairWith(a,ss.at(&w,28,0).?));
  // both in light (they cast and take in only lit)
  for(ss.list.items)|*c|c.lit=1;
  _=ss.insert(&g,a,.fibre,10);
  try bench.run(&ss,&w,&plants,&g,1);
  _=ss.remove(&w,ss.at(&w,28,0).?);
  // uprooting it cut the pairing
  try testing.expect(ss.get(ss.at(&w,0,0).?).partner()==null);
  try bench.run(&ss,&w,&plants,&g,24);
  // the sender, its spores home again
  const back=ss.get(ss.at(&w,0,0).?);
  try testing.expectEqual(@as(u32,10),back.inv.count(.fibre));
  for(back.state.sporecaster.spores)|sp|try testing.expect(sp==null);
}
