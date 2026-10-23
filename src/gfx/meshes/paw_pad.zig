//! mesh: PAW PAD. the central (metacarpal) bean under the foot: a rounded
//! triangle of three merged lobes, unit size; instances flatten it onto the
//! sole. Sap, made denser and browner by the instance.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  for ([_][2]f32{.{-0.38, -0.2}, .{0.38, -0.2}, .{0, 0.32}}) |c| {
    try mg.ellipsoid(b, .{.center = v3(c[0], 0, c[1]), .radii = v3(0.62, 1, 0.56), .col = pal.sap, .part = .bloom, .rings = 6, .segs = 9, .t = 0.5});
  }
}

/// mesh: PAW BEAN. a small rounded oval of sap, unit size: the toe pads
/// under each foot, and the wolf's nose pad.
pub const bean = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(1, 1, 1), .col = pal.sap, .part = .bloom, .rings = 6, .segs = 9, .t = 0.5});
  }
};
