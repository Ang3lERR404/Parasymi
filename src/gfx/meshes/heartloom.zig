//! mesh: HEARTLOOM. a weftstone and a driftbraid grown into one 2x2 tree
//! (convergence_kit, the driftbraid's look): out of each corner of its
//! ground a weave of green and pale strands rises, its foot rooted both
//! ways, the four winding round one another as they climb and closing in
//! until they meet and run on as one great weave, parting into a cage;
//! at its top a great sac of both saps where what it holds hangs and what
//! it weaves forms (emitted), a flower of both crowning it, and five lilac
//! boughs arching out round it exactly alike, each with leaves of its own
//! and a flower of both at its tip.
//! It grows on a hidden trunk (gfx/growth.zig): the four corner weaves dig
//! up out of the soil together with it, their roots spreading, and wind
//! inward; the trunk's weave rises from where they meet, the sac swells
//! out of its top, the boughs arch out last, their flowers after them.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");
const growth = @import("../growth.zig");
const pal = @import("palette.zig");
const pk = @import("parasite_kit.zig");
const kit = @import("convergence_kit.zig");

const V3 = m.V3;
const v3 = m.v3;

/// where the corner weaves come up (out from the centre of its 2x2
/// ground), where they meet, and the top of the one weave they become
const CORNER:f32 = 0.62;
const MEET = v3(0, 0.75, 0);
const TOP = v3(0, 1.45, 0);
/// how far round the corner weaves turn as they climb
const TURN:f32 = 0.9 * m.pi;
const CORNER_STALK:pk.Stalk = .{.girth = 0.055, .part = 2.2, .from = 0.38, .to = 0.82, .foot = 0.6};
const TRUNK_STALK:pk.Stalk = .{.girth = 0.11, .part = 2.0, .from = 0.2, .to = 0.78, .foot = 0.2};
/// the sac at its top, where what it holds hangs and what it weaves forms
pub const SAC_R = v3(0.17, 0.2, 0.17);
pub const SAC_AT = TOP + v3(0, SAC_R[1] * 0.85, 0);
const BOUGHS = kit.FOLD;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var k = growth.Skeleton.begin(b);
  // the hidden trunk: up from under the middle of its ground to its top
  const trunk = k.trunk(&.{v3(0, -0.3, 0), v3(0, 0.25, 0), MEET, v3(0.015, 1.1, -0.01), TOP}, .{.pace = 1.4});
  // the corner weaves: each digs up at its corner and winds in to `MEET`
  for (0..4) |i| try corner(b, &k, trunk, i);
  // the one weave, from where they meet to its top
  {
    var sp:[growth.RES]V3 = undefined;
    var ts:[growth.RES]f32 = undefined;
    var sec:[growth.RES]pk.Section = undefined;
    const from = k.nearest(trunk, MEET - v3(0, 0.08, 0));
    k.path(trunk, from, 1, &sp);
    for (&ts, 0..) |*t, j| t.* = m.lerp(0.45, 0.8, m.ratio(j, growth.RES - 1));
    kit.sections(TRUNK_STALK, &sec);
    const mk = b.mark();
    try kit.weave(b, &sp, &ts, &sec, .{.seed = 0x4EA1});
    try k.along(b, mk, trunk);
  }
  const sac = b.mark();
  try kit.sac(b, .{.center = SAC_AT, .radii = SAC_R, .t = 0.85, .arms = 3, .swirl = 1.1, .phase = 2.1});
  try k.on(b, sac, trunk, 1, .{.from = TOP});
  // the boughs, alike: up the sac's flank from its foot, then arching out
  for (0..BOUGHS) |i| {
    const a = (m.f(i) + 0.5) / m.f(BOUGHS) * m.tau;
    var c:[11]V3 = undefined;
    for (c[0..4], 0..) |*q, j| {
      const th = m.lerp(m.pi * 0.9, 0.6, m.ratio(j, 3));
      q.* = SAC_AT + v3(@sin(th) * @cos(a) * SAC_R[0] * 1.1, @cos(th) * SAC_R[1] * 1.1, @sin(th) * @sin(a) * SAC_R[2] * 1.1);
    }
    pk.frondPath(c[3], v3(@cos(a), 0, @sin(a)), 0.7, 0.75, 2.0, 0x4EA2, c[3..]);
    const id = k.branch(trunk, 1, &c, .{.delay = 0.06});
    try k.tube(b, id, .{.r0 = 0.024, .tip = 0.4, .col = kit.lilac, .part = .tendril, .sides = 6, .t0 = 0.8, .t1 = 1});
    try k.leaves(b, id, .{.n = 4, .len = 0.12, .width = 0.04, .from = 0.4, .to = 0.85, .t0 = 0.8, .t1 = 1, .col = kit.leaf_dark, .tip = kit.leaf_lite, .seed = 0x4EA3 +% i * 97});
    const fl = b.mark();
    const tip = k.point(id, 1);
    try kit.bloom(b, .{.heart = tip, .len = 0.09, .spin = a, .petals = 6, .seed = 0x4EA4});
    try k.on(b, fl, id, 1, .{.from = tip});
  }
  // a flower of both crowning the sac
  const crown = b.mark();
  const heart = SAC_AT + v3(0, SAC_R[1] * 1.0, 0);
  try kit.bloom(b, .{.heart = heart, .len = 0.16, .petals = 8, .seed = 0x4EA5});
  try k.on(b, crown, trunk, 1, .{.from = heart, .delay = 0.1});
  k.finish(b);
}

