//! what gets drawn: turns the game state into a render Scene (plant
//! instances, rigid parts, HUD, sky/fog/light push constants). Read-only with
//! respect to the simulation.
const std = @import("std");
const Allocator = std.mem.Allocator;
const pdq = std.sort.pdq;
const swap = std.mem.swap;
const m = @import("../core/math.zig");
const rng = @import("../core/rng.zig");
const ck = @import("../world/chunk.zig");
const species = @import("../sim/species.zig");
const turn = @import("../sim/turn.zig");
const renderer = @import("../render/renderer.zig");
const meshgen = @import("../gfx/meshgen.zig");
const vertex = @import("../gfx/vertex.zig");
const st = @import("structures.zig");
const halo_mod = @import("structures/halo.zig");

const resources = @import("resources.zig");
const actions = @import("actions.zig");
const hud = @import("hud.zig");
const play = @import("play.zig");

const Game = play.Game;
const gen = @import("../world/gen.zig");

/// shader time wraps this often (s) so f32 keeps its precision
const TIME_WRAP:f64 = 3600;
/// no hovered tile: a position far off any tile
const NO_HOVER:f32 = 1e9;
/// no wolf: its paws' contact shadows far off any tile
const NO_FEET = [2]m.V3{ m.splat3(NO_HOVER), m.splat3(NO_HOVER) };
/// fog thickens over this many chunks' eighths past the camera distance
const FOG_REACH:f32 = 32 * ck.SIZE / 8;
/// fog starts to close in at this share of the drawn reach
const FOG_NEAR:f32 = 0.7;
/// a plant's bounding sphere: this much plus its footprint, centred this
/// share of the way up
const PLANT_BOUND:f32 = 1.2;
const PLANT_BOUND_UP:f32 = 0.6;
/// floaters: bob amplitudes and rates, drift about the tile, and a shadow
/// that shrinks as they rise
const BOB = [2]f32{ 0.07, 0.025 };
const BOB_RATE = [2]f32{ 0.5, 1.13 };
const DRIFT:f32 = 0.05;
const DRIFT_RATE = [2]f32{ 0.31, 0.27 };
const SHADOW_R:f32 = 0.42;
const SHADOW_SHRINK:f32 = 0.6;
const SHADOW_LIFT:f32 = 0.03;
const SHADOW_FADE:f32 = 0.6;
/// beams: how far they bow, and the last share of growth they reach out over
const BEAM_SAG:f32 = 0.03;
const BEAM_SAG_RATE:f32 = 0.4;
const BEAM_FROM:f32 = 0.85;
const BEAM_DIM:f32 = 0.1;
/// structures breathe at one tempo, deeper with activity, and glow with it
const BREATH_RATE:f32 = 1.6;
const BREATH:f32 = 0.02;
const BREATH_ACTIVE:f32 = 0.04;
const GLOW:f32 = 0.25;
const GLOW_ACTIVE:f32 = 1.1;
/// how much a standing structure's leaves flutter
const FLUTTER:f32 = 0.6;
/// placement preview: fixed plant seed, structure lift and shrink, tints,
/// pulse
const GHOST_SEED:f32 = 0.37;
const GHOST_LIFT:f32 = 0.02;
const GHOST_SCALE:f32 = 0.96;
const GHOST_FITS = [4]f32{ 0.6, 1.4, 0.8, 0.7 };
const GHOST_BLOCKED = [4]f32{ 1.6, 0.4, 0.4, 0.8 };
const GHOST_PULSE_RATE:f32 = 5;
/// a structure ghost's glow pulses about `GHOST_GLOW`, by `GHOST_PULSE`
const GHOST_GLOW:f32 = 0.6;
const GHOST_PULSE:f32 = 0.4;
/// resource nodes shrink to `NODE_MIN` of full size as they empty
const NODE_MIN:f32 = 0.55;
/// star motes: size, and echoes trailing a falling one
const MOTE_SIZE:f32 = 1.8;
const ECHOES = 3;
const ECHO_SIZE:f32 = 1.2;
/// points of light. A celestial bloom: how far its light reaches, how
/// strong it is (a dark network's a share of it), how high over its float
/// its core is, how much of its pearl's film tints it, and its slow pulse
const BLOOM_REACH:f32 = 9;
const BLOOM_LIGHT:f32 = 3.5;
const BLOOM_DARK:f32 = 0.2;
const BLOOM_CORE:f32 = 0.35;
const BLOOM_FILM:f32 = 0.35;
const BLOOM_PULSE:f32 = 0.15;
const BLOOM_PULSE_RATE:f32 = 1.1;
/// a bloom sheds light only once it has assembled this far
const BLOOM_LIT_FROM:f32 = 0.6;
/// a star mote: its reach, strength and colour (linear)
const MOTE_REACH:f32 = 3.2;
const MOTE_LIGHT:f32 = 0.9;
const MOTE_COL = m.V3{ 1.0, 0.86, 0.62 };
/// a glowing resource node (ley shards): its reach and strength, and colour
const NODE_REACH:f32 = 2.6;
const NODE_LIGHT:f32 = 0.45;
const NODE_COL = m.V3{ 0.5, 0.3, 1.0 };
/// and how high over its tile the light sits
const NODE_LIFT:f32 = 0.3;
/// turning (R, sim/turn.zig): how high a rooted thing heaves itself up on
/// its roots (plus this much a tile of its size); its roots (this many a
/// tile of its size, at least `ROOTS_MIN`): where they leave its foot and
/// how far out they dig in (shares of its size), how deep their tips lie,
/// how high they arch while out, how high their tips step as it turns
/// round on them and how many steps it takes, and how they flutter
const HEAVE:f32 = 0.16;
const HEAVE_PER:f32 = 0.12;
const ROOTS_PER:f32 = 3;
const ROOTS_MIN:f32 = 4;
const ROOT_FOOT:f32 = 0.14;
const ROOT_REACH:f32 = 0.5;
const ROOT_DEEP:f32 = 0.35;
const ROOT_ARCH:f32 = 0.22;
const ROOT_STEP:f32 = 0.1;
const ROOT_STEPS:f32 = 3;
const ROOT_FLUTTER:f32 = 0.35;

