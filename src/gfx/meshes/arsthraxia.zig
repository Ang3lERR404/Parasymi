//! mesh: ARSTHRAXIA. a bloom that studies: three braided stems rise out of
//! a root mat and twine round one another, part into an open cage round a
//! pod of resin threaded on a nerve, and gather again in a calyx under its
//! flower, over which its core of research energy condenses. Down the
//! middle of every stem runs a nerve (part `.nerve`) showing between its
//! strands: thought climbs it while it studies (part.vert).
//! The structure emits the rest, each built here in its own space: the
//! flower's two whorls (`whorl`, `cup`), turning while it studies; the
//! satellite saps (`satellite`), the core (`core`) and the wisps drawn
//! into it (`wisp`); and what research grows on it: the vines climbing its
//! stems (`vines`, Arsthraxia) and its offshoots (`shoot`, the minor
//! studies). `whole` is it at rest with its flower: the placement preview.
//! All grow on hidden growth splines (gfx/growth.zig): the stems with
//! their roots, leaves unfolding up them, the cage's tendrils and pod, the
//! calyx; then (`FORM`) the whorls open, petal after petal, and last
//! (`CORE_FORM`) the core.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const engine = lib.engine;
const m = engine.core.math;
const mg = lib.meshgen;
const pal = lib.palette;
const color = engine.core.color;
const kit = lib.structure_kit;
const growth = lib.growth;

const V3 = m.V3;
const v3 = m.v3;
/// how tall it stands to its flower's heart
pub const HEIGHT:f32 = 1.55;
/// the flower's heart, where its whorls turn
pub const HEART = v3(0, HEIGHT - 0.02, 0);
const STEMS = 3;
const petal_heart = color.rgb(0.30, 0.22, 0.46);
const petal_rim = color.rgb(0.62, 0.5, 0.86);
const stamen = color.rgb(0.8, 0.74, 0.9);
/// a nerve at rest: dark wood with a violet cast
const nerve = color.rgb(0.2, 0.15, 0.24).toRgba8(255);
/// research energy is light: white under the shading's own colours
const energy_white = color.rgb(1, 1, 1).toRgba8(255);
/// the last share of its growth, its stems grown, over which its whorls
/// open (they are emitted, so carry it in their vertices) ...
pub const FORM:f32 = 0.3;
/// ... and the end of it, over which the core and its satellites form
/// (placed by the structure: `growth.formed`)
pub const CORE_FORM:f32 = 0.12;
/// how long a petal of the whorls takes to open, and how much later each
/// opens than the one before (shares of the whole growth)
const PETAL_OPEN:f32 = 0.1;
const WHORL_STAGGER:f32 = 0.005;
/// likewise an offshoot's satellite, over the last of the offshoot's growth
pub const SHOOT_FORM:f32 = 0.3;
/// the stems grow this slowly per unit of their length
const STALK_PACE:f32 = 1.2;
/// how much later each sepal or petal opens than the one before (a share
/// of the skeleton's time)
const PETAL_STAGGER:f32 = 0.025;

/// a stem's course, from the root mat's heart: (height, out from the axis,
/// how far it has wound round it) at each control point. It flares out of
/// the roots, twines tight with the others, parts into the cage and
/// gathers again under the flower.
const STEM_AT = [_][3]f32{
  .{0.0, 0.0, 0.0}, .{0.12, 0.13, 0.15}, .{0.35, 0.085, 0.95}, .{0.6, 0.075, 1.95},
  .{0.84, 0.09, 2.9}, .{1.02, 0.21, 3.45}, .{1.17, 0.26, 3.75}, .{1.32, 0.2, 4.0},
  .{1.44, 0.08, 4.15}, .{HEIGHT - 0.04, 0.02, 4.2},
};
/// where the cage is widest (the resin pod's height), and the pod
const CAGE_Y:f32 = 1.17;
const POD_R = v3(0.1, 0.13, 0.1);
/// where up the stems the foot leaves unfold, and the stems' own leaves
const FOOT_AT:f32 = 0.06;

fn stemAngle(k:usize) f32 { return m.ratio(k, STEMS) * m.tau; }

/// its nerve's tu.x at a height: 0 at its roots .. 1 at its flower
fn nerveAt(y:f32) f32 { return m.clamp01(y / HEIGHT); }

pub fn build(b:*mg.Builder) Allocator.Error!void { try stand(b); }

