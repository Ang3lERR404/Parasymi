//! POLYP: woven of both lineages, it feeds on the light of grown celestial
//! blooms within `feedReach` tiles, and on it grows flowers of both
//! lineages with no stem, letting them drift off its crown as a polyp
//! lets its jellyfish go: they drift round it, never far and never
//! fading, up to `most` at once, until the wolf pulls one from the air (a
//! click, `pull`). The halo no longer needs it: four blooms in a cross
//! form the diamond on their own (`halo.seek`).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the drawing calls may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, matrices, easing
const m=lib.engine.core.math;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// what can be held: its drifting flowers
const items=lib.items;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the scene's list of moving parts its flowers are drawn into
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the halo's helpers: whether a grown bloom stands at a tile
const halo=lib.haloStructure;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.driftFlower};
/// what a polyp is: grown from its bulb, one tile across, swaying gently,
/// standing a tile tall, rich in sap
pub const def:st.Def=.{.item=.polyp,.lineage=.convergent,.size=1,.mesh=.polyp,.sway=0.4,.tall=1,.grow=6,.sap=0.6};
/// how far (tiles, either way) it reaches for blooms to feed on
pub const feedReach:i32=4;
/// seconds of one bloom's light it takes to grow a flower
const feedTime:f32=20;
// decision: with every bloom gone after the unforming, a polyp feeds on
// what light is left on its own, a flower taking this long
/// seconds a flower takes to grow once the unforming has passed (no blooms left)
const lateFeedTime:f32=90;
/// the most flowers it lets drift at once (the exact fives of both lineages)
pub const most:u32=5;
/// seconds a new flower takes to rise out of its crown to where it drifts
const rise:f32=3;
/// where its crown is, over its foot (where flowers rise from)
const crownAt=m.v3(0,0.78,0);
/// how far out round it its flowers drift, and how high
const driftR:f32=0.55;
/// (their height over its foot, give or take `bob`)
const driftH:f32=0.95;
/// how far a drifting flower bobs up and down
const bob:f32=0.12;
/// radians a second its flowers drift round it
const driftTurn:f32=0.12;
/// what a polyp remembers: how far along the next flower is, and how long
/// since the last rose
pub const State=struct{
  /// how far grown the next flower is (0..1)
  feed:f32=0,
  /// seconds since the last flower rose off it
  since:f32=rise,
};
/// how many grown, unwithered blooms within `feedReach` it feeds on
fn blooms(ctx:st.Ctx,x:i32,y:i32)u32{
  // the count so far
  var n:u32=0;
  var dy:i32=-feedReach;
  while(dy<=feedReach):(dy+=1){
    var dx:i32=-feedReach;
    while(dx<=feedReach):(dx+=1){
      if(halo.active(ctx.plants,ctx.w,.{x+dx,y+dy}))n+=1;
    }
  }
  return n;
}
/// feeds on every grown bloom near enough, growing a flower once it has had
/// `feedTime` seconds of one bloom's light, and lets it rise off its crown,
/// until `most` drift round it. Returns whether it is feeding.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the polyp itself, and its remembered state
  const self=ctx.ss.get(i);
  const p=&self.state.polyp;
  p.since+=dt;
  if(self.inv.count(.driftFlower)>=most)return false;
  if(ctx.g.done.contains(.unforming)){
    // the unforming passed: it grows them on its own, slowly
    p.feed+=dt/lateFeedTime;
  }else{
    // how many blooms it feeds on
    const n=blooms(ctx,self.x,self.y);
    if(n==0)return false;
    p.feed+=dt*m.f(n)/feedTime;
  }
  if(p.feed>=1 and self.inv.add(.driftFlower,1)==1){
    p.feed=0;
    p.since=0;
    ctx.g.discover(.driftFlower);
  }
  return true;
}
/// a click pulls one drifting flower from the air
pub fn handOver(s:*st.Structure)?items.Item{
  return if(s.inv.take(.driftFlower,1)).driftFlower else null;
}
/// its flowers drifting round it, the newest rising out of its crown
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // how many drift, and how far the newest has risen
  const n=s.inv.count(.driftFlower);
  const risen=m.smooth(m.clamp01(s.state.polyp.since/rise));
  for(0..n)|k|{
    // its own phase, the bearing it drifts at, and where that is
    const ph=m.ratio(k,most)+s.seed;
    const a=tf*driftTurn+ph*m.tau;
    const at=ctr+m.v3(@cos(a)*driftR*(1+0.15*@sin(tf*0.3+ph*9)),driftH+bob*@sin(tf*0.7+ph*11),@sin(a)*driftR*(1+0.15*@sin(tf*0.3+ph*9)));
    // the newest rises from the crown and opens as it comes
    const newest=k+1==n;
    const k1=if(newest)risen else 1;
    const p=ctr+crownAt+(at-ctr-crownAt)*m.splat3(k1);
    try out.emit(.driftFlower,m.chain(&.{m.translate(p),m.rotY(tf*0.2+ph*m.tau),m.rotX(0.25*@sin(tf*0.5+ph*7)),m.scale3(m.splat3(m.lerp(0.3,1,k1)))}),.{.phase=ph,.glow=0.3});
  }
}
/// its line in the panel: what it feeds on and how many flowers drift
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // how many drift
  const n=s.inv.count(.driftFlower);
  if(s.activity<0.05 and n<most)_=try d.print(x,y,style.textBody,style.dim,txt.s.describe.polypHungry,.{feedReach})
  else _=try d.print(x,y,style.textBody,style.gold,txt.s.describe.polypFeeds,.{n,most});
}
test"a polyp feeds on a grown bloom near it, letting flowers drift up to five, and one is pulled from the air"{
  // the test harness and its allocator
  const testing=std.testing;
  const gpa=testing.allocator;
  // chunk layout, the world, the plants
  const ck=lib.ck;
  const World=lib.world.World;
  const Plants=lib.plants.Plants;
  // the world, streamed in round the origin
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // the chunk at the origin, laid flat with bare soil
  const c=w.chunkOfTile(0,0).?;
  for(0..16)|yy|for(0..16)|xx|{const t=yy*ck.sizeTiles+xx;c.kind[t]=.soil;c.height[t]=1;c.res[t]=0;};
  // the plants, structures and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,7,7,.polyp,0,0));
  // the polyp, grown
  const id=ss.at(&w,7,7).?;
  ss.get(id).grown=1;
  // the tick context
  const ctx:st.Ctx=.{.gpa=gpa,.w=&w,.plants=&plants,.g=&g,.ss=&ss};
  // no bloom: it starves
  for(0..600)|_|try st.Structures.tickWith(ctx,lib.play.tickTime);
  try testing.expectEqual(@as(u32,0),ss.get(id).inv.count(.driftFlower));
  // a grown bloom two tiles off: it feeds, until five drift
  try testing.expect(try plants.placeEx(gpa,&w,9,7,.{.x=9,.y=7,.chunk=undefined,.tile=undefined,.sp=.bloom,.seed=0,.growth=1,.mana=10}));
  for(0..60*@as(usize,@intFromFloat(feedTime))*7)|_|try st.Structures.tickWith(ctx,lib.play.tickTime);
  try testing.expectEqual(most,ss.get(id).inv.count(.driftFlower));
  // one is pulled from the air
  try testing.expectEqual(items.Item.driftFlower,handOver(ss.get(id)).?);
  try testing.expectEqual(most-1,ss.get(id).inv.count(.driftFlower));
}
/// its bulb: a woven stem opening into a violet disc, three flowers of
/// both lineages drifting off it, bobbing.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // the disc at its top
  const disc:iconKit.P=.{0,0.55};
  try ic.stem(.{.{0,iconKit.topAt},.{0.07,0.3},.{-0.06,0.42},disc},0.1,iconKit.stemCol);
  try ic.stem(.{.{0,iconKit.topAt},.{-0.07,0.3},.{0.06,0.42},disc},0.06,iconPale);
  try ic.bud(disc,0.13,iconDisc,0.7);
  for(0..3)|i|{
    // where this flower drifts, bobbing
    const a=m.f(i)*2.1+ic.t*0.4;
    const at:iconKit.P=.{0.45*@cos(a),0.72+0.12*@sin(a)+0.04*@sin(ic.t*2+m.f(i))};
    try ic.glow(at,0.12,iconGlow);
    try ic.bud(at,0.09,iconFlower,0.5+0.5*@sin(ic.t*1.5+m.f(i)*2));
  }
  try ic.coat(col);
}
/// the pale strand woven through its stem in its bulb
const iconPale:Color=.{225,220,240,255};
/// the violet of its disc
const iconDisc:Color=.{170,120,230,255};
/// the warm rose of a drifting flower
const iconFlower:Color=.{245,150,200,255};
/// the soft glow round a drifting flower
const iconGlow:Color=.{255,200,230,70};
