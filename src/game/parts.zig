//! per-frame collector of rigid part instances, grouped by library mesh.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../core/math.zig");
const meshlib = @import("../gfx/meshlib.zig");
const Builder = @import("../gfx/meshgen.zig").Builder;
const PartInstance = @import("../gfx/vertex.zig").PartInstance;

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
};

pub const Parts = struct {
  gpa:Allocator,
  lists:[meshlib.count]std.ArrayList(PartInstance) = @splat(.empty),
  pub fn init(gpa:Allocator) Parts { return .{.gpa = gpa}; }
  pub fn deinit(p:*Parts) void {
    for (&p.lists) |*l| l.deinit(p.gpa);
  }
  pub fn clear(p:*Parts) void {
    for (&p.lists) |*l| l.clearRetainingCapacity();
  }

  pub fn emit(p:*Parts, id:meshlib.Id, mat:m.M4, look:Look) Allocator.Error!void {
    try p.lists[@intFromEnum(id)].append(p.gpa, instance(mat, look));
  }

  /// a mesh built straight up +Y over 0..1, bent on the GPU along the
  /// Catmull-Rom curve through `ctrl`, its x laid toward `side`; `len` is
  /// the length the mesh was built at.
  pub fn emitCurve(p:*Parts, id:meshlib.Id, ctrl:[4]m.V3, side:m.V3, len:f32, look:Look) Allocator.Error!void {
    var inst = instance(m.identity, look);
    inst.c0 = .{ctrl[0][0], ctrl[0][1], ctrl[0][2], 1};
    inst.c1 = .{ctrl[1][0], ctrl[1][1], ctrl[1][2], 1};
    inst.c2 = .{ctrl[2][0], ctrl[2][1], ctrl[2][2], 1};
    inst.c3 = .{ctrl[3][0], ctrl[3][1], ctrl[3][2], 1};
    inst.tint = .{side[0], side[1], side[2], 0};
    inst.e = .{1, 0, 0, len};
    try p.lists[@intFromEnum(id)].append(p.gpa, inst);
  }

  /// a star mote at `at`: part.vert turns it, twinkles it and hovers it;
  /// `echo` 0 the mote, 1.. its trail above it while falling, -1 resting.
  pub fn emitMote(p:*Parts, at:m.V3, phase:f32, life:f32, echo:f32, glow:f32) Allocator.Error!void {
    var inst = instance(m.translate(at), .{.glow = glow, .phase = phase});
    inst.e = .{2, phase, life, echo};
    try p.lists[@intFromEnum(meshlib.Id.mote)].append(p.gpa, inst);
  }


  pub fn slices(p:*const Parts) [meshlib.count][]const PartInstance {
    var out:[meshlib.count][]const PartInstance = undefined;
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
  };
}
