//! what gets drawn: turns the game state into a render Scene (plant
//! instances, rigid parts, HUD, sky/fog/light push constants). Read-only with
//! respect to the simulation.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../core/math.zig");
const rng = @import("../core/rng.zig");
const ck = @import("../world/chunk.zig");
const species = @import("../sim/species.zig");
const renderer = @import("../render/renderer.zig");
const meshgen = @import("../gfx/meshgen.zig");
const st = @import("structures.zig");
const resources = @import("resources.zig");
const actions = @import("actions.zig");
const hud = @import("hud.zig");
const play = @import("play.zig");

const Game = play.Game;

pub fn scene(g:*Game, screen:[2]f32) Allocator.Error!renderer.Scene {
  const reach = g.cam.reach(play.DRAW_LIMIT);
  const tf:f32 = @floatCast(@mod(g.time, 3600));

  // parts first: plants add parts of their own (shadows under floaters)
  g.parts.clear();
  try plants(g, reach, tf);
  const feet = try g.player.rig(&g.parts);
  try nodes(g, @intFromFloat(reach));
  try structures(g, reach, tf);
  try ghost(g, tf);
  try motes(g);
  try hud.build(g, screen);

  const veil = g.prog.veil;
  const sky = g.sky.color(veil);
  const eye = g.cam.viewEye();
  const hv:[2]f32 = if (g.hover) |h| .{m.f(h[0]), m.f(h[1])} else .{1e9, 1e9};
  const ld = g.sky.lightDir();
  var out:renderer.Scene = .{
    .push = .{
      .vp = g.cam.viewProj(),
      .eye_time = .{eye[0], eye[1], eye[2], tf},
      .fog = .{sky[0], sky[1], sky[2], 1.0 / (32 * ck.SIZE / 8 + g.cam.dist)},
      .misc = .{veil, if (g.prog.done.contains(.ley_sight)) 1 else 0, hv[0], hv[1]},
      .sun = .{ld[0], ld[1], ld[2], g.sky.daylight()},
      .view = .{g.cam.target[0], g.cam.target[2], reach * 0.7, reach},
      .feet = .{
        .{feet[0][0], feet[0][1], feet[0][2], g.player.facing},
        .{feet[1][0], feet[1][1], feet[1][2], g.player.facing},
      },
    },
    .clear = sky,
    .instances = undefined,
    .parts = g.parts.slices(),
    .live = g.parts.live.v.items,
    .live_inst = g.parts.liveInstance(),
    .ui = g.ui.v.items,
    .ui_time = @floatCast(@mod(g.ui_time, 3600)),
  };
  for (&out.instances, g.inst) |*o, l| o.* = l.items;
  return out;
}

