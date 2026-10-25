//! WOLF REAR: one lobe per side of solidified sap, like the pectorals: a
//! full resin dome laid over the hips' base and grown out of the hide
//! (wolf_kit.resinLobe), so its base follows the body's curve and its rim
//! melts into it with no edge; rounder and heavier toward its bottom, its
//! inner edge drawn straighter where the two press together at the cleft.
//! One watertight sheet, every vertex part `.resin` with tu.y its height
//! through the lobe (0 on the body, 1 at its crown), so it thins toward
//! its surface and the rig's spring moves the crown while the base holds.
//!
//! Built per side around `CENTRE` (the pelvis bone's frame), each vertex
//! weighted as the hide under it is: the pelvis, and toward its lower edge
//! the thigh beneath it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const skel = @import("wolf_skeleton.zig");
const kit = @import("wolf_kit.zig");
const body = @import("wolf_body.zig");

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
/// the outer share of the radius over which it eases into the hide
const FOOT:f32 = 0.3;
pub const RINGS = 36;
pub const STEPS = 72;


/// outline at angle `a` (x outward, y up), unit radius
fn outline(a:f32) [2]f32 {
  const c = @cos(a);
  const s = @sin(a);
  // round, the inner side only a little fuller where it presses against
  // the other lobe (the lobe is turned to face back, so its +x lies
  // toward the cleft)
  const w = if (c < 0) W_OUT else W_IN;
  const e:f32 = if (c < 0) 1 else 0.8;
  return .{ m.signedPow(c, e) * w, s * (if (s > 0) H_TOP else H_BOT) };
}

/// the lobe's shape for the kit (wolf_kit.resinLobe): a full dome, heavier
/// below, easing into the hide at its rim with no edge
const Shape = struct {
  pub const CROWN = DEPTH;
  pub fn outline(a:f32) [2]f32 { return rump.outline(a); }
  pub fn height(k:f32, a:f32, _:f32, _:f32) f32 {
    const full = 1 + LOW_FULL * @max(-@sin(a), 0) * k;
    // a round dome (a sphere's profile), easing into the hide at its rim
    return DEPTH * @sqrt(@max(1 - k * k, 0)) * full * m.smooth(m.clamp01((1 - k) / FOOT));
  }
};
const rump = @This();

/// the hide it grows over: the hips and the thighs below them (not the
/// tail rising between the two lobes)
const UNDER = [_]skel.Bone{ .pelvis, .waist, .thigh_l, .thigh_r };

pub fn lobe(b:*mg.Builder, side:f32) Allocator.Error!void {
  const w = skel.bind();
  var s = try body.sculptedOf(b.gpa, &w, &UNDER);
  defer s.deinit();
  // facing back (+z of the lobe toward -z of the body); the left lobe is
  // the right one mirrored
  const at = m.chain(&.{
    w[@intFromEnum(skel.Bone.pelvis)], m.translate(CENTRE * v3(side, 1, 1)),
    m.scale3(v3(side, 1, 1)),
    m.rotY(m.pi - FACE_OUT), m.rotX(FACE_DOWN),
  });
  try kit.resinLobe(b, &s, at, Shape, RINGS, STEPS, pal.sap, 0.3);
}

/// the two lobes, one library mesh each
pub const left = struct { pub fn build(b:*mg.Builder) Allocator.Error!void { try lobe(b, -1); } };
pub const right = struct { pub fn build(b:*mg.Builder) Allocator.Error!void { try lobe(b, 1); } };

/// a quad's facing in a lobe's patch (`first` its first vertex): the
/// cross of its diagonals
fn facing(b:*const mg.Builder, first:usize) V3 {
  const p = struct {
    fn f(bb:*const mg.Builder, i:usize) V3 { return v3(bb.v.items[i].pos[0], bb.v.items[i].pos[1], bb.v.items[i].pos[2]); }
  }.f;
  return m.cross(p(b, first + 2) - p(b, first), p(b, first + 5) - p(b, first + 1));
}

test "a resin lobe never folds over itself" {
  const pec = @import("wolf_pec.zig");
  inline for (.{ .{ lobe, RINGS, STEPS }, .{ pec.lobe, pec.RINGS, pec.STEPS } }) |l| {
    for ([_]f32{ -1, 1 }) |side| {
      var b:mg.Builder = .{.gpa = std.testing.allocator};
      defer b.deinit();
      try l[0](&b, side);
      // the raised face, then the base under it, quad for quad (the base's
      // columns run the other way): each face quad faces away from its base
      const steps = l[2];
      const half = l[1] * steps * 6;
      try std.testing.expectEqual(2 * half, b.v.items.len);
      for (0..l[1]) |ri| for (0..steps) |ci| {
        const f = facing(&b, (ri * steps + ci) * 6);
        const u = facing(&b, half + (ri * steps + (steps - 1 - ci)) * 6);
        if (m.len(f) < 1e-12 or m.len(u) < 1e-12) continue;
        try std.testing.expect(m.dot(f, u) < 0);
      };
    }
  }
}
