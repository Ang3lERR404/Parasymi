//! NEBULARBOR: the mist tree, of both lineages, the first thing to breathe
//! moisture into the garden's air. It roots in moss alone, on 3x3 ground,
//! and never stops growing: quickly at first, a real tree after eight of
//! the garden's days, then ever more slowly, its old age still to come (its
//! last young leaves falling, offshoots where they were, its foot hardening;
//! gfx/meshes/nebularbor.zig lays out its whole life). It has no work of
//! its own: it breathes, a mist falling off the curtains at its rim and
//! pooling round its foot, and a cloud gathering over its crown, drifting
//! off on the wind (the moisture field, render/passes/moisture.zig, which
//! the fog draws). The further along its life, the more it breathes. What
//! it breathes does nothing yet; it is where the garden's weather will begin.
// decision: it draws on nothing for now (the ground's wetness it will
// root into is not yet kept), so it can never run anything dry
// decision: its whole life is its `grown`, over `def.grow` (80 days, far
// past any one garden's play), drawn along a curve that slows forever
// (`drawn`); it is never "grown" for working, which it has none of
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
pub const def:st.Def=.{.item=.nebularbor,.lineage=.convergent,.size=3,.mesh=.nebularbor,.grow=24000,.bare=true,.sway=0.25,.tall=2.6,.sap=0.3};
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
/// how much it breathes a second as a real tree: into the mist on the
/// ground, and into the cloud over it
const mistRate:f32=3.2;
/// (into the cloud)
const cloudRate:f32=2.4;
/// a sapling just put down breathes this share of what it will
const sapling:f32=0.08;
/// through its old age it comes to breathe up to this much more
const ageGain:f32=0.6;
/// how far along its drawn life it is, `grown` into its life: quickly at
/// first, ever more slowly, a real tree at `realAt`
pub fn drawn(grown:f32)f32{return 1-m.pow(f32,1-m.clamp01(grown),slowing);}
/// how much of a real tree's breath it breathes, `grown` into its life
pub fn share(grown:f32)f32{
  // how far along its drawn life
  const d=drawn(grown);
  return m.lerp(sapling,1,m.smooth(m.clamp01(d/realDrawn)))*(1+ageGain*m.unlerp(realDrawn,1,d));
}
/// it roots in moss alone.
pub fn ground(k:ck.Kind)bool{return k==.moss;}
/// it breathes into the air round it: more the further along its life
pub fn breath(s:*const st.Structure)?st.Breath{
  // how much of a real tree's breath it breathes now
  const k=share(s.grown);
  return.{.reach=reach,.low=mistRate*k,.high=cloudRate*k};
}
/// itself, as far along its life as it has come
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,_:f32)Allocator.Error!void{
  try out.emit(def.mesh,s.place(ctr),.{.glow=glow,.flutter=flutter,.phase=s.seed,.fade=def.sap,.sway=def.sway,.tall=def.tall,.grown=drawn(s.grown)});
}
/// its line in the panel: how much it breathes a minute, into the mist and into its cloud
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // what it breathes now
  const b=breath(s).?;
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.breathes,.{m.floorTo(u32,b.low*60),m.floorTo(u32,b.high*60)});
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
test"a nebularbor breathes more the further along its life"{
  try testing.expect(share(0)>0);
  try testing.expect(share(0.05)>share(0));
  try testing.expect(share(realAt)>share(0.05));
  try testing.expect(share(0.5)>share(realAt));
  try testing.expect(share(1)<=1+ageGain+1e-4);
}
