//! mesh: WOLF THIGH. hip at origin, knee at +Y LEN (mesh -Z faces front):
//! the leg's power. A squared core tapering from 1.3x the leg radius at the
//! hip to 1x at the knee, a quadriceps form on the front and a hamstring on
//! the back, and grown vines wrapped across it like muscle bands.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");

const V3 = m.V3;
const v3 = m.v3;

pub const LEN:f32 = 0.22;
/// the leg's reference radius (the knee); thigh 1.3x..1x, calf 1x..0.7x
pub const LEG_R:f32 = 0.07;
const N = 14;

fn radius(k:f32) f32 { return LEG_R * m.lerp(1.2, 0.92, k); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try kit.limbCore(b, LEN, radius, pal.wolf_core);
  try kit.muscle(b, v3(0, 0.55 * LEN, -0.03), v3(0.062, 0.1, 0.05), -0.06, pal.wolf_core);
  try kit.muscle(b, v3(0, 0.45 * LEN, 0.03), v3(0.058, 0.095, 0.048), 0.06, pal.wolf_core);
  var radii:[N]f32 = undefined;
  for (&radii, 0..) |*r, i| r.* = radius(m.ratio(i, N - 1)) * 1.12;
  try wraps(b, &radii, LEN, 2, 1.6, 0x7A17);
}

/// `n` grown vines winding diagonally over a segment `len` long whose radius
/// along it is `radii`.
pub fn wraps(b:*mg.Builder, radii:[]const f32, len:f32, n:u32, turn:f32, seed:u64) Allocator.Error!void {
  for (0..n) |w| {
    const a0 = m.ratio(w, n) * m.tau + 0.5;
    var ctrl:[6]V3 = undefined;
    for (&ctrl, 0..) |*c, j| {
      const k = m.ratio(j, ctrl.len - 1);
      const r = radii[@min(@as(usize, @intFromFloat(k * m.f(radii.len - 1))), radii.len - 1)];
      const a = a0 + k * turn;
      c.* = v3(@cos(a) * r, k * len * 0.92 + len * 0.04, @sin(a) * r);
    }
    mg.grow(&ctrl, .{
      .start = ctrl[0], .direction = m.norm(ctrl[ctrl.len - 1] - ctrl[0]), .length = len,
      .wobble = 0.04, .curl = 0, .seed = seed +% w,
    });
    var path:[16]V3 = undefined;
    m.splineResample(&ctrl, &path);
    var ts:[16]f32 = undefined;
    var rs:[16]f32 = undefined;
    for (&ts, &rs, 0..) |*t, *rr, i| {
      t.* = m.ratio(i, 15);
      // tapering to a point at both ends
      rr.* = @max(0.011 * @sqrt(@sin(m.pi * t.*)), 0.0006);
    }
    try b.tubeR(&path, &ts, &rs, pal.wolf_vine, .stem, 5);
  }
}
