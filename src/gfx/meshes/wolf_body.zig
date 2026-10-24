//! mesh: WOLF BODY. the vine-wolf as one skin: every form of its body (the
//! ribcage, waist and hips, the muscles of its limbs, its neck and head,
//! its tail) is sculpted around the skeleton's bind pose (wolf_skeleton)
//! and melted into the next (sculpt_kit), so shoulder runs into arm,
//! thigh into hip and neck into skull without a seam, and the whole bends
//! with its bones on the GPU. Over the hide lie the things grown on it:
//! vines along the limbs and round the torso, fur leaves over the skull,
//! shoulders and tail, the digits and claws of its hands and feet, and the
//! eyes set deep in their sockets.
//!
//! The head: a broad cranium, a brow ridge hooding each eye socket, a short
//! muzzle whose bridge rises a little to an upturned nose, and the lower
//! jaw tucked up close under it (its own bone, so it can open).
//!
//! The pectorals, the rear, the ears and the belly are their own skinned
//! meshes (translucent sap and resin, sprung by the rig).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");
const vertex = @import("../vertex.zig");
const kit = @import("wolf_kit.zig");
const sculpt = @import("sculpt_kit.zig");
const skel = @import("wolf_skeleton.zig");

const V3 = m.V3;
const v3 = m.v3;
const M4 = m.M4;
const Bone = skel.Bone;
const Form = sculpt.Form;

/// the hide's cells at full detail (each level of detail doubles them)
pub const CELL:f32 = 0.005;

/// the hide: a muted olive-brown, the vine's tone on the muscles, the
/// core's darker brown on the hands and feet, a paler muzzle
const hide = color.mix(pal.wolf_core, pal.wolf_vine, 0.45);
const muscle = color.mix(pal.wolf_core, pal.wolf_vine, 0.7);
const dark = color.mix(pal.wolf_core, color.rgb(0.1, 0.08, 0.05).toRgba8(255), 0.35);
const muzzle = color.mix(pal.wolf_core, pal.wolf_vine, 0.55);
const lip = color.rgb(0.08, 0.06, 0.05).toRgba8(255);

/// the eyes: centre and radius in the head's frame (x for the right one)
pub const EYE = v3(0.034, 0.03, 0.071);
const EYE_R:f32 = 0.0125;
/// the nose pad, at the upturned end of the muzzle (head frame), and the
/// way its face looks (up and forward)
pub const NOSE = v3(0, 0.038, 0.174);
pub const NOSE_TILT:f32 = 0.45;

/// where each paw's beans sit (hand and foot frames, x for the right side)
pub const PALM = v3(-0.02, -0.05, 0.0);
pub const FINGERS = [4]f32{ -0.027, -0.009, 0.009, 0.027 };
pub const FINGER_AT:f32 = -0.088;
pub const SOLE_Y:f32 = -0.006;
pub const PAD_AT = v3(0, SOLE_Y + 0.002, 0.035);
pub const TOES = [4][2]f32{ .{ -0.027, 0.098 }, .{ -0.009, 0.108 }, .{ 0.009, 0.108 }, .{ 0.027, 0.098 } };

fn bi(b:Bone) u8 { return @intFromEnum(b); }

fn ell(c:V3, r:V3) sculpt.Shape { return .{ .ellipsoid = .{ .c = c, .r = r } }; }
fn cone(a:V3, b:V3, ra:f32, rb:f32) sculpt.Shape { return .{ .cone = .{ .a = a, .b = b, .ra = ra, .rb = rb } }; }

