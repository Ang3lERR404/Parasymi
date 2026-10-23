//! mesh: WOLF DELTOID. origin at the shoulder joint, the arm hanging along
//! -Y, its front toward +Z. A shoulder of distinct forms rather than a
//! ball: a squared cap over the joint, overlapping the torso, with a front
//! and a rear head draping down over the upper arm and gathering into a
//! tendon that sinks into it a third of the way down; a vine strap runs
//! down the groove between the heads.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");
const upper = @import("wolf_upper_arm.zig");

const V3 = m.V3;
const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const r = upper.ARM_R * 1.4;
  // the cap
  try kit.form(b, .{.center = v3(0, 0.0, 0), .radii = v3(r * 0.95, r * 0.75, r * 0.95), .ns = 0.75, .ew = 0.65, .col = pal.wolf_core});
  // front and rear heads, leaning in toward the insertion below
  for ([_]f32{-1, 1}) |face| {
    const s = b.mark();
    try kit.form(b, .{.center = v3(0, 0, 0), .radii = v3(r * 0.62, r * 1.15, r * 0.5), .ns = 0.8, .ew = 0.7, .col = pal.wolf_core, .rings = 10, .segs = 12});
    b.xform(s, m.chain(&.{m.translate(v3(0, -r * 0.55, face * r * 0.42)), m.rotX(face * 0.3)}));
  }
  // the tendon gathering the heads into the arm
  try kit.form(b, .{.center = v3(0, -r * 1.45, 0), .radii = v3(r * 0.45, r * 0.6, r * 0.5), .ns = 0.9, .ew = 0.85, .col = pal.wolf_core, .rings = 8, .segs = 10});
  // a strap of vine down the outer face, between the heads
  for ([_]f32{-1, 1}) |side| {
    var path:[8]V3 = undefined;
    var ts:[8]f32 = undefined;
    var rs:[8]f32 = undefined;
    for (&path, &ts, &rs, 0..) |*p, *t, *q, i| {
      const k = m.ratio(i, 7);
      const y = m.lerp(r * 0.55, -r * 1.7, k);
      const w = m.lerp(r * 0.97, r * 0.48, m.smooth(k));
      p.* = v3(side * w, y, 0);
      t.* = 0.3;
      q.* = r * 0.13 * (1 - 0.4 * k);
    }
    try b.tubeR(&path, &ts, &rs, pal.wolf_vine, .stem, 5);
  }
}