fn stand(b:*mg.Builder) Allocator.Error!void {
  var sk = growth.Skeleton.begin(b);
  sk.tail = FORM;
  var stems:[STEMS]growth.Id = undefined;
  for (&stems, 0..) |*id, k| id.* = try stem(b, &sk, if (k == 0) null else stems[0], k);
  try kit.rootMat(b, 8, 1.0, 0.075, 0x7B01, .{.k = &sk, .id = stems[0]});
  try kit.footLeaves(b, 7, 0.27, 0.5, 0.18, 0x7B02, .{.k = &sk, .id = stems[0], .u = FOOT_AT});
  for (stems, 0..) |id, k| try tendril(b, &sk, id, k);
  try cage(b, &sk, stems[0]);
  try calyx(b, &sk, stems[0]);
  sk.finish(b);
}

/// stem `k`: a braid of five strands round its nerve along its course
/// (the first is the trunk; the others grow with it from the same root),
/// a few leaves along its twined stretch
fn stem(b:*mg.Builder, sk:*growth.Skeleton, first:?growth.Id, k:usize) Allocator.Error!growth.Id {
  const a0 = stemAngle(k);
  var ctrl:[STEM_AT.len]V3 = undefined;
  for (&ctrl, STEM_AT) |*c, p| c.* = v3(@cos(a0 + p[2]) * p[1], p[0], @sin(a0 + p[2]) * p[1]);
  const top = ctrl[ctrl.len - 1];
  mg.grow(&ctrl, .{.start = ctrl[0], .direction = v3(0, 1, 0), .length = HEIGHT, .wobble = 0.05, .seed = 0x7B10 +% k * 31});
  // it gathers with the others under the flower, where it was laid
  ctrl[ctrl.len - 1] = top;
  const id = if (first) |f| sk.branch(f, 0, &ctrl, .{.after = .with, .pace = STALK_PACE}) else sk.trunk(&ctrl, .{.pace = STALK_PACE});
  const N = growth.RES;
  const path = &sk.get(id).pts;
  var ts:[N]f32 = undefined;
  var rs:[N]f32 = undefined;
  var turn:[N]f32 = undefined;
  for (&ts, &rs, &turn, path, 0..) |*t, *r, *a, p, i| {
    const u = m.ratio(i, N - 1);
    t.* = nerveAt(p[1]);
    r.* = 0.06 * (1 + 0.55 * @exp(-u * 12)) * m.lerp(1, 0.55, u);
    a.* = u * 3.4 + m.f(k);
  }
  const s = b.mark();
  try mg.braidAround(b, path, &ts, &rs, &turn, 5, pal.STRAND_WOBBLE, 0x7B20 +% k * 7, nerve, pal.vine, .nerve);
  try sk.along(b, s, id);
  try sk.leaves(b, id, .{.n = 3, .len = 0.3, .width = 0.1, .from = 0.15, .to = 0.48, .t0 = 0.1, .t1 = 0.5, .col = pal.leaf_dark, .tip = pal.leaf_lite, .seed = 0x7B30 +% k * 11});
  return id;
}

/// off stem `k` where the cage is widest, a tendril reaching out and up,
/// curling at its tip, two leaves along it
fn tendril(b:*mg.Builder, sk:*growth.Skeleton, id:growth.Id, k:usize) Allocator.Error!void {
  const a = stemAngle(k) + STEM_AT[6][2];
  const u = sk.nearest(id, v3(@cos(a) * STEM_AT[6][1], STEM_AT[6][0], @sin(a) * STEM_AT[6][1]));
  const out = v3(@cos(a), 0, @sin(a));
  const side = v3(-out[2], 0, out[0]);
  const t = sk.vine(id, u, .{.start = undefined, .direction = m.norm(out + side * m.splat3(0.4) + v3(0, 0.55, 0)), .length = 0.42, .wobble = 0.15, .curl = 0.45, .seed = 0x7B40 +% k * 13}, 7, .{.after = .passing});
  try sk.tube(b, t, .{.r0 = 0.016, .tip = 0.05, .col = pal.vine, .sides = 5, .t0 = 0.75, .t1 = 0.95});
  try sk.leaves(b, t, .{.n = 2, .len = 0.15, .width = 0.055, .from = 0.2, .to = 0.6, .t0 = 0.75, .t1 = 0.95, .col = pal.leaf_dark, .tip = pal.leaf_lite, .seed = 0x7B48 +% k * 5});
}