/// corner weave `i`: up out of the soil at its corner (the stretch from
/// under the middle out to it is underground), winding inward as it climbs
/// to meet the others; rooted both ways where it breaks the ground
fn corner(b:*mg.Builder, k:*growth.Skeleton, trunk:growth.Id, i:usize) Allocator.Error!void {
  const a0 = (m.f(i) + 0.5) / 4 * m.tau;
  const foot = v3(@cos(a0) * CORNER, 0, @sin(a0) * CORNER);
  var c:[9]V3 = undefined;
  c[0] = v3(0, -0.3, 0);
  c[1] = foot * m.splat3(0.85) - v3(0, 0.12, 0);
  for (c[2..], 0..) |*q, j| {
    const f = m.ratio(j, 6);
    const a = a0 + TURN * f;
    const r = CORNER * (1 - m.smooth(f));
    q.* = v3(@cos(a) * r, -0.02 + MEET[1] * f, @sin(a) * r);
  }
  const id = k.branch(trunk, 0, &c, .{.after = .with});
  var sp:[growth.RES]V3 = undefined;
  var sec:[growth.RES]pk.Section = undefined;
  try kit.weaveOn(b, k, id, CORNER_STALK, .{.seed = 0x4EB0 +% i * 31}, 0, 0.45, &sp, &sec);
  // its roots, both ways, out of where it breaks the ground
  const u = k.nearest(id, foot);
  const bulb = b.mark();
  try pk.nodule(b, foot + v3(0, 0.01, 0), v3(0.09, 0.045, 0.09), 0, kit.pale, color.mix(kit.pale, pk.core, 0.4), kit.pearl);
  try k.on(b, bulb, id, u, .{.from = foot});
  for (0..3) |j| {
    const ra = a0 + (m.f(j) - 1) * 0.7;
    var rc:[6]V3 = undefined;
    kit.rootPath(foot, ra, 0.05, 0.32, 0.25, 0x4EC0 +% i * 13 +% j, &rc);
    const root = k.branch(id, u, &rc, .{.after = .passing});
    if (j == 1) {
      try k.tube(b, root, .{.r0 = 0.014, .tip = 0.05, .col = kit.pearl, .sides = 5});
    } else {
      try k.braid(b, root, .{.girth = 0.022, .tip = 0.3, .wobble = pal.STRAND_WOBBLE, .seed = 0x4ED0 +% i * 7 +% j, .core = pal.core, .strand = kit.green});
    }
  }
}

/// mesh: VULTRIXI TETHER. the tether from a Vultrixi to its heartloom, built
/// straight up +Y over 0..1 (bent on the GPU along its curve): a green
/// strand and a pale one twined round each other, a violet knot where they
/// cross, as thin at either end as along it (it hangs between two).
pub const tether = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const N = 40;
    const TWISTS:f32 = 9;
    const R:f32 = 0.006;
    for ([_]f32{1, -1}, [_]color.Rgba8{kit.green, kit.pearl}) |way, col| {
      var p:[N]V3 = undefined;
      var ts:[N]f32 = undefined;
      var rs:[N]f32 = undefined;
      for (&p, &ts, &rs, 0..) |*q, *t, *r, j| {
        const f = m.ratio(j, N - 1);
        const a = way * f * TWISTS * m.tau + (if (way > 0) @as(f32, 0) else m.pi);
        q.* = v3(@cos(a) * R, f, @sin(a) * R);
        t.* = f;
        r.* = 0.0032;
      }
      try b.tubeR(&p, &ts, &rs, col, .tendril, 4);
    }
    if (b.lod > 0) return;
    // they cross wherever each has turned a quarter more than a whole half
    // turn (f = (2n + 1) / 4 TWISTS); a knot at every fourth crossing
    var j:u32 = 1;
    while (m.f(j) < 4 * TWISTS) : (j += 8) {
      const f = m.f(j) / (4 * TWISTS);
      try mg.ellipsoid(b, .{.center = v3(0, f, 0), .radii = m.splat3(R * 1.6), .col = kit.knot, .part = .tendril, .rings = 4, .segs = 6, .t = f});
    }
  }
};
