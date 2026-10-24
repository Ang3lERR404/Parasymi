//! WOLF REAR: one lobe per side of solidified sap, like the pectorals: a
//! full resin dome over the hips' base, rounder and heavier toward its
//! bottom, its inner edge drawn straighter where the two press together
//! at the cleft. One watertight sheet (front dome, concave base meeting it
//! at the rim), every vertex part `.resin` with tu.y its height through the
//! lobe (0 on the body, 1 at its crown), so it thins toward its surface and
//! the rig's spring moves the crown while the base holds.
//!
//! Built per side around `CENTRE` (the pelvis bone's frame) and skinned to
//! the pelvis, its lower edge partly to the thigh beneath it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const skel = @import("wolf_skeleton.zig");
const Sculpt = @import("sculpt_kit.zig").Sculpt;

const V3 = m.V3;
const v3 = m.v3;

/// each lobe's centre on the hips (x for the right one), in the pelvis
/// bone's frame, and the way it faces (back, a little down and out)
pub const CENTRE = v3(0.083, 0.01, -0.094);
const FACE_DOWN:f32 = 0.28;
const FACE_OUT:f32 = 0.25;
/// half-widths (outer edge, the inner edge at the cleft), half-heights
/// (above, below) and how far the crown stands off the body
const W_OUT:f32 = 0.102;
const W_IN:f32 = 0.088;
const H_TOP:f32 = 0.1;
const H_BOT:f32 = 0.112;
const DEPTH:f32 = 0.098;
/// the lower half carries more mass
const LOW_FULL:f32 = 0.22;
/// how much of the lower edge follows the thigh
const THIGH_SHARE:f32 = 0.3;
const RINGS = 36;
const STEPS = 72;

fn signedPow(x:f32, p:f32) f32 {
  const y = m.pow(f32, @abs(x), p);
  return if (x < 0) -y else y;
}

/// outline at angle `a` (x outward, y up), unit radius
fn outline(a:f32) [2]f32 {
  const c = @cos(a);
  const s = @sin(a);
  // the inner side squarer, pressed flat against the other lobe (the lobe
  // is turned to face back, so its +x lies toward the cleft)
  const w = if (c < 0) W_OUT else W_IN;
  const e:f32 = if (c < 0) 0.9 else 0.6;
  return .{ signedPow(c, e) * w, signedPow(s, 0.9) * (if (s > 0) H_TOP else H_BOT) };
}

fn front(k:f32, a:f32) V3 {
  const o = outline(a);
  const full = 1 + LOW_FULL * @max(-@sin(a), 0) * k;
  return v3(o[0] * k, o[1] * k, DEPTH * m.pow(f32, @max(1 - m.pow(f32, k, 2.2), 0), 0.6) * full);
}

fn back(k:f32, a:f32) V3 {
  const o = outline(a);
  return v3(o[0] * k, o[1] * k, -0.015 * (1 - k * k));
}

fn surfaceNormal(comptime f:fn (f32, f32) V3, k:f32, a:f32) V3 {
  const e:f32 = 1e-3;
  const kk = @max(k, 2 * e);
  const dk = f(kk + e, a) - f(@max(kk - e, 0), a);
  const da = f(kk, a + e) - f(kk, a - e);
  return m.norm(m.cross(dk, da));
}

pub fn lobe(b:*mg.Builder, side:f32) Allocator.Error!void {
  const R = RINGS + 1;
  const C = STEPS + 1;
  var pts:[R * C]V3 = undefined;
  var nrm:[R * C]V3 = undefined;
  var cols:[R * C]@TypeOf(pal.sap) = undefined;
  var us:[R * C]f32 = undefined;
  const start = b.mark();
  inline for (.{ front, back }, 0..) |f, face| {
    for (0..R) |i| for (0..C) |j| {
      const k = m.ratio(i, RINGS);
      const t = if (face == 0) m.ratio(j, STEPS) else 1 - m.ratio(j, STEPS);
      const a = t * m.tau;
      const at = i * C + j;
      pts[at] = f(k, a);
      const n = surfaceNormal(f, k, a);
      nrm[at] = if (face == 0) n else -n;
      cols[at] = pal.sap;
      us[at] = if (face == 0) m.clamp01(pts[at][2] / DEPTH) else 0;
    };
    try mg.patch(b, R, C, &pts, &nrm, &cols, &us, 0.3, .resin);
  }
  // facing back (+z of the lobe toward -z of the body); the left lobe is
  // the right one mirrored
  const sd = skel.sides[if (side < 0) 0 else 1];
  const pelvis = skel.bind()[@intFromEnum(skel.Bone.pelvis)];
  b.xform(start, m.chain(&.{
    pelvis, m.translate(CENTRE * v3(side, 1, 1)),
    m.scale3(v3(side, 1, 1)),
    m.rotY(m.pi - FACE_OUT), m.rotX(FACE_DOWN),
  }));
  // the lower edge partly follows the thigh as it swings
  for (b.v.items[start..], try b.skinOf(start)) |vx, *k| {
    const low = m.clamp01((CENTRE[1] + skel.HIP_Y - vx.pos[1]) / H_BOT);
    const share = THIGH_SHARE * m.smooth(low);
    k.* = Sculpt.pack(&weights(@intFromEnum(sd.thigh), share));
  }
}

fn weights(thigh:u8, share:f32) [skel.COUNT]f32 {
  var w:[skel.COUNT]f32 = @splat(0);
  w[@intFromEnum(skel.Bone.pelvis)] = 1 - share;
  w[thigh] = share;
  return w;
}

/// the two lobes, one library mesh each
pub const left = struct { pub fn build(b:*mg.Builder) Allocator.Error!void { try lobe(b, -1); } };
pub const right = struct { pub fn build(b:*mg.Builder) Allocator.Error!void { try lobe(b, 1); } };
