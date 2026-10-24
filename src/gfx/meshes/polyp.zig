//! mesh: POLYP. the heart of a halo: a short woven stalk on a root mat,
//! opening into a small cup of petals that holds a bead of resin, with a
//! ring of pale tentacles curling up around it. The diamond (`diamond`)
//! forms in the cup as the halo completes, with a flash of light (`flash`)
//! as it does; the halo's ring is beams of light (`bloom_thread`).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");
const kit = @import("structure_kit.zig");
const mineral = @import("mineral_kit.zig");

const V3 = m.V3;
const v3 = m.v3;
const HEIGHT:f32 = 0.55;
/// where the diamond sits in the cup (its centre, mesh space)
pub const SEAT:f32 = 0.86;
const pearl = color.rgb(0.78, 0.74, 0.84);
const lilac = color.rgb(0.62, 0.52, 0.78);
const heart = color.rgb(0.34, 0.28, 0.44);

fn stalkProfile(k:f32) f32 { return 0.1 * (1 - 0.35 * k) + 0.04 * @exp(-k * 10) + 0.03 * @exp(-(1 - k) * 8); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var rng = pal.rngFor("polyp");
  try kit.rootMat(b, 6, 0.55, 0.05, 0x9071);
  try kit.footLeaves(b, 5, 0.16, 0.34, 0.13, 0x9072);
  const s = b.mark();
  try mg.bundle(b, stalkProfile, 5, 2.6, pal.STRAND_WOBBLE, 0x9073, pal.core, color.rgb(0.42, 0.38, 0.5).toRgba8(255));
  b.xform(s, m.scale3(v3(1.5, HEIGHT, 1.5)));
  const crown = v3(0, HEIGHT - 0.02, 0);
  // the cup: a whorl of short petals rising almost upright
  for (0..7) |i| {
    const a = m.ratio(i, 7) * m.tau;
    try mg.petal(b, .{
      .base = crown, .out = v3(@cos(a), 0, @sin(a)), .len = 0.26, .width = 0.12,
      .rise = 1.05, .flare = 0.55, .cup = 0.5,
      .col = heart.toRgba8(255), .tip = pearl.toRgba8(255), .part = .leaf,
    });
  }
  // a bead of resin in the cup: the diamond's bed
  try kit.resinPod(b, v3(0, HEIGHT + 0.04, 0), v3(0.1, 0.05, 0.1), 6, 10);
  // tentacles: grown from the crown, reaching up and out, curling in at the
  // tips, tapering to a point
  for (0..6) |i| {
    const a = (m.f(i) + 0.5 + rng.range(-0.12, 0.12)) / 6 * m.tau;
    const out = v3(@cos(a), 0, @sin(a));
    var c:[6]V3 = undefined;
    mg.growthPath(.{.start = crown + out * m.splat3(0.08), .direction = m.norm(out * m.splat3(0.7) + v3(0, 1, 0)), .length = rng.range(0.4, 0.5), .wobble = 0.2, .curl = 0.12, .seed = 0x9080 +% i * 17}, &c);
    // the tip bends back toward the cup
    c[5] = c[5] - out * m.splat3(0.08);
    c[4] = c[4] - out * m.splat3(0.03);
    var p:[14]V3 = undefined;
    m.splineResample(&c, &p);
    var ts:[14]f32 = undefined;
    var rs:[14]f32 = undefined;
    for (&ts, &rs, 0..) |*t, *r, j| {
      const k = m.ratio(j, 13);
      t.* = m.lerp(0.6, 1, k);
      // swells from its root, tapers to a point
      r.* = 0.024 * @min(1, k * 6 + 0.35) * (1 - k * 0.92);
    }
    try b.tubeR(&p, &ts, &rs, lilac.toRgba8(255), .tendril, 5);
  }
}

