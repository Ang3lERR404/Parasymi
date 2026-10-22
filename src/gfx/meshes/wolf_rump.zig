//! the wolf's rear: one lobe per side, a knotted ball of dense vine with
//! small sap nodes at the hip joint and along its lower edge. Built per
//! side (`wolf_rump_l`, `wolf_rump_r`) rather than mirrored, so winding and
//! lighting stay correct. Origin at the lobe's centre; +X outward for the
//! right lobe, +Z forward.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const V3 = m.V3;
const v3 = m.v3;

/// each lobe's centre (right side; mirrored) and radii in the hips' frame
pub const centre = v3(0.075, 0.03, -0.07);
pub const radii = v3(0.085, 0.08, 0.072);

pub fn lobe(b:*mg.Builder, side:f32) Allocator.Error!void {
  // a slightly faceted ball: fewer rings than the soft sap reads as knotted
  try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = radii, .col = pal.wolf_core, .rings = 6, .segs = 9, .t = 0.3});
  // grown vine bundles wrapping across it, breaking up the surface
  const bands = [_][2]f32{.{0.2, 0.9}, .{1.3, 2.0}, .{2.5, 3.3}, .{-0.9, -0.2}};
  for (bands, 0..) |band, i| {
    var ctrl:[6]V3 = undefined;
    for (&ctrl, 0..) |*c, j| {
      const k = m.ratio(j, ctrl.len - 1);
      const th = 0.35 + k * 2.4;
      const ph = m.lerp(band[0], band[1], k);
      c.* = v3(@sin(th) * @cos(ph) * side, @cos(th), @sin(th) * @sin(ph)) * radii * m.splat(1.03);
    }
    mg.grow(&ctrl, .{
      .start = ctrl[0], .direction = m.norm(ctrl[ctrl.len - 1] - ctrl[0]), .length = m.len(ctrl[ctrl.len - 1] - ctrl[0]),
      .wobble = 0.05, .curl = 0, .seed = 0x2B0 +% i * 17 +% @as(u64, @intFromFloat(side + 2)),
    });
    var path:[16]V3 = undefined;
    m.splineResample(&ctrl, &path);
    var ts:[16]f32 = undefined;
    var rs:[16]f32 = undefined;
    for (&ts, &rs, 0..) |*t, *r, j| {
      t.* = m.ratio(j, 15);
      r.* = 0.016;
    }
    try b.tubeR(&path, &ts, &rs, pal.wolf_vine, .stem, 5);
  }
  // sap nodes: one where the thigh joins (the lobe's outer, lower front) and
  // a few along the lower edge; translucent through the instance's fade
  const nodes = [_]V3{
    v3(0.85, -0.25, 0.3), v3(0.45, -0.85, -0.2), v3(-0.1, -0.9, -0.45), v3(-0.55, -0.75, -0.3),
  };
  for (nodes, 0..) |n, i| {
    const r:f32 = if (i == 0) 0.024 else 0.016;
    try mg.ellipsoid(b, .{.center = n * radii * v3(side, 1, 1), .radii = m.splat(r), .col = pal.sap, .part = .bloom, .rings = 5, .segs = 7, .t = 0.3});
  }
}
