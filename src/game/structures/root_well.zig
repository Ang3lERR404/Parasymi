//! ROOT WELL: a breed the first rain opens, of both lineages: a woven
//! basket on a rooted foot, its rim of leaves catching the rain, that
//! stores what falls on it above the ground. While it rains it fills;
//! when the ground round it dries past soaked, it pours what it holds back
//! out round its foot (a spring into the moisture field's ground water),
//! keeping the ground there soaked through the dry spells between showers,
//! for the mire lilies and the moss creepers that need it.
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
/// the ecology: how wet ground must be to count as soaked
const ecology=lib.ecology;
/// the scene's list of moving parts it draws itself into
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// the tools its bulb's icon is drawn with
const iconKit=lib.icon;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the well's mesh: where its water lies
const mesh=lib.rootWellMesh;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.rootWellWater};
/// what a root well is: one tile across, of the convergent lineage, grown
/// in eight seconds, swaying a little, standing under a tile tall
pub const def:st.Def=.{.item=.rootWell,.lineage=.convergent,.size=1,.mesh=.rootWell,.grow=8,.sway=0.35,.tall=0.95,.sap=0.3};
/// the most it holds (the moisture field's water: a unit is a tile soaked through)
pub const holds:f32=60;
/// how much it catches a second in a downpour (less in lighter rain)
const catchRate:f32=2;
/// how much it pours a second while the ground round it is dry
const pourRate:f32=0.8;
/// how far round its foot it pours (units)
const pourReach:f32=2;
/// what a root well remembers: the rain it holds, and whether it is pouring
pub const State=struct{
  /// the rain it holds (0 .. `holds`)
  held:f32=0,
  /// whether it is pouring it out round its foot
  pouring:bool=false,
};
/// the rain it holds after `dt` s with `rain` falling on it (0..1 of a
/// downpour) and the ground round it `wet` (0..1): filling while it rains,
/// pouring while the ground is drier than soaked. Returns what it holds and
/// whether it pours.
pub fn step(held:f32,rain:f32,wet:f32,dt:f32)struct{f32,bool}{
  // what it holds once the rain is caught
  var h=@min(held+catchRate*rain*dt,holds);
  const pours=h>0 and wet<ecology.soakedAt;
  if(pours)h=@max(h-pourRate*dt,0);
  return.{h,pours};
}
/// it catches the rain falling on it and pours it out where the ground
/// round it has dried. Busy while it does either.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the well, and the ground under it
  const self=ctx.ss.get(i);
  const c=ctx.w.chunkOfTile(self.x,self.y) orelse return false;
  const t=ck.localIndex(self.x,self.y);
  const held,const pours=step(self.state.rootWell.held,c.rain[t],c.wet[t],dt);
  self.state.rootWell.held=held;
  self.state.rootWell.pouring=pours;
  return pours or c.rain[t]>0.05;
}
/// pouring, it pours what it holds onto the ground round its foot
pub fn breath(s:*const st.Structure)?st.Breath{
  if(!s.state.rootWell.pouring)return null;
  return.{.reach=pourReach,.low=0,.high=0,.water=pourRate};
}
/// the surface of the water it holds, risen in its basket as high as it is full
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,_:f32)Allocator.Error!void{
  // how full it is
  const full=s.state.rootWell.held/holds;
  if(s.grown<1 or full<=0)return;
  // where its surface lies, and how wide
  const at,const r=mesh.surface(full);
  try out.emit(.rootWellWater,m.mul(s.place(ctr),m.chain(&.{m.translate(at),m.scale3(m.v3(r,1,r))})),.{.phase=s.seed,.fade=def.sap});
}
/// its line in the panel: how full it is, and whether it is filling or pouring
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // what it is doing now
  const doing=if(s.state.rootWell.pouring)txt.s.describe.pouring else txt.s.describe.holding;
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.rootWell,.{s.state.rootWell.held/holds*100,doing});
}
/// its bulb: a woven basket on a short stem, leaves round its rim, a drop
/// of rain falling into it and the water in it rising and falling
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // the basket's middle, and how full it shows now
  const bowl:iconKit.P=.{0,0.5};
  const full=0.5+0.4*@sin(ic.t*0.7+ic.phase*3);
  try ic.stem(.{.{0,iconKit.topAt},.{0.03,0.24},.{-0.02,0.34},.{bowl[0],bowl[1]-0.12}},0.06,iconKit.stemCol);
  try ic.bud(.{bowl[0],bowl[1]-0.06+0.05*full},0.12*(0.6+0.4*full),iconWater,0.6);
  for(staves)|a|try ic.leaf(.{bowl[0],bowl[1]-0.12},m.halfPi+a,0.22,0.035,iconStave,1);
  for(rimLeaves)|a|try ic.leaf(.{bowl[0]+0.16*@sin(a),bowl[1]+0.08},m.halfPi+a*1.6,0.12,0.05,iconLeaf,1);
  // a drop of rain falling into it
  const k=@mod(ic.t*0.8+ic.phase,1);
  try ic.bud(.{0.02,m.lerp(0.95,bowl[1]+0.05,k)},0.025,iconWater,@sin(k*m.pi));
  try ic.coat(col);
}
/// its staves' lean in the icon (radians off upright)
const staves=[_]f32{-0.5,-0.2,0.2,0.5};
/// its rim leaves' place round the rim in the icon
const rimLeaves=[_]f32{-0.9,0.9};
/// the icon's woven staves: pale lilac
const iconStave:Color=.{200,180,230,255};
/// the icon's rim leaves: green
const iconLeaf:Color=.{110,170,80,255};
/// the icon's water: pale blue
const iconWater:Color=.{150,200,255,230};
test"a root well fills while it rains and pours only once the ground round it dries"{
  // a downpour on soaked ground: it fills and holds
  var h,var pours=step(0,1,1,10);
  try testing.expect(h>0 and !pours);
  // the rain gone, the ground still soaked: it keeps what it holds
  const kept=h;
  h,pours=step(h,0,1,10);
  try testing.expectEqual(kept,h);
  // the ground dried: it pours, emptying, until it is empty
  h,pours=step(h,0,0,10);
  try testing.expect(pours and h<kept);
  for(0..100)|_|h,pours=step(h,0,0,10);
  try testing.expect(h==0 and !pours);
  // never past what it holds
  h,_=step(0,1,1,1e4);
  try testing.expectEqual(holds,h);
}
