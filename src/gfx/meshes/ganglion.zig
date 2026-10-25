//! mesh: GANGLION. a parasite's nerve knot: a bulbous foot half sunk in the
//! soil, a short stalk of the lineage's lattice parting round a sac on its
//! core, and on it a knot of pale nodules in two even rings of five round a
//! translucent bladder where what it holds hangs (emitted, `belly_lump`s),
//! a crown of five short lilac fronds curling over it, alike. Its nerves out to the neighbours it feeds are its own
//! (`nerve`, emitted per side), and pulses run out along them.
//! It grows on a hidden stalk (gfx/growth.zig): the foot swells and its
//! roots spread with it, the stalk rises, the nodules swell out of its
//! top ring by ring round the bladder, the fronds curl over last.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const growth = @import("../growth.zig");
const pk = @import("parasite_kit.zig");

const V3 = m.V3;
const v3 = m.v3;

const NECK = v3(0, 0.17, 0);
const STALK:pk.Stalk = .{.girth = 0.03, .part = 2.0, .from = 0.25, .to = 0.92};
/// the bladder at the knot's heart, where what it holds hangs
pub const HEART = v3(0, 0.29, 0);
pub const HEART_R = v3(0.115, 0.1, 0.115);
/// rings of nodules round it, and how much later each swells than the
/// one below
const RINGS = 2;
const RING_STAGGER:f32 = 0.06;
const FRONDS = pk.FOLD;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var k = growth.Skeleton.begin(b);
  const stalk = k.trunk(&.{v3(0, -0.03, 0), v3(0.012, 0.07, -0.008), NECK}, .{.pace = 1.6});
  try pk.foot(b, &k, stalk, v3(0, -0.01, 0), v3(0.11, 0.07, 0.11));
  try pk.roots(b, &k, stalk, pk.FOLD, 0.22, 0.014, 0x6A7);
  try pk.stalk(b, &k, stalk, STALK);
  try pk.organs(b, &k, stalk, STALK, 1, 0.6);
  try pk.bladder(b, &k, stalk, 1, HEART, HEART_R, 1, .{.from = NECK});
  // the nodules: pale knots of nerve in two rings round the bladder, one
  // round its lower flank and a smaller one round its waist turned half a
  // step, each ring swelling out of the stalk's top at once
  for (0..RINGS) |ring| for (0..pk.FOLD) |i| {
    const a = (m.f(i) + 0.5 * m.f(ring)) / m.f(pk.FOLD) * m.tau;
    const dir = m.norm(v3(@cos(a), if (ring == 0) @as(f32, -0.35) else 0.15, @sin(a)));
    const r:f32 = if (ring == 0) 0.052 else 0.042;
    const at = HEART + dir * HEART_R + dir * m.splat3(r * 0.7);
    const s = b.mark();
    try pk.nodule(b, at, v3(r, r * 0.85, r), 0.9, pk.skin, pk.core, pk.pearl);
    try k.on(b, s, stalk, 1, .{.from = NECK, .delay = 0.04 + RING_STAGGER * m.f(ring)});
  };
  // a crown of short fronds curling in over the bladder, alike
  for (0..FRONDS) |i| {
    const a = (m.f(i) + 0.4) / FRONDS * m.tau;
    var c:[8]V3 = undefined;
    for (&c, 0..) |*p, j| {
      const f = m.ratio(j, 7);
      const th = m.lerp(m.pi * 0.62, -0.25, f);
      const lift = 1.12 + 0.3 * f * f;
      p.* = HEART + v3(@sin(th) * @cos(a + 0.3 * f) * HEART_R[0] * lift, @cos(th) * HEART_R[1] * 1.12 - 0.03 * f * f * f, @sin(th) * @sin(a + 0.3 * f) * HEART_R[2] * lift);
    }
    c[0] = NECK;
    mg.grow(c[1..], .{.start = c[1], .direction = v3(0, 1, 0), .length = 0.3, .wobble = 0.12, .seed = 0x6B0});
    const id = k.branch(stalk, 1, &c, .{.delay = 0.14});
    try k.tube(b, id, .{.r0 = 0.011, .tip = 0.15, .col = pk.lilac, .part = .tendril, .sides = 5, .t0 = 0.8, .t1 = 1});
  }
  k.finish(b);
}

/// mesh: GANGLION NERVE. a nerve from under the knot out along +X to the
/// tile's edge, arching low and diving into the ground there toward the
/// neighbour it feeds; its core (part `.core`, tu.x 0 at the knot .. 1 at
/// the edge) carries a pulse of what it hands on (part.vert). It grows
/// out along its own spline as it reaches (emitted with that as `grown`).
pub const nerve = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    var k = growth.Skeleton.begin(b);
    var c:[6]V3 = undefined;
    for (&c, 0..) |*p, j| {
      const f = m.ratio(j, 5);
      p.* = v3(0.06 + 0.46 * f, 0.09 * (1 - f) + 0.05 * @sin(m.pi * f) - 0.05 * f * f * f, 0);
    }
    mg.grow(c[1..], .{.start = c[1], .direction = v3(1, 0, 0), .length = 0.46, .wobble = 0.2, .seed = 0x6C0});
    const id = k.trunk(&c, .{});
    // the core the pulse runs through, sheathed in two pale strands
    var sp:[growth.RES]V3 = undefined;
    var ts:[growth.RES]f32 = undefined;
    var rs:[growth.RES]f32 = undefined;
    k.path(id, 0, 1, &sp);
    for (&ts, &rs, 0..) |*t, *r, j| {
      const u = m.ratio(j, growth.RES - 1);
      t.* = u;
      r.* = 0.016 * (1 - 0.45 * u);
    }
    const s = b.mark();
    try b.tubeR(&sp, &ts, &rs, pk.lilac, .core, 6);
    var sheath:[growth.RES]f32 = undefined;
    for (&sheath, rs) |*r, r0| r.* = r0 * 1.15;
    try mg.braid(b, &sp, &ts, &sheath, 2, 3.2, pk.WOBBLE, 0x6C1, pk.core, pk.pearl);
    try k.along(b, s, id);
    k.finish(b);
  }
};
