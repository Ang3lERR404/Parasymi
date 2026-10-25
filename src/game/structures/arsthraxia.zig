//! ARSTHRAXIA: the lab, a bloom that studies. It condenses the chosen
//! technology's units of research one at a time: by itself, slowly, and at
//! full pace for each unit whose per-unit ingredients it is fed (eaten as
//! the unit starts).
//!
//! It is seen through by its work, never by bobbing or breathing: idle, it
//! stands still in the wind, its satellite saps fused as one core of sap
//! over its flower. Studying, thought climbs its nerves from the roots in
//! violet pulses (part.vert), its flower's whorls open and turn against
//! each other, the satellites split apart and spin round where the core
//! stood, shedding wisps of energy that condense into a new core there,
//! swelling as the unit condenses; a unit done flares it and sends one
//! surge of light up its nerves.
//! What is learned grows on it: Arsthraxia sends vines climbing its stems;
//! each minor study along it an offshoot out of them (a bough with a
//! flower and a satellite of its own) and another satellite round its core.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const icon_kit = @import("../icon.zig");
const txt = @import("../text.zig");
const prog = @import("../progression.zig");
const style = @import("../style.zig");
const Parts = @import("../parts.zig").Parts;
const Look = @import("../parts.zig").Look;
const mesh = @import("../../gfx/meshes/arsthraxia.zig");
const growth = @import("../../gfx/growth.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const Color = @import("../../ui/draw.zig").Color;

const V3 = m.V3;
const v3 = m.v3;

// decision: drawn by its own `emit` (`bare`), so its look carries what it
// is doing (its nerves' light, a unit's surge) instead of the shared breath
pub const def:st.Def = .{ .item = .arsthraxia, .size = 2, .mesh = .arsthraxia, .preview = .arsthraxia_whole, .store = true, .sway = 0.8, .tall = 2.0, .grow = 8, .bare = true };

/// most of one ingredient it will hold
const STOCK = 20;
/// the satellites round its core from the start; one more per growth
const SATELLITES = 3;
/// offshoots it may grow (one per minor study along Arsthraxia): how high
/// up the stems each leaves them, toward what bearing, how large
const SHOOTS = 3;
const SHOOT_AT = [SHOOTS]f32{0.48, 0.66, 0.8};
const SHOOT_BEARING = [SHOOTS]f32{0.6, 2.85, 4.85};
const SHOOT_SCALE = [SHOOTS]f32{1.3, 1.15, 1.0};
/// seconds an offshoot (or the vines) takes to grow out; its satellites
/// spin this much wider with each offshoot
const SHOOT_GROW:f32 = 6;
const VINES_GROW:f32 = 9;
const REACH_STEP:f32 = 0.1;
/// its core: this high over the ground, bobbing; it forms over the last
/// of its growth, once the flower has opened (`mesh.CORE_FORM`)
const CORE_H:f32 = 2.2;
const CORE_BOB:f32 = 0.08;
const CORE_BOB_RATE:f32 = 1.4;
/// the energy condensing in it: its radius as a unit starts .. as it is done
const CORE_R = [2]f32{0.05, 0.19};
/// its light: as a unit starts .. done, more while fed, a burst at a flare
const CORE_GLOW = [2]f32{0.3, 0.75};
const FED_GLOW:f32 = 0.6;
const FLARE_GLOW:f32 = 1.4;
/// a unit's flare fades out over 1/this seconds (its surge climbs the
/// nerves as it does)
const FLARE_FADE:f32 = 1.6;
/// how quickly it eases into running brighter for a fed unit (per second)
const FED_EASE:f32 = 2;
/// the light it sheds round it (linear), how far
const LIGHT_COL = v3(0.55, 0.32, 1.0);
const LIGHT:f32 = 0.5;
const LIGHT_REACH:f32 = 4.5;
/// its flower while it studies: the whorls turn against each other (rad/s
/// at full study, the inner cup the other way, faster), and the outer one
/// opens, laid flatter and wider
const WHORL_TURN:f32 = 0.35;
const CUP_TURN:f32 = -0.6;
const WHORL_OPEN:f32 = 0.16;
const WHORL_WIDE:f32 = 0.05;
/// the satellites: how far out they spin and how fast (rad/s, a little
/// faster each, so they never fall in step), how their orbits tilt, how
/// fast each turns about itself
const ORBIT_R:f32 = 0.4;
const SPIN_RATE:f32 = 4.8;
const SPIN_SPREAD:f32 = 0.11;
const ORBIT_TILT = [_]f32{0.35, 0.95, 0.6, 1.2, 0.2, 0.8};
const SELF_SPIN:f32 = 7;
/// resting, fused as one core: this far from its heart, this much larger,
/// turning slowly together
const FUSED_R:f32 = 0.075;
const FUSED_SCALE:f32 = 1.9;
const FUSED_TURN:f32 = 0.3;
/// how see-through a satellite's sap is at its thinnest
const SAT_SAP:f32 = 0.55;
/// the wisps: their light, more while fed
const WISP_GLOW:f32 = 1.6;
/// an offshoot's own satellite: this far over its flower, spun this far
/// round it this fast, this large
const TIP_LIFT:f32 = 0.12;
const TIP_ORBIT:f32 = 0.045;
const TIP_SPIN:f32 = 2.2;
const TIP_SCALE:f32 = 0.7;
/// spread round the fused core, as round a sphere
const GOLDEN:f32 = 2.39996;

pub const State = struct {
  lab:prog.Lab = .{},
  /// how far each offshoot has grown out (0..1), and the vines (0..1)
  shoot:[SHOOTS]f32 = @splat(0),
  vines:f32 = 0,
  /// how much wider its satellites spin, grown with its offshoots
  reach:f32 = 1,
  /// a unit just finished: 1, fading to 0
  flare:f32 = 0,
  /// eases toward 1 while the unit under way was fed
  fed:f32 = 0,
  /// how far its flower's outer whorl and inner cup have turned
  turn:[2]f32 = @splat(0),
};

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  const a = &self.state.arsthraxia;
  const study = ctx.g.study();
  if (ctx.g.labTick(&a.lab, self.inv.bag(), study, dt)) a.flare = 1;
  a.flare = @max(0, a.flare - dt * FLARE_FADE);
  a.fed += ((if (a.lab.fed) @as(f32, 1) else 0) - a.fed) * @min(1, dt * FED_EASE);
  // its flower turns while it studies, easing in and out with it
  const busy = m.smooth(self.activity);
  a.turn[0] = @mod(a.turn[0] + dt * WHORL_TURN * busy, m.tau);
  a.turn[1] = @mod(a.turn[1] + dt * CUP_TURN * busy, m.tau);
  // it grows with what is learned along Arsthraxia, an offshoot at a time
  if (study.vines) a.vines = @min(1, a.vines + dt / VINES_GROW);
  var grown:f32 = 0;
  for (&a.shoot, 0..) |*sh, k| {
    sh.* = if (k < study.growth) @min(1, sh.* + dt / SHOOT_GROW) else sh.*;
    grown += m.smooth(sh.*);
  }
  a.reach = 1 + REACH_STEP * grown;
  return a.lab.active;
}

