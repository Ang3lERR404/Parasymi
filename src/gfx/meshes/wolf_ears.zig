//! mesh: WOLF EARS. both ears, skinned to their bones (wolf_skeleton) above
//! their roots and to the skull below (so the root never leaves it), each
//! built at its root rising along the bone's +Y, its inner face toward +Z. A thick ear with weight: its base flares wide and sinks into the
//! skull (below the origin) so it grows out of the head rather than sitting
//! on it, narrowing to a softly rounded tip. The inner face is sap
//! (translucent through the instance's fade), cupped, with its outer rim
//! rolled forward (the helix) and a fold running up inside it; the back is
//! a dense shell of vine, the two joined by the rolled rim.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("engine").core.color;
const skel = @import("wolf_skeleton.zig");
const Sculpt = @import("sculpt_kit.zig").Sculpt;

const V3 = m.V3;
const v3 = m.v3;

pub const HEIGHT:f32 = 0.12;
const HALF_BASE:f32 = 0.032;
/// how far below the origin the base runs into the skull (fraction of HEIGHT)
const SINK:f32 = 0.3;
const CUP:f32 = 0.014;
const ROWS = 16;
const COLS = 11;

fn gauss(x:f32, mu:f32, sigma:f32) f32 {
  const d = (x - mu) / sigma;
  return @exp(-d * d);
}

/// half the ear's width at `k` up it (negative k: sunk in the skull)
fn half(k:f32) f32 {
  const up = m.clamp01(k);
  // a wide root flaring into the skull, a rounded tip
  const flare = 0.016 * m.pow(f32, m.clamp01(1 - (k + SINK) / (SINK + 0.25)), 2);
  return HALF_BASE * m.pow(f32, @cos(up * m.pi / 2.0), 0.75) + flare;
}

/// how thick the ear is at `k`: heavy at the root, thin toward the tip
fn thick(k:f32) f32 { return m.lerp(0.012, 0.0025, m.clamp01(k)); }

/// a point on the inner face: k up the ear, u across it (-1..1)
fn inner(k:f32, u:f32) V3 {
  const rise = @sin(m.clamp01(k) * m.pi * 0.9 + 0.15);
  // cupped, the rim rolling forward toward the inner side, a fold inside
  const cup = -CUP * (1 - u * u) * rise;
  const rim = 0.009 * m.smooth(m.clamp01((@abs(u) - 0.6) / 0.4)) * rise;
  const fold = -0.004 * gauss(u, -0.3, 0.16) * rise + 0.0025 * gauss(u, 0.12, 0.12) * rise;
  return v3(-u * half(k), k * HEIGHT, cup + rim + fold);
}

fn outer(k:f32, u:f32) V3 {
  const p = inner(k, u);
  // the back is rounder than the face: thickest down the middle
  return p - v3(0, 0, thick(k) * (0.35 + 0.65 * (1 - u * u)));
}

fn gridNormal(comptime f:fn (f32, f32) V3, k:f32, u:f32, toward:f32) V3 {
  const e:f32 = 0.01;
  const n = m.norm(m.cross(f(k + e, u) - f(k - e, u), f(k, u + e) - f(k, u - e)));
  return if (n[2] * toward < 0) -n else n;
}

fn kAt(r:usize) f32 { return m.lerp(-SINK, 0.985, m.ratio(r, ROWS - 1)); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const w = skel.bind();
  for (skel.sides) |sd| {
    const start = b.mark();
    try ear(b);
    // its root holds with the skull it is sunk in (rising from the root
    // mound sculpted there), and only above that does it turn with its
    // own bone, bending smoothly between
    for (b.v.items[start..], try b.skinOf(start)) |vx, *k| {
      const own = m.smooth(m.clamp01((vx.pos[1] - ROOT_HOLD) / ROOT_BEND));
      var wt:[skel.COUNT]f32 = @splat(0);
      wt[@intFromEnum(sd.ear)] = own;
      wt[@intFromEnum(skel.Bone.head)] = 1 - own;
      k.* = Sculpt.pack(&wt);
    }
    b.xform(start, w[@intFromEnum(sd.ear)]);
  }
}

/// how high up the ear (its own frame) the skull still holds it, and over
/// how much more it passes to the ear's bone
const ROOT_HOLD:f32 = 0.004;
const ROOT_BEND:f32 = 0.04;

fn ear(b:*mg.Builder) Allocator.Error!void {
  var pts:[ROWS * COLS]V3 = undefined;
  var nrms:[ROWS * COLS]V3 = undefined;
  var cols:[ROWS * COLS]color.Rgba8 = undefined;
  var us:[ROWS * COLS]f32 = undefined;
  // the inner face (sap; its normal points back, so the face seen from in
  // front is the sap-lined one)
  for (0..ROWS) |r| for (0..COLS) |c| {
    const k = kAt(r);
    const u = m.ratio(c, COLS - 1) * 2 - 1;
    const i = r * COLS + c;
    pts[i] = inner(k, u);
    nrms[i] = gridNormal(inner, k, u, -1);
    cols[i] = color.mix(pal.wolf_core, pal.wolf_vine, m.clamp01(k));
    us[i] = m.clamp01(k);
  };
  try mg.patch(b, ROWS, COLS, &pts, &nrms, &cols, &us, 1, .ear);
  // the back: a dense shell of vine
  for (0..ROWS) |r| for (0..COLS) |c| {
    const k = kAt(r);
    const u = m.ratio(c, COLS - 1) * 2 - 1;
    const i = r * COLS + c;
    pts[i] = outer(k, u);
    nrms[i] = gridNormal(outer, k, u, -1);
    cols[i] = color.mix(pal.wolf_core, pal.wolf_vine, 0.4 * m.clamp01(k));
  };
  try mg.patch(b, ROWS, COLS, &pts, &nrms, &cols, &us, 1, .stem);
  // the rolled rim joining face and back, up one edge, over the tip and
  // down the other
  const R = 2 * ROWS - 1;
  var rim:[R]V3 = undefined;
  var ts:[R]f32 = undefined;
  var rs:[R]f32 = undefined;
  for (0..R) |j| {
    const up = j < ROWS;
    const r = if (up) j else R - 1 - j;
    const u:f32 = if (up) -1 else 1;
    const k = kAt(r);
    rim[j] = (inner(k, u) + outer(k, u)) * m.splat3(0.5);
    ts[j] = m.clamp01(k);
    rs[j] = thick(k) * 0.3 + 0.0012;
  }
  // over the tip the two edges meet: pull them together there
  try b.tubeR(&rim, &ts, &rs, pal.wolf_vine, .stem, 5);
}
