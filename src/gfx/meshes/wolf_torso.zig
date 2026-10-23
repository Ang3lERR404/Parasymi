//! mesh: WOLF TORSO. hips at origin, chest top at y=0.5, forward is +Z.
//! Three sections flowing into one another: a broad upper torso (shoulders
//! to mid-chest, a loose diagonal weave), a short narrow waist (vines
//! gathered tight and nearly vertical, like a corset) and the hips flaring
//! back out toward the rear. The sap pectorals are their own instances
//! (`wolf_pec`, sprung by the player rig); the chest vines tuck in behind.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const Mesh = @import("../vertex.zig").Mesh;

const V3 = m.V3;
const v3 = m.v3;
const core = pal.wolf_core;
const vine = pal.wolf_vine;

/// each pectoral lobe's centre (x for the right side; mirrored) and radii,
/// in torso space. The two lobes overlap at the sternum.
pub const pec_centre = v3(0.066, 0.355, 0.10);
pub const pec_radii = v3(0.07, 0.056, 0.05);

/// the three sections along the height (0 hips .. 1 neck): radius and how
/// fast the vines wind (radians per unit height) at each key
const Key = struct { k:f32, r:f32, wind:f32 };
const keys = [_]Key{
  .{.k = 0, .r = 0.1, .wind = 1.8},     // hips: flare toward the rear
  .{.k = 0.18, .r = 0.112, .wind = 1.8},
  .{.k = 0.42, .r = 0.095, .wind = 0.4}, // waist: 15% in from the hips, tight and vertical
  .{.k = 0.62, .r = 0.12, .wind = 3.2},
  .{.k = 0.8, .r = 0.135, .wind = 3.2},  // upper torso: the widest, a loose weave
  .{.k = 1, .r = 0.12, .wind = 3.2},
};

/// smooth (not piecewise-linear) blend through the keys, so the waist curves
/// in and the hips flare out without hard edges.
fn sample(k:f32, comptime field:[]const u8) f32 {
  var i:usize = 0;
  while (i + 2 < keys.len and k > keys[i + 1].k) i += 1;
  const a = keys[i];
  const b = keys[i + 1];
  return m.lerp(@field(a, field), @field(b, field), m.smooth(m.clamp01((k - a.k) / (b.k - a.k))));
}

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const N = 30;
  var spine:[N]V3 = undefined;
  var ts:[N]f32 = undefined;
  var radii:[N]f32 = undefined;
  var turn:[N]f32 = undefined;
  var a:f32 = 0;
  for (0..N) |i| {
    const k = m.ratio(i, N - 1);
    spine[i] = v3(0, k, 0);
    ts[i] = k;
    radii[i] = sample(k, "r");
    if (i > 0) a += sample(k, "wind") / (N - 1);
    turn[i] = a;
  }
  const s = b.mark();
  try mg.braidTurned(b, &spine, &ts, &radii, &turn, 7, pal.STRAND_WOBBLE, 0x7055, core, vine);
  b.xform(s, m.scale3(v3(1.25, 0.5, 0.95)));
  tuck(b.v.items[s..]);
  // collarbone vine across the shoulders, passing just behind the lobes
  try b.tube(&.{v3(-0.16, 0.43, -0.005), v3(0, 0.41, 0.035), v3(0.16, 0.43, -0.005)}, &.{0.9, 0.9, 0.9}, 0.022, 0.022, vine, .stem, 5);
}

/// pull the chest vines in and down where the pectorals sit, so the lobes
/// cover them and they show only at the lobes' edges. A smooth field of
/// position: every copy of a shared vertex moves alike, so the braid stays
/// watertight.
fn tuck(vs:[]Mesh) void {
  const reach = v3(0.1, 0.08, 0.09);
  for (vs) |*v| {
    const p = v3(v.pos[0], v.pos[1], v.pos[2]);
    var w:f32 = 0;
    for ([_]f32{-1, 1}) |side| {
      const c = pec_centre * v3(side, 1, 1);
      w = @max(w, 1 - m.smooth(m.clamp01(m.len((p - c) / reach))));
    }
    w *= m.smooth(m.clamp01(p[2] / 0.06));
    const q = v3(p[0] * (1 - 0.15 * w), p[1] - 0.03 * w, p[2] * (1 - 0.15 * w));
    v.pos = .{q[0], q[1], q[2]};
  }
}
