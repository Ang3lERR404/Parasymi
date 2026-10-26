//! per-frame collector of rigid part instances, grouped by library mesh.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const meshlib = @import("../gfx/meshlib.zig");
const mg = @import("../gfx/meshgen.zig");
const vertex = @import("../gfx/vertex.zig");
const PartInstance = vertex.PartInstance;

/// how part.vert places an instance (`PartInstance.e.x`): by its matrix,
/// bent along a curve, or as a star mote
const PLACE_CURVE:f32 = 1;
const PLACE_MOTE:f32 = 2;
const PLACE_SKIN:f32 = 3;
/// culling spheres: a mesh reaches `BOUND` times its scale plus
/// `BOUND_PAD` from its origin; a mote `MOTE_BOUND`
const BOUND:f32 = 2.5;
const BOUND_PAD:f32 = 0.5;
const MOTE_BOUND:f32 = 0.6;
/// what may cast a shadow into view is kept too: a thing this high over
/// the ground, at most this far along the key light's rays
const CAST_ABOVE:f32 = 2;
const CAST_REACH:f32 = 24;
/// the least rise of the key light the casting reach is worked out for
const CAST_LOW:f32 = 0.15;
/// a skinned mesh's hidden bones go to the GPU this many to a float
const HIDE_WORD = 24;
/// a curve is always drawn at least this far along
const MIN_REACH:f32 = 1e-3;

pub const Look = struct {
  glow:f32 = 0,
  flutter:f32 = 0,
  phase:f32 = 0,
  fade:f32 = 1,
  /// rgb tint + weight (weight 0 = no tint, 1 = full tint)
  tint:[4]f32 = .{1, 1, 1, 0},
  /// how far a resin part's surface is pushed off its rest (mesh space);
  /// its base on the body stays put (see vertex.Part.resin)
  give:[3]f32 = .{0, 0, 0},
  /// how far it bends in the garden's wind, as the plants do (0 rigid),
  /// over what height, rooted how far below its origin
  sway:f32 = 0,
  tall:f32 = 1,
  drop:f32 = 0,
  /// how far a grown structure has come along (0 sprout .. 1 grown): its
  /// leaves and petals unfold from the bottom up
  grown:f32 = 1,
  /// a forming halo it rides with (see `vertex.NO_HALO`), and for a curve,
  /// which of its ends that halo draws in (1 first, 2 last, 3 both)
  halo:[4]f32 = vertex.NO_HALO,
  ends:f32 = 0,
  /// essence carried through a conduit's core: how far along it (0..1,
  /// < 0 none) and its colour (sRGB 0..1)
  carry:f32 = -1,
  carry_col:[3]f32 = .{0, 0, 0},
  /// a placement preview: drawn, but casts no shadow
  ghost:bool = false,
  /// a skinned mesh: the bones (one bit each) whose part of it is not
  /// drawn, though it still casts its shadow (the wolf's head, seen from
  /// its eyes)
  hide:u64 = 0,
};

