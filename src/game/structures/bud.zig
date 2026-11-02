//! CONSTELLATE BUD: a closed bud of light (a teardrop wound in a golden spiral) the star hyena builds of fragments and puts
//! down on its own (act 2). It floats over its tile, bobbing, a web
//! holding its shape (game/structures/constellate_part.zig), until a combo
//! takes it in: four fastened to a stem's joints begin the heart (not yet in the game).
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
pub const meshes=.{.constellateBud};
/// what a bud put down is: one tile, drawn by its own `emit`, still
pub const def:st.Def=.{.item=.constellateBud,.lineage=null,.size=1,.mesh=.constellateBud,.bare=true,.still=true};
/// it, floating over its tile
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  try part.float(s,out,ctr,tf,.constellateBud);
}
/// its line in the panel: floating, waiting to be joined
pub fn describe(_:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  try part.describe(d,x,y);
}
/// its bulb: one closed bud of light, glowing
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.glow(.{0,0.5},0.35,part.iconGlow);
  try ic.bud(.{0,0.5},0.2,part.iconLight,0.8);
  try ic.coat(col);
}
