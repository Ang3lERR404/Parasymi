//! per-frame collector of rigid part instances, grouped by library mesh.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../core/math.zig");
const meshlib = @import("../gfx/meshlib.zig");
const PartInstance = @import("../gfx/vertex.zig").PartInstance;

pub const Look = struct {
  glow:f32 = 0,
  flutter:f32 = 0,
  phase:f32 = 0,
  fade:f32 = 1,
  tint:[4]f32 = .{1, 1, 1, 0},
};

pub const Parts = struct {
  gpa:Allocator,
  lists:[meshlib.count]std.ArrayList(PartInstance) = @splat(.empty),

  pub fn deinit(p:*Parts) void { for (&p.lists) |*l| l.deinit(p.gpa); }
  pub fn clear(p:*Parts) void { for (&p.lists) |*l| l.clearRetainingCapacity(); }

  pub fn emit(p:*Parts, id:meshlib.Id, mat:m.M4, look:Look) Allocator.Error!void {
    try p.lists[@intFromEnum(id)].append(p.gpa, .{
      .c0 = mat[0], .c1 = mat[1], .c2 = mat[2], .c3 = mat[3],
      .p = .{look.glow, look.flutter, look.phase, look.fade},
      .tint = look.tint,
    });
  }

  pub fn slices(p:*const Parts) [meshlib.count][]const PartInstance {
    var out:[meshlib.count][]const PartInstance = undefined;
    for (&out, p.lists) |*o, l| o.* = l.items;
    return out;
  }
};
