//! mesh: WOLF TORSO. hips at origin, chest top at y=0.5, forward is +Z.
//! Three sections flowing into one another: a broad upper torso (shoulders
//! to mid-chest, a loose diagonal weave), a short narrow waist (vines
//! gathered tight and nearly vertical, like a corset) and the hips flaring
//! back out toward the rear. The sap pectorals are their own instances
//! (`wolf_pec_l`/`_r`, sprung by the player rig); the chest vines tuck in behind.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const Mesh = @import("../vertex.zig").Mesh;
const kit = @import("wolf_kit.zig");

const V3 = m.V3;
const v3 = m.v3;
const core = pal.wolf_core;
const vine = pal.wolf_vine;

/// each pectoral's centre on the chest (x for the right side; mirrored), in
/// torso space; the lobes themselves are built around it (wolf_pec.zig) and
/// meet at the sternum.
pub const pec_centre = v3(0.072, 0.36, 0.098);

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
  const shape = m.scale3(SHAPE);
  // the core, and the vines woven over it: each a grown vine tapering to a
  // point at both ends, its tips tucking into the core rather than cut off
  var r:[N]f32 = undefined;
  for (0..N) |i| r[i] = radii[i] * mg.BRAID_CORE;
  try b.tubeR(&spine, &ts, &r, core, .stem, 8);
  var fn_:[N]V3 = undefined;
  var fb:[N]V3 = undefined;
  mg.transport(&spine, &fn_, &fb);
  var paths:[STRANDS][N]V3 = undefined;
  for (0..STRANDS) |si| {
    const a0 = m.ratio(si, STRANDS) * m.tau;
    const sd:u64 = 0x7055 +% si * mg.STRAND_SALT;
    // strands start and end at different heights, so their tips are staggered
    const lo = 0.02 + 0.06 * m.f(si % 3) / 2;
    const hi = 0.98 - 0.06 * m.f((si + 1) % 3) / 2;
    for (0..N) |i| {
      const u = m.ratio(i, N - 1);
      const e = m.smooth(m.clamp01((u - lo) / 0.12)) * m.smooth(m.clamp01((hi - u) / 0.12));
      const ang = a0 + turn[i] + mg.strandTurn(sd, u, pal.STRAND_WOBBLE);
      // toward their tips the strands sink into the core
      const off = radii[i] * m.lerp(0.55, mg.BRAID_OFF, e) * mg.strandSwell(sd, u, pal.STRAND_WOBBLE);
      paths[si][i] = spine[i] + (fn_[i] * m.splat3(@cos(ang)) + fb[i] * m.splat3(@sin(ang))) * m.splat3(off);
      r[i] = @max(radii[i] * mg.BRAID_STRAND * e, 0.0008);
    }
    try b.tubeR(&paths[si], &ts, &r, vine, .stem, 5);
  }
  b.xform(s, shape);
  tuck(b.v.items[s..]);
  try strandLeaves(b, &paths);
  // forms of planes under the weave, as on the limbs: trapezius sloping
  // from the neck to each shoulder, and the lats fanning down the back
  // into the waist
  for ([_]f32{-1, 1}) |side| {
    try kit.muscle(b, v3(side * 0.09, 0.45, -0.035), v3(0.085, 0.035, 0.06), 0, core);
    const lat = b.mark();
    try kit.form(b, .{.center = v3(0, 0, 0), .radii = v3(0.05, 0.11, 0.04), .ns = 0.72, .ew = 0.6, .col = core});
    b.xform(lat, m.chain(&.{m.translate(v3(side * 0.09, 0.34, -0.095)), m.rotZ(side * 0.35), m.rotX(-0.15)}));
  }
  // collarbone vine across the shoulders, passing just behind the lobes,
  // tapering to a point at each end
  const ctrl = [_]V3{v3(-0.17, 0.435, -0.02), v3(-0.08, 0.42, 0.025), v3(0, 0.41, 0.035), v3(0.08, 0.42, 0.025), v3(0.17, 0.435, -0.02)};
  var cp:[16]V3 = undefined;
  m.splineResample(&ctrl, &cp);
  var ct:[16]f32 = undefined;
  var cr:[16]f32 = undefined;
  for (&ct, &cr, 0..) |*t, *q, i| {
    const k = m.ratio(i, 15);
    t.* = 0.9;
    q.* = @max(0.022 * @sqrt(@sin(m.pi * k)), 0.0008);
  }
  try b.tubeR(&cp, &ct, &cr, vine, .stem, 5);
}

/// the torso's shape: the weave is built in a unit column, then shaped
const SHAPE = v3(1.25, 0.5, 0.95);
const STRANDS = 7;

/// small leaves along the woven vines, lying down them like fur. None on the
/// chest under the pectorals or over the belly, where the sap shows through.
fn strandLeaves(b:*mg.Builder, paths:*const [STRANDS][30]V3) Allocator.Error!void {
  for (paths, 0..) |path, si| {
    for ([_]f32{0.22, 0.5, 0.78}, 0..) |k0, j| {
      const k = k0 + 0.07 * m.f((si + j) % 3) - 0.07;
      const i = m.floorTo(usize, k * 29);
      const p = path[i] * SHAPE;
      const tan = m.norm((path[i + 1] - path[i - 1]) * SHAPE);
      const out = m.norm(v3(p[0], 0, p[2]));
      // the front, from the belly up through the pectorals, stays bare
      if (out[2] > 0.25 and p[1] < 0.43) continue;
      // lying down the vine (toward the hips), off the surface
      const along = if (tan[1] > 0) -tan else tan;
      try kit.leaf(b, .{
        .base = p + out * m.splat3(0.004), .along = along, .out = out,
        .len = 0.05, .width = 0.016, .lift = 0.35, .curl = 0.4, .cup = 0.3,
        .col = pal.wolf_leaf_dark, .tip = pal.wolf_leaf_lite, .t = k,
      });
    }
  }
}

/// pull the chest vines in and down where the pectorals sit, so the lobes
/// cover them and they show only at the lobes' edges. A smooth field of
/// position: every copy of a shared vertex moves alike, so the braid stays
/// watertight.
fn tuck(vs:[]Mesh) void {
  const reach = v3(0.13, 0.1, 0.09);
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
