//! WOLF PECTORAL: one lobe of solidified sap on the chest, laid over it
//! around its centre (`CENTRE`, in the chest bone's frame) and grown out of
//! the hide (wolf_kit.resinLobe): its base follows the chest wherever it
//! curves, and its rim melts into it with no edge. A broad dish: wider
//! along its top edge, the lower edge sweeping in toward the sternum, a
//! shallow bowl in cross-section (flat-topped, falling steeply, easing
//! into the hide). The areola (a raised disc) and the nipple (a dome on
//! it) sit in the lower-inner quadrant as part of the same smooth height
//! field, so the surface stays one watertight sheet.
//!
//! Every vertex is part `.resin` with tu.y its height through the lobe (0 at
//! the base on the chest, 1 at the crown): the shader thins the resin toward
//! the surface and the rig's spring moves the crown while the base holds.
//! Each is weighted as the hide under it is, so it moves with the chest
//! and breathes with it. Built once per side (`left` /
//! `right`), mirrored, not flipped by an instance, so normals and facing
//! stay true.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const engine = lib.engine;
const m = engine.core.math;
const mg = lib.meshgen;
const pal = lib.palette;
const skel = lib.skeleton;
const kit = lib.wolf_kit;
const body = lib.wolf_body;

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
/// the outer share of the radius over which it eases into the hide
const FOOT:f32 = 0.3;
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
pub const RINGS = 44;
pub const STEPS = 96;

/// outline point at angle `a` (x right, y up), unit radius
fn outline(a:f32) [2]f32 {
  const c = @cos(a);
  const s = @sin(a);
  const up = m.smooth(m.clamp01(s * 0.5 + 0.5));
  const w = m.lerp(W_BOT, W_TOP, up);
  const h = if (s > 0) H_TOP else H_BOT;
  // a superellipse, squarer than an ellipse, so the top edge reads broad
  return .{ m.signedPow(c, 0.8) * w - SWEEP * @max(-s, 0), m.signedPow(s, 0.85) * h };
}


/// the bump of a raised disc (smooth shoulder) of radius `r` at distance `d`
fn disc(d:f32, r:f32) f32 { return 1 - m.smooth(m.clamp01((d - r * 0.7) / (r * 0.3))); }


/// the lobe's shape for the kit (wolf_kit.resinLobe): its outline and how
/// high it rises off the hide at radial fraction `k` (0 crown .. 1 rim),
/// angle `a`, point `x`, `y` across it
const Shape = struct {
  pub const CROWN = DEPTH;
  pub fn outline(a:f32) [2]f32 { return pec.outline(a); }
  pub fn height(k:f32, a:f32, x:f32, y:f32) f32 {
    // dish profile: flat-topped crown falling steeply, then easing into
    // the hide with no edge at all, so it grows out of the chest
    var z = DEPTH * m.pow(f32, @max(1 - m.pow(f32, k, 2.4), 0), 0.55) * (1 + LOW_FULL * @max(-@sin(a), 0) * k);
    z *= m.smooth(m.clamp01((1 - k) / FOOT));
    const dx = x - NIPPLE_AT[0];
    const dy = y - NIPPLE_AT[1];
    const d = @sqrt(dx * dx + dy * dy);
    z += AREOLA_RISE * disc(d, AREOLA_R);
    const n = m.clamp01(1 - (d * d) / (NIPPLE_R * NIPPLE_R));
    z += NIPPLE_RISE * @sqrt(n);
    return z;
  }
};
const pec = @This();

/// the hide it grows over: the chest and the waist below it (its upper
/// edge tucks under the shoulders and the neck rather than climbing them)
const UNDER = [_]skel.Bone{ .chest, .waist };

pub fn lobe(b:*mg.Builder, side:f32) Allocator.Error!void {
  const w = skel.bind();
  var s = try body.sculptedOf(b.gpa, &w, &UNDER);
  defer s.deinit();
  // on the chest; the left lobe is the right one mirrored
  const at = m.chain(&.{
    w[@intFromEnum(skel.Bone.chest)], m.translate(CENTRE * v3(side, 1, 1)),
    m.scale3(v3(side, 1, 1)),
    m.rotY(YAW_OUT), m.rotX(TILT_DOWN), m.rotZ(ROLL),
  });
  try kit.resinLobe(b, &s, at, Shape, RINGS, STEPS, pal.sap, 0.6);
}

/// the two lobes, one library mesh each
pub const left = struct { pub fn build(b:*mg.Builder) Allocator.Error!void { try lobe(b, -1); } };
pub const right = struct { pub fn build(b:*mg.Builder) Allocator.Error!void { try lobe(b, 1); } };
