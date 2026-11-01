//! NEBULARBOR: the mist tree, of both lineages, the first thing to breathe
//! moisture into the garden's air. It roots in moss alone, on 3x3 ground,
//! and grows slowly, looking a real tree only after eight days. It has no
//! work of its own: it breathes, a mist falling off the curtains at its
//! rim and pooling round its foot, and a cloud gathering over its crown,
//! drifting off on the wind (the moisture field, render/passes/
//! moisture.zig, which the fog draws). The more grown and the older it
//! is, the more it breathes. What it breathes does nothing yet; it is
//! where the garden's weather will begin.
// decision: it draws on nothing for now (the ground's wetness it will
// root into is not yet kept), so it can never run anything dry
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
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// what a nebularbor is: three tiles across, of the convergent lineage,
/// growing in over eight of the garden's days (`sky.dayLen` 300 s), a tall
/// tree swaying a little
pub const def:st.Def=.{.item=.nebularbor,.lineage=.convergent,.size=3,.mesh=.nebularbor,.grow=2400,.sway=0.25,.tall=2.6,.sap=0.3};
/// how far round its centre it breathes (units): its crown and a little more
const reach:f32=2.4;
/// how much it breathes a second, fully grown and young: into the mist on
/// the ground, and into the cloud over it
const mistRate:f32=3.2;
/// (into the cloud)
const cloudRate:f32=2.4;
/// a sapling just put down breathes this share of what it will
const sapling:f32=0.08;
/// as it ages past grown, it breathes up to this much more
const ageGain:f32=0.6;
/// how many seconds past grown it takes to come most of the way to that
const agePace:f32=4800;
/// what a nebularbor remembers: how long it has stood grown
pub const State=struct{
  /// seconds it has stood fully grown
  age:f32=0,
};
/// it roots in moss alone.
pub fn ground(k:ck.Kind)bool{return k==.moss;}
/// it ages once grown. Never busy: it has no work.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  ctx.ss.get(i).state.nebularbor.age+=dt;
  return false;
}
/// how much more it breathes than it did young, `age` seconds grown (1 young)
fn aged(age:f32)f32{return 1+ageGain*(1-@exp(-age/agePace));}
/// how much of its full breath it breathes, `grown` of the way grown and
/// `age` seconds past it
pub fn share(grown:f32,age:f32)f32{return m.lerp(sapling,1,m.smooth(m.clamp01(grown)))*aged(age);}
/// it breathes into the air round it: more the more grown and the older
pub fn breath(s:*const st.Structure)?st.Breath{
  // how much of its full breath it breathes now
  const k=share(s.grown,s.state.nebularbor.age);
  return.{.reach=reach,.low=mistRate*k,.high=cloudRate*k};
}
/// its line in the panel: how much it breathes a minute, into the mist and into its cloud
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // what it breathes now
  const b=breath(s).?;
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.breathes,.{m.floorTo(u32,b.low*60),m.floorTo(u32,b.high*60)});
}
test"a nebularbor breathes more as it grows and as it ages, never stopping"{
  try testing.expect(share(0,0)>0);
  try testing.expect(share(0.5,0)>share(0,0));
  try testing.expect(share(1,0)>share(0.5,0));
  try testing.expect(share(1,agePace)>share(1,0));
  try testing.expect(share(1,agePace*10)<=1+ageGain);
}
