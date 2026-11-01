//! WOLF PECTORAL: one lobe of solidified sap on the chest, laid over it
//! around its centre (`centre`, in the chest bone's frame) and grown out of
//! the hide (wolf_kit.resinLobe): its base follows the chest wherever it
//! curves, and its rim melts into it with no edge. A broad dish: wider
//! along its top edge, the lower edge sweeping in toward the sternum, a
//! shallow bowl in cross-section (flat-topped, falling steeply, easing
//! into the hide). The areola (a raised disc) and the nipple (a dome on
//! it) sit in the lower-inner quadrant as part of the same smooth height
//! field, so the surface stays one watertight sheet.
//!
//! Every vertex is part `.resin` with tu.y its height through the lobe (0 at
//! the base on the chest, 1 at the crown): the shader thins the resin toward
//! the surface and the rig's spring moves the crown while the base holds.
//! Each is weighted as the hide under it is, so it moves with the chest
//! and breathes with it. Built once per side (`left` /
//! `right`), mirrored, not flipped by an instance, so normals and facing
//! stay true.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error every building call may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// the mesh builder the lobe is laid into
const mg=lib.meshgen;
/// the garden's shared colours (the sap the resin is)
const pal=lib.palette;
/// the wolf's bones and their bind pose
const skel=lib.skeleton;
/// the wolf's kit, whose `resinLobe` raises the lobe off the hide
const kit=lib.wolfKit;
/// the wolf's body, whose sculpted hide the lobe is cast onto
const body=lib.wolfBody;
/// a point or direction in 3D
const V3=m.V3;
/// makes a `V3` from three numbers
const v3=m.v3;
/// each lobe's centre on the chest (x for the right one), in the chest
/// bone's frame; the two meet at the sternum
pub const centre=v3(0.078,0.09,0.088);
/// half-widths of the outline: top edge (wider) and bottom edge
const wTop:f32=0.116;
/// the bottom edge's half-width
const wBot:f32=0.096;
/// half-heights above and below the centre (the top edge is flatter)
const hTop:f32=0.082;
/// the half-height below the centre
const hBot:f32=0.096;
/// how far the lower edge sweeps toward the sternum (-x on the right lobe)
const sweep:f32=0.024;
/// crown height of the dish above the chest
const depth:f32=0.078;
/// the lower half carries a little more mass
const lowFull:f32=0.15;
/// the outer share of the radius over which it eases into the hide
const foot:f32=0.3;
/// where the areola and nipple sit (x, y from the crown: below it and only
/// just inside it, so the two sit well apart across the chest)
const nippleAt=m.Vice(f32,2){0.005,-0.034};
/// the areola's radius and how far its disc rises
const areolaR:f32=0.027;
const areolaRise:f32=0.0035;
/// the nipple's radius and how high its dome rises
const nippleR:f32=0.01;
const nippleRise:f32=0.0075;
/// how far the lobe rolls, its lower edge turned toward the sternum
/// (radians)
const rollAngle:f32=0.18;
/// how far its face tilts down (radians)
const tiltDown:f32=0.2;
/// how far it yaws out to follow the chest's curve (radians)
const yawOut:f32=0.22;
/// polar grid: rings from the crown out to the rim, and steps around it
/// (fine enough that the nipple spans several vertices)
pub const rings=44;
/// the steps round it
pub const stepCount=96;
/// outline point at angle `a` (x right, y up), unit radius
fn outline(a:f32)m.Vice(f32,2){
  // the angle's cosine and sine: across and up
  const c=@cos(a);
  const s=@sin(a);
  // how far toward the top edge this angle is, 0 bottom .. 1 top
  const up=m.smooth(m.clamp01(s*0.5+0.5));
  // the half-width here, wider toward the top
  const w=m.lerp(wBot,wTop,up);
  // the half-height: above the centre or below it
  const h=if(s>0)hTop else hBot;
  // a superellipse, squarer than an ellipse, so the top edge reads broad
  return.{m.signedPow(c,0.8)*w-sweep*@max(-s,0),m.signedPow(s,0.85)*h};
}
/// the bump of a raised disc (smooth shoulder) of radius `r` at distance `d`
fn disc(d:f32,r:f32)f32{return 1-m.smooth(m.clamp01((d-r*0.7)/(r*0.3)));}
/// the lobe's shape for the kit (wolf_kit.resinLobe): its outline and how
/// high it rises off the hide at radial fraction `k` (0 crown .. 1 rim),
/// angle `a`, point `x`, `y` across it
const Shape=struct{
  /// its crown's height: the dish's full depth
  pub const crown=depth;
  /// the outline point at angle `a`, unit radius
  pub fn outline(a:f32)m.Vice(f32,2){return pec.outline(a);}
  /// how high it stands off the hide at `k` (0 crown .. 1 rim), angle `a` and point
  /// `x`, `y`: the dish, with the areola's disc and the nipple's dome added on
  pub fn height(k:f32,a:f32,x:f32,y:f32)f32{
    // dish profile: flat-topped crown falling steeply, then easing into
    // the hide with no edge at all, so it grows out of the chest
    var z=depth*m.pow(f32,@max(1-m.pow(f32,k,2.4),0),0.55)*(1+lowFull*@max(-@sin(a),0)*k);
    z*=m.smooth(m.clamp01((1-k)/foot));
    // how far this point is from the nipple, across, up and in all
    const dx=x-nippleAt[0];
    const dy=y-nippleAt[1];
    const d=@sqrt(dx*dx+dy*dy);
    z+=areolaRise*disc(d,areolaR);
    // how far inside the nipple's dome this point lies, 1 at its middle
    const n=m.clamp01(1-(d*d)/(nippleR*nippleR));
    z+=nippleRise*@sqrt(n);
    return z;
  }
};
/// this file, so the shape can reach its outline
const pec=@This();
/// the hide it grows over: the chest and the waist below it (its upper
/// edge tucks under the shoulders and the neck rather than climbing them)
const underAt=[_]skel.Bone{.chest,.waist};
/// lays one lobe on the side `side` (1 right, -1 left, mirrored): casts it
/// onto the hide sculpted from its bones in the bind pose and raises it as resin
pub fn lobe(b:*mg.Builder,side:f32)Allocator.Error!void{
  // the bones' bind-pose transforms
  const w=skel.bind();
  // the hide under the lobe, sculpted from only the bones it grows over
  var s=try body.sculptedOf(b.gpa,&w,&underAt);
  defer s.deinit();
  // on the chest; the left lobe is the right one mirrored
  // where the lobe is placed on the body: its centre, mirrored per side and turned to sit
  const at=m.chain(&.{
    w[@intFromEnum(skel.Bone.chest)],m.translate(centre*v3(side,1,1)),
    m.scale3(v3(side,1,1)),
    m.rotY(yawOut),m.rotX(tiltDown),m.rotZ(rollAngle),
  });
  try kit.resinLobe(b,&s,at,Shape,rings,stepCount,pal.sap,0.6);
}
/// mesh: WOLF PECTORAL, LEFT. the left lobe, the right one mirrored
pub const left=struct{pub fn build(b:*mg.Builder)Allocator.Error!void{try lobe(b,-1);}};
/// mesh: WOLF PECTORAL, RIGHT. the right lobe
pub const right=struct{pub fn build(b:*mg.Builder)Allocator.Error!void{try lobe(b,1);}};