/// mesh: HALO FLASH. the light thrown out where a halo's blooms became one:
/// a flat disc of radius 1 (tu.x its radius 0..1), fine near its rim where
/// the light is a thin ring. part.vert spreads it with its age; part.frag
/// lights it.
pub const flash = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const col = color.rgb(1.0, 0.97, 0.9).toRgba8(255);
    const N = 48;
    const radii = [_]f32{ 0, 0.4, 0.7, 0.82, 0.88, 0.92, 0.96, 1.0 };
    for (0..N) |i| for (0..radii.len - 1) |j| {
      const a0 = m.ratio(i, N) * m.tau;
      const a1 = m.ratio(i + 1, N) * m.tau;
      const q = [4][2]f32{ .{ a0, radii[j] }, .{ a1, radii[j] }, .{ a1, radii[j + 1] }, .{ a0, radii[j + 1] } };
      for ([_]usize{ 0, 2, 1, 0, 3, 2 }) |c| try b.put(v3(@cos(q[c][0]) * q[c][1], 0, @sin(q[c][0]) * q[c][1]), v3(0, 1, 0), col, q[c][1], 0, .flash);
    };
  }
};

/// mesh: HALO DIAMOND. where the four blooms became one: a cut crystal,
/// eight-sided, its girdle bevelled into a crown and a pavilion of
/// staggered triangular facets running up to a long point and down to a
/// shorter one, three small crystals grown out at its foot. Each face a
/// little uneven, like a grown one. It has no light of its own; part.frag
/// lays a warm iridescent film over its facets, so it only catches light.
/// Centred on its girdle. part.vert gathers its facets in from shards as
/// the halo forms (they are separate faces, so each comes in on its own).
pub const diamond = struct {
  const S = 8;
  /// rings from the bottom point to the top one: height, radius, twist
  /// (in half steps), each staggered from the next
  const rings = [_][3]f32{
    .{ -0.24, 0, 0 },
    .{ -0.09, 0.085, 1 },
    .{ 0, 0.125, 0 },
    .{ 0.07, 0.09, 1 },
    .{ 0.13, 0.05, 0 },
    .{ 0.28, 0, 1 },
  };

  pub fn build(b:*mg.Builder) Allocator.Error!void {
    var rng = pal.rngFor("halo_diamond");
    const deep = color.rgb(0.95, 0.84, 0.76).toRgba8(255);
    const lite = color.rgb(1.0, 0.97, 0.92).toRgba8(255);
    var pts:[rings.len][S]V3 = undefined;
    for (rings, &pts) |rg, *row| for (row, 0..) |*p, i| {
      const a = (m.f(i) + rg[2] * 0.5) / S * m.tau;
      const r = rg[1] * rng.range(0.92, 1.08);
      p.* = v3(@cos(a) * r, rg[0] + rng.range(-0.006, 0.006) * @min(1, rg[1] * 20), @sin(a) * r);
    };
    const inside = v3(0, 0.01, 0);
    for (0..rings.len - 1) |k| {
      const lo = pts[k];
      const hi = pts[k + 1];
      const cl = if (k < 2) deep else lite;
      const ch = if (k + 1 < 2) deep else lite;
      const t0 = m.ratio(k, rings.len - 1);
      // a point is a ring of one place: the faces along it vanish
      const lo0 = rings[k][1] == 0;
      const hi0 = rings[k + 1][1] == 0;
      for (0..S) |i| {
        const j = (i + 1) % S;
        // the upper ring sits half a step on: stagger between them
        if (rings[k + 1][2] > rings[k][2]) {
          if (!lo0) try mineral.facet(b, .{ lo[i], lo[j], hi[i] }, inside, .{ cl, cl, ch }, t0, .prism);
          if (!hi0) try mineral.facet(b, .{ hi[i], lo[j], hi[j] }, inside, .{ ch, cl, ch }, t0, .prism);
        } else {
          if (!hi0) try mineral.facet(b, .{ lo[i], hi[j], hi[i] }, inside, .{ cl, ch, ch }, t0, .prism);
          if (!lo0) try mineral.facet(b, .{ lo[i], lo[j], hi[j] }, inside, .{ cl, cl, ch }, t0, .prism);
        }
      }
    }
    // small crystals grown out at its foot, leaning away
    for (0..3) |i| {
      const a = (m.f(i) + rng.range(-0.15, 0.15)) / 3 * m.tau + 0.4;
      try mineral.crystal(b, .{
        .base = v3(@cos(a) * 0.05, -0.12, @sin(a) * 0.05),
        .dir = m.norm(v3(@cos(a) * 0.9, 0.6, @sin(a) * 0.9)),
        .len = rng.range(0.12, 0.17), .r = rng.range(0.022, 0.03), .col = deep, .tip = lite, .part = .prism,
      }, &rng);
    }
  }
};
