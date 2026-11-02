//! mesh: WOLF SAP PANEL. a thin sheet of amber sap welling through the bark
//! down the wolf's front, as the gardener drew it: narrow under the
//! pectorals, widest over the belly, drawing to a point at the groin. Laid
//! over the chest, waist and hips around `centre` (the pelvis bone's frame)
//! and grown out of the hide (wolf_kit.resinLobe), so its base follows the
//! body wherever it curves and its rim melts into the bark with no edge.
//! The belly's sac swells over it.
//!
//! Every vertex is part `.resin` with tu.y its height through the sheet (0
//! on the body, 1 at its face), weighted as the hide under it is, so it
//! bends and breathes with the torso.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error every building call may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// the mesh builder the sheet is laid into
const mg=lib.meshgen;
/// the garden's shared colours (the sap the sheet is)
const pal=lib.palette;
/// the wolf's bones and their bind pose
const skel=lib.skeleton;
/// the wolf's kit, whose `resinLobe` raises the sheet off the hide
const kit=lib.wolfKit;
/// the wolf's body, whose sculpted hide the sheet is cast onto
const body=lib.wolfBody;
/// makes a `V3` from three numbers
const v3=m.v3;
/// the sheet's centre down the front, in the pelvis bone's frame: over the
/// waist, a little below the navel's height
pub const centre=v3(0,0.12,0.07);
/// its half-width at its broadest, over the belly
const wide:f32=0.16;
/// how far it narrows toward its top, under the pectorals (share of `wide`)
const narrowTop:f32=0.3;
/// the half-height above the centre, reaching up under the pectorals
const hTop:f32=0.22;
/// the half-height below it, down to the groin
const hBot:f32=0.2;
/// how thick the sap stands off the bark: a thin sheet, not a lobe
const depth:f32=0.0075;
/// the outer share of the radius over which it eases into the hide
const foot:f32=0.22;
/// polar grid: rings from the middle out to the rim
pub const rings=32;
/// the steps round it
pub const stepCount=72;
/// outline point at angle `a` (x right, y up), unit radius: an egg, broad
/// over the belly, narrowing upward and drawn to a point below
fn outline(a:f32)m.Vice(f32,2){
  // the angle's cosine and sine: across and up
  const c=@cos(a);
  const s=@sin(a);
  // the half-width here: narrower above, drawn in to a point below
  const w=wide*(1-(1-narrowTop)*m.smooth(@max(s,0)))*(1-0.75*m.pow(f32,@max(-s,0),1.5));
  return.{c*w,s*(if(s>0)hTop else hBot)};
}
/// the sheet's shape for the kit (wolf_kit.resinLobe): its outline and how
/// high it stands off the hide at radial fraction `k` (0 middle .. 1 rim)
const Shape=struct{
  /// the height its face is measured against (tu.y = height / crown): well
  /// over the sheet's thickness, so the shader reads it as dense sap near
  /// its base, nearly opaque amber, not a thin clear glaze
  pub const crown=depth/0.4;
  /// the outline point at angle `a`, unit radius
  pub fn outline(a:f32)m.Vice(f32,2){return panel.outline(a);}
  /// how high it stands off the hide at `k`: level across, easing into
  /// the bark at its rim with no edge
  pub fn height(k:f32,a:f32,x:f32,y:f32)f32{
    _=a;
    _=x;
    _=y;
    return depth*m.smooth(m.clamp01((1-k)/foot));
  }
};
/// this file, so the shape can reach its outline
const panel=@This();
/// the hide it grows over: the hips, the waist and the chest (never the
/// thighs, so its point at the groin keeps to the body's front)
const underAt=[_]skel.Bone{.pelvis,.waist,.chest};
/// lays the sheet: casts it onto the hide sculpted from its bones in the
/// bind pose and raises it as resin
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the bones' bind-pose transforms
  const w=skel.bind();
  // the hide under the sheet, sculpted from only the bones it grows over
  var s=try body.sculptedOf(b.gpa,&w,&underAt);
  defer s.deinit();
  // where the sheet is placed on the body: its centre on the front, facing forward
  const at=m.mul(w[@intFromEnum(skel.Bone.pelvis)],m.translate(centre));
  try kit.resinLobe(b,&s,at,Shape,rings,stepCount,pal.sap,0.4);
}
test"the sap panel is one sheet of resin down the front"{
  // a builder to lay the sheet into, freed after
  var b:mg.Builder=.{.gpa=std.testing.allocator};
  defer b.deinit();
  try build(&b);
  try std.testing.expect(b.v.items.len>0);
  // every vertex resin, and in front of the spine in the bind pose
  for(b.v.items)|vx|{
    try std.testing.expect(vx.part==@intFromEnum(lib.vertex.Part.resin));
    try std.testing.expect(vx.pos[2]>0);
  }
}