/// the forms, built into `s` around the bind pose `w`
fn sculptBody(s:*sculpt.Sculpt, w:*const [skel.COUNT]M4) Allocator.Error!void {
  const Add = struct {
    s:*sculpt.Sculpt,
    w:*const [skel.COUNT]M4,
    fn f(a:@This(), bone:Bone, shape:sculpt.Shape, col:color.Rgba8, k:f32) Allocator.Error!void {
      try a.s.add(.{ .shape = shape, .at = a.w[bi(bone)], .bone = bi(bone), .col = col, .k = k });
    }
    /// placed with a turn of its own inside the bone's frame
    fn turned(a:@This(), bone:Bone, at:M4, shape:sculpt.Shape, col:color.Rgba8, k:f32) Allocator.Error!void {
      try a.s.add(.{ .shape = shape, .at = m.mul(a.w[bi(bone)], at), .bone = bi(bone), .col = col, .k = k });
    }
  };
  const a:Add = .{ .s = s, .w = w };

  // hips: the pelvis's mass (the resin rear sits on its back)
  try a.f(.pelvis, ell(v3(0, 0.045, -0.008), v3(0.14, 0.1, 0.105)), hide, 0.04);
  // the waist drawn in between hips and ribs
  try a.f(.waist, ell(v3(0, 0.045, -0.006), v3(0.112, 0.105, 0.088)), hide, 0.05);
  // the ribcage, broad and deep; the trapezius sloping from the neck to
  // each shoulder; the lats fanning down the back into the waist
  try a.f(.chest, ell(v3(0, 0.085, -0.004), v3(0.148, 0.135, 0.108)), hide, 0.05);
  for ([_]f32{ -1, 1 }) |x| {
    try a.turned(.chest, m.rotZ(x * 0.35), ell(v3(x * 0.075, 0.185, -0.03), v3(0.08, 0.038, 0.058)), muscle, 0.035);
    try a.turned(.chest, m.chain(&.{ m.translate(v3(x * 0.088, 0.05, -0.055)), m.rotZ(x * 0.3) }), ell(v3(0, 0, 0), v3(0.048, 0.11, 0.042)), muscle, 0.03);
  }
  // the neck: a thick column, the throat under it
  try a.f(.neck, cone(v3(0, -0.05, -0.012), v3(0, 0.09, 0.015), 0.068, 0.055), hide, 0.05);
  try a.f(.neck, ell(v3(0, 0.03, 0.03), v3(0.045, 0.06, 0.038)), hide, 0.04);

  // the head
  try a.f(.head, ell(v3(0, 0.036, -0.024), v3(0.07, 0.07, 0.084)), hide, 0.04);
  for ([_]f32{ -1, 1 }) |x| {
    // cheekbones flaring out below and behind the eyes; the jaw muscle
    try a.f(.head, ell(v3(x * 0.05, 0.008, 0.036), v3(0.03, 0.024, 0.04)), hide, 0.025);
    try a.f(.head, ell(v3(x * 0.05, -0.016, 0.0), v3(0.026, 0.036, 0.036)), hide, 0.03);
    // the brow ridge, a shelf over each eye
    try a.turned(.head, m.rotY(x * 0.35), ell(v3(x * 0.022, 0.056, 0.058), v3(0.027, 0.011, 0.02)), hide, 0.022);
    // the ear's root, grown out of the skull
    try a.f(.head, ell(skel.EAR_AT * v3(x, 1, 1) + v3(0, -0.006, 0), v3(0.028, 0.024, 0.02)), hide, 0.025);
  }
  // the muzzle: short, its bridge rising a little to the upturned nose,
  // the cartilage of the nose at its end, the upper lip filling it below
  try s.add(.{ .shape = cone(v3(0, 0.012, 0.042), v3(0, 0.03, 0.148), 0.04, 0.021), .at = w[bi(.head)], .stretch = v3(1.12, 1, 1), .bone = bi(.head), .col = muzzle, .k = 0.03 });
  try a.f(.head, ell(v3(0, 0.034, 0.158), v3(0.023, 0.018, 0.018)), muzzle, 0.014);
  try a.f(.head, ell(v3(0, -0.001, 0.105), v3(0.033, 0.017, 0.05)), muzzle, 0.02);
  // the lower jaw, tucked up under the muzzle, and the chin
  const j = skel.JAW_AT;
  try a.f(.jaw, cone(v3(0, -0.032, 0.012) - j, v3(0, -0.014, 0.135) - j, 0.03, 0.015), muzzle, 0.012);
  try a.f(.jaw, ell(v3(0, -0.026, 0.112) - j, v3(0.02, 0.012, 0.028)), muzzle, 0.012);
  // the lip line, the dark rim of each socket
  try s.add(.{ .shape = cone(v3(0, -0.012, 0.158), v3(0, -0.006, 0.05), 0.002, 0.002), .stretch = v3(9, 1, 1), .at = w[bi(.head)], .bone = bi(.head), .col = lip, .ink = 0.0015 });
  for ([_]f32{ -1, 1 }) |x| {
    // the eye socket: carved in under the brow, looking forward and out
    const socket = m.chain(&.{ w[bi(.head)], m.translate(EYE * v3(x, 1, 1)), m.rotY(x * 0.55) });
    try s.add(.{ .shape = ell(v3(0, 0, 0.004), v3(0.021, 0.016, 0.02)), .at = socket, .bone = bi(.head), .col = dark, .k = 0.008, .carve = true });
    try s.add(.{ .shape = ell(v3(0, 0, 0.004), v3(0.021, 0.016, 0.02)), .at = socket, .bone = bi(.head), .col = lip, .ink = 0.006 });
  }

  // arms: a deltoid capping the shoulder, a squared arm under it with the
  // bicep before and the tricep behind; the forearm swelling below the
  // elbow and tapering to the wrist; the back of the hand
  for (skel.sides, 0..) |sd, si| {
    const x = skel.sign(si);
    try a.f(sd.arm, ell(v3(0, -0.035, 0), v3(0.068, 0.085, 0.07)), muscle, 0.04);
    try a.f(sd.arm, cone(v3(0, -0.02, 0), v3(0, -skel.UPPER_ARM, 0), 0.05, 0.041), hide, 0.03);
    try a.f(sd.arm, ell(v3(0, -0.105, 0.024), v3(0.04, 0.07, 0.034)), muscle, 0.02);
    try a.f(sd.arm, ell(v3(0, -0.145, -0.024), v3(0.04, 0.075, 0.034)), muscle, 0.02);
    try a.f(sd.forearm, ell(v3(0, 0.0, -0.022), v3(0.03, 0.032, 0.026)), hide, 0.02);
    try a.f(sd.forearm, cone(v3(0, 0, 0), v3(0, -skel.FOREARM, 0), 0.042, 0.028), hide, 0.03);
    try a.f(sd.forearm, ell(v3(0, -0.075, 0.014), v3(0.04, 0.075, 0.033)), muscle, 0.02);
    try a.f(sd.hand, ell(v3(0, -0.045, 0), v3(0.019, 0.05, 0.04)), dark, 0.022);

    // legs: the thigh's power (quadriceps before, hamstring behind), the
    // kneecap; the shin with the calf swelling on its back; the hock and
    // the long metatarsal down to the ball; the long flat foot
    try a.f(sd.thigh, cone(v3(0, 0.0, 0), v3(0, -skel.THIGH, 0), 0.074, 0.06), hide, 0.04);
    try a.f(sd.thigh, ell(v3(0, -0.1, 0.03), v3(0.064, 0.1, 0.054)), muscle, 0.025);
    try a.f(sd.thigh, ell(v3(0, -0.1, -0.032), v3(0.058, 0.095, 0.05)), muscle, 0.025);
    try a.f(sd.thigh, ell(v3(x * 0.028, -0.06, 0), v3(0.05, 0.09, 0.058)), hide, 0.03);
    try a.f(sd.thigh, ell(v3(0, -skel.THIGH, 0.042), v3(0.038, 0.04, 0.028)), hide, 0.02);
    try a.f(sd.shin, cone(v3(0, 0, 0), v3(0, -skel.SHIN, 0), 0.058, 0.04), hide, 0.035);
    try a.f(sd.shin, ell(v3(0, -0.085, -0.034), v3(0.05, 0.085, 0.044)), muscle, 0.02);
    try a.f(sd.meta, ell(v3(0, 0, -0.018), v3(0.034, 0.034, 0.03)), hide, 0.02);
    try a.f(sd.meta, cone(v3(0, 0, 0), v3(0, -skel.META, 0), 0.04, 0.029), dark, 0.03);
    try a.f(sd.foot, ell(v3(0, 0.013, 0.03), v3(0.035, 0.019, 0.06)), dark, 0.03);
    try a.f(sd.foot, ell(v3(0, 0.022, -0.008), v3(0.029, 0.024, 0.032)), dark, 0.025);
  }

  // the tail, growing out of the rear and tapering to its tip
  const radii = [_]f32{ 0.056, 0.048, 0.04, 0.03, 0.011 };
  for ([_]Bone{ .tail0, .tail1, .tail2, .tail3 }, 0..) |tb, i| {
    const from:f32 = if (i == 0) -0.03 else 0;
    const len = if (i == 3) skel.TAIL_SEG * 0.92 else skel.TAIL_SEG;
    try a.f(tb, cone(v3(0, from, 0), v3(0, len, 0), radii[i], radii[i + 1]), hide, if (i == 0) 0.045 else 0.03);
  }
}

