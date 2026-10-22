//! mesh: WOLF THIGH. hip at origin, knee at +Y LEN: the leg's power. A dense
//! braid tapering from 1.3x the leg radius at the hip to 1x at the knee,
//! with a few grown vines wrapped across it like muscle bands.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const V3 = m.V3;
const v3 = m.v3;

pub const LEN:f32 = 0.18;
/// the leg's reference radius (the knee); thigh 1.3x..1x, calf 1x..0.7x
pub const LEG_R:f32 = 0.07;

const N = 14;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var spine:[N]V3 = undefined;
  var ts:[N]f32 = undefined;
  var radii:[N]f32 = undefined;
  for (0..N) |i| {
    const k = m.ratio(i, N - 1);
    spine[i] = v3(0, k * LEN, 0);
    ts[i] = k;
    radii[i] = LEG_R * m.lerp(1.3, 1, k);
  }
  try mg.braid(b, &spine, &ts, &radii, 5, 2.2, pal.STRAND_WOBBLE, 0x7A16, pal.wolf_core, pal.wolf_vine);
  try wraps(b, &radii, LEN, 3, 1.6, 0x7A17);
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
      rr.* = 0.013;
    }
    try b.tubeR(&path, &ts, &rs, pal.wolf_vine, .stem, 5);
  }
}