/// inside the cage: a nerve rising up its middle from the trunk to the
/// flower's heart, a pod of resin threaded on it where the cage is widest
fn cage(b:*mg.Builder, sk:*growth.Skeleton, trunk:growth.Id) Allocator.Error!void {
  const N = growth.RES;
  const from = sk.nearest(trunk, v3(0, STEM_AT[4][0] - 0.06, 0));
  const id = sk.branch(trunk, from, &.{v3(0, 0, 0), v3(0, 0.95, 0), v3(0, CAGE_Y, 0), v3(0, HEART[1] - 0.03, 0)}, .{.after = .passing});
  const path = &sk.get(id).pts;
  var ts:[N]f32 = undefined;
  var rs:[N]f32 = undefined;
  for (&ts, &rs, path, 0..) |*t, *r, p, i| {
    const u = m.ratio(i, N - 1);
    t.* = nerveAt(p[1]);
    r.* = @max(0.017 * m.pow(f32, @sin(m.pi * u), 0.4), 2e-4);
  }
  const s = b.mark();
  try b.tubeR(path, &ts, &rs, nerve, .nerve, 6);
  try sk.along(b, s, id);
  const at = v3(0, CAGE_Y, 0);
  const p = b.mark();
  try kit.resinPod(b, at, POD_R, 10, 14);
  try sk.on(b, p, id, sk.nearest(id, at), .{.from = at});
}

/// the calyx the stems gather into: sepals cupped up under the flower
fn calyx(b:*mg.Builder, sk:*growth.Skeleton, trunk:growth.Id) Allocator.Error!void {
  const heart = HEART - v3(0, 0.05, 0);
  for (0..5) |i| {
    const a = (m.f(i) + 0.5) / 5 * m.tau;
    const out = v3(@cos(a), 0, @sin(a));
    const s = b.mark();
    try mg.petal(b, .{
      .base = heart + out * m.splat3(0.03), .out = out, .len = 0.26, .width = 0.12,
      .rise = 0.75, .flare = 0.35, .cup = 0.5,
      .col = pal.leaf_dark, .tip = pal.leaf_lite, .t = 1, .part = .leaf,
    });
    try sk.on(b, s, trunk, 1, .{.from = heart, .delay = PETAL_STAGGER * m.f(i)});
  }
}

/// a whorl of `n` petals round the heart (the origin), opening one after
/// another from `first` on over the structure's last `FORM` of growth
fn petals(b:*mg.Builder, n:usize, turn:f32, first:usize, p:mg.Petal) Allocator.Error!void {
  for (0..n) |i| {
    const a = (m.f(i) + turn) / m.f(n) * m.tau;
    var q = p;
    q.out = v3(@cos(a), 0, @sin(a));
    const s = b.mark();
    try mg.petal(b, q);
    try growth.tag(b, s, q.base, .{1 - FORM + WHORL_STAGGER * m.f(first + i), PETAL_OPEN});
  }
}

/// mesh: ARSTHRAXIA WHORL. the flower's broad outer whorl, opening wide
/// round its heart (the origin); it turns slowly while it studies.
pub const whorl = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try petals(b, 9, 0, 0, .{
      .base = v3(0, 0, 0), .out = undefined, .len = 0.62, .width = 0.3, .rise = 0.55, .flare = 0.7, .cup = 0.4,
      .col = petal_heart.toRgba8(255), .tip = petal_rim.toRgba8(255), .t = 1, .part = .leaf,
    });
  }
};

/// mesh: ARSTHRAXIA CUP. the inner whorl cupping the core that condenses
/// over it, stamens arching out of its heart (the origin) beneath it; it
/// turns against the outer whorl while it studies.
pub const cup = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try petals(b, 5, 0.5, 9, .{
      .base = v3(0, 0, 0), .out = undefined, .len = 0.42, .width = 0.22, .rise = 1.15, .flare = 0.4, .cup = 0.4,
      .col = petal_heart.toRgba8(255), .tip = petal_rim.toRgba8(255), .t = 1, .part = .leaf,
    });
    const s = b.mark();
    try mg.stamens(b, .{
      .heart = v3(0, 0, 0), .axis = v3(0, 1, 0), .n = 9, .len = 0.32, .r = 0.009, .anther = 0.055,
      .lean = 0.4, .arch = 0.6, .col = stamen.toRgba8(255), .t = 1, .seed = 0x7B05,
    });
    try growth.tag(b, s, v3(0, 0, 0), .{1 - FORM + WHORL_STAGGER * 14, PETAL_OPEN});
  }
};

/// mesh: ARSTHRAXIA WHOLE. it at rest with its flower, whorls set on its
/// heart: what the gardener sees before putting it down.
pub const whole = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try stand(b);
    const s = b.mark();
    try whorl.build(b);
    try cup.build(b);
    b.xform(s, m.translate(HEART));
  }
};