/// the sculpted wolf (forms only), for meshes that sit on its surface
pub fn sculpted(gpa:Allocator, w:*const [skel.COUNT]M4) Allocator.Error!sculpt.Sculpt {
  var s:sculpt.Sculpt = .{ .gpa = gpa, .parents = &parents };
  errdefer s.deinit();
  try sculptBody(&s, w);
  return s;
}

const parents = blk: {
  var out:[skel.COUNT]?u8 = undefined;
  for (&out, 0..) |*o, i| o.* = if (skel.parent(@enumFromInt(i))) |p| @intFromEnum(p) else null;
  break :blk out;
};

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const w = skel.bind();
  var s = try sculpted(b.gpa, &w);
  defer s.deinit();
  try s.mesh(b, CELL * m.f(@as(u32, 1) << @intCast(b.lod)), 0.5, .stem);
  try eyes(b, &w);
  try vines(b, &s, &w);
  try fur(b, &s, &w);
  try digits(b, &w);
}

fn xf(mat:M4, p:V3) V3 {
  const r = m.mulV(mat, .{ p[0], p[1], p[2], 1 });
  return v3(r[0], r[1], r[2]);
}
fn dir(mat:M4, d:V3) V3 {
  const r = m.mulV(mat, .{ d[0], d[1], d[2], 0 });
  return m.norm(v3(r[0], r[1], r[2]));
}