pub fn wants(s:*const st.Structure, g:*const prog.Progression, item:items.Item) u32 {
  const id = g.current orelse return 0;
  for (prog.tree.get(id).per_unit) |ing| {
    if (ing.item == item) return STOCK -| s.inv.count(item);
  }
  return 0;
}

/// where satellite `k` of `n` spins round the core's heart at time `tf`,
/// and which way it is going, both a unit out
fn orbit(k:usize, tf:f32) struct { at:V3, ahead:V3 } {
  const turn = tf * SPIN_RATE * (1 + SPIN_SPREAD * m.f(k)) + m.ratio(k, SATELLITES) * m.tau;
  const plane = m.chain(&.{m.rotY(m.f(k) * GOLDEN), m.rotX(ORBIT_TILT[k % ORBIT_TILT.len])});
  return .{
    .at = m.mulPoint(plane, v3(@cos(turn), 0, @sin(turn))),
    .ahead = m.mulPoint(plane, v3(-@sin(turn), 0, @cos(turn))),
  };
}

/// where satellite `k` rests, fused into one core with the others, a unit out
fn fused(k:usize, tf:f32) V3 {
  const y = 1 - 2 * (m.f(k) + 0.5) / m.f(SATELLITES + SHOOTS);
  const r = @sqrt(@max(0, 1 - y * y));
  const a = m.f(k) * GOLDEN + tf * FUSED_TURN;
  return v3(@cos(a) * r, y, @sin(a) * r);
}

