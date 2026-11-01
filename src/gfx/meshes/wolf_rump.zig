//! WOLF REAR: one lobe per side of solidified sap, like the pectorals: a
//! full resin dome laid over the hips' base and grown out of the hide
//! (wolf_kit.resinLobe), so its base follows the body's curve and its rim
//! melts into it with no edge; rounder and heavier toward its bottom, its
//! inner edge drawn straighter where the two press together at the cleft.
//! One watertight sheet, every vertex part `.resin` with tu.y its height
//! through the lobe (0 on the body, 1 at its crown), so it thins toward
//! its surface and the rig's spring moves the crown while the base holds.
//!
//! Built per side around `centre` (the pelvis bone's frame), each vertex
//! weighted as the hide under it is: the pelvis, and toward its lower edge
//! the thigh beneath it.
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
/// each lobe's centre on the hips (x for the right one), in the pelvis
/// bone's frame; it faces back, a little down and out
pub const centre=v3(0.083,0.01,-0.094);
/// how far it faces down (radians)
const faceDown:f32=0.28;
/// how far it faces out from the cleft (radians)
const faceOut:f32=0.25;
/// half-width at its outer edge
const wOut:f32=0.102;
/// half-width at its inner edge, at the cleft
const wIn:f32=0.088;
/// half-height above the centre
const hTop:f32=0.1;
/// half-height below the centre (it hangs heavier)
const hBot:f32=0.112;
/// how far its crown stands off the body
const depth:f32=0.098;
/// the lower half carries more mass
const lowFull:f32=0.22;
/// the outer share of the radius over which it eases into the hide
const foot:f32=0.3;
/// its polar grid: rings from the crown out to the rim
pub const rings=36;
/// the steps round it
pub const stepCount=72;
/// outline at angle `a` (x outward, y up), unit radius
fn outline(a:f32)m.Vice(f32,2){
  // the angle's cosine and sine: across and up
  const c=@cos(a);
  const s=@sin(a);
  // round, the inner side only a little fuller where it presses against
  // the other lobe (the lobe is turned to face back, so its +x lies
  // toward the cleft)
  // the half-width (outer or inner edge) and how square that side is
  const w=if(c<0)wOut else wIn;
  const e:f32=if(c<0)1 else 0.8;
  return.{m.signedPow(c,e)*w,s*(if(s>0)hTop else hBot)};
}
/// the lobe's shape for the kit (wolf_kit.resinLobe): a full dome, heavier
/// below, easing into the hide at its rim with no edge
const Shape=struct{
  /// its crown's height: the dish's full depth
  pub const crown=depth;
  /// the outline point at angle `a`, unit radius
  pub fn outline(a:f32)m.Vice(f32,2){return rump.outline(a);}
  /// how high it stands off the hide at `k` (0 crown .. 1 rim) and angle `a`:
  /// a round dome, fuller below, easing to nothing at the rim
  pub fn height(k:f32,a:f32,_:f32,_:f32)f32{
    // how much fuller it stands here: more below its centre, toward the rim
    const full=1+lowFull*@max(-@sin(a),0)*k;
    // a round dome (a sphere's profile), easing into the hide at its rim
    return depth*@sqrt(@max(1-k*k,0))*full*m.smooth(m.clamp01((1-k)/foot));
  }
};
/// this file, so the shape can reach its outline
const rump=@This();
/// the hide it grows over: the hips and the thighs below them (not the
/// tail rising between the two lobes)
const underAt=[_]skel.Bone{.pelvis,.waist,.thighL,.thighR};
/// lays one lobe on the side `side` (1 right, -1 left, mirrored): casts it
/// onto the hide sculpted from its bones in the bind pose and raises it as resin
pub fn lobe(b:*mg.Builder,side:f32)Allocator.Error!void{
  // the bones' bind-pose transforms
  const w=skel.bind();
  // the hide under the lobe, sculpted from only the bones it grows over
  var s=try body.sculptedOf(b.gpa,&w,&underAt);
  defer s.deinit();
  // facing back (+z of the lobe toward -z of the body); the left lobe is
  // the right one mirrored
  // where the lobe is placed on the body: its centre, mirrored per side and turned to sit
  const at=m.chain(&.{
    w[@intFromEnum(skel.Bone.pelvis)],m.translate(centre*v3(side,1,1)),
    m.scale3(v3(side,1,1)),
    m.rotY(m.pi-faceOut),m.rotX(faceDown),
  });
  try kit.resinLobe(b,&s,at,Shape,rings,stepCount,pal.sap,0.3);
}
/// mesh: WOLF REAR, LEFT. the left lobe, the right one mirrored
pub const left=struct{pub fn build(b:*mg.Builder)Allocator.Error!void{try lobe(b,-1);}};
/// mesh: WOLF REAR, RIGHT. the right lobe
pub const right=struct{pub fn build(b:*mg.Builder)Allocator.Error!void{try lobe(b,1);}};
/// a quad's facing in a lobe's patch (`first` its first vertex): the
/// cross of its diagonals
fn facing(b:*const mg.Builder,first:usize)V3{
  // a vertex's position as a `V3`
  const p=struct{
    /// reads vertex `i`'s position out of the builder
    fn f(bb:*const mg.Builder,i:usize)V3{return v3(bb.v.items[i].pos[0],bb.v.items[i].pos[1],bb.v.items[i].pos[2]);}
  }.f;
  return m.cross(p(b,first+2)-p(b,first),p(b,first+5)-p(b,first+1));
}
test"a resin lobe never folds over itself"{
  // the pectorals, checked alongside the rear
  const pec=lib.wolfPec;
  inline for(.{.{lobe,rings,stepCount},.{pec.lobe,pec.rings,pec.stepCount}})|l|{
    for([_]f32{-1,1})|side|{
      // a builder to lay this side's lobe into, freed after
      var b:mg.Builder=.{.gpa=std.testing.allocator};
      defer b.deinit();
      try l[0](&b,side);
      // the raised face, then the base under it, quad for quad (the base's
      // columns run the other way): each face quad faces away from its base
      // the steps round the lobe, and how many vertices one sheet (face or base) holds
      const steps=l[2];
      const half=l[1]*steps*6;
      try std.testing.expectEqual(2*half,b.v.items.len);
      for(0..l[1])|ri|for(0..steps)|ci|{
        // this face quad's facing, and the facing of the base quad under it
        const f=facing(&b,(ri*steps+ci)*6);
        const u=facing(&b,half+(ri*steps+(steps-1-ci))*6);
        if(m.len(f)<1e-12 or m.len(u)<1e-12)continue;
        try std.testing.expect(m.dot(f,u)<0);
      };
    }
  }
}