/// every vertex since `start` moves with `bone` alone
fn rigid(b:*mg.Builder, start:usize, bone:Bone) Allocator.Error!void {
  for (try b.skinOf(start)) |*k| k.* = .{ .bones = bi(bone), .weights = .{ 255, 0, 0, 0 } };
}

/// the eyes: amber sap set back in the sockets, glowing
fn eyes(b:*mg.Builder, w:*const [skel.COUNT]M4) Allocator.Error!void {
  for ([_]f32{ -1, 1 }) |x| {
    const start = b.mark();
    try mg.ellipsoid(b, .{ .center = v3(0, 0, 0), .radii = v3(EYE_R * 0.95, EYE_R * 0.8, EYE_R), .col = pal.sap, .part = .bloom, .rings = 8, .segs = 12, .t = 1 });
    b.xform(start, m.chain(&.{ w[bi(.head)], m.translate(EYE * v3(x, 1, 1) + v3(0, 0, -0.004)), m.rotY(x * 0.55) }));
    try rigid(b, start, .head);
  }
}

/// points along a vine: each found by casting out of the body from a point
/// on a bone's axis (`axis`) along `out`, so it always lies on that part's
/// own hide, never jumping across to another
const VINE = 22;
const Lay = struct { axis:[VINE]V3, out:[VINE]V3 };

