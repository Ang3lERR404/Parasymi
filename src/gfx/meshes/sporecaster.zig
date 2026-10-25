//! mesh: SPORECASTER. a parasite that sends: a bulbous foot half sunk in
//! the soil, a tall stalk of three strands wound tight, small bladders
//! clinging up it, and on it a great translucent spore sac where what it
//! holds hangs (emitted, `belly_lump`s), pursed at its crown into a pore
//! its spore carriers rise out of and drift down into (`carrier`), a crown
//! of lilac fronds flaring out round the pore and curling down and back.
//! It grows on a hidden stalk (gfx/growth.zig): the foot swells and its
//! roots spread with it, the stalk rises, the bladders cling as it passes,
//! the sac swells out of its top, the pore purses and the fronds flare
//! last, one after another.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const growth = @import("../growth.zig");
const pk = @import("parasite_kit.zig");

const V3 = m.V3;
const v3 = m.v3;

const NECK = v3(0, 0.36, 0);
const STALK_R:f32 = 0.03;
/// the sac at the stalk's top, where the seeds it holds hang
pub const SAC_AT = v3(0, 0.49, 0);
pub const SAC_R = v3(0.12, 0.14, 0.12);
/// the pore at its crown it casts from
pub const PORE = SAC_AT + v3(0, SAC_R[1] * 1.05, 0);
const FRONDS = 7;
const FROND_STAGGER:f32 = 0.04;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var k = growth.Skeleton.begin(b);
  const stalk = k.trunk(&.{v3(0, -0.03, 0), v3(0.014, 0.12, -0.01), v3(-0.012, 0.25, 0.008), NECK}, .{.pace = 1.8});
  try pk.foot(b, &k, stalk, v3(0, -0.012, 0), v3(0.12, 0.08, 0.12));
  try pk.roots(b, &k, stalk, 6, 0.24, 0.015, 0x5C01);
  try pk.stalk(b, &k, stalk, STALK_R, 0x5C02);
  try pk.clinging(b, &k, stalk, 4, 0.3, 0.8, 0.03, STALK_R);
  try pk.bladder(b, &k, stalk, 1, SAC_AT, SAC_R, 1, .{.from = NECK});
  // the pore: a pursed pearl lip at the sac's crown
  const pore = b.mark();
  var ring:[9]V3 = undefined;
  var ts:[9]f32 = undefined;
  var rs:[9]f32 = undefined;
  for (&ring, &ts, &rs, 0..) |*p, *t, *r, j| {
    const f = m.ratio(j, 8);
    p.* = PORE + v3(0, -0.02 + 0.035 * f, 0);
    t.* = 1;
    // a lip swelling out and closing in round the opening
    r.* = 0.022 + 0.014 * @sin(m.pi * f) - 0.008 * f;
  }
  try b.tubeR(&ring, &ts, &rs, pk.pearl, .stem, 10);
  try k.on(b, pore, stalk, 1, .{.from = SAC_AT, .delay = 0.05});
  // fronds flaring out round the pore and curling down and back
  for (0..FRONDS) |i| {
    const a = (m.f(i) + 0.5) / FRONDS * m.tau;
    var c:[9]V3 = undefined;
    // up the sac's flank from its foot pole, held just off its skin...
    for (c[0..4], 0..) |*p, j| {
      const th = m.lerp(m.pi, 0.55, m.ratio(j, 3));
      p.* = SAC_AT + v3(@sin(th) * @cos(a) * SAC_R[0] * 1.08, @cos(th) * SAC_R[1] * 1.08, @sin(th) * @sin(a) * SAC_R[2] * 1.08);
    }
    // ...then flaring out over the pore and curling down and back
    pk.frondPath(c[3], v3(@cos(a), 0, @sin(a)), 0.3, 0.9, 3.4, 0x5C10 +% i * 13, c[3..]);
    const id = k.branch(stalk, 1, &c, .{.delay = 0.08 + FROND_STAGGER * m.f(i)});
    try k.tube(b, id, .{.r0 = 0.012, .tip = 0.12, .col = pk.lilac, .part = .tendril, .sides = 5, .t0 = 0.75, .t1 = 1});
  }
  k.finish(b);
}

/// mesh: SPORE CARRIER. one spore drifting from caster to caster, about
/// its own origin, its tip (+Y) leading: a clear sac of thin-film sap (part `.bloom`, the instance's `fade`) round a bead
/// of what it carries (part `.essence`, its colour the instance tint),
/// fine lilac cilia trailing from its foot, waving (part `.tendril`).
pub const carrier = struct {
  pub const R:f32 = 0.04;
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(R * 0.45, R * 0.5, R * 0.45), .col = pk.pearl, .part = .essence, .rings = 6, .segs = 8, .t = -1});
    try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(R, R * 1.12, R), .col = pk.sac, .part = .bloom, .rings = 8, .segs = 10, .t = 1});
    // a pursed pearl tip, the way it rises
    try mg.ellipsoid(b, .{.center = v3(0, R * 1.05, 0), .radii = v3(R * 0.22, R * 0.18, R * 0.22), .col = pk.pearl, .rings = 4, .segs = 6, .t = 1});
    for (0..CILIA) |i| {
      const a = m.ratio(i, CILIA) * m.tau;
      const out = v3(@cos(a), 0, @sin(a));
      var p:[8]V3 = undefined;
      var ts:[8]f32 = undefined;
      var rs:[8]f32 = undefined;
      for (&p, &ts, &rs, 0..) |*q, *t, *r, j| {
        const f = m.ratio(j, 7);
        q.* = out * m.splat3(R * (0.75 + 0.35 * f)) + v3(0, -R * (0.6 + 2.6 * f), 0) + out * m.splat3(0.012 * @sin(f * m.pi * 1.5 + m.f(i)));
        t.* = f;
        r.* = 0.0035 * (1 - 0.85 * f);
      }
      try b.tubeR(&p, &ts, &rs, pk.lilac, .tendril, 4);
    }
  }
  const CILIA = 7;
};
