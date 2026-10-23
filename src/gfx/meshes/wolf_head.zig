//! mesh: WOLF HEAD. neck joint at origin, muzzle along +Z. One closed
//! surface from the back of the skull to the nose, built of planes rather
//! than a ball: a broad cranium with flat temples, a brow ridge hooding the
//! eyes, a stop stepping down to a long, flat-bridged muzzle that tapers
//! to the nose, cheekbones flaring out below the eyes, and the jaw line
//! running back from the chin to the cheek. A separate lower jaw sits under
//! the muzzle (the seam opens a little at the back). The ears and the nose
//! pad are their own instances (`wolf_ear`, `paw_bean`), placed by the rig.
//! Leaves lie back over the skull behind the ears like fur, wrapping the
//! nape in a ruff, and small leaves emerge along each cheekbone.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");
const kit = @import("wolf_kit.zig");

const V3 = m.V3;
const v3 = m.v3;
const core = pal.wolf_core;
const sap = pal.sap;

/// the head runs from the back of the skull to the end of the muzzle
const BACK:f32 = -0.1;
const FRONT:f32 = 0.22;
/// where the forehead steps down to the muzzle (the stop)
const STOP:f32 = 0.07;
/// the nose pad's centre, at the end of the muzzle
pub const nose = v3(0, 0.074, FRONT + 0.004);
/// where the ears root on the skull (x either side), for the rig
pub const ear_root = v3(0.056, 0.152, -0.01);

const STATIONS = 44;
const AROUND = 28;

fn gauss(x:f32, mu:f32, sigma:f32) f32 {
  const d = (x - mu) / sigma;
  return @exp(-d * d);
}

/// the head's outline along its length: top and bottom (y) and half width
const Outline = struct { top:f32, bottom:f32, half:f32, box:f32, snout:f32 };

fn outline(z:f32) Outline {
  // the muzzle takes over past the stop
  const snout = m.smooth(m.clamp01((z - 0.02) / (STOP + 0.03 - 0.02)));
  const along = m.clamp01((z - STOP) / (FRONT - STOP));
  // cranium: a broad dome; muzzle: a straight bridge, falling a little
  const dome = 0.17 - 0.06 * m.pow(f32, m.clamp01((-0.03 - z) / 0.07), 2);
  const bridge = m.lerp(0.104, 0.094, along);
  const top = m.lerp(dome, bridge, snout);
  const bottom = m.lerp(0.012, m.lerp(0.036, 0.054, m.pow(f32, along, 0.8)), snout);
  const half = m.lerp(0.084, m.lerp(0.056, 0.026, m.pow(f32, along, 0.8)), snout);
  // the back of the skull rounds off to a point
  const r = @sqrt(@max(0, 1 - m.pow(f32, m.clamp01((-0.03 - z) / (-0.03 - BACK)), 2)));
  const mid = (top + bottom) / 2;
  return .{
    .top = mid + (top - mid) * r, .bottom = mid - (mid - bottom) * r, .half = half * r,
    // how boxy the section is: planes on the muzzle, a rounder cranium
    .box = m.lerp(4.2, 6.0, snout),
    .snout = snout,
  };
}

/// a point on the head: `z` along it, `a` around it (0 the left side,
/// pi/2 the top).
fn point(z:f32, a:f32) V3 {
  const o = outline(z);
  const c = @cos(a);
  const s = @sin(a);
  const e = 2 / o.box;
  var x = m.sign(c) * m.pow(f32, @abs(c), e);
  const y = m.sign(s) * m.pow(f32, @abs(s), e);
  // temples slope in toward the crown; below, the jaw line runs in to the
  // chin as its own plane
  // the muzzle is a wedge: a narrow flat bridge, its sides falling away
  x *= if (s >= 0) 1 - (0.16 + 0.22 * o.snout) * s else 1 - 0.45 * m.pow(f32, -s, 1.3);
  const mid = (o.top + o.bottom) / 2;
  var p = v3(x * o.half, mid + y * (if (s >= 0) o.top - mid else mid - o.bottom), z);
  // the angle up the side, from the side (0) to the crown (pi/2)
  const up = m.atan2(s, @abs(c));
  const side = m.sign(c);
  // cheekbones: flaring out below and behind the eyes
  p[0] += side * 0.03 * gauss(z, 0.03, 0.026) * gauss(up, -0.15, 0.32);
  // the jaw muscle filling the back of the jaw line
  p[0] += side * 0.014 * gauss(z, -0.005, 0.03) * gauss(up, -0.75, 0.3);
  // brow ridge: a shelf over each eye
  const brow = gauss(z, 0.052, 0.012) * gauss(up, 0.8, 0.28);
  p[1] += 0.018 * brow;
  p[0] += side * 0.01 * brow;
  p[2] += 0.008 * brow;
  // a shallow groove up the forehead between the brows
  p[1] -= 0.006 * gauss(z, 0.03, 0.04) * gauss(up, m.pi / 2.0, 0.25);
  return p;
}