/// a grown vine lying along the hide through the points `lay` casts to,
/// half sunk in it, tapering to a point at both ends and weighted to the
/// bones under it
fn vineOver(b:*mg.Builder, s:*const sculpt.Sculpt, lay:*const Lay, r:f32, col:color.Rgba8) Allocator.Error!void {
  var path:[VINE]V3 = undefined;
  var ts:[VINE]f32 = undefined;
  var rs:[VINE]f32 = undefined;
  var n:usize = 0;
  for (lay.axis, lay.out, 0..) |a, o, i| {
    const hit = (try s.cast(a, o, 0.4)) orelse continue;
    const k = m.ratio(i, VINE - 1);
    rs[n] = @max(r * @sqrt(@sin(m.pi * k)), 0.0006);
    path[n] = hit.p + hit.n * m.splat3(rs[n] * 0.45);
    ts[n] = k;
    n += 1;
  }
  if (n < 4) return;
  rs[0] = 0.0006;
  rs[n - 1] = 0.0006;
  const start = b.mark();
  try b.tubeR(path[0..n], ts[0..n], rs[0..n], col, .stem, 5);
  for (b.v.items[start..], try b.skinOf(start)) |vx, *k| k.* = try s.weigh(v3(vx.pos[0], vx.pos[1], vx.pos[2]));
}

/// a stretch of a bone's axis a vine winds around (local y from `y0` to `y1`)
const Seg = struct { bone:Bone, y0:f32, y1:f32 };

/// a vine winding around the axis of `segs` in turn, starting at angle `a0`
/// (about each bone's y, 0 toward its +z) and turning `turn` radians along
fn wind(w:*const [skel.COUNT]M4, segs:[]const Seg, a0:f32, turn:f32) Lay {
  var lay:Lay = undefined;
  var total:f32 = 0;
  for (segs) |sg| total += @abs(sg.y1 - sg.y0);
  for (0..VINE) |i| {
    const k = m.ratio(i, VINE - 1);
    var along = k * total;
    var at = segs[segs.len - 1];
    var f:f32 = 1;
    for (segs) |sg| {
      const l = @abs(sg.y1 - sg.y0);
      if (along <= l) {
        at = sg;
        f = along / @max(l, 1e-6);
        break;
      }
      along -= l;
    }
    const mat = w[bi(at.bone)];
    const a = a0 + k * turn;
    lay.axis[i] = xf(mat, v3(0, m.lerp(at.y0, at.y1, f), 0));
    lay.out[i] = dir(mat, v3(@sin(a), 0, @cos(a)));
  }
  return lay;
}

/// a vine along a line inside one bone (`from` to `to`, local), cast out
/// along `out` (local)
fn line(w:*const [skel.COUNT]M4, bone:Bone, from:V3, to:V3, out:V3) Lay {
  var lay:Lay = undefined;
  const mat = w[bi(bone)];
  for (0..VINE) |i| {
    const k = m.ratio(i, VINE - 1);
    lay.axis[i] = xf(mat, m.lerpV(from, to, k));
    lay.out[i] = dir(mat, out);
  }
  return lay;
}

