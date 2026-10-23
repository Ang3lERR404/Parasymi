//! mesh: WOLF JOINT. unit radius, the hinge across X (limbs leave it along
//! -Y). Not a ball: a squared knuckle block with a condyle swelling at
//! either end of the hinge and a groove between them, a tendon strap of
//! vine running over its front and back from the limb above to the one
//! below. Hides the seam where two limbs meet.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");

const V3 = m.V3;
const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  // the block: flat front, back and sides, rounded edges
  try kit.form(b, .{.center = v3(0, 0, 0), .radii = v3(0.82, 0.9, 0.8), .ns = 0.65, .ew = 0.55, .col = pal.wolf_core});
  // condyles: the hinge's two ends swelling out past the block
  for ([_]f32{-1, 1}) |side| {
    try kit.form(b, .{.center = v3(side * 0.42, -0.08, 0), .radii = v3(0.52, 0.72, 0.84), .ns = 0.85, .ew = 0.8, .col = pal.wolf_core});
  }
  // tendon straps over the front and back, in the groove between condyles
  for ([_]f32{-1, 1}) |face| {
    var path:[9]V3 = undefined;
    var ts:[9]f32 = undefined;
    var rs:[9]f32 = undefined;
    for (&path, &ts, &rs, 0..) |*p, *t, *r, i| {
      const k = m.ratio(i, 8);
      const y = m.lerp(1.05, -1.1, k);
      // hugging the block, standing proud most over the hinge
      p.* = v3(0, y, face * (0.78 + 0.12 * @cos(y * 1.4)));
      t.* = 0.5;
      r.* = 0.16 * (1 - 0.25 * @abs(y));
    }
    try b.tubeR(&path, &ts, &rs, pal.wolf_vine, .stem, 6);
  }
}