/// mesh: ARSTHRAXIA VINES. what Arsthraxia's study grows on it: two vines
/// climbing its twined stems from the soil, winding round them, then
/// breaking away under the cage and curling in at their tips, leaves and
/// small tendrils along them. Grown by that study's progress.
pub const vines = struct {
  const N = 2;
  const CLIMB = 11;
  const CTRL = CLIMB + 6;
  /// how many turns they wind round the stems on their way up
  const TURNS:f32 = 1.6;
  const TOP:f32 = 0.86;

  fn ctrl(v:usize, out:*[CTRL]V3) void {
    const a0 = m.ratio(v, N) * m.tau + 0.9;
    for (0..CLIMB) |j| {
      const k = m.ratio(j, CLIMB - 1);
      const y = m.lerp(-0.02, TOP, k);
      // clear of the stems' flared foot, then close round their twine
      const r = 0.175 + 0.13 * @exp(-y * 9);
      const a = a0 + k * TURNS * m.tau;
      out[j] = v3(@cos(a) * r, y, @sin(a) * r);
    }
    const a1 = a0 + TURNS * m.tau;
    const outw = v3(@cos(a1), 0, @sin(a1));
    const up = v3(0, 1, 0);
    const last = out[CLIMB - 1];
    out[CLIMB] = last + outw * m.splat3(0.12) + up * m.splat3(0.08);
    out[CLIMB + 1] = last + outw * m.splat3(0.24) + up * m.splat3(0.2);
    // a crozier rolling in toward the stems
    const c = last + outw * m.splat3(0.3) + up * m.splat3(0.33);
    const rho = [_]f32{0.1, 0.075, 0.052, 0.034};
    for (rho, 0..) |r, j| {
      const th = -0.27 + 1.3 * m.f(j);
      out[CLIMB + 2 + j] = c + (outw * m.splat3(@cos(th)) + up * m.splat3(@sin(th))) * m.splat3(r);
    }
    mg.grow(out, .{.start = out[0], .direction = up, .length = TOP, .wobble = 0.04, .seed = 0x7B50 +% v * 17});
  }

  pub fn build(b:*mg.Builder) Allocator.Error!void {
    var sk = growth.Skeleton.begin(b);
    for (0..N) |v| {
      var c:[CTRL]V3 = undefined;
      ctrl(v, &c);
      const id = sk.trunk(&c, .{.delay = 0.15 * m.f(v)});
      try sk.tube(b, id, .{.r0 = 0.016, .tip = 0.05, .col = pal.vine, .sides = 5, .t0 = 0, .t1 = 0.7});
      try sk.leaves(b, id, .{.n = 8, .len = 0.13, .width = 0.045, .from = 0.1, .to = 0.78, .t0 = 0, .t1 = 0.7, .col = pal.leaf_dark, .tip = pal.leaf_lite, .seed = 0x7B58 +% v * 7});
      // small tendrils off it, curling
      for ([_]f32{0.32, 0.58}, 0..) |u, j| {
        const tan = sk.tangent(id, u);
        const away = m.norm(sk.point(id, u) * v3(1, 0, 1));
        const t = sk.vine(id, u, .{.start = undefined, .direction = m.norm(away + tan * m.splat3(0.5)), .length = 0.13, .wobble = 0.1, .curl = 0.5, .seed = 0x7B60 +% v * 5 +% j}, 5, .{.after = .passing});
        try sk.tube(b, t, .{.r0 = 0.005, .tip = 0.1, .col = pal.vine, .sides = 4, .t0 = 0.3, .t1 = 0.6});
      }
    }
    sk.finish(b);
  }
};

/// mesh: ARSTHRAXIA SATELLITE. a small sap of resin held in two grown vine
/// bands, one of those the old core split into; spun round the core.
pub const satellite = struct {
  pub const R:f32 = 0.075;

  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try kit.resinPod(b, v3(0, 0, 0), v3(R, R, R), 8, 12);
    // two bands wrapping it, pole to pole, crossing
    const arcs = [_][4]f32{ .{0.15, 0.3, 2.99, 2.4}, .{0.2, 3.5, 2.9, 5.6} };
    try mg.bands(b, v3(0, 0, 0), v3(R, R, R), &arcs, 1, 0.008, 0.12, 0x0B5, pal.vine);
  }
};