fn vines(b:*mg.Builder, s:*const sculpt.Sculpt, w:*const [skel.COUNT]M4) Allocator.Error!void {
  // limbs: vines winding down each segment and across the joints, so the
  // limb reads as grown and bound, never jointed
  for (skel.sides, 0..) |sd, si| {
    const x = skel.sign(si);
    for (0..2) |vi| {
      const a0 = m.f(vi) * m.pi + x * 0.6;
      try vineOver(b, s, &wind(w, &.{ .{ .bone = sd.arm, .y0 = -0.06, .y1 = -skel.UPPER_ARM }, .{ .bone = sd.forearm, .y0 = 0, .y1 = -0.2 } }, a0, 2.4), 0.0085, pal.wolf_vine);
      try vineOver(b, s, &wind(w, &.{ .{ .bone = sd.thigh, .y0 = -0.03, .y1 = -skel.THIGH }, .{ .bone = sd.shin, .y0 = 0, .y1 = -0.22 } }, a0, 2.8), 0.01, pal.wolf_vine);
    }
    // a tendon of vine down the back of the metatarsal to the heel, and
    // one down the front of the forearm to the hand
    try vineOver(b, s, &line(w, sd.meta, v3(0, -0.02, 0), v3(0, -skel.META * 0.92, 0), v3(0, 0, -1)), 0.008, pal.wolf_vine);
    try vineOver(b, s, &wind(w, &.{ .{ .bone = sd.forearm, .y0 = -0.08, .y1 = -skel.FOREARM }, .{ .bone = sd.hand, .y0 = 0, .y1 = -0.05 } }, 0, 0), 0.006, pal.wolf_vine);
  }
  // the torso: strands woven diagonally round it from the hips over the
  // ribs, over the sides and back only, leaving the chest and belly bare
  // where the sap shows
  const torso = [_]Seg{ .{ .bone = .pelvis, .y0 = -0.02, .y1 = skel.WAIST_AT[1] }, .{ .bone = .waist, .y0 = 0, .y1 = skel.CHEST_AT[1] }, .{ .bone = .chest, .y0 = 0, .y1 = 0.17 } };
  for ([_]f32{ 1.2, 2.3, 3.5, 4.6 }, 0..) |a0, vi| {
    const turn:f32 = if (vi % 2 == 0) 1.5 else -1.5;
    try vineOver(b, s, &wind(w, &torso, a0, turn), 0.011, pal.wolf_vine);
  }
  // the neck: two strands spiralling up it into the nape
  for (0..2) |vi| {
    try vineOver(b, s, &wind(w, &.{ .{ .bone = .neck, .y0 = -0.06, .y1 = skel.HEAD_AT[1] * 0.8 } }, m.f(vi) * m.pi + 2.2, 1.6), 0.009, pal.wolf_vine);
  }
  // the tail: three strands braided along it
  const tail = [_]Seg{
    .{ .bone = .tail0, .y0 = 0.02, .y1 = skel.TAIL_SEG }, .{ .bone = .tail1, .y0 = 0, .y1 = skel.TAIL_SEG },
    .{ .bone = .tail2, .y0 = 0, .y1 = skel.TAIL_SEG }, .{ .bone = .tail3, .y0 = 0, .y1 = skel.TAIL_SEG * 0.85 },
  };
  for (0..3) |vi| try vineOver(b, s, &wind(w, &tail, m.ratio(vi, 3) * m.tau, 5.0), 0.012, pal.wolf_vine);
}

/// a fur leaf lying on the surface near `guess`, along `along` (pulled
/// into the surface's plane), moving rigidly with the bones at its base
fn furLeaf(b:*mg.Builder, s:*const sculpt.Sculpt, guess:V3, along:V3, len:f32, width:f32, lift:f32, curl:f32) Allocator.Error!void {
  const on = try s.project(guess);
  const al = m.norm(along - on.n * m.splat3(m.dot(along, on.n)));
  const start = b.mark();
  try kit.leaf(b, .{
    .base = on.p - on.n * m.splat3(0.002), .along = al, .out = on.n,
    .len = len, .width = width, .lift = lift, .curl = curl, .cup = 0.3,
    .col = pal.wolf_leaf_dark, .tip = pal.wolf_leaf_lite, .t = 0.9,
  });
  const k = try s.weigh(on.p);
  for (try b.skinOf(start)) |*q| q.* = k;
}

