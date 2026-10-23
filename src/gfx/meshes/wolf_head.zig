//! mesh: WOLF HEAD. neck joint at origin, muzzle along +Z. The muzzle is a
//! flat-bridged, slightly upturned wedge of tight bark-smooth vine with a
//! shorter lower jaw beneath it (the seam opens a little at the back); the
//! eyes sit on its sides at the base. The ears and the nose pad are their
//! own instances (`wolf_ear`, `paw_bean`), placed by the rig.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const V3 = m.V3;
const v3 = m.v3;
const core = pal.wolf_core;
const leaf_dark = pal.wolf_leaf_dark;
const sap = pal.sap;

/// the muzzle's length from the face, and where its tip (the nose) is
pub const MUZZLE_BASE:f32 = 0.07;
pub const MUZZLE_LEN:f32 = 0.15;
pub const nose = v3(0, 0.073, MUZZLE_BASE + MUZZLE_LEN + 0.004);

/// the muzzle's section: flat across the bridge, rounded down the sides,
/// slightly hollow underneath
fn muzzleShape(a:f32) [2]f32 {
  const c = @cos(a);
  const s = @sin(a);
  const x = m.sign(c) * m.pow(f32, @abs(c), 0.8);
  const y = if (s >= 0) 0.7 * m.pow(f32, s, 0.35) else -m.pow(f32, -s, 0.9) + 0.22 * m.pow(f32, 1 - c * c, 4) * -s;
  return .{x, y};
}

fn jawShape(a:f32) [2]f32 { return .{@cos(a), @sin(a)}; }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var rng = pal.rngFor("wolf_head");
  try mg.ellipsoid(b, .{.center = v3(0, 0.08, 0.0), .radii = v3(0.1, 0.095, 0.11), .col = core, .t = 1});

  // muzzle: from inside the face out to the nose, its bridge lifting slightly
  const N = 10;
  var spine:[N]V3 = undefined;
  var ts:[N]f32 = undefined;
  var ws:[N]f32 = undefined;
  var hs:[N]f32 = undefined;
  for (0..N) |i| {
    const k = m.ratio(i, N - 1);
    spine[i] = v3(0, 0.062 + 0.011 * k * k, 0.035 + (MUZZLE_BASE - 0.035 + MUZZLE_LEN) * k);
    // a smooth hide: t barely changes, so the strand sheen stays faint
    ts[i] = 0.45 + 0.1 * k;
    ws[i] = m.lerp(0.054, 0.028, k);
    hs[i] = m.lerp(0.05, 0.026, k);
  }
  const hide = color.mix(core, pal.wolf_vine, 0.35);
  try mg.loft(b, &spine, &ts, &ws, &hs, v3(0, 1, 0), muzzleShape, hide, .stem, 16);

  // lower jaw: shorter, under the muzzle, its seam opening toward the back
  const J = 8;
  var jspine:[J]V3 = undefined;
  var jts:[J]f32 = undefined;
  var jws:[J]f32 = undefined;
  var jhs:[J]f32 = undefined;
  for (0..J) |i| {
    const k = m.ratio(i, J - 1);
    const z = 0.045 + (MUZZLE_BASE - 0.045 + MUZZLE_LEN * 0.8) * k;
    const above = m.lerp(0.062, 0.062 + 0.011 * 0.64, k) - m.lerp(0.05, 0.03, k) * 0.78;
    jhs[i] = m.lerp(0.022, 0.012, k);
    jws[i] = m.lerp(0.042, 0.022, k);
    const gap = 0.006 * (1 - k);
    jspine[i] = v3(0, above - jhs[i] - gap, z);
    jts[i] = 0.45;
  }
  try mg.loft(b, &jspine, &jts, &jws, &jhs, v3(0, 1, 0), jawShape, color.shade(color.rgb(0.2, 0.18, 0.12), 1), .stem, 12);

  // eyes on the sides of the muzzle's base, looking forward and out
  for ([_]f32{-1, 1}) |side| {
    try mg.ellipsoid(b, .{.center = v3(side * 0.058, 0.098, 0.093), .radii = v3(0.014, 0.014, 0.019), .col = sap, .part = .bloom, .rings = 5, .segs = 7, .t = 1});
  }
  // mane: living tendrils sweeping back off the skull
  for (0..6) |i| {
    const a = (m.f(i) - 2.5) * 0.35;
    try mg.vine(b, .{
      .start = v3(0, 0.15, -0.05), .direction = m.norm(v3(@sin(a) * 0.6, 0.3, -1)), .length = 0.14 * rng.range(0.8, 1.2),
      .curl = 0.3, .wobble = 0.1, .taper = 0.1, .seed = 0x3A9E +% i,
    }, 5, 12, 0.014, leaf_dark, .tendril, 4, 0.8, 1);
  }
}