pub const Parts = struct {
  gpa:Allocator,
  lists:[meshlib.SLOTS]std.ArrayList(PartInstance) = @splat(.empty),
  /// this frame's bones for skinned meshes (see `pose`)
  bones:std.ArrayList(m.M4) = .empty,
  /// where the eye is this frame and what it sees: parts are drawn at the
  /// level of detail their distance calls for, and not at all out of view
  eye:m.V3 = .{0, 0, 0},
  view:?m.Frustum = null,
  /// toward the key light (sun or moon): what stands out of view may still
  /// cast its shadow into it
  toward:m.V3 = .{0, 1, 0},
  /// this frame's points of light (see `light`)
  lights:std.ArrayList(vertex.Light) = .empty,
  /// while set, everything emitted (and every light) is carried by it: a
  /// structure turning (R) takes all it draws along with its body
  around:?m.M4 = null,
  pub fn init(gpa:Allocator) Parts { return .{.gpa = gpa}; }
  pub fn deinit(p:*Parts) void {
    for (&p.lists) |*l| l.deinit(p.gpa);
    p.bones.deinit(p.gpa);
    p.lights.deinit(p.gpa);
  }
  pub fn clear(p:*Parts) void {
    for (&p.lists) |*l| l.clearRetainingCapacity();
    p.bones.clearRetainingCapacity();
    p.lights.clearRetainingCapacity();
  }

  /// set this frame's eye, view and the direction toward the key light
  /// before emitting
  pub fn look(p:*Parts, eye:m.V3, view:m.Frustum, toward:m.V3) void {
    p.eye = eye;
    p.view = view;
    p.toward = toward;
  }

  /// whether a thing within `r` of `at` is worth drawing: it can be seen,
  /// or its shadow can (it reaches down the key light's rays to the ground)
  pub fn sees(p:*const Parts, at:m.V3, r:f32) bool {
    const v = p.view orelse return true;
    const reach = @min((@max(at[1], 0) + r + CAST_ABOVE) / @max(p.toward[1], CAST_LOW), CAST_REACH);
    return v.capsule(at, at - p.toward * m.splat3(reach), r);
  }

  /// a point of light at `at` (linear `col` times its strength) lighting
  /// what lies within `reach` of it: kept if any of that can be seen
  pub fn light(p:*Parts, at_:m.V3, col:m.V3, reach:f32) Allocator.Error!void {
    const at = if (p.around) |a| m.mulPoint(a, at_) else at_;
    if (p.view) |v| if (!v.sphere(at, reach)) return;
    try p.lights.append(p.gpa, .{.pos = .{at[0], at[1], at[2], reach}, .col = .{col[0], col[1], col[2], 0}});
  }

  /// a mesh placed by its matrix: skipped when out of view (a sphere a few
  /// times its scale), at the level of detail for its distance.
  pub fn emit(p:*Parts, id:meshlib.Id, mat_:m.M4, look_:Look) Allocator.Error!void {
    const mat = if (p.around) |a| m.mul(a, mat_) else mat_;
    const at = m.v3(mat[3][0], mat[3][1], mat[3][2]);
    const scale = @max(m.len(m.v3(mat[0][0], mat[0][1], mat[0][2])), @max(m.len(m.v3(mat[1][0], mat[1][1], mat[1][2])), m.len(m.v3(mat[2][0], mat[2][1], mat[2][2]))));
    if (!p.sees(at, BOUND * scale + BOUND_PAD)) return;
    try p.add(id, at, instance(mat, look_));
  }

  fn add(p:*Parts, id:meshlib.Id, at:m.V3, inst:PartInstance) Allocator.Error!void {
    const lod = mg.lodAt(m.len(at - p.eye));
    try p.lists[meshlib.slot(id, lod)].append(p.gpa, inst);
  }

  /// a mesh built straight up +Y over 0..1, bent on the GPU along the
  /// Catmull-Rom curve through `ctrl`, its x laid toward `side`; `len` is
  /// the length the mesh was built at, `reach` how far along it is drawn
  /// (0..1; what lies beyond gathers at its end).
  pub fn emitCurve(p:*Parts, id:meshlib.Id, ctrl_:[4]m.V3, side_:m.V3, len:f32, reach:f32, look_:Look) Allocator.Error!void {
    var ctrl = ctrl_;
    var side = side_;
    if (p.around) |a| {
      for (&ctrl) |*c| c.* = m.mulPoint(a, c.*);
      side = m.mulDir(a, side);
    }
    var inst = instance(m.identity, look_);
    inst.c0 = .{ctrl[0][0], ctrl[0][1], ctrl[0][2], 1};
    inst.c1 = .{ctrl[1][0], ctrl[1][1], ctrl[1][2], 1};
    inst.c2 = .{ctrl[2][0], ctrl[2][1], ctrl[2][2], 1};
    inst.c3 = .{ctrl[3][0], ctrl[3][1], ctrl[3][2], 1};
    inst.tint = .{side[0], side[1], side[2], 0};
    inst.e = .{PLACE_CURVE, @max(reach, MIN_REACH), look_.ends, len};
    // a curve has no resin to give: q.yzw carries its essence's colour
    inst.q = .{look_.carry, look_.carry_col[0], look_.carry_col[1], look_.carry_col[2]};
    try p.add(id, ctrl[0], inst);
  }

  /// a skeleton's bones this frame (each carrying a vertex from where its
  /// mesh was built to where it is now); what `emitSkinned` takes
  pub fn pose(p:*Parts, bones:[]const m.M4) Allocator.Error!u32 {
    const base:u32 = @intCast(p.bones.items.len);
    try p.bones.appendSlice(p.gpa, bones);
    return base;
  }

  /// a skinned mesh, moved by the bones `pose` put from `base`; `at` is
  /// about where it is (to cull it and pick its level of detail)
  pub fn emitSkinned(p:*Parts, id:meshlib.Id, base:u32, at:m.V3, look_:Look) Allocator.Error!void {
    if (!p.sees(at, BOUND + BOUND_PAD)) return;

    var inst = instance(m.translate(at), look_);
    // (the mask 24 bones to a float, as part.vert reads it)
    std.debug.assert(look_.hide < 1 << 2 * HIDE_WORD);
    inst.e = .{PLACE_SKIN, m.f(base), m.f(look_.hide & (1 << HIDE_WORD) - 1), m.f(look_.hide >> HIDE_WORD)};
    try p.add(id, at, inst);
  }

  /// a star mote at `at`: part.vert turns it, twinkles it and hovers it;
  /// `echo` 0 the mote, 1.. its trail above it while falling, -1 resting.
  pub fn emitMote(p:*Parts, at:m.V3, phase:f32, life:f32, echo:f32, glow:f32) Allocator.Error!void {
    var inst = instance(m.translate(at), .{.glow = glow, .phase = phase});
    inst.e = .{PLACE_MOTE, phase, life, echo};
    if (p.view) |v| if (!v.sphere(at, MOTE_BOUND)) return;
    try p.add(.mote, at, inst);
  }


  pub fn slices(p:*const Parts) [meshlib.SLOTS][]const PartInstance {
    var out:[meshlib.SLOTS][]const PartInstance = undefined;
    for (&out, p.lists) |*o, l| o.* = l.items;
    return out;
  }
};

/// an instance placed by its matrix, looking as `look` says
pub fn instance(mat:m.M4, look:Look) PartInstance {
  return .{
    .c0 = mat[0], .c1 = mat[1], .c2 = mat[2], .c3 = mat[3],
    .p = .{look.glow, look.flutter, look.phase, look.fade},
    .tint = look.tint,
    // q.x = carry, q.yzw = give
    .q = .{look.carry, look.give[0], look.give[1], look.give[2]},
    .w = .{look.sway, look.tall, look.drop, look.grown},
    // placed by the matrix: e.yzw the carried essence's colour
    .e = .{0, look.carry_col[0], look.carry_col[1], look.carry_col[2]},
    .h = look.halo,
    .flags = if (look.ghost) vertex.PART_GHOST else 0,
  };
}
