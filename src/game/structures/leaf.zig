//! CONSTELLATE LEAF: a leaf of light (a stalk running on as a midrib, folded, pointed) the star hyena builds of fragments and puts
//! down on its own (act 2). It floats over its tile, bobbing, a web
//! holding its shape (game/structures/constellate_part.zig), until a combo
//! takes it in: a stem within reach with its lowest or highest joint free,
//! which it drifts over to and fastens at.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the drawing calls may fail with
const Allocator=std.mem.Allocator;
/// all the maths: angles
const m=lib.engine.core.math;
/// the structures registry: `Def`, `Structure`
const st=lib.structures;
/// what the gardener has understood
const prog=lib.progression;
/// what every constellate part put down shares
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
pub const meshes=.{.constellateLeaf};
/// what a leaf put down is: one tile, drawn by its own `emit`, still
pub const def:st.Def=.{.item=.constellateLeaf,.lineage=null,.size=1,.mesh=.constellateLeaf,.bare=true,.still=true};
/// what a leaf put down remembers: the stem it drifts to, if any
pub const State=struct{
  /// its drift over to a stem's joint
  drift:part.Drift=.{},
};
/// it drifts over to a stem's free lowest or highest joint and fastens there
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  return part.fasten(ctx,i,&ctx.ss.get(i).state.leaf.drift,.leaf,dt);
}
/// it, floating over its tile, or drifting over to its stem's joint
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its drift
  const d=s.state.leaf.drift;
  if(d.to==null)try part.float(s,out,ctr,tf,.constellateLeaf)else try part.driftTo(s,out,ctr,tf,.constellateLeaf,d);
}
/// its line in the panel: floating, waiting to be joined
pub fn describe(_:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  try part.describe(d,x,y);
}
/// its bulb: one leaf of light, glowing
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.glow(.{0,0.5},0.35,part.iconGlow);
  try ic.leaf(.{0,0.2},m.halfPi+0.3,0.6,0.16,part.iconLight,1);
  try ic.coat(col);
}