fn fur(b:*mg.Builder, s:*const sculpt.Sculpt, w:*const [skel.COUNT]M4) Allocator.Error!void {
  var rng = pal.rngFor("wolf_fur");
  const head = w[bi(.head)];
  const back = dir(head, v3(0, -0.25, -1));
  // hair: staggered rows of leaves from just behind the brow back over
  // the crown (narrow between the ears, widening behind them), lying back
  // and lengthening toward the nape, wrapping it in a ruff over the neck
  const rows = [_]struct { z:f32, a0:f32, a1:f32, n:u32, len:f32 }{
    .{ .z = 0.04, .a0 = 1.25, .a1 = 1.89, .n = 3, .len = 0.042 },
    .{ .z = 0.022, .a0 = 1.15, .a1 = 1.99, .n = 4, .len = 0.046 },
    .{ .z = 0.004, .a0 = 1.1, .a1 = 2.04, .n = 5, .len = 0.05 },
    .{ .z = -0.014, .a0 = 0.95, .a1 = 2.19, .n = 6, .len = 0.054 },
    .{ .z = -0.032, .a0 = 0.7, .a1 = 2.44, .n = 7, .len = 0.058 },
    .{ .z = -0.05, .a0 = 0.4, .a1 = 2.74, .n = 8, .len = 0.064 },
    .{ .z = -0.068, .a0 = 0.1, .a1 = 3.04, .n = 10, .len = 0.07 },
    .{ .z = -0.086, .a0 = -0.3, .a1 = 3.44, .n = 11, .len = 0.076 },
    .{ .z = -0.1, .a0 = -0.7, .a1 = 3.84, .n = 12, .len = 0.082 },
    .{.z = 0.8,.a0 = 1.1,.a1 = 3.94,.n = 13,.len = 0.12}
  };
  for (rows, 0..) |row, ri| {
    for (0..row.n) |i| {
      const stagger:f32 = if (ri % 2 == 0) 0.5 else 0.25;
      const a = m.lerp(row.a0, row.a1, (m.f(i) + stagger) / m.f(row.n)) + rng.range(-0.05, 0.05);
      const guess = xf(head, v3(@cos(a) * 0.1, 0.04 + @sin(a) * 0.1, row.z));
      try furLeaf(b, s, guess, back + v3(0, -0.2, 0), row.len * rng.range(0.85, 1.1), 0.017 * rng.range(0.9, 1.1), 0.4, 0.5);
    }
  }
  // a forelock between the ears: a few longer leaves rising off the brow
  // and arching back over the crown
  for ([_]f32{ -0.012, 0.0, 0.012 }, 0..) |x, i| {
    try furLeaf(b, s, xf(head, v3(x, 0.12, 0.03 - 0.008 * m.f(i % 2))), dir(head, v3(x * 4, 0.6, -1)), 0.07 * rng.range(0.9, 1.1), 0.02, 0.75, 0.6);
  }
  // the mane running on down the back of the neck, longest at its root
  const neck = w[bi(.neck)];
  for ([_]f32{ 0.07, 0.035, 0.0, -0.035 }, 0..) |y, ri| {
    const n:u32 = 5 + @as(u32, @intCast(ri));
    for (0..n) |i| {
      const a = m.lerp(m.pi * 0.62, m.pi * 1.38, (m.f(i) + 0.5) / m.f(n)) + rng.range(-0.06, 0.06);
      try furLeaf(b, s, xf(neck, v3(@sin(a) * 0.1, y, @cos(a) * 0.1)), dir(neck, v3(@sin(a) * 0.3, -1, -0.5)), (0.075 + 0.006 * m.f(ri)) * rng.range(0.85, 1.1), 0.019, 0.38, 0.5);
    }
  }
  // along each cheekbone, angling back and up
  for ([_]f32{ -1, 1 }) |x| {
    for ([_]f32{ 0.0, 0.022, 0.044 }, 0..) |z, i| {
      try furLeaf(b, s, xf(head, v3(x * 0.09, 0.0, z)), dir(head, v3(0, 0.35, -1)), 0.03 + 0.007 * m.f(2 - i), 0.012, 0.7, 0.25);
    }
  }
  // a tuft over each shoulder
  for (skel.sides) |sd| {
    const arm = w[bi(sd.arm)];
    for (0..6) |i| {
      const a = m.ratio(i, 6) * m.tau;
      try furLeaf(b, s, xf(arm, v3(@sin(a) * 0.05, 0.06, @cos(a) * 0.05)), dir(arm, v3(@sin(a), -0.6, @cos(a))), 0.085 * rng.range(0.85, 1.1), 0.026, 0.45, 0.45);
    }
  }
  // rings of fur down the tail, longer toward the tip, and the tuft there
  for (0..6) |ring| {
    const along = 1.2 + 0.45 * m.f(ring);
    const seg = @min(@as(usize, @intFromFloat(along)), 3);
    const tb = w[bi(.tail0) + seg];
    for (0..3) |j| {
      const a = m.f(j) / 3 * m.tau + m.f(ring) * 1.05;
      try furLeaf(b, s, xf(tb, v3(@sin(a) * 0.08, (along - m.f(seg)) * skel.TAIL_SEG, @cos(a) * 0.08)), dir(tb, v3(0, 1, 0)), 0.06 + 0.012 * m.f(ring), 0.02, 0.45, 0.4);
    }
  }
  const tip = m.chain(&.{ w[bi(.tail3)], m.translate(v3(0, skel.TAIL_SEG * 0.85, 0)) });
  const start = b.mark();
  for (0..9) |i| {
    const inner = i >= 6;
    const a = if (inner) (m.f(i - 6) + 0.5) / 3 * m.tau else m.f(i) / 6 * m.tau + rng.range(-0.15, 0.15);
    const out = v3(@cos(a), 0.0, @sin(a));
    try kit.leaf(b, .{
      .base = out * m.splat3(0.008), .along = m.norm(v3(0, 1, 0) + out * m.splat3(0.35)), .out = out,
      .len = (if (inner) @as(f32, 0.08) else 0.12) * rng.range(0.85, 1.1), .width = if (inner) 0.024 else 0.03,
      .lift = if (inner) 0.25 else 0.4, .curl = 0.35, .cup = 0.3,
      .col = pal.wolf_leaf_dark, .tip = pal.wolf_leaf_lite,
    });
  }
  b.xform(start, tip);
  try rigid(b, start, .tail3);
}

