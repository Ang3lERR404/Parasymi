//! per-frame collector of rigid part instances, grouped by library mesh.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the per-mesh lists grow with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, matrices, frustums
const m=lib.engine.core.math;
/// the mesh library: ids and the slot each level of detail lives in
const meshlib=lib.meshlib;
/// the plant mesh builder, for the level of detail a distance calls for
const mg=lib.meshgen;
/// the vertex and instance layouts the GPU reads
const vertex=lib.vertex;
/// one part as the GPU reads it: matrix, look, curve and placement
const PartInstance=vertex.PartInstance;
/// how part.vert places an instance (`PartInstance.e.x`; 0: by its matrix):
/// bent along a curve
const placeCurve:f32=1;
/// how part.vert places a star mote
const placeMote:f32=2;
/// how part.vert places a skinned mesh, moved by its bones
const placeSkin:f32=3;
/// part.vert's burst placement: flung out from where a yield came loose
const placeBurst:f32=4;
/// culling spheres: a mesh reaches `bound` times its scale plus
/// `boundPad` from its origin
const bound:f32=2.5;
/// what a mesh's culling sphere reaches beyond its scaled size
const boundPad:f32=0.5;
/// how far a star mote's culling sphere reaches
const moteBound:f32=0.6;
/// what may cast a shadow into view is kept too: a thing this high over
/// the ground is assumed to cast
const castAbove:f32=2;
/// how far along the key light's rays a shadow is followed, at most
const castReach:f32=24;
/// the least rise of the key light the casting reach is worked out for
const castLow:f32=0.15;
/// a skinned mesh's hidden bones go to the GPU this many to a float
const hideWord=24;
/// a curve is always drawn at least this far along
const minReach:f32=1e-3;
/// how one part looks: its glow, tint, sway, growth and what it carries
pub const Look=struct{
  /// how brightly it glows, 0..1
  glow:f32=0,
  /// how much its leaves flutter
  flutter:f32=0,
  /// its own phase, so neighbours move apart
  phase:f32=0,
  /// how opaque it is, 0..1
  fade:f32=1,
  /// rgb tint + weight (weight 0 = no tint, 1 = full tint)
  tint:m.Vice(f32,4)=.{1,1,1,0},
  /// how far a resin part's surface is pushed off its rest (mesh space);
  /// its base on the body stays put (see vertex.Part.resin)
  give:m.Vice(f32,3)=.{0,0,0},
  /// how far it bends in the garden's wind, as the plants do (0 rigid)
  /// over what height, rooted how far below its origin
  sway:f32=0,
  /// the height the wind bends it over
  tall:f32=1,
  /// how far below its origin it is rooted
  drop:f32=0,
  /// how far a grown structure has come along (0 sprout .. 1 grown): its
  /// leaves and petals unfold from the bottom up
  grown:f32=1,
  /// a forming halo it rides with (see `vertex.noHalo`)
  /// which of its ends that halo draws in (1 first, 2 last, 3 both)
  halo:m.Vice(f32,4)=vertex.noHalo,
  /// for a curve, which of its ends that halo draws in (1 first, 2 last, 3 both)
  ends:f32=0,
  /// essence carried through a conduit's core: how far along it (0..1, < 0 none)
  carry:f32=-1,
  /// the carried essence's colour (sRGB 0..1)
  carryCol:m.Vice(f32,3)=.{0,0,0},
  /// a placement preview: drawn, but casts no shadow
  ghost:bool=false,
  /// how far it is blended into its mesh's next key (0..1; a bud opening
  /// between two of its shapes)
  morph:f32=0,
  /// a skinned mesh: the bones (one bit each) whose part of it is not
  /// drawn, though it still casts its shadow (the wolf's head, seen from
  /// its eyes)
  hide:u64=0,
};
/// the scene's moving parts for one frame: instances gathered per library
/// mesh and level of detail, the bones and lights they bring, and the eye
/// they are culled for
pub const Parts=struct{
  /// the allocator the lists grow with
  gpa:Allocator,
  /// every mesh slot's instances this frame
  lists:[meshlib.slots]std.ArrayList(PartInstance)=@splat(.empty),
  /// this frame's bones for skinned meshes (see `pose`)
  bones:std.ArrayList(m.M4)=.empty,
  /// where the eye is this frame: parts are drawn at the level of detail
  /// their distance calls for
  eye:m.V3=.{0,0,0},
  /// what the eye sees (null: everything is kept)
  view:?m.Frustum=null,
  /// toward the key light (sun or moon): what stands out of view may still
  /// cast its shadow into it
  toward:m.V3=.{0,1,0},
  /// this frame's points of light (see `light`)
  lights:std.ArrayList(vertex.Light)=.empty,
  /// this frame's breaths of moisture into the air (see `breathe`), kept
  /// however far off: the air is stepped on everywhere, seen or not
  moisture:std.ArrayList(vertex.Moisture)=.empty,
  /// while set, everything emitted (and every light) is carried by it: a
  /// structure turning (R) takes all it draws along with its body
  around:?m.M4=null,
  /// an empty collector, growing with `gpa`
  pub fn init(gpa:Allocator)Parts{return.{.gpa=gpa};}
  /// frees every list
  pub fn deinit(p:*Parts)void{
    for(&p.lists)|*l|l.deinit(p.gpa);
    p.bones.deinit(p.gpa);
    p.lights.deinit(p.gpa);
    p.moisture.deinit(p.gpa);
  }
  /// empties every list for the next frame, keeping their room
  pub fn clear(p:*Parts)void{
    for(&p.lists)|*l|l.clearRetainingCapacity();
    p.bones.clearRetainingCapacity();
    p.lights.clearRetainingCapacity();
    p.moisture.clearRetainingCapacity();
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
    // the view; none set, and everything is kept
    const v=p.view orelse return true;
    // how far down the key light's rays its shadow may fall
    const reach=@min((@max(at[1],0)+r+castAbove)/@max(p.toward[1],castLow),castReach);
    return v.capsule(at,at-p.toward*m.splat3(reach),r);
  }
  /// a point of light at `at` (linear `col` times its strength) lighting
  /// what lies within `reach` of it: kept if any of that can be seen
  pub fn light(p:*Parts,where:m.V3,col:m.V3,reach:f32)Allocator.Error!void{
    // where it is, carried by the turning structure if one is set
    const at=if(p.around)|a|m.mulPoint(a,where)else where;
    if(p.view)|v|if(!v.sphere(at,reach))return;
    try p.lights.append(p.gpa,.{.pos=.{at[0],at[1],at[2],reach},.col=.{col[0],col[1],col[2],0}});
  }
  /// something breathing moisture into the air round `at` (x, z) within
  /// `reach`: `low` a second into the mist on the ground, `high` into the
  /// cloud over it (render passes/moisture.zig)
  pub fn breathe(p:*Parts,at:m.Vice(f32,2),reach:f32,low:f32,high:f32)Allocator.Error!void{
    try p.moisture.append(p.gpa,.{.at=.{at[0],at[1],reach,0},.rate=.{low,high,0,0}});
  }
  /// a spring at world (x, z) `at`: `water` a second poured onto the
  /// ground over a soft disc `reach` across (the moisture field's
  /// ground water, which pools past wet through and runs downhill)
  pub fn spring(p:*Parts,at:m.Vice(f32,2),reach:f32,water:f32)Allocator.Error!void{
    try p.moisture.append(p.gpa,.{.at=.{at[0],at[1],reach,0},.rate=.{0,0,water,0}});
  }
  /// a mesh placed by its matrix: skipped when out of view (a sphere a few
  /// times its scale), at the level of detail for its distance.
  pub fn emit(p:*Parts,id:meshlib.Id,matIn:m.M4,lookIn:Look)Allocator.Error!void{
    try p.emitReaching(id,matIn,lookIn,bound);
  }
  /// a mesh placed by its matrix that reaches `reach` times its scale from
  /// its origin (a great tree, wider and taller than `bound`): skipped only
  /// when all of that is out of view
  pub fn emitReaching(p:*Parts,id:meshlib.Id,matIn:m.M4,lookIn:Look,reach:f32)Allocator.Error!void{
    // the matrix, carried by the turning structure if one is set
    const mat=if(p.around)|a|m.mul(a,matIn)else matIn;
    // where it stands, and its largest axis scale
    const at=m.v3(mat[3][0],mat[3][1],mat[3][2]);
    const scale=@max(m.len(m.v3(mat[0][0],mat[0][1],mat[0][2])),@max(m.len(m.v3(mat[1][0],mat[1][1],mat[1][2])),m.len(m.v3(mat[2][0],mat[2][1],mat[2][2]))));
    if(!p.sees(at,reach*scale+boundPad))return;
    try p.add(id,at,instance(mat,lookIn));
  }
  /// files an instance under its mesh's slot for the level of detail its
  /// distance from the eye calls for
  fn add(p:*Parts,id:meshlib.Id,at:m.V3,inst:PartInstance)Allocator.Error!void{
    // the level of detail its distance calls for
    const lod=mg.lodAt(m.dist(at,p.eye));
    try p.lists[meshlib.slot(id,lod)].append(p.gpa,inst);
  }
  /// a mesh built straight up +Y over 0..1, bent on the GPU along the
  /// Catmull-Rom curve through `ctrl`, its x laid toward `side`; `len` is
  /// the length the mesh was built at, `reach` how far along it is drawn
  /// (0..1; what lies beyond gathers at its end).
  pub fn emitCurve(p:*Parts,id:meshlib.Id,ctrlIn:[4]m.V3,sideIn:m.V3,len:f32,reach:f32,lookIn:Look)Allocator.Error!void{
    // the control points and side, carried by the turning structure if one is set
    var ctrl=ctrlIn;
    var side=sideIn;
    if(p.around)|a|{
      for(&ctrl)|*c|c.*=m.mulPoint(a,c.*);
      side=m.mulDir(a,side);
    }
    // the instance, its matrix unused: the curve places it
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
    // where its bones start in this frame's list
    const base:u32=@intCast(p.bones.items.len);
    try p.bones.appendSlice(p.gpa,bones);
    return base;
  }
  /// a skinned mesh, moved by the bones `pose` put from `base`; `at` is
  /// about where it is (to cull it and pick its level of detail)
  pub fn emitSkinned(p:*Parts,id:meshlib.Id,base:u32,at:m.V3,lookIn:Look)Allocator.Error!void{
    if(!p.sees(at,bound+boundPad))return;
    try p.add(id,at,skinned(at,base,lookIn));
  }
  /// a mesh part.vert lays along a path all of its own: `n` points put by
  /// `pose` from `base` (each a point in its first column and how far
  /// along the path it lies, its w), `len` long; `at` within `r` bounds it
  /// all (to cull it and pick its level of detail)
  pub fn emitPath(p:*Parts,id:meshlib.Id,base:u32,n:u32,len:f32,at:m.V3,r:f32,lookIn:Look)Allocator.Error!void{
    if(!p.sees(at,r+boundPad))return;
    // the instance, its matrix unused: the path places it
    var inst=instance(m.identity,lookIn);
    inst.e=.{0,m.f(base),m.f(n),len};
    try p.add(id,at,inst);
  }
  /// a star mote at `at`: part.vert turns it, twinkles it and hovers it;
  /// `echo` 0 the mote, 1.. its trail above it while falling, -1 resting.
  pub fn emitMote(p:*Parts,at:m.V3,phase:f32,life:f32,echo:f32,glow:f32)Allocator.Error!void{
    // the mote's instance
    var inst=instance(m.translate(at),.{.glow=glow,.phase=phase});
    inst.e=.{placeMote,phase,life,echo};
    if(p.view)|v|if(!v.sphere(at,moteBound))return;
    try p.add(.mote,at,inst);
  }
  /// a burst of library mesh `id` at `at`, `reach` across, `age` through
  /// its life (0..1): part.vert flings its beads out and shrinks them away
  pub fn emitBurst(p:*Parts,id:meshlib.Id,at:m.V3,reach:f32,age:f32,lookIn:Look)Allocator.Error!void{
    // the burst's instance
    var inst=instance(m.chain(&.{m.translate(at),m.scale3(m.splat3(reach))}),lookIn);
    inst.e=.{placeBurst,age,0,0};
    if(!p.sees(at,reach*2+boundPad))return;
    try p.add(id,at,inst);
  }
  /// every slot's instances this frame, as slices for the renderer
  pub fn slices(p:*const Parts)[meshlib.slots][]const PartInstance{
    // the slices being filled
    var out:[meshlib.slots][]const PartInstance=undefined;
    for(&out,p.lists)|*o,l|o.*=l.items;
    return out;
  }
};
/// an instance of a skinned mesh, moved by this frame's bones from `base`
/// on, standing about at `at`, looking as `look` says (its `hide` the
/// bones whose part is not drawn)
pub fn skinned(at:m.V3,base:u32,look:Look)PartInstance{
  // the instance, at about where it stands
  var inst=instance(m.translate(at),look);
  // (the mask 24 bones to a float, as part.vert reads it)
  std.debug.assert(look.hide<1<<2*hideWord);
  inst.e=.{placeSkin,m.f(base),m.f(look.hide&(1<<hideWord)-1),m.f(look.hide>>hideWord)};
  return inst;
}
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
    .k=.{look.morph,0,0,0},
  };
}
