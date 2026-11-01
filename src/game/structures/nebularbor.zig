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
/// how far round its centre it breathes (units): its crown and a little more
const reach:f32=2.4;
/// how much it breathes a second as a real tree drinking all it wants:
/// into the mist on the ground, and into the cloud over it
const mistRate:f32=3.2;
/// (into the cloud)
const cloudRate:f32=2.4;
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
/// what a nebularbor remembers: how much it drank, the last it drank
pub const State=struct{
  /// water a second its roots drew up, the last time they drank
  drunk:f32=0,
};
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
/// it breathes into the air round it: its trickle and what it drinks
pub fn breath(s:*const st.Structure)?st.Breath{
  // how much of a real tree's breath it breathes now
  const k=share(s.grown,s.state.nebularbor.drunk);
  return.{.reach=reach,.low=mistRate*k,.high=cloudRate*k};
}
/// itself, as far along its life as it has come
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,_:f32)Allocator.Error!void{
  try out.emit(def.mesh,s.place(ctr),.{.glow=glow,.flutter=flutter,.phase=s.seed,.fade=def.sap,.sway=def.sway,.tall=def.tall,.grown=drawn(s.grown)});
}
/// its line in the panel: how much it drinks and breathes a minute, into
/// the mist and into its cloud
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // what it breathes now
  const b=breath(s).?;
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.breathes,.{s.state.nebularbor.drunk*60,m.floorTo(u32,b.low*60),m.floorTo(u32,b.high*60)});
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