/// a wisp of energy from `from` (going `ahead`) curling into the core at `heart`
fn wisp(out:*Parts, from:V3, ahead:V3, heart:V3, reach:f32, look:Look) Allocator.Error!void {
  const d = heart - from;
  const lag = ahead * m.splat3(-m.len(d) * 0.35);
  const ctrl = [4]V3{from, from + d * m.splat3(0.25) + lag, from + d * m.splat3(0.7) + lag * m.splat3(0.5), heart};
  try out.emitCurve(.arsthraxia_wisp, ctrl, m.norm(m.cross(d, v3(0, 1, 0))), 1, reach, look);
}

/// where offshoot `k` is placed on its mesh as it stands
fn shootAt(base:m.M4, k:usize) m.M4 {
  return m.mul(base, m.chain(&.{m.translate(mesh.stalkAt(SHOOT_AT[k])), m.rotY(SHOOT_BEARING[k]), m.scale3(m.splat3(SHOOT_SCALE[k]))}));
}

/// all of it: its stems, its flower's whorls, what research has grown on
/// it, the satellites and the energy condensing among them; placed on its
/// mesh as it stands (`place`), swaying with it from its root.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  const a = &s.state.arsthraxia;
  const base = s.place(ctr);
  const busy = m.smooth(s.activity);
  const sway:Look = .{.phase = s.seed, .sway = def.sway, .tall = def.tall};
  // its nerves light with its study (glow) and carry a unit's surge (flutter)
  var body = sway;
  body.glow = busy;
  body.flutter = a.flare;
  body.fade = def.sap;
  body.grown = s.grown;
  try out.emit(.arsthraxia, base, body);

  // its flower: the whorls open and turn against each other while it studies
  var flower = body;
  flower.drop = mesh.HEART[1];
  const open = v3(1 + WHORL_WIDE * busy, 1 - WHORL_OPEN * busy, 1 + WHORL_WIDE * busy);
  try out.emit(.arsthraxia_whorl, m.mul(base, m.chain(&.{m.translate(mesh.HEART), m.rotY(a.turn[0]), m.scale3(open)})), flower);
  try out.emit(.arsthraxia_cup, m.mul(base, m.chain(&.{m.translate(mesh.HEART), m.rotY(a.turn[1])})), flower);

  // the vines Arsthraxia sends climbing its stems, by how far they have grown
  if (a.vines > 0) {
    var vines = sway;
    vines.grown = a.vines * s.grown;
    try out.emit(.arsthraxia_vines, base, vines);
  }

  // the offshoots, growing out of the stems with what is learned; thought
  // runs out along their nerves too
  for (a.shoot, 0..) |g, k| {
    if (g <= 0) continue;
    var look = body;
    look.drop = SHOOT_AT[k];
    look.grown = g * s.grown;
    try out.emit(.arsthraxia_shoot, shootAt(base, k), look);
  }

  // the core forms last, once the flower has opened
  const form = growth.formed(mesh.CORE_FORM, s.grown);
  if (form <= 0) return;
  const heart = ctr + v3(0, CORE_H + CORE_BOB * @sin(tf * CORE_BOB_RATE + s.seed * 5), 0);
  // studying, the satellites split apart and spin out round it
  const split = busy;
  const reach = ORBIT_R * a.reach;
  const fed = a.fed;
  var sat = sway;
  sat.fade = SAT_SAP;
  sat.glow = 0.1 + 0.3 * split;
  var thread = sway;
  thread.glow = WISP_GLOW * (1 + FED_GLOW * fed);
  thread.fade = split;
  thread.drop = heart[1] - ctr[1];
  for (0..SATELLITES + SHOOTS) |k| {
    // the later ones come with the offshoots, growing as they do
    const appear = if (k < SATELLITES) 1 else m.smooth(a.shoot[k - SATELLITES]);
    if (appear <= 0) continue;
    const o = orbit(k, tf);
    const at = m.lerpV(heart + fused(k, tf) * m.splat3(FUSED_R * a.reach), heart + o.at * m.splat3(reach), split);
    const r = m.lerp(FUSED_SCALE, 1, split) * a.reach * form * appear;
    sat.drop = at[1] - ctr[1];
    try out.emit(.arsthraxia_satellite, m.chain(&.{m.translate(at), m.rotY(tf * SELF_SPIN + m.f(k)), m.scale3(m.splat3(r))}), sat);
    if (split > 0.02) {
      thread.phase = s.seed + m.f(k) * 0.17;
      try wisp(out, at, o.ahead, heart, split * appear, thread);
    }
  }

  // each offshoot's own satellite, spun slowly over its flower, shedding
  // its wisp into the core too
  const tip = mesh.shootTip();
  for (a.shoot, 0..) |g, k| {
    // (once its flower has opened)
    const grow = growth.formed(mesh.SHOOT_FORM, g);
    if (grow <= 0) continue;
    const turn = tf * TIP_SPIN + m.f(k) * 2.1;
    const over = m.mulPoint(shootAt(base, k), tip.at + tip.axis * m.splat3(TIP_LIFT));
    const at = over + v3(@cos(turn), 0, @sin(turn)) * m.splat3(TIP_ORBIT * a.reach);
    sat.drop = at[1] - ctr[1];
    try out.emit(.arsthraxia_satellite, m.chain(&.{m.translate(at), m.rotY(tf * SELF_SPIN), m.scale3(m.splat3(TIP_SCALE * a.reach * grow * form))}), sat);
    if (split > 0.02) {
      thread.phase = s.seed + 0.5 + m.f(k) * 0.23;
      try wisp(out, at, v3(-@sin(turn), 0, @cos(turn)), heart, split * grow, thread);
    }
  }

  // the energy condensing where the old core stood: swelling as the unit
  // condenses, flaring as it is done and gathering anew
  const dense = m.smooth(m.clamp01(a.lab.t));
  const rad = @max(m.lerp(CORE_R[0], CORE_R[1], dense), CORE_R[1] * a.flare) * a.reach * split * form;
  if (rad <= 1e-3) return;
  const glow = m.lerp(CORE_GLOW[0], CORE_GLOW[1], dense) * (1 + FED_GLOW * fed) + FLARE_GLOW * a.flare;
  var core = sway;
  core.glow = glow;
  core.fade = dense;
  core.flutter = a.flare;
  core.drop = heart[1] - ctr[1];
  try out.emit(.arsthraxia_core, m.chain(&.{m.translate(heart), m.rotY(tf * 0.7), m.scale3(m.splat3(rad))}), core);
  try out.light(heart, LIGHT_COL * m.splat3(LIGHT * glow * split * form), LIGHT_REACH);
}