/// the outward normal of the surface at (z, a)
fn normal(z:f32, a:f32) V3 {
  const ez:f32 = 0.002;
  const ea:f32 = 0.01;
  const dz = point(z + ez, a) - point(z - ez, a);
  const da = point(z, a + ea) - point(z, a - ea);
  const n = m.cross(da, dz);
  const l = m.len(n);
  if (l < 1e-9) return if (z < 0) v3(0, 0, -1) else v3(0, 0, 1);
  const o = outline(z);
  const out = point(z, a) - v3(0, (o.top + o.bottom) / 2, z);
  const nn = n / m.splat3(l);
  return if (m.dot(nn, out) < 0) -nn else nn;
}

fn zAt(i:usize) f32 { return m.lerp(BACK, FRONT, m.ratio(i, STATIONS - 1)); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  // the head: one closed surface. Darker toward the back, the hide's
  // vine tone on the muzzle.
  const hide = color.mix(core, pal.wolf_vine, 0.35);
  var pts:[STATIONS][AROUND]V3 = undefined;
  var ns:[STATIONS][AROUND]V3 = undefined;
  for (0..STATIONS) |i| for (0..AROUND) |k| {
    const a = m.ratio(k, AROUND) * m.tau;
    pts[i][k] = point(zAt(i), a);
    ns[i][k] = normal(zAt(i), a);
  };
  for (0..STATIONS - 1) |i| for (0..AROUND) |k| {
    const k1 = (k + 1) % AROUND;
    const q = [4][2]usize{.{i, k}, .{i, k1}, .{i + 1, k1}, .{i + 1, k}};
    for ([_]usize{0, 1, 2, 0, 2, 3}) |c| {
      const s = q[c][0];
      const col = color.mix(core, hide, m.smooth(m.ratio(s, STATIONS - 1)));
      try b.put(pts[s][q[c][1]], ns[s][q[c][1]], col, 0.45 + 0.1 * m.ratio(s, STATIONS - 1), 0, .stem);
    }
  };
  // the muzzle's end, closed behind the nose pad
  const end = STATIONS - 1;
  const o = outline(FRONT);
  const tip = v3(0, (o.top + o.bottom) / 2, FRONT);
  for (0..AROUND) |k| {
    const k1 = (k + 1) % AROUND;
    for ([_]V3{tip, pts[end][k], pts[end][k1]}) |p| try b.put(p, v3(0, 0, 1), hide, 0.55, 0, .stem);
  }

  // lower jaw: under the muzzle from below the cheek to the chin, its seam
  // opening toward the back
  const J = 10;
  var jspine:[J]V3 = undefined;
  var jts:[J]f32 = undefined;
  var jws:[J]f32 = undefined;
  var jhs:[J]f32 = undefined;
  for (0..J) |i| {
    const k = m.ratio(i, J - 1);
    const z = m.lerp(0.0, FRONT - 0.03, k);
    jhs[i] = m.lerp(0.03, 0.011, k);
    jws[i] = m.lerp(0.056, 0.02, k);
    // its top tucks just under the muzzle; the seam opens toward the back
    const gap = 0.008 * (1 - k);
    jspine[i] = v3(0, outline(z).bottom + 0.006 - 0.02 * (1 - k) - jhs[i] - gap, z);
    jts[i] = 0.45;
  }
  try mg.loft(b, &jspine, &jts, &jws, &jhs, v3(0, 1, 0), jawShape, color.rgb(0.2, 0.18, 0.12).toRgba8(255), .stem, 12);

  // eyes: set in under the brow on the plane between skull and muzzle,
  // looking forward and out
  for ([_]f32{-1, 1}) |side| {
    const a:f32 = if (side > 0) 0.5 else m.pi - 0.5;
    const at = point(0.058, a) - normal(0.058, a) * m.splat3(0.006);
    try mg.ellipsoid(b, .{.center = at, .radii = v3(0.012, 0.012, 0.017), .col = sap, .part = .bloom, .rings = 5, .segs = 7, .t = 1});
  }
  try fur(b);
  try cheekLeaves(b);
}

