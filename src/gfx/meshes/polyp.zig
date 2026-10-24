//! mesh: POLYP. the heart of a halo: a short woven stalk on a root mat,
//! opening into a small cup of petals that holds a bead of resin, with a
//! ring of pale tentacles curling up around it. The diamond (`diamond`)
//! rests in the cup once the halo completes; the ring of light around it
//! is `ring`.
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
pub const SEAT:f32 = 0.74;
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

/// mesh: HALO RING. one half of an edge of the halo's square, from a corner
/// to the edge's middle: a flat band of still light, its length up +Y over
/// 0..1 (tu.x), its width across x (tu.y -1..1). part.vert (curve mode)
/// lays it on the ground along the edge; part.frag fills it. Both faces,
/// so it reads from above and below a slope.
pub const ring = struct {
  /// half the band's width, world units
  pub const HALF:f32 = 0.2;

  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const col = color.rgb(1.0, 0.95, 0.9).toRgba8(255);
    const N = 24;
    const across = [_]f32{-1, -0.4, 0, 0.4, 1};
    for (0..N) |i| for (0..across.len - 1) |j| {
      const k0 = m.ratio(i, N);
      const k1 = m.ratio(i + 1, N);
      const q = [4][2]f32{.{k0, across[j]}, .{k0, across[j + 1]}, .{k1, across[j + 1]}, .{k1, across[j]}};
      for ([_]usize{0, 1, 2, 0, 2, 3}) |c| try b.put(v3(q[c][1] * HALF, q[c][0], 0), v3(0, 0, 1), col, q[c][0], q[c][1], .halo);
      for ([_]usize{0, 2, 1, 0, 3, 2}) |c| try b.put(v3(q[c][1] * HALF, q[c][0], 0), v3(0, 0, -1), col, q[c][0], q[c][1], .halo);
    };
  }
};

/// mesh: HALO DIAMOND. where the four blooms became one: a small
/// double-terminated crystal, its six faces a little uneven like a grown
/// one, standing upright. It has no light of its own; part.frag lays a warm
/// iridescent film over its facets, so it only catches light. Centred on
/// its girdle.
pub const diamond = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    var rng = pal.rngFor("halo_diamond");
    const S = 6;
    const body = color.rgb(0.98, 0.9, 0.82).toRgba8(255);
    const lite = color.rgb(1.0, 0.97, 0.92).toRgba8(255);
    const top = v3(rng.range(-0.006, 0.006), 0.17, rng.range(-0.006, 0.006));
    const bottom = v3(0, -0.14, 0);
    var hi:[S]V3 = undefined;
    var lo:[S]V3 = undefined;
    const turn = rng.range(0, m.tau);
    for (0..S) |i| {
      const a = turn + m.tau * m.ratio(i, S);
      const r = 0.07 * rng.range(0.88, 1.1);
      hi[i] = v3(@cos(a) * r, 0.06 * rng.range(0.85, 1.15), @sin(a) * r);
      lo[i] = v3(@cos(a) * r * 0.95, -0.05 * rng.range(0.85, 1.15), @sin(a) * r * 0.95);
    }
    const inside = v3(0, 0, 0);
    for (0..S) |i| {
      const j = (i + 1) % S;
      try mineral.facet(b, .{lo[i], lo[j], hi[j]}, inside, .{body, body, lite}, 0.5, .prism);
      try mineral.facet(b, .{lo[i], hi[j], hi[i]}, inside, .{body, lite, lite}, 0.5, .prism);
      try mineral.facet(b, .{hi[i], hi[j], top}, inside, .{lite, lite, lite}, 1, .prism);
      try mineral.facet(b, .{lo[i], bottom, lo[j]}, inside, .{body, body, body}, 0, .prism);
    }
  }
};