pub fn scene(g:*Game, screen:[2]f32) Allocator.Error!renderer.Scene {
  const reach = g.cam.reach(play.DRAW_LIMIT);
  const tf:f32 = @floatCast(@mod(g.time, TIME_WRAP));

  // parts first: plants add parts of their own (shadows under floaters).
  // Everything is culled to what the camera sees and drawn at the level of
  // detail its distance from the eye calls for.
  g.parts.clear();
  g.parts.look(g.cam.viewEye(), m.Frustum.of(g.cam.viewProj()), g.sky.lightDir());
  try plants(g, reach, tf);
  try threads(g, tf);
  // a specimen stands alone: no wolf, ghosts or motes, and a plant no
  // nodes or structures (their meshes were never built)
  const alone = g.specimen != null;
  const feet = if (alone) NO_FEET else try g.player.rig(&g.parts);
  if (!alone or g.specimen.?.what == .structure) {
    try nodes(g, @intFromFloat(reach));
    try structures(g, reach, tf);
  }
  if (!alone) {
    try ghost(g, tf);
    try motes(g);
  }
  rankLights(g);
  try hud.build(g, screen);

  const veil = g.prog.veil;
  const sky = g.sky.color(veil);
  const eye = g.cam.viewEye();
  const hv:[2]f32 = if (g.hover) |h| .{m.f(h[0]), m.f(h[1])} else .{NO_HOVER, NO_HOVER};
  const ld = g.sky.lightDir();
  var out:renderer.Scene = .{
    .push = .{
      .vp = g.cam.viewProj(),
      .eye_time = .{eye[0], eye[1], eye[2], tf},
      .fog = .{sky[0], sky[1], sky[2], 1.0 / (FOG_REACH + g.cam.dist)},
      .misc = .{veil, if (g.prog.done.contains(.ley_sight)) 1 else 0, hv[0], hv[1]},
      .sun = .{ld[0], ld[1], ld[2], g.sky.daylight()},
      .view = .{g.cam.target[0], g.cam.target[2], reach * FOG_NEAR, reach},
      .feet = .{
        .{feet[0][0], feet[0][1], feet[0][2], g.player.facing},
        .{feet[1][0], feet[1][1], feet[1][2], g.player.facing},
      },
    },
    .clear = sky,
    .instances = undefined,
    .parts = g.parts.slices(),
    .bones = g.parts.bones.items,
    .lights = g.parts.lights.items,
    .ui = g.ui.v.items,
    .ui_time = @floatCast(@mod(g.ui_time, TIME_WRAP)),
  };
  for (&out.instances, g.inst) |*o, l| o.* = l.items;
  return out;
}

