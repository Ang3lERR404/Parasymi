//! per-frame collector of rigid part instances, grouped by library mesh.
const lib=@import("../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const m=lib.engine.core.math;
const meshlib=lib.meshlib;
const mg=lib.meshgen;
const vertex=lib.vertex;
const PartInstance=vertex.PartInstance;
/// how part.vert places an instance (`PartInstance.e.x`): by its matrix,
/// bent along a curve, or as a star mote
const placeCurve:f32=1;
const placeMote:f32=2;
const placeSkin:f32=3;
/// culling spheres: a mesh reaches `BOUND` times its scale plus
/// `BOUND_PAD` from its origin; a mote `MOTE_BOUND`
const bound:f32=2.5;
const boundPad:f32=0.5;
const moteBound:f32=0.6;
/// what may cast a shadow into view is kept too: a thing this high over
/// the ground, at most this far along the key light's rays
const castAbove:f32=2;
const castReach:f32=24;
/// the least rise of the key light the casting reach is worked out for
const castLow:f32=0.15;
/// a skinned mesh's hidden bones go to the GPU this many to a float
const hideWord=24;
/// a curve is always drawn at least this far along
const minReach:f32=1e-3;
pub const Look=struct{
  glow:f32=0,
  flutter:f32=0,
  phase:f32=0,
  fade:f32=1,
  /// rgb tint + weight (weight 0 = no tint, 1 = full tint)
  tint:[4]f32=.{1,1,1,0},
  /// how far a resin part's surface is pushed off its rest (mesh space);
  /// its base on the body stays put (see vertex.Part.resin)
  give:[3]f32=.{0,0,0},
  /// how far it bends in the garden's wind, as the plants do (0 rigid),
  /// over what height, rooted how far below its origin
  sway:f32=0,
  tall:f32=1,
  drop:f32=0,
  /// how far a grown structure has come along (0 sprout .. 1 grown): its
  /// leaves and petals unfold from the bottom up
  grown:f32=1,
  /// a forming halo it rides with (see `vertex.NO_HALO`), and for a curve,
  /// which of its ends that halo draws in (1 first, 2 last, 3 both)
  halo:[4]f32=vertex.noHalo,
  ends:f32=0,
  /// essence carried through a conduit's core: how far along it (0..1,
  /// < 0 none) and its colour (sRGB 0..1)
  carry:f32=-1,
  carryCol:[3]f32=.{0,0,0},
  /// a placement preview: drawn, but casts no shadow
  ghost:bool=false,
  /// a skinned mesh: the bones (one bit each) whose part of it is not
  /// drawn, though it still casts its shadow (the wolf's head, seen from
  /// its eyes)
  hide:u64=0,
};
pub const Parts=struct{
  gpa:Allocator,
  lists:[meshlib.slots]std.ArrayList(PartInstance)=@splat(.empty),
  /// this frame's bones for skinned meshes (see `pose`)
  bones:std.ArrayList(m.M4)=.empty,
  /// where the eye is this frame and what it sees: parts are drawn at the
  /// level of detail their distance calls for, and not at all out of view
  eye:m.V3=.{0,0,0},
  view:?m.Frustum=null,
  /// toward the key light (sun or moon): what stands out of view may still
  /// cast its shadow into it
  toward:m.V3=.{0,1,0},
  /// this frame's points of light (see `light`)
  lights:std.ArrayList(vertex.Light)=.empty,
  /// while set, everything emitted (and every light) is carried by it: a
  /// structure turning (R) takes all it draws along with its body
  around:?m.M4=null,
  pub fn init(gpa:Allocator)Parts{return.{.gpa=gpa};}
  pub fn deinit(p:*Parts)void{
    for(&p.lists)|*l|l.deinit(p.gpa);
    p.bones.deinit(p.gpa);
    p.lights.deinit(p.gpa);
  }
  pub fn clear(p:*Parts)void{
    for(&p.lists)|*l|l.clearRetainingCapacity();
    p.bones.clearRetainingCapacity();
    p.lights.clearRetainingCapacity();
  }
  /// set this frame's eye, view and the direction toward the key light
  /// before emitting
  pub fn look(p:*Parts,eye:m.V3,view:m.Frustum,toward:m.V3)void{
    p.eye=eye;
    p.view=view;
    p.toward=toward;
  }
  /// whether a thing within `r` of `at` is worth drawing: it can be seen,
  /// or its shadow can (it reaches down the key light's rays to the ground)
  pub fn sees(p:*const Parts,at:m.V3,r:f32)bool{
    const v=p.view orelse return true;
    const reach=@min((@max(at[1],0)+r+castAbove)/@max(p.toward[1],castLow),castReach);
    return v.capsule(at,at-p.toward*m.splat3(reach),r);
  }
  /// a point of light at `at` (linear `col` times its strength) lighting
  /// what lies within `reach` of it: kept if any of that can be seen
  pub fn light(p:*Parts,where:m.V3,col:m.V3,reach:f32)Allocator.Error!void{
    const at=if(p.around)|a|m.mulPoint(a,where)else where;
    if(p.view)|v|if(!v.sphere(at,reach))return;
    try p.lights.append(p.gpa,.{.pos=.{at[0],at[1],at[2],reach},.col=.{col[0],col[1],col[2],0}});
  }
  /// a mesh placed by its matrix: skipped when out of view (a sphere a few
  /// times its scale), at the level of detail for its distance.
  pub fn emit(p:*Parts,id:meshlib.Id,matIn:m.M4,lookIn:Look)Allocator.Error!void{
    const mat=if(p.around)|a|m.mul(a,matIn)else matIn;
    const at=m.v3(mat[3][0],mat[3][1],mat[3][2]);
    const scale=@max(m.len(m.v3(mat[0][0],mat[0][1],mat[0][2])),@max(m.len(m.v3(mat[1][0],mat[1][1],mat[1][2])),m.len(m.v3(mat[2][0],mat[2][1],mat[2][2]))));
    if(!p.sees(at,bound*scale+boundPad))return;
    try p.add(id,at,instance(mat,lookIn));
  }
  fn add(p:*Parts,id:meshlib.Id,at:m.V3,inst:PartInstance)Allocator.Error!void{
    const lod=mg.lodAt(m.len(at-p.eye));
    try p.lists[meshlib.slot(id,lod)].append(p.gpa,inst);
  }
  /// a mesh built straight up +Y over 0..1, bent on the GPU along the
  /// Catmull-Rom curve through `ctrl`, its x laid toward `side`; `len` is
  /// the length the mesh was built at, `reach` how far along it is drawn
  /// (0..1; what lies beyond gathers at its end).
  pub fn emitCurve(p:*Parts,id:meshlib.Id,ctrlIn:[4]m.V3,sideIn:m.V3,len:f32,reach:f32,lookIn:Look)Allocator.Error!void{
    var ctrl=ctrlIn;
    var side=sideIn;
    if(p.around)|a|{
      for(&ctrl)|*c|c.*=m.mulPoint(a,c.*);
      side=m.mulDir(a,side);
    }
    var inst=instance(m.identity,lookIn);
    inst.c0=.{ctrl[0][0],ctrl[0][1],ctrl[0][2],1};
    inst.c1=.{ctrl[1][0],ctrl[1][1],ctrl[1][2],1};
    inst.c2=.{ctrl[2][0],ctrl[2][1],ctrl[2][2],1};
    inst.c3=.{ctrl[3][0],ctrl[3][1],ctrl[3][2],1};
    inst.tint=.{side[0],side[1],side[2],0};
    inst.e=.{placeCurve,@max(reach,minReach),lookIn.ends,len};
    // a curve has no resin to give: q.yzw carries its essence's colour
    inst.q=.{lookIn.carry,lookIn.carryCol[0],lookIn.carryCol[1],lookIn.carryCol[2]};
    try p.add(id,ctrl[0],inst);
  }
  /// a skeleton's bones this frame (each carrying a vertex from where its
  /// mesh was built to where it is now); what `emitSkinned` takes
  pub fn pose(p:*Parts,bones:[]const m.M4)Allocator.Error!u32{
    const base:u32=@intCast(p.bones.items.len);
    try p.bones.appendSlice(p.gpa,bones);
    return base;
  }
  /// a skinned mesh, moved by the bones `pose` put from `base`; `at` is
  /// about where it is (to cull it and pick its level of detail)
  pub fn emitSkinned(p:*Parts,id:meshlib.Id,base:u32,at:m.V3,lookIn:Look)Allocator.Error!void{
    if(!p.sees(at,bound+boundPad))return;
    var inst=instance(m.translate(at),lookIn);
    // (the mask 24 bones to a float, as part.vert reads it)
    std.debug.assert(lookIn.hide<1<<2*hideWord);
    inst.e=.{placeSkin,m.f(base),m.f(lookIn.hide&(1<<hideWord)-1),m.f(lookIn.hide>>hideWord)};
    try p.add(id,at,inst);
  }
  /// a star mote at `at`: part.vert turns it, twinkles it and hovers it;
  /// `echo` 0 the mote, 1.. its trail above it while falling, -1 resting.
  pub fn emitMote(p:*Parts,at:m.V3,phase:f32,life:f32,echo:f32,glow:f32)Allocator.Error!void{
    var inst=instance(m.translate(at),.{.glow=glow,.phase=phase});
    inst.e=.{placeMote,phase,life,echo};
    if(p.view)|v|if(!v.sphere(at,moteBound))return;
    try p.add(.mote,at,inst);
  }
  pub fn slices(p:*const Parts)[meshlib.slots][]const PartInstance{
    var out:[meshlib.slots][]const PartInstance=undefined;
    for(&out,p.lists)|*o,l|o.*=l.items;
    return out;
  }
};
/// an instance placed by its matrix, looking as `look` says
pub fn instance(mat:m.M4,look:Look)PartInstance{
  return.{
    .c0=mat[0],.c1=mat[1],.c2=mat[2],.c3=mat[3],
    .p=.{look.glow,look.flutter,look.phase,look.fade},
    .tint=look.tint,
    // q.x = carry, q.yzw = give
    .q=.{look.carry,look.give[0],look.give[1],look.give[2]},
    .w=.{look.sway,look.tall,look.drop,look.grown},
    // placed by the matrix: e.yzw the carried essence's colour
    .e=.{0,look.carryCol[0],look.carryCol[1],look.carryCol[2]},
    .h=look.halo,
    .flags=if(look.ghost)vertex.partGhost else 0,
  };
}