pub fn describe(s:*const st.Structure, d:*Draw, g:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const id = g.current orelse {
    _ = try d.text(x, y, style.text_body, style.dim, txt.s.describe.choose_study);
    return;
  };
  const r = prog.tree.get(id);
  // how much of the study it adds a minute, at the pace it goes now
  const per_min = s.state.arsthraxia.lab.pace(g, g.study()) * PERCENT * m.S_PER_MIN;
  _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.studies, .{txt.research(id).name, per_min});
  try d.tendril(x + style.desc_bar_x, y + 2, style.desc_bar_w, style.bar_h, style.research_tendril, m.ratio(g.progress.get(id), r.units), 0.3);
}
const PERCENT:f32 = 100;

/// its bulb: a sprout opening into a violet flower, satellites spinning
/// over it round a core of light (it studies).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const top:icon_kit.P = .{0, 0.62};
  const heart:icon_kit.P = .{0, 0.86};
  try ic.stem(.{.{0, icon_kit.TOP}, .{0.12, 0.3}, .{-0.12, 0.5}, top}, 0.11, icon_kit.stem_col);
  try ic.leaf(.{0.04, 0.3}, 0.25, 0.3, 0.17, icon_kit.sprout, 0.9);
  for (0..ICON_PETALS) |i| {
    try ic.leaf(top, m.half_pi + m.tau * m.ratio(i, ICON_PETALS), 0.26, 0.17, icon_petal, 1);
  }
  try ic.glow(heart, 0.3, icon_glow);
  try ic.bud(heart, 0.07, icon_core, 1);
  for (0..ICON_SATELLITES) |i| {
    const a = m.tau * m.ratio(i, ICON_SATELLITES) + 0.4;
    try ic.bud(.{heart[0] + @cos(a) * 0.2, heart[1] + @sin(a) * 0.09}, 0.045, icon_satellite, 0.6);
  }
  try ic.coat(col);
}
const ICON_PETALS = 5;
const ICON_SATELLITES = 3;
const icon_petal:Color = .{200, 150, 255, 255};
const icon_core:Color = .{255, 230, 190, 255};
const icon_satellite:Color = .{255, 190, 90, 255};
const icon_glow:Color = .{190, 140, 255, 90};