/// plant instances near the camera, grouped by mesh: each plant's variant
/// comes from its tile, so it always regrows the same shape.
fn plants(g:*Game, reach:f32, tf:f32) Allocator.Error!void {
  for (&g.inst) |*l| l.clearRetainingCapacity();
  const s = g.plants.list.slice();
  const radiating = g.eco.radiance.radiating.items;
  for (0..g.plants.len()) |i| {
    const ctr = g.plants.centre(i);
    if (@abs(ctr[0] - g.cam.target[0]) > reach or @abs(ctr[1] - g.cam.target[2]) > reach) continue;
    try plant(g, .{
      .sp = s.items(.sp)[i], .x = s.items(.x)[i], .y = s.items(.y)[i], .ground = s.items(.chunk)[i].height[s.items(.tile)[i]],
      .growth = s.items(.growth)[i], .mana = s.items(.mana)[i], .seed = s.items(.seed)[i],
      .flow = s.items(.flow)[i], .health = s.items(.health)[i],
      .dir = s.items(.dir)[i], .turn = s.items(.turn)[i],
      // (worked out each tick: a plant sown since has none yet)
      .radiating = i < radiating.len and radiating[i],
    }, tf);
  }
}

/// a thin film's hue as the shaders take it (common.glsl `filmHue`): one
/// turn of the rainbow per unit of `x`
fn filmHue(x:f32) m.V3 {
  return .{
    0.5 + 0.5 * @cos(m.tau * x),
    0.5 + 0.5 * @cos(m.tau * (0.33 + x)),
    0.5 + 0.5 * @cos(m.tau * (0.67 + x)),
  };
}



/// the most telling points of light first, the rest dropped: the renderer
/// takes `renderer.MAX_LIGHTS` (strong, far reaching lights near what the
/// camera looks at win)
fn rankLights(g:*Game) void {
  const ls = g.parts.lights.items;
  if (ls.len <= renderer.MAX_LIGHTS) return;
  const Rank = struct {
    focus:m.V3,
    fn score(ctx:@This(), l:vertex.Light) f32 {
      const d = m.v3(l.pos[0], l.pos[1], l.pos[2]) - ctx.focus;
      const strength = @max(l.col[0], @max(l.col[1], l.col[2]));
      return strength * l.pos[3] * l.pos[3] / (1 + m.dot(d, d));
    }
    fn before(ctx:@This(), a:vertex.Light, b:vertex.Light) bool { return score(ctx, a) > score(ctx, b); }
  };
  pdq(vertex.Light, ls, Rank{ .focus = g.cam.target }, Rank.before);
  g.parts.lights.shrinkRetainingCapacity(renderer.MAX_LIGHTS);
}

/// where a floater hangs this frame: its hover height with a slow rise and
/// fall, and a lazy drift about its tile.
fn floatAt(def:*const species.Species, x:i32, y:i32, ground:f32, seed:f32, tf:f32) m.V3 {
  const c = m.footprintCentre(x, y, def.size, 0);
  const lift = BOB[0] * @sin(tf * BOB_RATE[0] + seed * 10) + BOB[1] * @sin(tf * BOB_RATE[1] + seed * 4);
  return m.v3(c[0] + DRIFT * @sin(tf * DRIFT_RATE[0] + seed * 7), @max(ground, 0) + def.hover + lift, c[2] + DRIFT * @cos(tf * DRIFT_RATE[1] + seed * 5));
}

