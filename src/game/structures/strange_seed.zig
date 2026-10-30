//! STRANGE SEED: the seed the unforming gathered out of the shattered
//! radiant light and let fall. It lies where it landed, of a lineage not
//! yet known, and never plants itself; the wolf may pick it up (its item)
//! and put it down again, nothing more, for now.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the drawing calls may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, angles
const m=lib.engine.core.math;
/// the structures registry: `Def`, `Structure`
const st=lib.structures;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// the scene's list of moving parts its light goes into
const Parts=lib.parts.Parts;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// what it is: lying on one tile, there at once, still
pub const def:st.Def=.{.item=.strangeSeed,.size=1,.mesh=.strangeSeed,.still=true};
/// the soft light it holds, pulsing slowly
pub fn emit(_:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  try out.light(ctr+m.v3(0,0.1,0),m.v3(0.85,0.8,1)*m.splat3(0.6+0.2*@sin(tf*0.8)),3);
}
/// its icon: the cut seed, faceted, glowing from inside
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.glow(.{0,0.5},0.35,iconGlow);
  try ic.gem(.{0,0.5},0.28,iconGem);
  try ic.coat(col);
}
/// the near-white of the cut seed
const iconGem:Color=.{235,235,255,255};
/// the violet glow inside it
const iconGlow:Color=.{180,150,255,90};
