//! the playable layer: owns world + sim + progression, turns input into
//! actions, runs the fixed-tick simulation and composes what gets drawn.
const std = @import("std");
const m = @import("../core/math.zig");
const Rng = @import("../core/rng.zig").Rng;
const ck = @import("../world/chunk.zig");
const gen = @import("../world/gen.zig");
const World = @import("../world/world.zig").World;
const species = @import("../sim/species.zig");
const Plants = @import("../sim/plants.zig").Plants;
const Ecology = @import("../sim/ecology.zig").Ecology;
const prog = @import("progression.zig");
const Input = @import("../platform/input.zig").Input;
const Camera = @import("../render/camera.zig").Camera;
const renderer = @import("../render/renderer.zig");
const vertex = @import("../gfx/vertex.zig");
const Draw = @import("../ui/draw.zig").Draw;

pub const TICK = 1.0 / 60.0;
const STREAM_RADIUS = 5;

pub const Game = struct {
  gpa:std.mem.Allocator,
  world:World,
  plants:Plants = .{},
  eco:Ecology = .{},
  prog:prog.Progression = .{},
  cam:Camera = .{},
  rng:Rng,
  selected:species.Id = .lumenroot,
  panel:bool = false,
  debug:bool = false,
  hover:?[2]i32 = null,
  time:f64 = 0,
  acc:f64 = 0,
  sim_ms:f32 = 0,
  frame_ms:f32 = 16,
  rate:f64 = 0,
  ticks:u64 = 0,
  inst:[species.count]std.ArrayList(vertex.PlantInstance) = @splat(.empty),
  ui:Draw,
  render_stats:renderer.Stats = .{},

  pub fn init(gpa:std.mem.Allocator, seed:u64) !Game {
    var g:Game = .{.gpa = gpa, .world = World.init(gpa, seed), .rng = Rng.init(seed ^ 0xA11CE), .ui = .{.gpa = gpa}};
    // start over land: spiral out from the origin until a fertile tile shows up.
    var r:i32 = 0;
    find: while (r < 400) : (r += 3) {
      var a:i32 = -r;
      while (a <= r) : (a += 3) {
        const s = gen.sample(seed, a, r - @divFloor(r, 2));
        if (s.kind.fertile()) {
          g.cam.target = m.v3(@as(f32, @floatFromInt(a)) + 0.5, s.height, @as(f32, @floatFromInt(r - @divFloor(r, 2))) + 0.5);
          break :find;
        }
      }
    }
    try g.world.stream(g.focus(), STREAM_RADIUS, 64);
    g.prog.say("THE SOIL HUMS. PLANT A SEED (LMB)", .{});
    return g;
  }

  /// plant a starter garden around the camera and fast-forward (for showcasing/testing).
  pub fn demo(g:*Game, seconds:f32) !void {
    const cx:i32 = @intFromFloat(@floor(g.cam.target[0]));
    const cz:i32 = @intFromFloat(@floor(g.cam.target[2]));
    var dz:i32 = -4;
    while (dz <= 4) : (dz += 1) {
      var dx:i32 = -6;
      while (dx <= 6) : (dx += 1) {
        const sp:species.Id = if (dx > 2) .thornleech else if (dx < -2 or @mod(dz, 2) == 0) .lumenroot else continue;
        _ = try g.plants.place(g.gpa, &g.world, cx + dx, cz + dz, sp, g.rng.float());
      }
    }
    var t:f32 = 0;
    while (t < seconds) : (t += TICK) g.prog.absorb(try g.eco.tick(g.gpa, &g.plants, &g.world, g.prog.mods(), TICK), TICK);
    g.prog.done.insert(.ley_sight);
  }

  /// fill a side x side field with random species (perf testing).
  pub fn stress(g:*Game, side:i32) !void {
    const cx:i32 = @intFromFloat(@floor(g.cam.target[0]));
    const cz:i32 = @intFromFloat(@floor(g.cam.target[2]));
    const r = @divFloor(side, 2);
    try g.world.stream(g.focus(), @divFloor(r, ck.SIZE) + 2, 1 << 20);
    var dz:i32 = -r;
    while (dz < r) : (dz += 1) {
      var dx:i32 = -r;
      while (dx < r) : (dx += 1) {
        const sp:species.Id = @enumFromInt(@as(u8, @intFromFloat(g.rng.float() * 2.999)));
        _ = try g.plants.place(g.gpa, &g.world, cx + dx, cz + dz, sp, g.rng.float());
      }
    }
  }

  pub fn deinit(g:*Game) void {
    for (&g.inst) |*l| l.deinit(g.gpa);
    g.ui.deinit();
    g.eco.deinit(g.gpa);
    g.plants.deinit(g.gpa);
    g.world.deinit();
  }

  fn focus(g:*const Game) ck.Coord {
    return ck.Coord.ofTile(@intFromFloat(@floor(g.cam.target[0])), @intFromFloat(@floor(g.cam.target[2])));
  }

  fn heightAt(g:*const Game, wx:i32, wy:i32) f32 {
    if (g.world.chunkOfTile(wx, wy)) |c| return c.height[ck.localIndex(wx, wy)];
    return gen.heightAt(g.world.seed, wx, wy);
  }

  /// march the mouse ray until it dips below the terraced ground.
  fn pick(g:*const Game, in:*const Input, screen:[2]f32) ?[2]i32 {
    const ray = g.cam.ray(in.mouse[0], in.mouse[1], screen[0], screen[1]);
    var t:f32 = 0;
    const step:f32 = 0.1;
    while (t < g.cam.dist * 4) : (t += step) {
      const p = ray.o + ray.d * m.splat(t);
      const tx:i32 = @intFromFloat(@floor(p[0]));
      const tz:i32 = @intFromFloat(@floor(p[2]));
      if (p[1] <= g.heightAt(tx, tz)) return .{tx, tz};
    }
    return null;
  }

  pub fn update(g:*Game, in:*const Input, dt:f32, screen:[2]f32) !void {
    g.time += dt;
    g.frame_ms += (dt * 1000 - g.frame_ms) * 0.05;

    // camera
    const speed = g.cam.dist * (if (in.down(.left_shift)) @as(f32, 2.2) else 0.9) * dt;
    var px:f32 = 0;
    var pz:f32 = 0;
    if (in.down(.a) or in.down(.left)) px -= 1;
    if (in.down(.d) or in.down(.right)) px += 1;
    if (in.down(.w) or in.down(.up)) pz += 1;
    if (in.down(.s) or in.down(.down)) pz -= 1;
    g.cam.pan(px * speed, pz * speed);
    if (in.held(.middle)) {
      const k = g.cam.dist / screen[1] * 1.6;
      g.cam.pan(-in.mouse_delta[0] * k, in.mouse_delta[1] * k);
    }
    if (in.down(.q)) g.cam.yaw -= dt * 1.5;
    if (in.down(.e)) g.cam.yaw += dt * 1.5;
    if (in.scroll != 0) g.cam.zoom(in.scroll);
    g.cam.aspect = screen[0] / @max(screen[1], 1);
    // keep the focus resting on the terrain surface
    const fh = g.heightAt(@intFromFloat(@floor(g.cam.target[0])), @intFromFloat(@floor(g.cam.target[2])));
    g.cam.target[1] += (fh - g.cam.target[1]) * @min(1, dt * 6);

    // toggles
    if (in.pressed(.tab)) g.panel = !g.panel;
    if (in.pressed(.F3)) g.debug = !g.debug;

    // number keys: research when the panel is open, otherwise seed choice
    const nums = [_]bool{in.pressed(.one), in.pressed(.two), in.pressed(.three), in.pressed(.four), in.pressed(.five)};
    for (nums, 0..) |p, i| {
      if (!p) continue;
      if (g.panel) {
        if (i < prog.tree.values.len) _ = g.prog.buy(@enumFromInt(i));
      } else if (i < species.count) {
        const sp:species.Id = @enumFromInt(i);
        if (g.prog.canPlant(sp)) g.selected = sp else g.prog.say("{s} IS NOT YET UNDERSTOOD", .{species.get(sp).name});
      }
    }

    // build mode
    g.hover = g.pick(in, screen);
    if (g.hover) |h| {
      if (in.held(.left) and g.prog.canPlant(g.selected)) {
        _ = try g.plants.place(g.gpa, &g.world, h[0], h[1], g.selected, g.rng.float());
      }
      if (in.held(.right)) _ = g.plants.removeAt(&g.world, h[0], h[1]);
    }

    try g.world.stream(g.focus(), STREAM_RADIUS, 4);
  }

  /// fixed-step simulation; never more than 8 catch-up ticks per frame.
  pub fn simulate(g:*Game, frame_dt:f64) !void {
    g.acc = @min(g.acc + frame_dt, TICK * 8);
    var essence:f64 = 0;
    while (g.acc >= TICK) : (g.acc -= TICK) {
      const ev = try g.eco.tick(g.gpa, &g.plants, &g.world, g.prog.mods(), TICK);
      g.prog.absorb(ev, TICK);
      essence += ev.essence;
      g.ticks += 1;
    }
    if (frame_dt > 0) g.rate += (essence / frame_dt - g.rate) * 0.02;
  }

  pub fn scene(g:*Game, screen:[2]f32) !renderer.Scene {
    // instances near the camera, grouped by species
    for (&g.inst) |*l| l.clearRetainingCapacity();
    const s = g.plants.list.slice();
    const reach = g.cam.dist * 2.2 + 12;
    const tx = g.cam.target[0];
    const tz = g.cam.target[2];
    for (0..g.plants.len()) |i| {
      const x:f32 = @as(f32, @floatFromInt(s.items(.x)[i])) + 0.5;
      const z:f32 = @as(f32, @floatFromInt(s.items(.y)[i])) + 0.5;
      if (@abs(x - tx) > reach or @abs(z - tz) > reach) continue;
      const sp = s.items(.sp)[i];
      const def = species.get(sp);
      const c = s.items(.chunk)[i];
      try g.inst[@intFromEnum(sp)].append(g.gpa, .{
        .pos = .{x, c.height[s.items(.tile)[i]], z},
        .a = .{s.items(.growth)[i], s.items(.mana)[i] / def.mana_cap, s.items(.seed)[i], def.lineage.affinity()},
        .b = .{s.items(.flow)[i], s.items(.health)[i], 0, 0},
      });
    }

    try g.hud(screen);

    const veil = g.prog.veil;
    const sky = [3]f32{m.lerp(0.035, 0.08, veil), m.lerp(0.05, 0.03, veil), m.lerp(0.075, 0.14, veil)};
    const eye = g.cam.eye();
    const hv:[2]f32 = if (g.hover) |h| .{@floatFromInt(h[0]), @floatFromInt(h[1])} else .{1e9, 1e9};
    var out:renderer.Scene = .{
      .push = .{
        .vp = g.cam.viewProj(),
        .eye_time = .{eye[0], eye[1], eye[2], @floatCast(@mod(g.time, 3600))},
        .fog = .{sky[0], sky[1], sky[2], 1.0 / (32 * ck.SIZE / 8 + g.cam.dist)},
        .misc = .{veil, if (g.prog.done.contains(.ley_sight)) 1 else 0, hv[0], hv[1]},
      },
      .clear = sky,
      .instances = undefined,
      .ui = g.ui.v.items,
    };
    for (&out.instances, g.inst) |*o, l| o.* = l.items;
    return out;
  }

  fn hud(g:*Game, screen:[2]f32) !void {
    const d = &g.ui;
    d.clear();
    const S:f32 = 2;
    const white = [4]u8{235, 235, 245, 255};
    const dim = [4]u8{150, 150, 170, 255};
    const gold = [4]u8{255, 215, 120, 255};
    const panel = [4]u8{10, 10, 20, 170};

    try d.rect(8, 8, 430, 96, panel);
    _ = try d.print(18, 18, 3, gold, "ESSENCE {d:.1}", .{g.prog.essence});
    _ = try d.print(18, 48, S, dim, "+{d:.2}/S   PLANTS {d}", .{g.rate, g.plants.len()});
    var x:f32 = 18;
    for (0..species.count) |i| {
      const sp:species.Id = @enumFromInt(i);
      const ok = g.prog.canPlant(sp);
      const col = if (sp == g.selected) gold else if (ok) white else [4]u8{90, 90, 100, 255};
      x = try d.print(x, 74, S, col, "{d} {s}", .{i + 1, if (ok) species.get(sp).name else "???"}) + 16;
    }

    // hovered tile / plant info
    if (g.hover) |h| if (g.world.chunkOfTile(h[0], h[1])) |c| {
      const t = ck.localIndex(h[0], h[1]);
      var y:f32 = 112;
      try d.rect(8, y, 430, 50, panel);
      _ = try d.print(18, y + 8, S, dim, "{s}  LEY {d:.1}/{d:.1}", .{@tagName(c.kind[t]), c.ley[t], c.ley_cap[t]});
      y += 28;
      if (c.plant[t] != ck.NONE) {
        const p = g.plants.list.get(c.plant[t]);
        const def = species.get(p.sp);
        _ = try d.print(18, y, S, white, "{s} {d:.0}%  MANA {d:.1}  HP {d:.0}%", .{def.name, p.growth * 100, p.mana, p.health * 100});
      }
    };

    // message log, newest first, fading out
    for (g.prog.log, 0..) |msg, i| {
      if (msg.len == 0 or msg.age > 12) continue;
      const a:u8 = @intFromFloat(255 * m.clamp01(1.5 - msg.age / 8));
      _ = try d.text(18, screen[1] - 70 - @as(f32, @floatFromInt(i)) * 22, S, .{220, 200, 255, a}, msg.buf[0..msg.len]);
    }
    _ = try d.text(18, screen[1] - 30, 1.5, dim, "WASD/MMB PAN  SCROLL ZOOM  Q/E TURN  LMB PLANT  RMB UPROOT  1-3 SEED  TAB RESEARCH  F3 DEBUG");

    if (g.panel) {
      const w:f32 = 620;
      const px = (screen[0] - w) / 2;
      const py:f32 = 140;
      try d.rect(px, py, w, 60 + 52 * @as(f32, @floatFromInt(prog.tree.values.len)), .{14, 10, 28, 225});
      _ = try d.text(px + 16, py + 14, 3, gold, "RESEARCH");
      for (prog.tree.values, 0..) |r, i| {
        const id:prog.Id = @enumFromInt(i);
        const st = g.prog.status(id);
        const y = py + 56 + 52 * @as(f32, @floatFromInt(i));
        const col = switch (st) { .done => [4]u8{120, 220, 160, 255}, .open => white, .locked => [4]u8{100, 100, 115, 255} };
        _ = try d.print(px + 16, y, S, col, "{d} {s}  ({d:.0})  {s}", .{i + 1, r.name, r.cost, @tagName(st)});
        _ = try d.text(px + 40, y + 20, 1.5, dim, r.desc);
      }
    }

    if (g.debug) {
      const st = g.render_stats;
      const bx = screen[0] - 360;
      try d.rect(bx, 8, 352, 150, panel);
      _ = try d.print(bx + 10, 16, S, white, "FPS {d:.0}  {d:.2} MS", .{1000 / @max(g.frame_ms, 0.01), g.frame_ms});
      _ = try d.print(bx + 10, 40, S, white, "SIM {d:.3} MS  TICK {d}", .{g.sim_ms, g.ticks});
      _ = try d.print(bx + 10, 64, S, white, "CHUNKS {d}  DRAWN {d}", .{g.world.map.count(), st.chunks});
      _ = try d.print(bx + 10, 88, S, white, "INSTANCES {d}  DRAWS {d}", .{st.instances, st.draws});
      _ = try d.print(bx + 10, 112, S, white, "CAM {d:.0},{d:.0}  Z {d:.0}", .{g.cam.target[0], g.cam.target[2], g.cam.dist});
      _ = try d.print(bx + 10, 136, S, dim, "GEN {d}  MESHED {d}", .{g.world.generated, st.meshed});
    }
  }

};