/// the forming halo drawing in the bloom at a tile, as the shaders take it
/// (vertex.NO_HALO for none): they spiral it in (common.glsl `haloSpiral`).
fn haloOf(g:*const Game, def:*const species.Species, x:i32, y:i32) [4]f32 {
  if (def.radiance <= 0) return vertex.NO_HALO;
  const hd = st.hold(&g.structs, x, y) orelse return vertex.NO_HALO;
  const to = structCentre(g, hd.s) + m.v3(0, hd.h.seat, 0);
  return .{ to[0], to[1], to[2], hd.h.k };
}

/// the threads of light between linked blooms (see ecology `Radiance`):
/// bent on the GPU from one bloom's core to the other's with a slight sag,
/// bright where their network radiates, faint where it is dark. A thread
/// reaches out from the more grown bloom as that bloom finishes assembling.
/// A forming halo draws its blooms in, and the GPU bends the threads from
/// them along (`Look.ends`).
fn threads(g:*Game, tf:f32) Allocator.Error!void {
  const s = g.plants.list.slice();
  for (g.eco.radiance.links.items) |l| {
    var ia = l.a.idx();
    var ib = l.b.idx();
    // links are worked out each tick; an uproot since then leaves a stale one
    if (ia >= g.plants.len() or ib >= g.plants.len()) continue;
    if (species.get(s.items(.sp)[ia]).radiance <= 0 or species.get(s.items(.sp)[ib]).radiance <= 0) continue;
    if (s.items(.growth)[ib] > s.items(.growth)[ia]) swap(usize, &ia, &ib);
    const pos = [2]m.V3{ end(g, ia, tf), end(g, ib, tf) };
    const span = pos[1] - pos[0];
    // a beam runs true, bowing only a breath as the blooms drift
    const sag = m.v3(0, BEAM_SAG * @sin(tf * BEAM_SAG_RATE + m.f(ia)), 0);
    const ctrl = [4]m.V3{ pos[0], pos[0] + span * m.splat3(1.0 / 3.0) + sag, pos[0] + span * m.splat3(2.0 / 3.0) + sag, pos[1] };
    const side = m.norm(m.cross(span, m.v3(0, 1, 0)));
    const reach = m.smooth(m.clamp01((s.items(.growth)[ia] - BEAM_FROM) / (1 - BEAM_FROM)));
    if (reach <= 0) continue;
    // decision: one halo per beam; a beam between two halos' blooms (never
    // at once in practice) follows the first
    const ha = haloOf(g, species.get(s.items(.sp)[ia]), s.items(.x)[ia], s.items(.y)[ia]);
    const hb = haloOf(g, species.get(s.items(.sp)[ib]), s.items(.x)[ib], s.items(.y)[ib]);
    const ends:f32 = (if (ha[3] >= 0) @as(f32, 1) else 0) + (if (hb[3] >= 0) @as(f32, 2) else 0);
    try g.parts.emitCurve(.bloom_thread, ctrl, side, 1, reach, .{
      .glow = if (l.live) 1 else BEAM_DIM, .phase = s.items(.seed)[ia],
      .halo = if (ha[3] >= 0) ha else hb, .ends = ends,
    });
  }
}

/// a bloom's core this frame (over its tile; a forming halo moves it on the GPU)
fn end(g:*Game, i:usize, tf:f32) m.V3 {
  const s = g.plants.list.slice();
  const def = species.get(s.items(.sp)[i]);
  return floatAt(def, s.items(.x)[i], s.items(.y)[i], s.items(.chunk)[i].height[s.items(.tile)[i]], s.items(.seed)[i], tf);
}

/// what drawing one plant needs to know about it.
const Drawn = struct {
  sp:species.Id, x:i32, y:i32, ground:f32,
  growth:f32, mana:f32 = 0, seed:f32, flow:f32 = 0, health:f32 = 1,
  /// a placement preview, and whether it fits
  ghost:bool = false, fits:bool = true,
  /// a celestial bloom: whether its network radiates (it shines in full)
  radiating:bool = false,
  /// the way it faces, and how it got there (R)
  dir:m.Dir = 0,
  turn:turn.Turn = .{},
};

