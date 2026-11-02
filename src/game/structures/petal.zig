//! CONSTELLATE PETAL: a petal of light the star hyena builds of fragments
//! and puts down on its own (act 2). It floats over its tile, swaying, a
//! web holding a petal's shape, until a yielder's core short of petals
//! stands within `reach` tiles; then it drifts slowly over to it, turning
//! to face out from its rim, and merges with it, the core taking it on as
//! one of its four (game/structures/yielder.zig), and is gone from here.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the drawing calls may fail with
const Allocator=std.mem.Allocator;
/// the test harness: expectations
const testing=std.testing;
/// all the maths: vectors, easing, turns
const m=lib.engine.core.math;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// what every constellate part put down shares: its bob, its bulb's colours
const part=lib.constellatePart;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// the scene's list of moving parts it draws itself into
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the hover text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the library meshes it draws: its web, by its own `emit`
pub const meshes=.{.constellatePetal};
/// what a petal put down is: one tile, drawn by its own `emit` (it drifts
/// off its tile to the core it merges with), still
pub const def:st.Def=.{.item=.constellatePetal,.lineage=null,.size=1,.mesh=.constellatePetal,.bare=true,.still=true};
/// how far off a core may stand for it to drift over (tiles, between them)
pub const reach:i32=4;
/// how long it takes to drift over (s)
pub const drifting:f32=6;
/// where on a core a petal merges: how far out from its middle and how much
/// higher than where it floats alone (part.vert `PLEXUS_YIELD_OUT`, and
/// `PLEXUS_YIELD_MIDDLE` less a lone petal's foot)
const rim=m.v3(0.5,0.43,0);
/// what a petal put down remembers: the core it drifts to (none: it waits),
/// where that core stands, and how far over it has come
pub const State=struct{
  /// the core it drifts to
  to:?st.Ref=null,
  /// where that core stands (its middle on the ground)
  toAt:m.V3=@splat(0),
  /// how far over it has come (0 here .. 1 merged)
  k:f32=0,
};
/// how far over it has come after `dt` s more, having come `k`
pub fn drift(k:f32,dt:f32)f32{return @min(k+dt/drifting,1);}
/// waiting, it looks for a core short of petals within `reach` and drifts
/// to the first that answers; drifting, it comes over, and once over it
/// merges (gone from here at the end of the tick). Busy while it drifts.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the petal, and where it stands
  const self=ctx.ss.get(i);
  const q=&self.state.petal;
  if(q.to)|to|{
    // its core, gone: it waits again
    const j=ctx.ss.where.get(to) orelse {
      q.*=.{};
      return false;
    };
    q.k=drift(q.k,dt);
    if(q.k<1)return true;
    // over: it merges, or, the core whole by now, waits again
    if(ctx.ss.send(ctx,j,.petalSnapped)==.done)ctx.ss.get(i).fade=1 else ctx.ss.get(i).state.petal=.{};
    return false;
  }
  const here=m.Vice(i32,2){self.x,self.y};
  for(ctx.ss.list.items,0..)|*o,k|{
    if(o.kind()!=.yielder)continue;
    if(@max(@abs(o.x-here[0]),@abs(o.y-here[1]))>reach)continue;
    if(ctx.ss.send(ctx,.of(k),.petalComing)!=.done)continue;
    // drifting to it (fetched again: the reply may not move the list, but
    // the petal is named afresh all the same)
    const at=ctx.ss.get(.of(k)).at;
    ctx.ss.get(i).state.petal=.{.to=ctx.ss.get(.of(k)).ref(),.toAt=at};
    return true;
  }
  return false;
}
/// it, floating over its tile, or drifting over to its core, turning to
/// face out from its rim and fading into it as it merges
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // what it remembers, and how far over it is, eased
  const q=s.state.petal;
  const e=m.smooth(q.k);
  // where it is bound for: the core's rim, on the side it comes from
  const from=ctr;
  const away=m.v3(from[0]-q.toAt[0],0,from[2]-q.toAt[2]);
  const out1=if(m.len(away)>1e-3)m.norm(away)else m.v3(1,0,0);
  const there=m.v3(q.toAt[0]+out1[0]*rim[0],ctr[1]+rim[1],q.toAt[2]+out1[2]*rim[0]);
  const at=if(q.to==null)from else m.lerpV(from,there,e);
  // facing out from the core as it comes over
  const face=if(q.to==null)s.seed*m.tau else m.atan2(out1[0],out1[2]);
  const y=part.bob*@sin(tf*part.bobRate+s.seed*9)*(1-e);
  try out.emit(.constellatePetal,m.chain(&.{m.translate(at+m.v3(0,y,0)),m.rotY(face)}),.{.phase=s.seed,.fade=1-0.6*e*e});
}
/// its line in the panel: drifting over to a core, or waiting for one
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  _=try d.print(x,y,style.textBody,style.white,if(s.state.petal.to!=null)txt.s.describe.petalDrifting else txt.s.describe.petalWaiting,.{});
}
/// its bulb: one petal of light, glowing
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.glow(.{0,0.5},0.35,part.iconGlow);
  try ic.leaf(.{0,0.25},m.halfPi,0.5,0.18,part.iconLight,1);
  try ic.coat(col);
}
test"a petal drifts over in `drifting` seconds and no further"{
  try testing.expectApproxEqAbs(@as(f32,0.5),drift(0,drifting/2),1e-5);
  try testing.expectEqual(@as(f32,1),drift(0.9,drifting));
}
