//! mesh: POLYP. the heart of a halo: a short woven stalk on a root mat,
//! opening into a small cup of petals that holds a bead of resin, with a
//! ring of pale tentacles curling up around it. The diamond forms high
//! over it as the halo completes (meshes/halo.zig: the radiant lineage's,
//! gathered, not grown). The polyp grows along growth splines.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");
const kit = @import("structure_kit.zig");
const growth = @import("../growth.zig");

const V3 = m.V3;
const v3 = m.v3;
const HEIGHT:f32 = 0.55;
const pearl = color.rgb(0.78, 0.74, 0.84);
const lilac = color.rgb(0.62, 0.52, 0.78);
const heart = color.rgb(0.34, 0.28, 0.44);

fn stalkProfile(k:f32) f32 { return 0.1 * (1 - 0.35 * k) + 0.04 * @exp(-k * 10) + 0.03 * @exp(-(1 - k) * 8); }

/// the stalk's girth over its profile
const GIRTH:f32 = 1.5;
/// the stalk rises this much slower than a unit a second's share
const STALK_PACE:f32 = 1.8;
/// where along the stalk the foot leaves unfold
const FOOT_AT:f32 = 0.1;
/// how much later each petal of the cup opens than the one before (the
/// skeleton's time); the bead fills and the stamens rise after them
const PETALS = 7;
const PETAL_STAGGER:f32 = 0.03;

/// It grows on a hidden stalk (gfx/growth.zig): the roots spread with it,
/// the foot leaves unfold, the woven stalk rises, then the cup opens petal
/// by petal round its bead and stamens while the tentacles reach up out of
/// its heart.
pub fn build(b:*mg.Builder) Allocator.Error!void {
  var rng = pal.rngFor("polyp");
  var k = growth.Skeleton.begin(b);
  const crown = v3(0, HEIGHT - 0.02, 0);
  const stalk = k.trunk(&.{v3(0, 0, 0), v3(0, HEIGHT * 0.5, 0), v3(0, HEIGHT, 0)}, .{.pace = STALK_PACE});
  try kit.rootMat(b, 6, 0.55, 0.05, 0x9071, .{.k = &k, .id = stalk});
  try kit.footLeaves(b, 5, 0.16, 0.34, 0.13, 0x9072, .{.k = &k, .id = stalk, .u = FOOT_AT});
  {
    var sp:[growth.RES]V3 = undefined;
    var ts:[growth.RES]f32 = undefined;
    var rs:[growth.RES]f32 = undefined;
    k.path(stalk, 0, 1, &sp);
    for (&ts, &rs, 0..) |*t, *r, i| {
      t.* = m.ratio(i, growth.RES - 1);
      r.* = stalkProfile(t.*) * GIRTH;
    }
    const s = b.mark();
    try mg.braid(b, &sp, &ts, &rs, 5, 2.6, pal.STRAND_WOBBLE, 0x9073, pal.core, color.rgb(0.42, 0.38, 0.5).toRgba8(255));
    try k.along(b, s, stalk);
  }
  // the cup: a whorl of short petals rising almost upright
  for (0..PETALS) |i| {
    const a = m.ratio(i, PETALS) * m.tau;
    const s = b.mark();
    try mg.petal(b, .{
      .base = crown, .out = v3(@cos(a), 0, @sin(a)), .len = 0.26, .width = 0.12,
      .rise = 1.05, .flare = 0.55, .cup = 0.5,
      .col = heart.toRgba8(255), .tip = pearl.toRgba8(255), .part = .leaf,
    });
    try k.on(b, s, stalk, 1, .{.from = crown, .delay = PETAL_STAGGER * m.f(i)});
  }
  // a bead of resin in the cup, stamens standing round it
  const bead = b.mark();
  try kit.resinPod(b, v3(0, HEIGHT + 0.04, 0), v3(0.1, 0.05, 0.1), 6, 10);
  try k.on(b, bead, stalk, 1, .{.from = crown, .delay = PETAL_STAGGER * PETALS});
  const st = b.mark();
  try mg.stamens(b, .{
    .heart = crown, .axis = v3(0, 1, 0), .n = 7, .len = 0.17, .r = 0.006, .anther = 0.032,
    .lean = 0.5, .arch = 0.45, .col = pearl.toRgba8(255), .spin = 0.45, .seed = 0x9074,
  });
  try k.on(b, st, stalk, 1, .{.from = crown, .delay = PETAL_STAGGER * (PETALS + 2)});
  // tentacles: grown from the crown, reaching up and out, curling in at the
  // tips, tapering to a point; each a branch out of the cup's heart (its
  // spline's first stretch hidden in the cup)
  for (0..6) |i| {
    const a = (m.f(i) + 0.5 + rng.range(-0.12, 0.12)) / 6 * m.tau;
    const out = v3(@cos(a), 0, @sin(a));
    var c:[7]V3 = undefined;
    mg.growthPath(.{.start = crown + out * m.splat3(0.08), .direction = m.norm(out * m.splat3(0.7) + v3(0, 1, 0)), .length = rng.range(0.4, 0.5), .wobble = 0.2, .curl = 0.12, .seed = 0x9080 +% i * 17}, c[1..]);
    // the tip bends back toward the cup
    c[6] = c[6] - out * m.splat3(0.08);
    c[5] = c[5] - out * m.splat3(0.03);
    const arm = k.branch(stalk, 1, &c, .{});
    var p:[14]V3 = undefined;
    m.splineResample(c[1..], &p);
    var ts:[14]f32 = undefined;
    var rs:[14]f32 = undefined;
    for (&ts, &rs, 0..) |*t, *r, j| {
      const f = m.ratio(j, 13);
      t.* = m.lerp(0.6, 1, f);
      // swells from its root, tapers to a point
      r.* = 0.024 * @min(1, f * 6 + 0.35) * (1 - f * 0.92);
    }
    const s = b.mark();
    try b.tubeR(&p, &ts, &rs, lilac.toRgba8(255), .tendril, 5);
    try k.along(b, s, arm);
  }
  k.finish(b);
}
