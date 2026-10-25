//! mesh: SAP CACHE. a store grown like the plants: a pod of resin sap held
//! in a woven basket of vines, on a root mat with broad leaves at its foot,
//! a leafy vine curling up from its neck. What it holds hangs inside the
//! resin (emitted by the structure, `belly_lump`s tinted per item).
//! It grows on a hidden stem rising through the pod (gfx/growth.zig): the
//! roots spread with it, the foot leaves unfold as it passes, the pod and
//! its basket fill and wrap upward, and the vine sprouts from the neck once
//! the stem is done.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("structure_kit.zig");
const growth = @import("../growth.zig");

const v3 = m.v3;

/// the resin pod's centre and radii, where stored items hang
pub const POD_AT = v3(0, 0.38, 0);
pub const POD_R = v3(0.3, 0.32, 0.3);

/// the neck where the basket's vines gather, at the pod's crown
const NECK = POD_AT + v3(0, POD_R[1] * 0.95, 0);
/// the stem grows this much slower than a unit a second's share, so the
/// pod fills and its basket wraps unhurried
const STEM_PACE:f32 = 1.6;
/// where along the stem the foot leaves unfold
const FOOT_AT:f32 = 0.12;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var k = growth.Skeleton.begin(b);
  // the stem: up from below the ground through the pod's heart to its neck
  const stem = k.trunk(&.{v3(0, -0.04, 0), v3(0.01, POD_AT[1], -0.01), NECK}, .{.pace = STEM_PACE});
  try kit.rootMat(b, 6, 0.5, 0.05, 0x5AC1, .{.k = &k, .id = stem});
  try kit.footLeaves(b, 6, 0.2, 0.36, 0.15, 0x5AC2, .{.k = &k, .id = stem, .u = FOOT_AT});
  try gourd(b, 1, .{.k = &k, .id = stem, .u = 1});
  k.finish(b);
}

/// the netted pod: resin sap in a basket of vines running pole to pole,
/// twisting as they go, a short neck at its crown with a leafy vine curling
/// up out of it. `scale` times its full size, standing on the origin. On a
/// stem (`on.u` at the neck), it fills and wraps up it and the vine
/// branches off at the neck.
pub fn gourd(b:*mg.Builder, scale:f32, on:?kit.On) Allocator.Error!void {
  const s = b.mark();
  try kit.resinPod(b, POD_AT, POD_R, 10, 14);
  var arcs:[6][4]f32 = undefined;
  for (&arcs, 0..) |*a, i| {
    const ph = m.ratio(i, 6) * m.tau;
    a.* = .{0.12, ph, 2.95, ph + 1.1};
  }
  try mg.bands(b, POD_AT, POD_R, &arcs, 1, 0.022, 0.15, 0x5AC3, pal.vine);
  // the neck where the basket's vines gather, and a vine curling out of it
  try mg.ellipsoid(b, .{.center = NECK, .radii = v3(0.07, 0.05, 0.07), .col = pal.core, .rings = 5, .segs = 8, .t = 0.7});
  if (on) |o| try o.k.along(b, s, o.id);
  try kit.leafyVine(b, NECK, NECK + v3(0.12, 0.32, 0.05), 0.025, 0.35, 3, 0.7, 1, 0x5AC4, on);
  if (scale != 1) b.xform(s, m.scale3(m.splat3(scale)));
}