/// mesh: ARSTHRAXIA CORE. the research energy condensing where the old sap
/// core stood: a ball of light a unit across (tu.x < 0 marks it from a
/// wisp); the structure sizes it by how far the unit has condensed.
pub const core = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(1, 1, 1), .col = energy_white, .part = .energy, .rings = 12, .segs = 18, .t = -1});
  }
};

/// mesh: ARSTHRAXIA WISP. a thread of energy a satellite sheds into the
/// core, running straight up +y over 0..1 (tu.x 0 at the satellite .. 1 at
/// the core); placed along its fall as a curve (part.vert). It closes to a
/// point at both ends.
pub const wisp = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    const N = 20;
    var path:[N]V3 = undefined;
    var ts:[N]f32 = undefined;
    var rs:[N]f32 = undefined;
    for (&path, &ts, &rs, 0..) |*p, *t, *r, i| {
      const k = m.ratio(i, N - 1);
      p.* = v3(0, k, 0);
      t.* = k;
      r.* = @max(0.024 * m.pow(f32, @sin(m.pi * k), 0.5) * (1 - 0.4 * k), 2e-4);
    }
    try b.tubeR(&path, &ts, &rs, energy_white, .energy, 6);
  }
};

/// where an offshoot leaves the stems, `y` up them: on their axis, inside
/// their twine, so it grows out of it
pub fn stalkAt(y:f32) V3 { return v3(0, y, 0); }

/// the control points an offshoot's bough runs through, from where it
/// leaves the stems (the origin) out along +x, rising toward the light
const SHOOT_CTRL = 8;
const SHOOT_LEN:f32 = 0.8;
fn shootCtrl(ctrl:*[SHOOT_CTRL]V3) void {
  const N = SHOOT_CTRL;
  ctrl[0] = v3(0, 0, 0);
  for (1..N) |j| {
    const s = m.ratio(j, N - 1);
    // heading turns from a low rise toward upright, mostly in its outer half
    const h = m.lerp(0.22, 1.25, s * s);
    ctrl[j] = ctrl[j - 1] + v3(@cos(h), @sin(h), 0) * m.splat3(SHOOT_LEN / (N - 1));
  }
  mg.grow(ctrl, .{.start = ctrl[0], .direction = m.norm(ctrl[N - 1]), .length = SHOOT_LEN, .wobble = 0.12, .curl = 0.03, .seed = 0x7B21});
}

/// where an offshoot's flower opens, in its own space, and which way
pub fn shootTip() struct { at:V3, axis:V3 } {
  var c:[SHOOT_CTRL]V3 = undefined;
  shootCtrl(&c);
  var p:[growth.RES]V3 = undefined;
  m.splineResample(&c, &p);
  return .{.at = p[growth.RES - 1], .axis = m.norm(p[growth.RES - 1] - p[growth.RES - 5])};
}

