//! what every constellate part put down shares (act 2): a petal, leaf, bud
//! or stem the star hyena builds of fragments is a structure of its own,
//! a web holding its shape that floats over its tile, bobbing and turned
//! its own way, until a combo takes it in (a petal drifting to a core, its
//! own file says how). Not a kind: the parts' kinds draw through it.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the drawing calls may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, turns
const m=lib.engine.core.math;
/// the structures registry: `Structure`
const st=lib.structures;
/// the library meshes a part is drawn with
const meshlib=lib.meshlib;
/// the scene's list of moving parts it draws itself into
const Parts=lib.parts.Parts;
/// the HUD's shared sizes and colours
const style=lib.style;
/// every player-facing string
const txt=lib.txt;
/// the UI's draw batch, which the hover text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// how far a part bobs as it floats (m)
pub const bob:f32=0.04;
/// how fast it bobs (rad/s)
pub const bobRate:f32=0.9;
/// where a part floats this frame: over its tile, bobbing its own way
pub fn floatAt(s:*const st.Structure,ctr:m.V3,tf:f32)m.V3{
  return ctr+m.v3(0,bob*@sin(tf*bobRate+s.seed*9),0);
}
/// draw part `s` (its web `mesh`) floating over its tile, turned its own way
pub fn float(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32,mesh:meshlib.Id)Allocator.Error!void{
  try out.emit(mesh,m.chain(&.{m.translate(floatAt(s,ctr,tf)),m.rotY(s.seed*m.tau)}),.{.phase=s.seed});
}
/// a part's line in the panel while nothing has taken it in
pub fn describe(d:*Draw,x:f32,y:f32)Allocator.Error!void{
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.partFloats,.{});
}
/// a part bulb's glow: deep blue, soft
pub const iconGlow:Color=.{60,110,255,80};
/// a part bulb's light: pale sea-glass blue
pub const iconLight:Color=.{150,210,255,220};