fn plant(g:*Game, d:Drawn, tf:f32) Allocator.Error!void {
  const def = species.get(d.sp);
  const foot = m.footprintCentre(d.x, d.y, def.size, d.ground);
  const reach = PLANT_BOUND + m.f(def.size);
  if (!g.parts.sees(foot + m.v3(0, reach * PLANT_BOUND_UP, 0), reach)) return;
  const lod = meshgen.lodAt(m.len(foot - g.parts.eye));
  var at = m.footprintCentre(d.x, d.y, def.size, 0);
  var y = d.ground;
  const halo = if (d.ghost) vertex.NO_HALO else haloOf(g, def, d.x, d.y);
  // turning, a rooted one heaves itself up on its roots; a floater only turns
  const pose = turn.pose(d.turn, d.dir, g.time, !def.floating);
  if (!pose.still() and !def.floating) {
    const size = m.f(def.size);
    y += heave(size) * pose.lift;
    try roots(g, m.footprintCentre(d.x, d.y, def.size, d.ground), size, m.dirYaw(d.dir) + pose.spin, pose, d.seed, def.lineage.affinity() < -0.5);
  }
  if (def.floating) {
    // floaters hang in the air: a slow rise and fall and a lazy drift,
    // never a bounce, over a soft shadow that shrinks as they rise (and
    // follows one a halo draws in, fading as it folds)
    const ground = @max(y, 0);
    at = floatAt(def, d.x, d.y, d.ground, d.seed, tf);
    y = at[1];
    const r = SHADOW_R - SHADOW_SHRINK * (at[1] - ground - def.hover);
    if (!d.ghost) try g.parts.emit(.shadow, m.chain(&.{m.translate(m.v3(at[0], ground + SHADOW_LIFT, at[2])), m.scale3(m.v3(r, 1, r))}), .{.fade = SHADOW_FADE, .halo = halo});
  }
  // a confluence grows through its keys, blending from one to the next;
  // other plants pick a shape by tile
  const key = meshgen.growthKey(d.sp, d.growth) orelse meshgen.Key{
    .v = @intCast(rng.hash2(0x7A11, d.x, d.y) % meshgen.VARIANTS), .f = 0,
  };
  try g.inst[meshgen.plantSlot(d.sp, key.v, lod)].append(g.gpa, .{
    .pos = .{at[0], y, at[2]},
    .a = .{d.growth, d.mana / def.mana_cap, d.seed, def.lineage.affinity()},
    .b = .{d.flow, d.health, def.sway, m.f(@intFromEnum(def.genome.form))},
    .c = .{key.f, if (d.ghost) 1 else 0, if (d.fits) 1 else 0, m.dirYaw(d.dir) + pose.spin},
    .h = halo,
  });
  // a celestial bloom is the garden's light: its core sheds it round
  // about, pearl tinted by its film, pulsing slowly, brighter as it
  // assembles (a dark network's only faintly), following it as a forming
  // halo draws it in and dimming as it folds
  if (def.radiance > 0 and !d.ghost) {
    const assembled = m.smooth(m.clamp01((d.growth - BLOOM_LIT_FROM) / (1 - BLOOM_LIT_FROM)));
    const drawn = halo_mod.spiral(m.v3(at[0], y + BLOOM_CORE, at[2]), halo);
    const pulse = 1 + BLOOM_PULSE * @sin(tf * BLOOM_PULSE_RATE + d.seed * m.tau);
    const strength = BLOOM_LIGHT * assembled * d.health * drawn.open * pulse * (if (d.radiating) @as(f32, 1) else BLOOM_DARK);
    if (strength > 0) {
      const tint = m.lerpV(m.v3(1, 1, 1), filmHue(d.seed * 3 + tf * 0.03), BLOOM_FILM);
      try g.parts.light(drawn.at, tint * m.splat3(strength), BLOOM_REACH);
    }
  }
}

fn structCentre(g:*const Game, s:*const st.Structure) m.V3 {
  return m.footprintCentre(s.x, s.y, s.def().size, g.heightAt(s.x, s.y));
}