/// mesh: ARSTHRAXIA SHOOT. an offshoot a minor study grows out of the
/// stems: a braided bough round a nerve of its own (thought runs out along
/// it to its flower), leaving along +x and rising, leaves along it, a
/// leafy twig off it and a vine winding round it that breaks away into a
/// curling tendril; it opens into a flower like the crown's, a calyx under
/// it (a satellite of its own hovers over it, emitted, `SHOOT_FORM`). Its
/// root lies inside the stems. It grows along its own growth splines by
/// research's progress.
pub const shoot = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    var sk = growth.Skeleton.begin(b);
    sk.tail = SHOOT_FORM;
    var ctrl:[SHOOT_CTRL]V3 = undefined;
    shootCtrl(&ctrl);
    const bough = sk.trunk(&ctrl, .{});
    try sk.braid(b, bough, .{.girth = 0.045, .tip = 0.5, .strands = 4, .twist = 3, .wobble = pal.STRAND_WOBBLE, .seed = 0x7B70, .core = nerve, .strand = pal.vine, .t0 = 0, .t1 = 1, .core_part = .nerve});
    try sk.leaves(b, bough, .{.n = 4, .len = 0.2, .width = 0.07, .from = 0.25, .to = 0.8, .t0 = 0, .t1 = 1, .col = pal.leaf_dark, .tip = pal.leaf_lite, .seed = 0x7B22});
    // a leafy twig off its back, reaching out and curling
    const twig = sk.vine(bough, 0.5, .{.start = undefined, .direction = m.norm(v3(0.5, 0.6, 0.7)), .length = 0.3, .wobble = 0.15, .curl = 0.3, .seed = 0x7B71}, 6, .{.after = .passing});
    try sk.tube(b, twig, .{.r0 = 0.014, .tip = 0.05, .col = pal.vine, .sides = 5, .t0 = 0.5, .t1 = 0.8});
    try sk.leaves(b, twig, .{.n = 3, .len = 0.12, .width = 0.045, .from = 0.25, .to = 0.85, .t0 = 0.5, .t1 = 0.8, .col = pal.leaf_dark, .tip = pal.leaf_lite, .seed = 0x7B72});
    try winding(b, &sk, bough);
    try flower(b, &sk, bough);
    sk.finish(b);
  }

  /// a vine winding round the bough as it grows, then breaking away up
  /// into a curling tendril, small leaves along it
  fn winding(b:*mg.Builder, sk:*growth.Skeleton, bough:growth.Id) Allocator.Error!void {
    const W = 10;
    const pts = &sk.get(bough).pts;
    var nrm:[growth.RES]V3 = undefined;
    var bin:[growth.RES]V3 = undefined;
    mg.transport(pts, &nrm, &bin);
    var c:[W + 3]V3 = undefined;
    for (0..W) |j| {
      const k = m.ratio(j, W - 1);
      const u = m.lerp(0.06, 0.66, k);
      const i:usize = @intFromFloat(@round(u * (growth.RES - 1)));
      const a = k * 2.2 * m.tau;
      // round the bough's strands, wound closer as it thins
      const r = 0.045 * m.lerp(1, 0.5, u) * 1.12 + 0.012;
      c[j] = pts[i] + (nrm[i] * m.splat3(@cos(a)) + bin[i] * m.splat3(@sin(a))) * m.splat3(r);
    }
    const last = c[W - 1];
    const off = m.norm(last - m.alongPath(pts, 0.66));
    c[W] = last + off * m.splat3(0.06) + v3(0, 0.06, 0);
    c[W + 1] = last + off * m.splat3(0.1) + v3(0, 0.15, 0);
    c[W + 2] = last + off * m.splat3(0.06) + v3(0, 0.2, 0);
    const id = sk.branch(bough, 0.06, &c, .{.after = .passing});
    try sk.tube(b, id, .{.r0 = 0.009, .tip = 0.08, .col = pal.vine, .sides = 4, .t0 = 0.1, .t1 = 0.7});
    try sk.leaves(b, id, .{.n = 4, .len = 0.08, .width = 0.03, .from = 0.15, .to = 0.7, .t0 = 0.1, .t1 = 0.7, .col = pal.leaf_dark, .tip = pal.leaf_lite, .seed = 0x7B73});
  }

  /// its flower at the bough's tip: a calyx, a whorl of petals, stamens
  fn flower(b:*mg.Builder, sk:*growth.Skeleton, bough:growth.Id) Allocator.Error!void {
    const tip = shootTip();
    for (0..5) |i| {
      const a = (m.f(i) + 0.5) / 5 * m.tau;
      const s = b.mark();
      try mg.petal(b, .{
        .base = tip.at - tip.axis * m.splat3(0.02), .out = v3(@cos(a), 0, @sin(a)),
        .len = 0.1, .width = 0.05, .rise = 0.6, .flare = 0.3, .cup = 0.5,
        .col = pal.leaf_dark, .tip = pal.leaf_lite, .t = 1, .part = .leaf,
      });
      try sk.on(b, s, bough, 1, .{.from = tip.at, .delay = PETAL_STAGGER * 0.5 * m.f(i)});
    }
    for (0..7) |i| {
      const a = m.ratio(i, 7) * m.tau;
      const p = b.mark();
      try mg.petal(b, .{
        .base = tip.at, .out = v3(@cos(a), 0, @sin(a)),
        .len = 0.2, .width = 0.1, .rise = 0.9, .flare = 0.6, .cup = 0.4,
        .col = petal_heart.toRgba8(255), .tip = petal_rim.toRgba8(255), .t = 1, .part = .leaf,
      });
      try sk.on(b, p, bough, 1, .{.from = tip.at, .delay = PETAL_STAGGER * (2.5 + 0.5 * m.f(i))});
    }
    const st = b.mark();
    try mg.stamens(b, .{
      .heart = tip.at, .axis = tip.axis, .n = 6, .len = 0.11, .r = 0.004, .anther = 0.022,
      .lean = 0.35, .arch = 0.5, .col = stamen.toRgba8(255), .t = 1, .seed = 0x7B23,
    });
    try sk.on(b, st, bough, 1, .{.from = tip.at, .delay = PETAL_STAGGER * 6.5});
  }
};
