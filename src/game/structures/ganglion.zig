//! GANGLION: a parasite's nerve knot that shares out what it is fed. Fed by
//! conduits (or the gardener), it holds a few things in its bladder and
//! hands them on, one at a time and in turn, to every neighbour that will
//! take one: any structure beside it that wants it (so one line can feed
//! several germinators or arsthraxias, each only what it needs), and any
//! carrier leading away from it, which splits a line two or three ways.
//! It never hands back into a carrier facing into it. It is a brain: a
//! folded pale knot, what it holds seen travelling inside it, glowing,
//! each leaving a trail of light. A nerve grows out to each neighbour it
//! feeds, branching as a neuron's, and a pulse of what it hands on runs
//! out along it.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the test harness: allocator and expectations
const testing=std.testing;
/// all the maths: vectors, directions, easing
const m=lib.engine.core.math;
/// colour conversions, for tinting a pulse by its item's colour
const color=lib.engine.core.color;
/// chunk sizes, for laying moss under the tests' loomferns
const ck=lib.ck;
/// the garden's tile world the tests grow on
const World=lib.world.World;
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
/// the scene's list of moving parts this ganglion adds to each frame
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the ganglion's mesh: the knot's middle and the path inside it what it holds travels
const mesh=lib.ganglion;
/// builds a three-float vector
const v3=m.v3;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.ganglionHeld,.ganglionNerve,.ganglionTrail};
/// what a ganglion is: grown from its seed, one tile across, a pale low
/// knot that stores and swaps sap, swaying a little
pub const def:st.Def=.{.item=.ganglion,.lineage=.parasitic,.size=1,.mesh=.ganglion,.store=true,.grow=4,.sway=0.4,.tall=0.45,.sap=0.3};
/// the most things its bladder holds at once
pub const holdMost=8;
/// seconds between one hand-off and the next
pub const pass:f32=0.35;
/// how fast a nerve grows out to a neighbour it may feed (lengths a second)
const nerveGrow:f32=0.8;
/// how fast a nerve withers once that neighbour is gone (lengths a second)
const nerveWither:f32=1.2;
/// a pulse runs out along a nerve this fast (its length a second)
const pulseRate:f32=3;
/// the size of a held shape holding a single thing
const lumpR:f32=0.013;
/// how much larger a held shape grows as the knot fills
const lumpGrow:f32=0.01;
/// how brightly the nerves glow
const glow:f32=0.2;
/// how brightly a held shape glows as it travels
const lumpGlow:f32=0.8;
/// how far behind a held shape its trail reaches (a share of the path)
const trailLen:f32=0.12;
/// how brightly a trail glows, and how wide it is at its head (metres)
const trailGlow:f32=2.2;
/// (how wide)
const trailWidth:f32=0.03;
/// how strongly what it holds lights the knot from within, the fuller the
/// brighter, and how far that light reaches
const innerLight:f32=1.2;
/// (how far)
const innerReach:f32=0.4;
/// what a ganglion remembers between ticks: whose turn it is, its nerves
/// and the pulses running along them
pub const State=struct{
  /// the side it hands on to next (round them in turn)
  turn:u8=0,
  /// seconds since its last hand-off
  t:f32=0,
  /// how far its nerve toward each side has grown (0..1), by world direction
  reach:m.Vice(f32,4)=@splat(0),
  /// a pulse running out along each nerve (0 just sent .. 1 arrived, or
  /// none) and the item it carries
  pulse:[4]?f32=@splat(null),
  /// the item each nerve's last pulse carried, for its colour
  sent:[4]items.Item=@splat(.essence),
};
/// the neighbour on side `d` it may feed, or null: none there, or a carrier
/// facing into it (it never hands back up a line)
fn feeds(ctx:st.Ctx,self:*const st.Structure,d:m.Dir)?st.Id{
  // the step toward that side, the neighbour there, and that neighbour
  const v=m.dirVec(d);
  const j=ctx.ss.at(ctx.w,self.x+v.x,self.y+v.z) orelse return null;
  const t=ctx.ss.get(j);
  if(t.def().carrier and t.dir==d+%2)return null;
  return j;
}
/// grows each nerve toward a neighbour it may feed (withering the rest),
/// runs the pulses along them, and every `pass` seconds hands one thing on
/// to the next side round that takes it. Returns true while it holds anything.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the ganglion itself, and its remembered state
  const self=ctx.ss.get(i);
  const gs=&self.state.ganglion;
  for(m.dirs)|d|{
    // this side's nerve reach
    const r=&gs.reach[d];
    r.*=st.reaching(r.*,feeds(ctx,self,d)!=null,dt*nerveGrow,dt*nerveWither);
    if(gs.pulse[d])|*p|{
      p.*+=dt*pulseRate;
      if(p.*>=1)gs.pulse[d]=null;
    }
  }
  if(self.inv.total()==0)return false;
  gs.t+=dt;
  if(gs.t<pass)return true;
  // round the sides in turn, each offered what it holds
  for(0..4)|k|{
    // the side offered now, starting from whose turn it is
    const d:m.Dir=@intCast((gs.turn+k)%4);
    if(gs.reach[d]<1)continue;
    // the neighbour fed on that side, and that neighbour
    const j=feeds(ctx,self,d) orelse continue;
    const t=ctx.ss.get(j);
    for(self.inv.slot)|slot|{
      // what this slot holds, offered whole to the neighbour
      const it=(slot orelse continue).item;
      if(!ctx.ss.handIn(ctx.g,j,it,(d+%2)-%t.dir))continue;
      _=self.inv.take(it,1);
      gs.pulse[d]=0;
      gs.sent[d]=it;
      gs.turn=@intCast((@as(usize,d)+1)%4);
      gs.t=0;
      return true;
    }
  }
  // nobody took anything: try again next tick
  return true;
}
/// it wants anything, while its knot has room (up to `holdMost` in all).
pub fn wants(s:*const st.Structure,_:*const prog.Progression,_:items.Item)u32{return holdMost-|s.inv.total();}
/// its nerves out to the neighbours it feeds, branching as a neuron's, a
/// pulse of what it hands on running out along each; and what it holds
/// travelling round the path inside its knot, glowing, each trailing
/// light, the knot lit from within by them.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its remembered state, and its kind (how it sways)
  const gs=&s.state.ganglion;
  const d=s.def();
  for(gs.reach,0..)|r,side|{
    if(r<=0)continue;
    // how far the pulse has run (-1: none), and the colour it carries
    const carry=gs.pulse[side]orelse-1;
    const col=color.Rgba8.of(gs.sent[side].info().col).toF4();
    try out.emit(.ganglionNerve,m.chain(&.{m.translate(ctr),m.rotY(m.dirYaw(@intCast(side)))}),.{
      .glow=glow,.phase=s.seed,.grown=r*s.grown,.carry=carry,.carryCol=.{col[0],col[1],col[2]},
      .sway=d.sway,.tall=d.tall,
    });
  }
  if(s.grown<1)return;
  // how many stacks it holds, and which of them is being drawn
  const n=s.inv.used();
  if(n==0)return;
  var k:usize=0;
  // its frame in the world, and the light of what it holds summed
  const base=s.place(ctr);
  var lit=m.splat3(0);
  for(s.inv.slot)|slot|{
    // the stack in this slot
    const it=slot orelse continue;
    // its colour, how far round the path it has travelled, and where that is
    const col=color.Rgba8.of(it.item.info().col).toF4();
    const u=m.ratio(k,n)+tf*mesh.travel+s.seed;
    const at=mesh.route(u);
    // its size: larger the fuller the stack
    const r=lumpR+lumpGrow*m.ratio(it.n,holdMost);
    try out.emit(.ganglionHeld,m.mul(base,m.chain(&.{m.translate(at),m.scale3(m.splat3(r))})),.{
      .glow=lumpGlow,.phase=s.seed,.tint=col,.sway=d.sway,.tall=d.tall,.drop=at[1],
    });
    // its trail: from as far back along the path as it reaches, up to it
    var ctrl:[4]m.V3=undefined;
    for(&ctrl,0..)|*c,j|c.*=m.mulPoint(base,mesh.route(u-trailLen*(1-m.ratio(j,3))));
    try out.emitCurve(.ganglionTrail,ctrl,m.v3(1,0,0),1,1,.{.glow=trailGlow,.flutter=trailWidth,.carryCol=.{col[0],col[1],col[2]}});
    lit+=v3(col[0],col[1],col[2]);
    k+=1;
  }
  // the knot lit from within, in the colours it holds, the fuller the brighter
  try out.light(m.mulPoint(base,mesh.brainAt),lit/m.splat3(m.f(n))*m.splat3(innerLight*(0.5+0.5*m.ratio(s.inv.total(),holdMost))),innerReach);
}
/// its line in the panel: how many neighbours it shares with, and how full
/// it is (dim while it feeds nobody).
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // how many nerves have reached a neighbour
  var n:u32=0;
  for(s.state.ganglion.reach)|r|{if(r>=1)n+=1;}
  // the line's colour: dim when it feeds nobody
  const col=if(n==0)style.dim else style.white;
  _=try d.print(x,y,style.textBody,col,txt.s.describe.shares,.{n,s.inv.total(),holdMost});
}
/// its bulb: a pale knot on a short stalk out of the seed, nerves reaching
/// out either side with beads running along them (it shares things out).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  for([_]f32{-1,1})|sx|{
    // this side's nerve curve
    const nerve=[4]iconKit.P{.{0.05*sx,0.55},.{0.35*sx,0.62},.{0.6*sx,0.5},.{0.78*sx,0.2}};
    try ic.stem(nerve,0.06,iconNerve);
    // how far along the nerve its bead has run (0..1), the sides half a run apart
    const k=@mod(ic.t*0.8+ic.phase+(if(sx<0)@as(f32,0.5)else 0),1);
    try ic.bud(iconKit.curve(nerve,k),0.07,iconBead,@sin(k*m.pi));
  }
  try ic.stem(.{.{0,iconKit.topAt},.{0.04,0.25},.{-0.03,0.4},.{0,0.5}},0.1,iconSkin);
  try ic.glow(.{0,0.62},0.26,iconSacGlow);
  try ic.bud(.{0,0.62},0.2,iconSac,0.3);
  for(0..5)|k|{
    // this knob's angle round the knot
    const a=m.ratio(k,5)*m.tau;
    try ic.bud(.{@cos(a)*0.2,0.6+@sin(a)*0.16},0.075,iconSkin,0.1);
  }
  try ic.coat(col);
}
/// the pale lilac of its knot and stalk in its bulb
const iconSkin:Color=.{190,182,205,255};
/// the violet of the nerves in its bulb
const iconNerve:Color=.{175,160,210,255};
/// the translucent blue of the bladder in its bulb
const iconSac:Color=.{120,160,220,200};
/// the soft blue glow behind that bladder
const iconSacGlow:Color=.{120,160,220,70};
/// the gold of the beads running along the nerves
const iconBead:Color=.{255,215,120,255};
// ---- tests ----
test"a ganglion splits a conduit line, never back into it"{
  // the allocator, the world and its ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=6,.depth=5});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  // cache > conduit > ganglion at (2,2); conduits lead away north, east
  // and south into a cache each
  try testing.expect(try ss.place(gpa,&w,0,2,.sapCache,0,0));
  try testing.expect(try ss.place(gpa,&w,1,2,.conduit,0,0));
  try testing.expect(try ss.place(gpa,&w,2,2,.ganglion,0,0));
  try testing.expect(try ss.place(gpa,&w,3,2,.conduit,0,0));
  try testing.expect(try ss.place(gpa,&w,4,2,.sapCache,0,0));
  try testing.expect(try ss.place(gpa,&w,2,1,.conduit,3,0));
  try testing.expect(try ss.place(gpa,&w,2,0,.sapCache,0,0));
  try testing.expect(try ss.place(gpa,&w,2,3,.conduit,1,0));
  try testing.expect(try ss.place(gpa,&w,2,4,.sapCache,0,0));
  _=ss.insert(&g,ss.at(&w,0,2).?,.fibre,30);
  try bench.run(&ss,&w,&plants,&g,40);
  for([_]m.Vice(i32,2){.{4,2},.{2,0},.{2,4}})|o|{
    // how much fibre reached this cache
    const n=ss.get(ss.at(&w,o[0],o[1]).?).inv.count(.fibre);
    try testing.expect(n>=8 and n<=12);
  }
  try testing.expectEqual(@as(u32,0),ss.get(ss.at(&w,0,2).?).inv.count(.fibre));
}
test"a ganglion feeds each neighbour only what it wants"{
  // the allocator, the world and its ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=6,.depth=5});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  // a ganglion between two loomferns (they want essence, nothing else)
  w.chunkOfTile(0,0).?.kind[2*ck.sizeTiles+1]=.moss;
  w.chunkOfTile(0,0).?.kind[2*ck.sizeTiles+3]=.moss;
  try testing.expect(try ss.place(gpa,&w,2,2,.ganglion,0,0));
  try testing.expect(try ss.place(gpa,&w,1,2,.loomfern,0,0));
  try testing.expect(try ss.place(gpa,&w,3,2,.loomfern,0,0));
  // the ganglion
  const id=ss.at(&w,2,2).?;
  try testing.expectEqual(@as(u16,4),ss.insert(&g,id,.essence,4));
  try testing.expectEqual(@as(u16,4),ss.insert(&g,id,.grit,4));
  try testing.expectEqual(@as(u16,0),ss.insert(&g,id,.grit,1));
  try bench.run(&ss,&w,&plants,&g,6);
  // the essence shared out between them, the grit kept
  try testing.expectEqual(@as(u32,0),ss.get(id).inv.count(.essence));
  try testing.expectEqual(@as(u32,4),ss.get(id).inv.count(.grit));
  try testing.expect(ss.get(ss.at(&w,1,2).?).inv.count(.essence)>=1);
  try testing.expect(ss.get(ss.at(&w,3,2).?).inv.count(.essence)>=1);
}