/// the hands' fingers and the feet's toes: knuckled forms of planes
/// arching to curved claws, and a dewclaw high on each hand
fn digits(b:*mg.Builder, w:*const [skel.COUNT]M4) Allocator.Error!void {
  for (skel.sides, 0..) |sd, si| {
    const x = skel.sign(si);
    // the palm faces the body: fingers hang down (-y), spread along z
    const palm = v3(-x, 0, 0);
    var start = b.mark();
    for (FINGERS) |z| {
      try kit.digit(b, .{
        .base = v3(0, FINGER_AT + 0.045, z * 0.9), .dir = m.norm(v3(0, -1, z * 1.6)), .down = palm,
        .len = 0.04, .r = 0.0105, .col = pal.wolf_core, .claw = pal.wolf_claw,
      });
    }
    try kit.digit(b, .{
      .base = v3(0, -0.02, 0.036), .dir = m.norm(v3(0, -0.6, 0.6)), .down = palm,
      .len = 0.018, .r = 0.007, .col = pal.wolf_core, .claw = pal.wolf_claw,
    });
    b.xform(start, w[bi(sd.hand)]);
    try rigid(b, start, sd.hand);
    start = b.mark();
    for (TOES) |t| {
      try kit.digit(b, .{
        .base = v3(t[0] * 0.9, 0.012, t[1] - 0.026), .dir = m.norm(v3(t[0] * 2.5, -0.1, 1)),
        .len = 0.034, .r = 0.0105, .col = pal.wolf_core, .claw = pal.wolf_claw,
      });
    }
    b.xform(start, w[bi(sd.foot)]);
    try rigid(b, start, sd.foot);
  }
}
