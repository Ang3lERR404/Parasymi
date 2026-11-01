//! NEBULARBOR: the mist tree, of both lineages, the first thing to breathe
//! moisture into the garden's air. It roots in moss alone, on 3x3 ground,
//! and never stops growing: quickly at first, a real tree after eight of
//! the garden's days, then ever more slowly, its old age still to come (its
//! last young leaves falling, offshoots where they were, its foot hardening;
//! gfx/meshes/nebularbor.zig lays out its whole life). Its roots drink the
//! ground's water under it and a tile round it, and it breathes a trickle
//! of its own and what it drinks: a mist falling off the curtains at its
//! rim and pooling round its foot, and a cloud gathering over its crown,
//! drifting off on the wind (the moisture field, render/passes/
//! moisture.zig, which the fog draws). The further along its life, the
//! more it drinks, and in its old age the more mist it makes of each drop.
//! What it breathes does nothing yet; it is where the garden's weather
//! will begin.
// decision: its roots never drink a tile below `floor` of the water it
// holds, and each tile they drink comes back toward it slowly, so the
// gardener has time to set up what they build toward before any ground
// runs dry
// decision: the ground's water is not saved (as the ley is not): a garden
// loaded back finds its ground soaked again
// decision: its whole life is its `grown`, over `def.grow` (80 days, far
// past any one garden's play), drawn along a curve that slows forever
// (`drawn`); its roots drink all through it (`worksGrowing`)
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the test harness: allocator and expectations
const testing=std.testing;
/// all the maths: easing and conversions
const m=lib.engine.core.math;
/// the seeded hashes each tree's place off the grid comes from
const rng=lib.engine.core.rng;
/// chunk sizes and tile kinds
const ck=lib.ck;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the scene's list of moving parts it draws itself into
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// what a nebularbor is: three tiles across, of the convergent lineage,
/// living out its life over eighty of the garden's days (`sky.dayLen` 300
/// s), drawn by itself along its life's curve (`bare`), a tall tree
/// swaying a little
pub const def:st.Def=.{.item=.nebularbor,.lineage=.convergent,.size=3,.mesh=.nebularbor,.grow=24000,.bare=true,.worksGrowing=true,.sway=0.25,.tall=2.6,.sap=0.3};
/// how far into its life (`grown`) it is a real tree: eight days of eighty
const realAt:f32=0.1;
/// how far along its drawn life it is a real tree then (its mesh: all of
/// its growing up, before its old age)
const realDrawn:f32=0.8;
/// how its life slows: the power that brings it to `realDrawn` at `realAt`
const slowing:f32=15.28;
/// how far a resting tree glows, and how much its leaves flutter (as every
/// standing structure's)
const glow:f32=0.25;
/// (how much its leaves flutter)
const flutter:f32=0.6;
/// how far round its centre it breathes (units): its crown, over 5x5 tiles
const reach:f32=2.5;
/// how far its crown spreads from its trunk (units): over 5x5 tiles, though
/// it roots in 3x3; crowns may overlap, and anything may stand under one
pub const crown:f32=2.5;
/// how far from the middle of its ground its trunk may stand (units): every
/// tree's own, from the world's seed and where it stands, so trees never
/// line up on the grid; still within its 3x3
const nudgeMost:f32=0.6;
/// how much of a mesh's reach the culling sphere takes: its crown wide and
/// high over everything round it
const meshReach:f32=4.6;
/// how much it breathes a second as a real tree drinking all it wants:
/// into the mist on the ground, and into the cloud over it
const mistRate:f32=3.2;
/// (into the cloud)
const cloudRate:f32=0.0125;
/// the share of that it breathes whatever it drinks: its own trickle
const trickle:f32=0.08;
/// a sapling just put down drinks this share of what it will
const sapling:f32=0.08;
/// through its old age it comes to make up to this much more mist of each drop
const ageGain:f32=0.6;
/// how much water a real tree drinks a second, all its roots together
/// (tiles' worth: 1 is a tile soaked through)
const thirst:f32=0.05;
/// how far past its footprint its roots reach (tiles, each way)
const rootReach:i32=1;
/// how many tiles its roots reach: its 3x3 and the ring round it
const rootTiles=(def.size+2*rootReach)*(def.size+2*rootReach);
/// its roots never drink a tile below this share of the water it holds
pub const floor:f32=0.4;
/// how fast a tile it drinks from comes back toward its water (a share of
/// what is missing, a second)
const refill:f32=1.0/600.0;
/// a grove (trees whose crowns overlap): how much more cloud its leaves
/// breathe for each real tree whose crown wholly overlaps its own, and the
/// most that count
/// (how much more cloud for each)
const groveGain:f32=4;
/// (the most that count)
const groveMost:f32=5;
/// what a nebularbor remembers: how much it drank, the last it drank, and
/// the grove it stands in
pub const State=struct{
  /// water a second its roots drew up, the last time they drank
  drunk:f32=0,
  /// the nebularbors whose crowns overlap its own, each as much as it is a
  /// real tree (a sapling counts for little) and as far as their crowns
  /// overlap
  grove:f32=0,
  /// how far its trunk stands off the middle of its ground (world x, z;
  /// `nudgeOf`), found once it is first linked
  nudge:m.Vice(f32,2)=.{0,0},
};
/// how far a tree on tile (`x`, `y`) of a world grown from `seed` stands off
/// the middle of its ground (world x, z): a hash of the three, within
/// `nudgeMost`
pub fn nudgeOf(seed:u64,x:i32,y:i32)m.Vice(f32,2){
  // a bearing and a distance, each from its own hash
  const a=rng.unit(rng.hash2(seed,x,y))*m.tau;
  const r=nudgeMost*@sqrt(rng.unit(rng.hash2(seed^0x4E55,x,y)));
  return.{@cos(a)*r,@sin(a)*r};
}
/// how much two crowns `d` apart (units) overlap: wholly on the same spot,
/// not at all once they only touch
pub fn overlap(d:f32)f32{return m.clamp01(1-d/(2*crown));}
/// how far along its drawn life it is, `grown` into its life: quickly at
/// first, ever more slowly, a real tree at `realAt`
pub fn drawn(grown:f32)f32{return 1-m.pow(f32,1-m.clamp01(grown),slowing);}
/// how much of a real tree's thirst it has, `grown` into its life
pub fn thirsty(grown:f32)f32{return m.lerp(sapling,1,m.smooth(m.clamp01(drawn(grown)/realDrawn)));}
/// how much mist it makes of each drop, `grown` into its life: more in its old age
pub fn efficiency(grown:f32)f32{return 1+ageGain*m.unlerp(realDrawn,1,drawn(grown));}
/// how much of a real tree's breath it breathes, `grown` into its life,
/// drinking `drunk` water a second: its trickle, and what it drinks
pub fn share(grown:f32,drunk:f32)f32{return trickle+(1-trickle)*drunk/thirst*efficiency(grown);}
/// how many times its own cloud a tree breathes standing among `grove`
/// others: alone, its leaves breathe only a little cloud; in a grove they
/// breathe together, much more
pub fn groveCloud(grove:f32)f32{return 1+groveGain*@min(grove,groveMost);}
/// it roots in moss alone.
pub fn ground(k:ck.Kind)bool{return k==.moss;}
/// what its roots draw this tick (`dt` s, `want` in all) from the tiles
/// `water` (each holding at most its `cap`): an even share from each, never
/// below `floor` of its cap; every tile drunk from comes back toward its
/// cap. Returns how much was drawn.
pub fn drink(water:[]f32,cap:[]const f32,want:f32,dt:f32)f32{
  // what was drawn so far
  var got:f32=0;
  for(water,cap)|*w,c|{
    // this tile's share, as much of it as it can spare
    const take=@min(want/m.f(water.len),@max(w.*-c*floor,0));
    w.*+=(c-w.*)*refill*dt-take;
    got+=take;
  }
  return got;
}
/// it takes its place off the grid and finds the grove it stands in: every
/// other nebularbor whose crown overlaps its own, each counted as much as
/// it is a real tree and as far as their crowns overlap
pub fn link(ctx:st.Ctx,i:st.Id)void{
  // the tree, where its trunk stands, and the grove found so far
  const self=ctx.ss.get(i);
  self.state.nebularbor.nudge=nudgeOf(ctx.w.seed,self.x,self.y);
  const at=trunkAt(self);
  var grove:f32=0;
  for(ctx.ss.list.items,0..)|*t,j|{
    if(j==i.idx() or t.kind()!=.nebularbor)continue;
    grove+=thirsty(t.grown)*overlap(m.lenOf(f32,2,at-trunkAt(t)));
  }
  self.state.nebularbor.grove=grove;
}
/// where tree `s`'s trunk stands (world x, z): the middle of its ground, nudged
fn trunkAt(s:*const st.Structure)m.Vec(f32,2){
  // half its ground across, from its corner tile to its middle
  const half=m.f(def.size)/2;
  return.{m.f(s.x)+half+s.state.nebularbor.nudge[0],m.f(s.y)+half+s.state.nebularbor.nudge[1]};
}
/// its roots drink from the ground under it and a tile round it, more the
/// further along its life. Busy while it drinks.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the tree, and the water it wants this tick
  const self=ctx.ss.get(i);
  const want=thirst*thirsty(self.grown)*dt;
  // the tiles its roots reach: their water, and what each holds at most
  var water:[rootTiles]f32=undefined;
  var cap:[rootTiles]f32=undefined;
  // where each tile is kept (its chunk and index), and how many are in loaded ground
  var where:[rootTiles]struct{*ck.Chunk,usize}=undefined;
  var n:usize=0;
  var it=m.footprint(self.x-rootReach,self.y-rootReach,def.size+2*rootReach);
  while(it.next())|t|{
    const c=ctx.w.chunkOfTile(t[0],t[1]) orelse continue;
    const k=ck.localIndex(t[0],t[1]);
    water[n]=c.water[k];
    cap[n]=c.waterCap[k];
    where[n]=.{c,k};
    n+=1;
  }
  // what it drew, and the tiles' water put back
  const got=drink(water[0..n],cap[0..n],want,dt);
  for(where[0..n],water[0..n])|wh,w|wh[0].water[wh[1]]=w;
  self.state.nebularbor.drunk=if(dt>0)got/dt else 0;
  return got>0;
}
/// it breathes into the air round it: its trickle and what it drinks; its
/// leaves breathe cloud, much more in a grove
pub fn breath(s:*const st.Structure)?st.Breath{
  // how much of a real tree's breath it breathes now
  const k=share(s.grown,s.state.nebularbor.drunk);
  return.{.reach=reach,.low=mistRate*k,.high=cloudRate*k*groveCloud(s.state.nebularbor.grove),.off=s.state.nebularbor.nudge};
}
/// itself, as far along its life as it has come
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,_:f32)Allocator.Error!void{
  // where its trunk stands, nudged off the middle of its ground
  const n=s.state.nebularbor.nudge;
  try out.emitReaching(def.mesh,m.mul(m.translate(m.v3(n[0],0,n[1])),s.place(ctr)),.{.glow=glow,.flutter=flutter,.phase=s.seed,.fade=def.sap,.sway=def.sway,.tall=def.tall,.grown=drawn(s.grown)},meshReach);
}
/// its line in the panel: how much it drinks and breathes a minute, into
/// the mist and into its cloud
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // what it breathes now
  const b=breath(s).?;
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.breathes,.{s.state.nebularbor.drunk*60,m.floorTo(u32,b.low*60),m.floorTo(u32,b.high*60)});
}
test"every tree stands off its middle its own way, within its ground, the same each time"{
  // trees on a row of tiles, in one world
  var far:f32=0;
  for(0..40)|x|{
    const n=nudgeOf(0x5eed,@intCast(x),7);
    try testing.expect(m.lenOf(f32,2,n)<=nudgeMost+1e-5);
    try testing.expectEqual(n,nudgeOf(0x5eed,@intCast(x),7));
    far=@max(far,m.lenOf(f32,2,n));
  }
  try testing.expect(far>nudgeMost*0.5);
}
test"crowns overlap wholly on one spot, less apart, not at all once they only touch"{
  try testing.expectEqual(@as(f32,1),overlap(0));
  try testing.expect(overlap(3)>0 and overlap(3)<1);
  try testing.expectEqual(@as(f32,0),overlap(2*crown));
}
test"a tree alone breathes a little cloud, a grove's trees much more, up to a limit"{
  try testing.expectEqual(@as(f32,1),groveCloud(0));
  try testing.expect(groveCloud(3)>=4*groveCloud(0));
  try testing.expectEqual(groveCloud(groveMost),groveCloud(groveMost+4));
}
test"a nebularbor grows quickly, then ever more slowly, a real tree at eight days"{
  try testing.expectApproxEqAbs(realDrawn,drawn(realAt),0.01);
  try testing.expect(drawn(0)==0);
  // each eight days grows it less than the eight before, never nothing
  // (over the first half of its life: past that, what is left is too
  // small to see, or for a float to tell apart)
  var last:f32=0;
  var gained:f32=1;
  var t:f32=realAt;
  while(t<0.45):(t+=realAt){
    const now=drawn(t);
    try testing.expect(now-last<gained and now>last);
    gained=now-last;
    last=now;
  }
}
test"a nebularbor thirsts more as it grows, and makes more of each drop as it ages"{
  try testing.expect(thirsty(0)>0);
  try testing.expect(thirsty(0.05)>thirsty(0));
  try testing.expect(thirsty(realAt)>thirsty(0.05));
  try testing.expect(efficiency(0.5)>efficiency(realAt));
  try testing.expect(efficiency(1)<=1+ageGain+1e-4);
  // dry, it breathes its trickle alone; drinking, more
  try testing.expect(share(realAt,0)==trickle);
  try testing.expect(share(realAt,thirst)>share(realAt,thirst*0.5));
}
test"its roots never drink the ground below its floor, and it comes back"{
  // two tiles, one soaked, one dry, drunk from for a long while
  var water=[_]f32{0.8,0.3};
  const cap=[_]f32{0.8,0.3};
  for(0..20000)|_|_=drink(&water,&cap,1,0.1);
  for(water,cap)|w,c|try testing.expect(w>=c*floor-1e-4);
  // left alone, it comes back toward what it holds
  const low=water[0];
  for(0..3000)|_|_=drink(&water,&cap,0,0.1);
  try testing.expect(water[0]>low and water[0]<=cap[0]+1e-5);
}