/// plant instances near the camera, grouped by mesh: each plant's variant
/// comes from its tile, so it always regrows the same shape.
fn plants(g:*Game, reach:f32, tf:f32) Allocator.Error!void {
  for (&g.inst) |*l| l.clearRetainingCapacity();
  const s = g.plants.list.slice();
  for (0..g.plants.len()) |i| {
    const ctr = g.plants.centre(i);
    if (@abs(ctr[0] - g.cam.target[0]) > reach or @abs(ctr[1] - g.cam.target[2]) > reach) continue;
    const sp = s.items(.sp)[i];
    const def = species.get(sp);
    var y = s.items(.chunk)[i].height[s.items(.tile)[i]];
    var at = ctr;
    if (def.floating) {
      // floaters hang in the air: a slow rise and fall and a lazy drift,
      // never a bounce, over a soft shadow that shrinks as they rise
      const sd = s.items(.seed)[i];
      const ground = @max(y, 0);
      const lift = 0.07 * @sin(tf * 0.5 + sd * 10) + 0.025 * @sin(tf * 1.13 + sd * 4);
      y = ground + 1.15 + lift;
      at = .{ctr[0] + 0.05 * @sin(tf * 0.31 + sd * 7), ctr[1] + 0.05 * @cos(tf * 0.27 + sd * 5)};
      const r = 0.42 - 0.6 * lift;
      try g.parts.emit(.shadow, m.chain(&.{m.translate(m.v3(at[0], ground + 0.03, at[1])), m.scale3(m.v3(r, 1, r))}), .{.fade = 0.6});
    }
    // a confluence grows through its keys, blending from one to the next;
    // other plants pick a shape by tile
    const growth = s.items(.growth)[i];
    const key = meshgen.growthKey(sp, growth) orelse meshgen.Key{
      .v = @intCast(rng.hash2(0x7A11, s.items(.x)[i], s.items(.y)[i]) % meshgen.VARIANTS), .f = 0,
    };
    try g.inst[meshgen.plantSlot(sp, key.v)].append(g.gpa, .{
      .pos = .{at[0], y, at[1]},
      .a = .{growth, s.items(.mana)[i] / def.mana_cap, s.items(.seed)[i], def.lineage.affinity()},
      .b = .{s.items(.flow)[i], s.items(.health)[i], def.sway, m.f(@intFromEnum(def.genome.form))},
      .c = .{key.f, 0, 0, 0},
    });
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
    if (@abs(ctr[0] - g.cam.target[0]) > reach or @abs(ctr[2] - g.cam.target[2]) > reach) continue;
    const a = s.activity;
    const yaw = m.dirYaw(s.dir);
    const breathe = 1 + (0.02 + 0.05 * a) * @sin(tf * (1.5 + 2 * a) + s.seed * 9);
    try g.parts.emit(s.def().mesh, m.chain(&.{m.translate(ctr), m.rotY(yaw), m.scale3(m.v3(breathe, 2 - breathe, breathe))}), .{.glow = 0.25 + 1.1 * a, .flutter = 0.6, .phase = s.seed});
    try st.emit(s, &g.parts, ctr, tf);
  }
}

/// a tinted, pulsing preview of the structure about to be grown.
fn ghost(g:*Game, tf:f32) Allocator.Error!void {
  const h = g.hover orelse return;
  const k = st.kindOf(play.hotbar[g.hot]) orelse return;
  if (g.mode != .roam) return;
  const def = st.defs.get(k);
  const ok = actions.canPut(g, h) and g.player.inReach(h[0], h[1]) and g.player.inv.count(def.item) > 0;
  const ctr = m.footprintCentre(h[0], h[1], def.size, g.heightAt(h[0], h[1]) + 0.02);
  const tint:[4]f32 = if (ok) .{0.6, 1.4, 0.8, 0.7} else .{1.6, 0.4, 0.4, 0.8};
  try g.parts.emit(def.mesh, m.chain(&.{m.translate(ctr), m.rotY(m.dirYaw(g.place_dir)), m.scale3(m.splat3(0.96))}), .{.glow = 0.6 + 0.4 * @sin(tf * 5), .tint = tint});
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
        const wx = c.originX() + @as(i32, @intCast(t % ck.SIZE));
        const wz = c.originY() + @as(i32, @intCast(t / ck.SIZE));
        const hsh = rng.unit(rng.hash2(0xD0D, wx, wz));
        const sc = 0.55 + 0.45 * m.f(c.res[t]) / 26;
        try g.parts.emit(node.mesh, m.chain(&.{
          m.translate(m.tileCentre(wx, wz, c.height[t])),
          m.rotY(hsh * m.tau), m.scale3(m.splat3(sc)),
        }), .{.glow = node.glow, .phase = hsh});
      }
    }
  }
}

fn motes(g:*Game) Allocator.Error!void {
  for (g.stars.motes.items) |mo| {
    const spin = @as(f32, @floatCast(g.time)) * 1.5 + mo.phase * 10;
    const fade = m.clamp01(mo.life);
    try g.parts.emit(.mote, m.chain(&.{m.translate(mo.pos), m.rotY(spin), m.rotX(spin * 0.7), m.scale3(m.splat3(0.6 + 0.6 * fade))}), .{.glow = 1.6 * fade, .phase = mo.phase});
  }
}
