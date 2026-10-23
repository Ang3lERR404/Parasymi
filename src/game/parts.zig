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
  /// how far a sac sags outward under its own weight (unit-radius units)
  sag:f32 = 0,
  /// how far a resin part's surface is pushed off its rest (mesh space);
  /// its base on the body stays put (see vertex.Part.resin)
  give:[3]f32 = .{0, 0, 0},
  /// how far it bends in the garden's wind, as the plants do (0 rigid),
  /// over what height, rooted how far below its origin
  sway:f32 = 0,
  tall:f32 = 1,
  drop:f32 = 0,
};

pub const Parts = struct {
  gpa:Allocator,
  lists:[meshlib.count]std.ArrayList(PartInstance) = @splat(.empty),
  /// geometry grown afresh every frame, already in world space (the wolf's
  /// tail follows its joints as one smooth vine), drawn with `live_look`.
  live:Builder,
  live_look:Look = .{},

  pub fn init(gpa:Allocator) Parts { return .{.gpa = gpa, .live = .{.gpa = gpa}}; }
  pub fn deinit(p:*Parts) void {
    for (&p.lists) |*l| l.deinit(p.gpa);
    p.live.deinit();
  }
  pub fn clear(p:*Parts) void {
    for (&p.lists) |*l| l.clearRetainingCapacity();
    p.live.v.clearRetainingCapacity();
  }

  pub fn emit(p:*Parts, id:meshlib.Id, mat:m.M4, look:Look) Allocator.Error!void {
    try p.lists[@intFromEnum(id)].append(p.gpa, instance(mat, look));
  }

  /// the single instance the live geometry is drawn with.
  pub fn liveInstance(p:*const Parts) PartInstance { return instance(m.identity, p.live_look); }


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
    .w = .{look.sway, look.tall, look.drop, 0},
  };
}
