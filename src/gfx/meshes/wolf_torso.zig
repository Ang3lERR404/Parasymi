//! mesh: WOLF TORSO. hips at origin, chest top at y=0.5, forward is +Z.
//! The sap pectorals are their own instances (`wolf_pec`, sprung by the
//! player rig); the chest vines here tuck in behind where they sit.
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

fn torsoProfile(k:f32) f32 {
  // narrow waist at the hips, broad ribcage, tapering into the neck
  return 0.085 + 0.05 * @sin(k * m.pi * 0.85) + 0.02 * k;
}

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const s = b.mark();
  try mg.bundle(b, torsoProfile, 7, 2.4, pal.STRAND_WOBBLE, 0x7055, core, vine);
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