/// the surface's direction toward the back of the head at (z, a), along it
fn backward(z:f32, a:f32) V3 {
  const d = point(z - 0.004, a) - point(z + 0.004, a);
  const n = normal(z, a);
  return m.norm(d - n * m.splat3(m.dot(d, n)));
}

/// leaves lying back over the skull behind the ears like fur, in staggered
/// rows that lengthen toward the nape and wrap around it into a ruff over
/// the neck, each overlapping the row behind
fn fur(b:*mg.Builder) Allocator.Error!void {
  var rng = pal.rngFor("wolf_fur");
  const rows = [_]struct { z:f32, a0:f32, a1:f32, n:u32, len:f32 }{
    .{.z = -0.028, .a0 = 1.05, .a1 = 2.09, .n = 3, .len = 0.05},
    .{.z = -0.048, .a0 = 0.55, .a1 = 2.59, .n = 6, .len = 0.058},
    .{.z = -0.066, .a0 = 0.05, .a1 = 3.09, .n = 8, .len = 0.066},
    .{.z = -0.082, .a0 = -0.5, .a1 = 3.64, .n = 10, .len = 0.074},
  };
  for (rows, 0..) |row, ri| {
    for (0..row.n) |i| {
      const stagger = if (ri % 2 == 0) @as(f32, 0.5) else 0.25;
      const a = m.lerp(row.a0, row.a1, (m.f(i) + stagger) / m.f(row.n)) + rng.range(-0.05, 0.05);
      const n = normal(row.z, a);
      // they lie back and settle down over the curve of the skull
      const along = m.norm(backward(row.z, a) + v3(0, -0.25, 0));
      try kit.leaf(b, .{
        .base = point(row.z, a) - n * m.splat3(0.002), .along = along, .out = n,
        .len = row.len * rng.range(0.85, 1.1), .width = 0.017 * rng.range(0.9, 1.1),
        .lift = 0.4, .curl = 0.5, .cup = 0.3,
        .col = pal.wolf_leaf_dark, .tip = pal.wolf_leaf_lite, .t = 0.9,
      });
    }
  }
}

/// small leaves emerging along each cheekbone, flush at the base, angling
/// out, back and a little up
fn cheekLeaves(b:*mg.Builder) Allocator.Error!void {
  for ([_]f32{-1, 1}) |side| {
    for ([_]f32{0.002, 0.024, 0.046}, 0..) |z, i| {
      const a:f32 = if (side > 0) -0.12 else m.pi + 0.12;
      const n = normal(z, a);
      const along = m.norm(backward(z, a) + v3(0, 0.35, 0));
      try kit.leaf(b, .{
        .base = point(z, a) - n * m.splat3(0.0015), .along = along, .out = n,
        .len = 0.03 + 0.007 * m.f(2 - i), .width = 0.012,
        .lift = 0.7, .curl = 0.25, .cup = 0.3,
        .col = pal.wolf_leaf_dark, .tip = pal.wolf_leaf_lite, .t = 0.9,
      });
    }
  }
}

fn jawShape(a:f32) [2]f32 { return .{@cos(a), @sin(a)}; }

test "the head is closed at both ends and wider at the cheeks than the muzzle" {
  const back = outline(BACK);
  try std.testing.expect(back.half < 1e-4);
  const cheek = point(0.035, -0.2)[0];
  const muzzle = point(0.15, 0)[0];
  try std.testing.expect(cheek > muzzle * 1.3);
}