/// structures breathe and glow with their activity; each kind adds its own
/// extras through its `emit` hook.
fn structures(g:*Game, reach:f32, tf:f32) Allocator.Error!void {
  for (g.structs.list.items) |*s| {
    const ctr = structCentre(g, s);
    if (@abs(ctr[0] - g.cam.target[0]) > reach or @abs(ctr[2] - g.cam.target[2]) > reach) {
      // what it sends far off is drawn wherever it is (each piece culled
      // to the view on its own)
      if (s.def().far) try st.emit(s, &g.parts, ctr, tf);
      continue;
    }
    const a = s.activity;
    // a fixed tempo: activity deepens the breath but never retimes it (a
    // tempo that followed activity jumped phase every time it changed)
    const breathe = if (s.def().still) 1 else 1 + (BREATH + BREATH_ACTIVE * a) * @sin(tf * BREATH_RATE + s.seed * 9);
    // turning, all it draws is carried with its body: lifted on its roots,
    // rocking, turned the rest of the way
    const rooted = !s.def().floating;
    const pose = turn.pose(s.turn, s.dir, g.time, rooted);
    if (!pose.still()) g.parts.around = m.chain(&.{
      m.translate(ctr + m.v3(0, heave(m.f(s.def().size)) * pose.lift, 0)),
      m.rotY(pose.spin), m.rotX(pose.rock[0]), m.rotZ(pose.rock[1]), m.translate(-ctr),
    });
    defer g.parts.around = null;
    if (!s.def().bare) try g.parts.emit(s.def().mesh, m.mul(s.place(ctr), m.scale3(m.v3(breathe, 2 - breathe, breathe))), .{
      .glow = GLOW + GLOW_ACTIVE * a, .flutter = FLUTTER, .phase = s.seed, .fade = s.def().sap,
      .sway = s.def().sway, .tall = s.def().tall, .grown = s.grown,
    });
    try st.emit(s, &g.parts, ctr, tf);
    g.parts.around = null;
    if (rooted and !pose.still()) try roots(g, ctr, m.f(s.def().size), m.dirYaw(s.dir) + pose.spin, pose, s.seed, s.def().pale);
  }
}

/// how high a rooted thing `size` tiles across heaves itself as it turns
fn heave(size:f32) f32 { return HEAVE + HEAVE_PER * size; }

/// the roots a rooted thing turns on (R), round its foot at `ctr` (on the
/// ground), `size` tiles across, facing `yaw` this moment: at rest all in
/// the soil; pulled out, they arch from under its lifted body to tips
/// laid on the ground round it, which step as it turns round on them,
/// then dig back in where it now faces
fn roots(g:*Game, ctr:m.V3, size:f32, yaw:f32, p:turn.Pose, seed:f32, pale:bool) Allocator.Error!void {
  if (p.out <= 0) return;
  const n = m.floorTo(u32, @max(ROOTS_MIN, ROOTS_PER * size));
  const foot_y = heave(size) * p.lift;
  for (0..n) |i| {
    const h = rng.unit(rng.hash2(0x7007, @intCast(i), m.floorTo(i32, seed * 1000)));
    const a = yaw + (m.f(i) + 0.4 * h) / m.f(n) * m.tau;
    const out = m.v3(@cos(a), 0, @sin(a));
    const foot = ctr + out * m.splat3(ROOT_FOOT * size) + m.v3(0, foot_y + 0.04, 0);
    const reach = ROOT_REACH * size * (0.85 + 0.3 * h);
    const sunk = ctr + out * m.splat3(reach) - m.v3(0, ROOT_DEEP * size, 0);
    // a tip steps (lifts and comes down again) as the body turns on it,
    // neighbours out of step
    const step = ROOT_STEP * size * p.lift * @max(@sin(p.k * ROOT_STEPS * m.tau + m.f(i) * 2.4), 0);
    const laid = ctr + out * m.splat3(reach * 1.1) + m.v3(0, 0.03 + step, 0);
    const tip = m.lerpV(sunk, laid, p.out);
    const arch = m.v3(0, ROOT_ARCH * size * p.out, 0);
    const ctrl = [4]m.V3{foot, m.lerpV(foot, tip, 0.33) + arch, m.lerpV(foot, tip, 0.7) + arch * m.splat3(0.6), tip};
    const side = m.norm(m.cross(tip - foot, m.v3(0, 1, 0)));
    try g.parts.emitCurve(if (pale) .turn_root_pale else .turn_root, ctrl, side, 1, 1, .{.flutter = ROOT_FLUTTER, .phase = seed + m.f(i) * 0.13});
  }
}

