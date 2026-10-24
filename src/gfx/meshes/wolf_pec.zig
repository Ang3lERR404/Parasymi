//! WOLF PECTORAL: one lobe of solidified sap on the chest, built around its
//! centre (`CENTRE`, in the chest bone's frame) and skinned to the chest. A broad dish: wider
//! along its top edge, the lower edge sweeping in toward the sternum, a
//! shallow bowl in cross-section (flat-topped, falling steeply at the rim).
//! The areola (a raised disc) and the nipple (a dome on it) sit in the
//! lower-inner quadrant as part of the same smooth height field, so the
//! surface stays one watertight sheet.
//!
//! Every vertex is part `.resin` with tu.y its height through the lobe (0 at
//! the base on the chest, 1 at the crown): the shader thins the resin toward
//! the surface and the rig's spring moves the crown while the base holds.
//! Built once per side (`left` / `right`), mirrored, not flipped
//! by an instance, so normals and facing stay true.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const skel = @import("wolf_skeleton.zig");

const V3 = m.V3;
const v3 = m.v3;

/// each lobe's centre on the chest (x for the right one), in the chest
/// bone's frame; the two meet at the sternum
pub const CENTRE = v3(0.078, 0.09, 0.088);

/// half-widths of the outline: top edge (wider) and bottom edge
const W_TOP:f32 = 0.116;
const W_BOT:f32 = 0.096;
/// half-heights above and below the centre (the top edge is flatter)
const H_TOP:f32 = 0.082;
const H_BOT:f32 = 0.096;
/// how far the lower edge sweeps toward the sternum (-x on the right lobe)
const SWEEP:f32 = 0.024;
/// crown height of the dish above the chest
const DEPTH:f32 = 0.078;
/// the lower half carries a little more mass
const LOW_FULL:f32 = 0.15;
/// areola and nipple: centre (below the crown, only just inside it, so the
/// two sit well apart across the chest), radii and rise
const NIPPLE_AT = [2]f32{ 0.005, -0.034 };
const AREOLA_R:f32 = 0.027;
const AREOLA_RISE:f32 = 0.0035;
const NIPPLE_R:f32 = 0.01;
const NIPPLE_RISE:f32 = 0.0075;
/// how the lobe sits: lower edge turned toward the sternum, face tilted
/// down, and yawed out to follow the chest's curve
const ROLL:f32 = 0.18;
const TILT_DOWN:f32 = 0.2;
const YAW_OUT:f32 = 0.22;
/// polar grid: rings from the crown out to the rim, and steps around it
/// (fine enough that the nipple spans several vertices)
const RINGS = 44;
const STEPS = 96;

/// outline point at angle `a` (x right, y up), unit radius
fn outline(a:f32) [2]f32 {
  const c = @cos(a);
  const s = @sin(a);
  const up = m.smooth(m.clamp01(s * 0.5 + 0.5));
  const w = m.lerp(W_BOT, W_TOP, up);
  const h = if (s > 0) H_TOP else H_BOT;
  // a superellipse, squarer than an ellipse, so the top edge reads broad
  return .{ signedPow(c, 0.8) * w - SWEEP * @max(-s, 0), signedPow(s, 0.85) * h };
}

fn signedPow(x:f32, p:f32) f32 {
  const y = m.pow(f32, @abs(x), p);
  return if (x < 0) -y else y;
}

/// the bump of a raised disc (smooth shoulder) of radius `r` at distance `d`
fn disc(d:f32, r:f32) f32 { return 1 - m.smooth(m.clamp01((d - r * 0.7) / (r * 0.3))); }

/// a point on the lobe's front surface at radial fraction `k` (0 crown ..
/// 1 rim) and angle `a`, before it is posed on the chest
fn front(k:f32, a:f32) V3 {
  const o = outline(a);
  const x = o[0] * k;
  const y = o[1] * k;
  // dish profile: flat-topped crown falling steeply to the rim
  var z = DEPTH * m.pow(f32, @max(1 - m.pow(f32, k, 2.4), 0), 0.55) * (1 + LOW_FULL * @max(-@sin(a), 0) * k);
  const dx = x - NIPPLE_AT[0];
  const dy = y - NIPPLE_AT[1];
  const d = @sqrt(dx * dx + dy * dy);
  z += AREOLA_RISE * disc(d, AREOLA_R);
  const n = m.clamp01(1 - (d * d) / (NIPPLE_R * NIPPLE_R));
  z += NIPPLE_RISE * @sqrt(n);
  return v3(x, y, z);
}

/// the base: a slightly concave back that meets the front exactly at the rim
fn back(k:f32, a:f32) V3 {
  const o = outline(a);
  return v3(o[0] * k, o[1] * k, -0.012 * (1 - k * k));
}

fn surfaceNormal(comptime f:fn (f32, f32) V3, k:f32, a:f32) V3 {
  const e:f32 = 1e-3;
  // at the crown every angle meets in one point: step out a little first
  const kk = @max(k, 2 * e);
  const dk = f(kk + e, a) - f(@max(kk - e, 0), a);
  const da = f(kk, a + e) - f(kk, a - e);
  return m.norm(m.cross(dk, da));
}

pub fn lobe(b:*mg.Builder, side:f32) Allocator.Error!void {
  const R = RINGS + 1;
  const C = STEPS + 1; // the seam column repeats the first, at the same place
  var pts:[R * C]V3 = undefined;
  var nrm:[R * C]V3 = undefined;
  var cols:[R * C]@TypeOf(pal.sap) = undefined;
  var us:[R * C]f32 = undefined;
  const start = b.mark();
  inline for (.{ front, back }, 0..) |f, face| {
    for (0..R) |i| for (0..C) |j| {
      const k = m.ratio(i, RINGS);
      // the back runs the other way round, so it faces away from the front
      const t = if (face == 0) m.ratio(j, STEPS) else 1 - m.ratio(j, STEPS);
      const a = t * m.tau;
      const at = i * C + j;
      pts[at] = f(k, a);
      const n = surfaceNormal(f, k, a);
      nrm[at] = if (face == 0) n else -n;
      cols[at] = pal.sap;
      us[at] = if (face == 0) m.clamp01(pts[at][2] / DEPTH) else 0;
    };
    try mg.patch(b, R, C, &pts, &nrm, &cols, &us, 0.6, .resin);
  }
  // pose on the chest; the left lobe is the right one mirrored
  const chest = skel.bind()[@intFromEnum(skel.Bone.chest)];
  b.xform(start, m.chain(&.{
    chest, m.translate(CENTRE * v3(side, 1, 1)),
    m.scale3(v3(side, 1, 1)),
    m.rotY(YAW_OUT), m.rotX(TILT_DOWN), m.rotZ(ROLL),
  }));
  for (try b.skinOf(start)) |*k| k.* = .{ .bones = @intFromEnum(skel.Bone.chest), .weights = .{ 255, 0, 0, 0 } };
}

/// the two lobes, one library mesh each
pub const left = struct { pub fn build(b:*mg.Builder) Allocator.Error!void { try lobe(b, -1); } };
pub const right = struct { pub fn build(b:*mg.Builder) Allocator.Error!void { try lobe(b, 1); } };
