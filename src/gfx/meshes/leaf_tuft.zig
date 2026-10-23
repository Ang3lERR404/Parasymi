//! mesh: LEAF TUFT. a whorl of leaves lying out from a point on the body
//! like a tuft of fur (origin at the body, +Y out of it): each emerges flush,
//! lifts off and curls back toward the body at its tip, the inner ones
//! shorter and more upright.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");

const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var rng = pal.rngFor("leaf_tuft");
  for (0..9) |i| {
    const inner = i >= 6;
    const a = if (inner) (m.f(i - 6) + 0.5) / 3 * m.tau else m.f(i) / 6 * m.tau + rng.range(-0.15, 0.15);
    const along = v3(@cos(a), 0, @sin(a));
    try kit.leaf(b, .{
      .base = along * m.splat3(0.01), .along = along, .out = v3(0, 1, 0),
      .len = (if (inner) @as(f32, 0.07) else 0.11) * rng.range(0.85, 1.1), .width = if (inner) 0.022 else 0.03,
      .lift = if (inner) 0.9 else 0.5, .curl = 0.45, .cup = 0.3,
      .col = pal.wolf_leaf_dark, .tip = pal.wolf_leaf_lite,
    });
  }
}
