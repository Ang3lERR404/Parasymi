//! mesh: SAP CACHE. a store grown like the plants: a pod of resin sap held
//! in a woven basket of vines, on a root mat with broad leaves at its foot,
//! a leafy vine curling up from its neck. What it holds hangs inside the
//! resin (emitted by the structure, `belly_lump`s tinted per item).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("structure_kit.zig");

const v3 = m.v3;

/// the resin pod's centre and radii, where stored items hang
pub const POD_AT = v3(0, 0.38, 0);
pub const POD_R = v3(0.3, 0.32, 0.3);

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try kit.rootMat(b, 6, 0.5, 0.05, 0x5AC1);
  try kit.footLeaves(b, 6, 0.2, 0.36, 0.15, 0x5AC2);
  try gourd(b, 1);
}

/// the netted pod: resin sap in a basket of vines running pole to pole,
/// twisting as they go, a short neck at its crown with a leafy vine curling
/// up out of it. `scale` times its full size, standing on the origin.
pub fn gourd(b:*mg.Builder, scale:f32) Allocator.Error!void {
  const s = b.mark();
  try kit.resinPod(b, POD_AT, POD_R, 10, 14);
  var arcs:[6][4]f32 = undefined;
  for (&arcs, 0..) |*a, i| {
    const ph = m.ratio(i, 6) * m.tau;
    a.* = .{0.12, ph, 2.95, ph + 1.1};
  }
  try mg.bands(b, POD_AT, POD_R, &arcs, 1, 0.022, 0.15, 0x5AC3, pal.vine);
  // the neck where the basket's vines gather, and a vine curling out of it
  const neck = POD_AT + v3(0, POD_R[1] * 0.95, 0);
  try mg.ellipsoid(b, .{.center = neck, .radii = v3(0.07, 0.05, 0.07), .col = pal.core, .rings = 5, .segs = 8, .t = 0.7});
  try kit.leafyVine(b, neck, neck + v3(0.12, 0.32, 0.05), 0.025, 0.35, 3, 0.7, 1, 0x5AC4);
  if (scale != 1) b.xform(s, m.scale3(m.splat3(scale)));
}