/// a tinted, pulsing preview of what is about to be sown or grown: the
/// plant as it will look grown (the same shape its tile will give it), or
/// the structure.
fn ghost(g:*Game, tf:f32) Allocator.Error!void {
  const h = g.hover orelse return;
  if (g.mode != .roam) return;
  const item = g.selected() orelse return;
  if (!play.known(g, item)) return;
  const ok = actions.canPut(g, h) and g.player.inReach(h[0], h[1]) and g.player.inv.count(item) > 0;
  if (item.plants()) |sp| {
    // a fixed seed so the preview does not spin about as the cursor moves
    return plant(g, .{.sp = sp, .x = h[0], .y = h[1], .ground = g.heightAt(h[0], h[1]), .growth = 1, .seed = GHOST_SEED, .ghost = true, .fits = ok, .dir = g.place_dir}, tf);
  }
  const k = st.kindOf(item) orelse return;
  const def = st.defs.get(k);
  // (a floating one where it will hang)
  const ctr = m.footprintCentre(h[0], h[1], def.size, g.heightAt(h[0], h[1]) + GHOST_LIFT + def.hover);
  const tint = if (ok) GHOST_FITS else GHOST_BLOCKED;
  try g.parts.emit(def.preview orelse def.mesh, m.chain(&.{m.translate(ctr), m.rotY(m.dirYaw(g.place_dir)), m.scale3(m.splat3(GHOST_SCALE))}), .{.glow = GHOST_GLOW + GHOST_PULSE * @sin(tf * GHOST_PULSE_RATE), .tint = tint, .ghost = true});
}

/// resource nodes within `nr` tiles of the camera focus.
fn nodes(g:*Game, nr:i32) Allocator.Error!void {
  const cx, const cz = m.tileAt(g.cam.target);
  const lo = ck.Coord.ofTile(cx - nr, cz - nr);
  const hi = ck.Coord.ofTile(cx + nr, cz + nr);
  var cy = lo.y;
  while (cy <= hi.y) : (cy += 1) {
    var cxx = lo.x;
    while (cxx <= hi.x) : (cxx += 1) {
      const c = g.world.get(.{.x = cxx, .y = cy}) orelse continue;
      for (0..ck.N) |t| {
        if (c.res[t] == 0) continue;
        const node = resources.of(c.kind[t]) orelse continue;
        const wx, const wz = c.tileOf(t);
        const hsh = rng.unit(rng.hash2(0xD0D, wx, wz));
        const sc = NODE_MIN + (1 - NODE_MIN) * m.f(c.res[t]) / gen.RES_FULL;
        try g.parts.emit(node.mesh, m.chain(&.{
          m.translate(m.tileCentre(wx, wz, c.height[t])),
          m.rotY(hsh * m.tau), m.scale3(m.splat3(sc)),
        }), .{.glow = node.glow, .phase = hsh, .sway = node.sway, .tall = node.tall * sc});
        // a glowing node (ley shards) lights the ground round it
        if (node.glow > 0) try g.parts.light(m.tileCentre(wx, wz, c.height[t] + NODE_LIFT), NODE_COL * m.splat3(NODE_LIGHT * node.glow * sc), NODE_REACH);
      }
    }
  }
}

/// fallen starlight: each mote turns slowly and twinkles, hovering with a
/// slow breath over the ground; while it falls, fading echoes of it trail
/// above, a streak of light.
fn motes(g:*Game) Allocator.Error!void {
  for (g.stars.motes.items) |mo| {
    const fade = m.clamp01(mo.life);
    try g.parts.emitMote(mo.pos, mo.phase, fade, if (mo.falling) 0 else -1, MOTE_SIZE * fade);
    // a mote is a spark of starlight: it lights what it falls past and the
    // ground it rests over
    try g.parts.light(mo.pos, MOTE_COL * m.splat3(MOTE_LIGHT * fade), MOTE_REACH);

    if (!mo.falling) continue;
    for (1..ECHOES + 1) |k| try g.parts.emitMote(mo.pos, mo.phase, fade, m.f(k), ECHO_SIZE * fade / (1 + m.f(k)));
  }
}
