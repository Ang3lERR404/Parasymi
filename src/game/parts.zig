//! per-frame collector of rigid part instances, grouped by library mesh.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../core/math.zig");
const meshlib = @import("../gfx/meshlib.zig");
const mg = @import("../gfx/meshgen.zig");
const vertex = @import("../gfx/vertex.zig");
const PartInstance = vertex.PartInstance;

/// how part.vert places an instance (`PartInstance.e.x`): by its matrix,
/// bent along a curve, or as a star mote
const PLACE_CURVE:f32 = 1;
const PLACE_MOTE:f32 = 2;
/// culling spheres: a mesh reaches `BOUND` times its scale plus
/// `BOUND_PAD` from its origin; a mote `MOTE_BOUND`
const BOUND:f32 = 2.5;
const BOUND_PAD:f32 = 0.5;
const MOTE_BOUND:f32 = 0.6;
/// a curve is always drawn at least this far along
const MIN_REACH:f32 = 1e-3;

pub const Look = struct {
  glow:f32 = 0,
  flutter:f32 = 0,
  phase:f32 = 0,
  fade:f32 = 1,
  /// rgb tint + weight (weight 0 = no tint, 1 = full tint)
  tint:[4]f32 = .{1, 1, 1, 0},
  /// how far a sac swells outward as it fills, most low and forward
  /// (mesh units, weighted by each vertex's tu.x)
  sag:f32 = 0,
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
};

pub const Parts = struct {
  gpa:Allocator,
  lists:[meshlib.SLOTS]std.ArrayList(PartInstance) = @splat(.empty),
  /// where the eye is this frame and what it sees: parts are drawn at the
  /// level of detail their distance calls for, and not at all out of view
  eye:m.V3 = .{0, 0, 0},
  view:?m.Frustum = null,
  pub fn init(gpa:Allocator) Parts { return .{.gpa = gpa}; }
  pub fn deinit(p:*Parts) void {
    for (&p.lists) |*l| l.deinit(p.gpa);
  }
  pub fn clear(p:*Parts) void {
    for (&p.lists) |*l| l.clearRetainingCapacity();
  }

  /// set this frame's eye and view before emitting
  pub fn look(p:*Parts, eye:m.V3, view:m.Frustum) void {
    p.eye = eye;
    p.view = view;
  }

  /// a mesh placed by its matrix: skipped when out of view (a sphere a few
  /// times its scale), at the level of detail for its distance.
  pub fn emit(p:*Parts, id:meshlib.Id, mat:m.M4, look_:Look) Allocator.Error!void {
    const at = m.v3(mat[3][0], mat[3][1], mat[3][2]);
    const scale = @max(m.len(m.v3(mat[0][0], mat[0][1], mat[0][2])), @max(m.len(m.v3(mat[1][0], mat[1][1], mat[1][2])), m.len(m.v3(mat[2][0], mat[2][1], mat[2][2]))));
    if (p.view) |v| if (!v.sphere(at, BOUND * scale + BOUND_PAD)) return;
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
  pub fn emitCurve(p:*Parts, id:meshlib.Id, ctrl:[4]m.V3, side:m.V3, len:f32, reach:f32, look_:Look) Allocator.Error!void {
    var inst = instance(m.identity, look_);
    inst.c0 = .{ctrl[0][0], ctrl[0][1], ctrl[0][2], 1};
    inst.c1 = .{ctrl[1][0], ctrl[1][1], ctrl[1][2], 1};
    inst.c2 = .{ctrl[2][0], ctrl[2][1], ctrl[2][2], 1};
    inst.c3 = .{ctrl[3][0], ctrl[3][1], ctrl[3][2], 1};
    inst.tint = .{side[0], side[1], side[2], 0};
    inst.e = .{PLACE_CURVE, @max(reach, MIN_REACH), look_.ends, len};
    try p.add(id, ctrl[0], inst);
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

fn instance(mat:m.M4, look:Look) PartInstance {
  return .{
    .c0 = mat[0], .c1 = mat[1], .c2 = mat[2], .c3 = mat[3],
    .p = .{look.glow, look.flutter, look.phase, look.fade},
    .tint = look.tint,
    // q.x = sag; q.yzw = give
    .q = .{look.sag, look.give[0], look.give[1], look.give[2]},
    .w = .{look.sway, look.tall, look.drop, look.grown},
    .h = look.halo,
  };
}
