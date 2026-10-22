//! the playable layer: owns world + sim + progression + the player, turns input
//! into actions, runs the fixed-tick simulation and composes what gets drawn.
//! Nothing is pooled globally: items live in the player (and later structures),
//! essence and seeds live in plants until harvested.
const std = @import("std");
const m = @import("../core/math.zig");
const rng = @import("../core/rng.zig");
const Rng = rng.Rng;
const ck = @import("../world/chunk.zig");
const gen = @import("../world/gen.zig");
const World = @import("../world/world.zig").World;
const species = @import("../sim/species.zig");
const plants_mod = @import("../sim/plants.zig");
const Plants = plants_mod.Plants;
const Ecology = @import("../sim/ecology.zig").Ecology;
const items = @import("../sim/items.zig");
const prog = @import("progression.zig");
const Input = @import("../platform/input.zig").Input;
const Camera = @import("../render/camera.zig").Camera;
const renderer = @import("../render/renderer.zig");
const vertex = @import("../gfx/vertex.zig");
const meshlib = @import("../gfx/meshlib.zig");
const Draw = @import("../ui/draw.zig").Draw;
const sky_mod = @import("sky.zig");
const Player = @import("player.zig").Player;
const Parts = @import("parts.zig").Parts;
const hud = @import("hud.zig");
const craft = @import("craft.zig");
const st = @import("structures.zig");

pub const TICK = 1.0 / 60.0;
const STREAM_RADIUS = 4;
pub const GATHER_TIME:f32 = 0.45;

/// everything the wolf can put into the world, in hotbar key order 1..9.
pub const hotbar = [_]items.Item{
  .seed_lumenroot, .seed_thornleech, .seed_vesper, .seed_driftwisp, .seed_hollowheart,
  .conduit, .sap_cache, .germinator, .research_bloom,
};

/// can the gardener place this hotbar item yet (seed understood / always for bulbs)?
pub fn known(g:*const Game, item:items.Item) bool {
  return if (item.plants()) |sp| g.prog.canPlant(sp) else true;
}

pub fn kindItem(k:ck.Kind) ?items.Item {
  return switch (k) { .stone, .soil => .grit, .moss => .fibre, .ley => .ley_shard, .water => null };
}

/// terrain queries for movement/starfall: height of a loaded, dry tile.
const Ground = struct {
  w:*const World,
  pub fn walkable(g:Ground, wx:i32, wz:i32) ?f32 {
    const c = g.w.chunkOfTile(wx, wz) orelse return null;
    const t = ck.localIndex(wx, wz);
    return if (c.kind[t] == .water) null else c.height[t];
  }
  pub fn heightAt(g:Ground, wx:i32, wz:i32) ?f32 { return g.walkable(wx, wz); }
};

pub const Game = struct {
  gpa:std.mem.Allocator,
  world:World,
  plants:Plants = .{},
  structs:st.Structures = .{},
  eco:Ecology = .{},
  prog:prog.Progression = .{},
  cam:Camera = .{},
  sky:sky_mod.Sky = .{},
  stars:sky_mod.Starfall,
  player:Player,
  rng:Rng,
  parts:Parts,
  ui:Draw,
  weave:craft.Crafter = .{},

  hot:usize = 0,
  /// facing for the next conduit placed (R rotates)
  place_dir:u2 = 0,
  show_inv:bool = false,
  show_research:bool = false,
  debug:bool = false,
  hover:?[2]i32 = null,
  /// progress of the current gather, and a short linger for one-off gestures
  gather_t:f32 = 0,
  linger:f32 = 0,
  plant_cd:f32 = 0,
  full_warned:bool = false,

  time:f64 = 0,
  acc:f64 = 0,
  sim_ms:f32 = 0,
  frame_ms:f32 = 16,
  ticks:u64 = 0,
  inst:[species.count]std.ArrayList(vertex.PlantInstance) = @splat(.empty),
  far:std.ArrayList(*ck.Chunk) = .empty,
  render_stats:renderer.Stats = .{},

  pub fn init(gpa:std.mem.Allocator, seed:u64) !Game {
    var g:Game = .{
      .gpa = gpa,
      .world = World.init(gpa, seed),
      .rng = Rng.init(seed ^ 0xA11CE),
      .stars = .{.rng = Rng.init(seed ^ 0x57A2)},
      .player = .{.pos = m.v3(0.5, 0, 0.5)},
      .parts = .{.gpa = gpa},
      .ui = .{.gpa = gpa},
    };
    // start on dry land: spiral out from the origin until a fertile tile shows up.
    var r:i32 = 0;
    find: while (r < 400) : (r += 3) {
      var a:i32 = -r;
      while (a <= r) : (a += 3) {
        const z = r - @divFloor(r, 2);
        const s = gen.sample(seed, a, z);
        if (s.kind.fertile()) {
          g.player.pos = m.v3(@as(f32, @floatFromInt(a)) + 0.5, s.height, @as(f32, @floatFromInt(z)) + 0.5);
          break :find;
        }
      }
    }
    g.cam.target = g.player.pos;
    try g.world.stream(g.focus(), STREAM_RADIUS, 1 << 10);
    g.prog.say("YOU WAKE AMONG BARE ROOTS. GATHER WHAT THE GROUND OFFERS", .{});
    g.prog.say("AT NIGHT, CATCH STARLIGHT. WEAVE SEEDS IN YOUR BELLY (TAB)", .{});
    return g;
  }

  pub fn deinit(g:*Game) void {
    for (&g.inst) |*l| l.deinit(g.gpa);
    g.far.deinit(g.gpa);
    g.parts.deinit();
    g.ui.deinit();
    g.stars.deinit(g.gpa);
    g.eco.deinit(g.gpa);
    g.plants.deinit(g.gpa);
    g.structs.deinit(g.gpa);
    g.world.deinit();
  }

  fn focus(g:*const Game) ck.Coord {
    return ck.Coord.ofTile(@intFromFloat(@floor(g.player.pos[0])), @intFromFloat(@floor(g.player.pos[2])));
  }

  fn ground(g:*const Game) Ground { return .{.w = &g.world}; }

  fn heightAt(g:*const Game, wx:i32, wy:i32) f32 {
    if (g.world.chunkOfTile(wx, wy)) |c| return c.height[ck.localIndex(wx, wy)];
    return gen.heightAt(g.world.seed, wx, wy);
  }

  /// march the mouse ray until it dips below the terraced ground.
  fn pick(g:*const Game, in:*const Input, screen:[2]f32) ?[2]i32 {
    const ray = g.cam.ray(in.mouse[0], in.mouse[1], screen[0], screen[1]);
    var t:f32 = 0;
    while (t < g.cam.dist * 4) : (t += 0.1) {
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
    g.sky.update(dt);

    // panels and selection
    if (in.pressed(.tab)) g.show_inv = !g.show_inv;
    if (in.pressed(.t)) g.show_research = !g.show_research;
    if (in.pressed(.F3)) g.debug = !g.debug;
    if (in.pressed(.r)) g.place_dir +%= 1;
    const nums = [_]bool{
      in.pressed(.one), in.pressed(.two), in.pressed(.three), in.pressed(.four), in.pressed(.five),
      in.pressed(.six), in.pressed(.seven), in.pressed(.eight), in.pressed(.nine),
    };
    for (nums, 0..) |p, i| {
      if (!p) continue;
      if (g.show_research) {
        if (i < prog.tree.values.len) g.prog.select(@enumFromInt(i));
      } else if (g.show_inv) {
        if (i < craft.hand.len) g.weaveByHand(i);
      } else if (i < hotbar.len) g.hot = i;
    }

    // movement relative to the camera
    var mx:f32 = 0;
    var mz:f32 = 0;
    if (in.down(.a) or in.down(.left)) mx -= 1;
    if (in.down(.d) or in.down(.right)) mx += 1;
    if (in.down(.w) or in.down(.up)) mz += 1;
    if (in.down(.s) or in.down(.down)) mz -= 1;
    const yaw = g.cam.yaw;
    var wish = [2]f32{@cos(yaw) * mx - @sin(yaw) * mz, -@sin(yaw) * mx - @cos(yaw) * mz};
    const wl = @sqrt(wish[0] * wish[0] + wish[1] * wish[1]);
    if (wl > 1) wish = .{wish[0] / wl, wish[1] / wl};

    if (in.down(.q)) g.cam.yaw -= dt * 1.5;
    if (in.down(.e)) g.cam.yaw += dt * 1.5;
    if (in.scroll != 0) g.cam.zoom(in.scroll);
    g.cam.aspect = screen[0] / @max(screen[1], 1);

    // interaction with the hovered tile
    g.hover = g.pick(in, screen);
    var working = false;
    g.plant_cd -= dt;
    g.linger -= dt;
    if (!in.held(.left)) {
      g.gather_t = 0;
      g.full_warned = false;
    }
    if (g.hover) |h| if (g.player.inReach(h[0], h[1])) if (g.world.chunkOfTile(h[0], h[1])) |c| {
      const t = ck.localIndex(h[0], h[1]);
      const on_struct = g.structs.at(&g.world, h[0], h[1]);
      if (in.held(.left) and on_struct == null) {
        if (c.res[t] > 0 and c.occ[t] == ck.NONE) working = g.gather(c, t, dt)
        else if (g.plant_cd <= 0) try g.put(h);
      }
      if (in.pressed(.f)) {
        if (on_struct) |j| {
          if (in.down(.left_shift)) g.takeFrom(j) else g.feed(j);
        } else g.harvest(h);
      }
      if (in.pressed(.c)) if (on_struct) |j| g.cycleRecipe(j);
      if (in.clicked(.right)) {
        if (on_struct) |j| g.unbuild(j)
        else if (g.plants.removeAt(&g.world, h[0], h[1])) _ = g.player.inv.add(.fibre, 1);
        g.linger = 0.35;
      }
      if (working or g.linger > 0) {
        g.player.work_at = m.v3(@as(f32, @floatFromInt(h[0])) + 0.5, c.height[t], @as(f32, @floatFromInt(h[1])) + 0.5);
      }
    };
    // weaving: hands work at the chest while the queue runs
    if (g.weave.tick(&g.player.inv, dt)) |made| g.prog.say("WOVE A {s}", .{made.info().name});
    if (g.weave.busy() and !working) {
      working = true;
      g.player.work_at = g.player.pos + m.v3(@sin(g.player.facing), 0, @cos(g.player.facing));
    }
    g.player.working = working or g.linger > 0;

    g.player.move(wish, in.down(.left_shift), g.ground(), dt);
    g.player.animate(dt);
    const follow = g.player.pos + m.v3(0, 0.6, 0);
    g.cam.target += (follow - g.cam.target) * m.splat(@min(1, dt * 6));

    // starlight: falls at night, drawn to the wolf's chest, absorbed on touch
    try g.stars.update(g.gpa, &g.sky, g.player.pos, g.ground(), dt);
    const chest = g.player.chest();
    var i:usize = 0;
    while (i < g.stars.motes.items.len) {
      const mo = &g.stars.motes.items[i];
      const d = chest - mo.pos;
      const dist = m.len(d);
      if (dist < 2.4) mo.pos += d * m.splat(@min(1, dt * (5 - dist * 1.5)));
      if (dist < 0.45 and g.player.inv.add(.starlight, 1) == 1) {
        _ = g.stars.motes.swapRemove(i);
        continue;
      }
      i += 1;
    }

    // stream the world around the player; chunks holding plants stay
    try g.world.stream(g.focus(), STREAM_RADIUS, 4);
    try g.world.far(g.focus(), STREAM_RADIUS, &g.far);
    for (g.far.items) |c| try g.world.unload(c);
  }

  /// returns whether the wolf keeps working this tile.
  fn gather(g:*Game, c:*ck.Chunk, t:usize, dt:f32) bool {
    const item = kindItem(c.kind[t]) orelse return false;
    g.gather_t += dt;
    if (g.gather_t < GATHER_TIME) return true;
    g.gather_t = 0;
    if (g.player.inv.add(item, 1) == 0) {
      if (!g.full_warned) g.prog.say("YOUR BELLY CAN HOLD NO MORE", .{});
      g.full_warned = true;
      return false;
    }
    c.res[t] -= 1;
    return c.res[t] > 0;
  }

  /// put the selected hotbar item into the world: sow a seed or grow a bulb.
  fn put(g:*Game, h:[2]i32) !void {
    const item = hotbar[g.hot];
    if (!known(g, item)) return;
    if (g.player.inv.count(item) == 0) {
      g.prog.say("NO {s}. WEAVE ONE IN YOUR BELLY (TAB)", .{item.info().name});
      g.plant_cd = 1.5;
      return;
    }
    const ok = if (item.plants()) |sp|
      try g.plants.place(g.gpa, &g.world, h[0], h[1], sp, g.rng.float())
    else if (st.kindOf(item)) |k|
      try g.structs.place(g.gpa, &g.world, h[0], h[1], k, g.place_dir, g.rng.float())
    else false;
    if (ok) {
      _ = g.player.inv.take(item, 1);
      g.plant_cd = 0.25;
      g.linger = 0.35;
    }
  }

  pub fn canPut(g:*const Game, h:[2]i32) bool {
    const item = hotbar[g.hot];
    if (item.plants()) |sp| return g.plants.canPlace(&g.world, h[0], h[1], sp);
    if (st.kindOf(item)) |k| return g.structs.canPlace(&g.world, h[0], h[1], k);
    return false;
  }

  fn weaveByHand(g:*Game, i:usize) void {
    const r = craft.hand[i];
    if (!r.unlocked(&g.prog)) return g.prog.say("{s} IS NOT YET UNDERSTOOD", .{r.out.info().name});
    if (!g.weave.push(&g.player.inv, i)) g.prog.say("NOT ENOUGH TO WEAVE {s}", .{r.out.info().name});
  }

  /// give a structure everything from the belly it will take.
  fn feed(g:*Game, j:u32) void {
    var moved:u32 = 0;
    for (&g.player.inv.slot) |*slot| if (slot.*) |*s| {
      // seeds and bulbs stay in the belly, ready to be placed
      if (s.item.plants() != null or st.kindOf(s.item) != null) continue;
      const n = g.structs.insert(&g.prog, j, s.item, s.n);
      moved += n;
      s.n -= n;
      if (s.n == 0) slot.* = null;
    };
    g.linger = 0.4;
    if (moved == 0) g.prog.say("IT WANTS NOTHING YOU CARRY", .{});
  }

  fn takeFrom(g:*Game, j:u32) void {
    const s = &g.structs.list.items[j];
    for (&s.inv.slot) |*slot| if (slot.*) |*it| {
      const n = g.player.inv.add(it.item, it.n);
      it.n -= n;
      if (it.n == 0) slot.* = null;
    };
    if (s.held) |h| if (g.player.inv.add(h, 1) == 1) { s.held = null; };
    g.linger = 0.4;
  }

  /// germinators cycle through the seed recipes you understand.
  fn cycleRecipe(g:*Game, j:u32) void {
    const s = &g.structs.list.items[j];
    if (s.kind != .germinator or s.weave.busy()) return;
    var r = s.recipe;
    for (0..craft.hand.len) |_| {
      r = @intCast((r + 1) % craft.hand.len);
      if (craft.isSeedRecipe(r) and craft.hand[r].unlocked(&g.prog)) break;
    }
    s.recipe = r;
    g.prog.say("GERMINATOR NOW WEAVES {s}", .{craft.hand[r].out.info().name});
  }

  /// uproot a structure: its bulb and contents come back (what fits).
  fn unbuild(g:*Game, j:u32) void {
    const s = g.structs.remove(&g.world, j);
    var lost:u32 = 0;
    lost += 1 - g.player.inv.add(s.def().item, 1);
    for (s.inv.slot) |slot| if (slot) |it| { lost += it.n - g.player.inv.add(it.item, it.n); };
    if (s.held) |h| lost += 1 - g.player.inv.add(h, 1);
    if (lost > 0) g.prog.say("{d} THINGS SPILLED AND WITHERED", .{lost});
  }

  /// take a mature plant's essence and ripe seeds. Where lineages touch and
  /// splicing is understood, one seed comes out a hybrid.
  fn harvest(g:*Game, h:[2]i32) void {
    const i = g.plants.at(&g.world, h[0], h[1]) orelse return;
    const s = g.plants.list.slice();
    const sp = s.items(.sp)[i];
    if (s.items(.growth)[i] < 1) {
      g.prog.say("{s} IS STILL GROWING ({d:.0}%)", .{species.get(sp).name, s.items(.growth)[i] * 100});
      return;
    }
    const es:u16 = @intFromFloat(@floor(s.items(.essence)[i]));
    var seeds:u16 = @intFromFloat(@floor(s.items(.seeds)[i]));
    if (es == 0 and seeds == 0) {
      g.prog.say("NOTHING IS RIPE YET", .{});
      return;
    }
    const got_es = g.player.inv.add(species.get(sp).yields, es);
    s.items(.essence)[i] -= @floatFromInt(got_es);
    if (seeds > 0 and g.prog.done.contains(.seed_splicing) and touchesOtherLineage(s, i)) {
      if (g.player.inv.add(.seed_vesper, 1) == 1) {
        seeds -= 1;
        s.items(.seeds)[i] -= 1;
      }
    }
    const got_sd = g.player.inv.add(items.Item.seedOf(sp), seeds);
    s.items(.seeds)[i] -= @floatFromInt(got_sd);
    g.linger = 0.5;
    if (got_es + got_sd < es + seeds) g.prog.say("YOUR BELLY CAN HOLD NO MORE", .{});
  }

  fn touchesOtherLineage(s:anytype, i:u32) bool {
    const mine = species.get(s.items(.sp)[i]).lineage;
    for (s.items(.n1)[i]) |j| {
      if (j == ck.NONE) break;
      if (species.get(s.items(.sp)[j]).lineage != mine and s.items(.growth)[j] >= 1) return true;
    }
    return false;
  }

  /// fixed-step simulation; never more than 8 catch-up ticks per frame.
  pub fn simulate(g:*Game, frame_dt:f64) !void {
    g.acc = @min(g.acc + frame_dt, TICK * 8);
    while (g.acc >= TICK) : (g.acc -= TICK) {
      var mods = g.prog.mods();
      mods.night = 1 - g.sky.daylight();
      const ev = try g.eco.tick(g.gpa, &g.plants, &g.world, mods, TICK);
      g.prog.absorb(ev, TICK);
      g.structs.tick(&g.world, &g.plants, &g.prog, TICK);
      g.ticks += 1;
    }
  }

  pub fn scene(g:*Game, screen:[2]f32) !renderer.Scene {
    const reach = g.cam.dist * 2.2 + 12;

    // plants near the camera, grouped by species
    for (&g.inst) |*l| l.clearRetainingCapacity();
    const s = g.plants.list.slice();
    const tf:f32 = @floatCast(@mod(g.time, 3600));
    for (0..g.plants.len()) |i| {
      const ctr = g.plants.centre(i);
      const x = ctr[0];
      const z = ctr[1];
      if (@abs(x - g.cam.target[0]) > reach or @abs(z - g.cam.target[2]) > reach) continue;
      const sp = s.items(.sp)[i];
      const def = species.get(sp);
      const c = s.items(.chunk)[i];
      var y = c.height[s.items(.tile)[i]];
      // floaters drift above whatever is beneath them
      if (def.floating) y = @max(y, 0) + 1.15 + 0.12 * @sin(tf * 1.3 + s.items(.seed)[i] * 10);
      try g.inst[@intFromEnum(sp)].append(g.gpa, .{
        .pos = .{x, y, z},
        .a = .{s.items(.growth)[i], s.items(.mana)[i] / def.mana_cap, s.items(.seed)[i], def.lineage.affinity()},
        .b = .{s.items(.flow)[i], s.items(.health)[i], 0, 0},
      });
    }

    // rigid parts: the wolf, resource nodes, starlight
    g.parts.clear();
    try g.player.rig(&g.parts);
    try g.emitNodes(@intFromFloat(@min(reach, 40)));
    try g.emitStructures(reach, tf);
    try g.emitGhost(tf);
    for (g.stars.motes.items) |mo| {
      const spin = @as(f32, @floatCast(g.time)) * 1.5 + mo.phase * 10;
      const fade = m.clamp01(mo.life);
      try g.parts.emit(.mote, m.chain(.{m.translate(mo.pos), m.rotY(spin), m.rotX(spin * 0.7), m.scale3(m.splat(0.6 + 0.6 * fade))}), .{.glow = 1.6 * fade, .phase = mo.phase});
    }

    try hud.build(g, screen);

    const veil = g.prog.veil;
    const sky = g.sky.color(veil);
    const eye = g.cam.eye();
    const hv:[2]f32 = if (g.hover) |h| .{@floatFromInt(h[0]), @floatFromInt(h[1])} else .{1e9, 1e9};
    const ld = g.sky.lightDir();
    var out:renderer.Scene = .{
      .push = .{
        .vp = g.cam.viewProj(),
        .eye_time = .{eye[0], eye[1], eye[2], @floatCast(@mod(g.time, 3600))},
        .fog = .{sky[0], sky[1], sky[2], 1.0 / (32 * ck.SIZE / 8 + g.cam.dist)},
        .misc = .{veil, if (g.prog.done.contains(.ley_sight)) 1 else 0, hv[0], hv[1]},
        .sun = .{ld[0], ld[1], ld[2], g.sky.daylight()},
      },
      .clear = sky,
      .instances = undefined,
      .parts = g.parts.slices(),
      .ui = g.ui.v.items,
    };
    for (&out.instances, g.inst) |*o, l| o.* = l.items;
    return out;
  }

  fn structCentre(g:*const Game, s:*const st.Structure) m.V3 {
    const size:f32 = @floatFromInt(s.def().size);
    return m.v3(@as(f32, @floatFromInt(s.x)) + size / 2, g.heightAt(s.x, s.y), @as(f32, @floatFromInt(s.y)) + size / 2);
  }

  /// structures breathe and glow with their activity; conduits show items in transit.
  fn emitStructures(g:*Game, reach:f32, tf:f32) !void {
    for (g.structs.list.items) |*s| {
      const ctr = g.structCentre(s);
      if (@abs(ctr[0] - g.cam.target[0]) > reach or @abs(ctr[2] - g.cam.target[2]) > reach) continue;
      const a = s.activity;
      const yaw = -@as(f32, @floatFromInt(s.dir)) * std.math.pi / 2.0;
      const breathe = 1 + (0.02 + 0.05 * a) * @sin(tf * (1.5 + 2 * a) + s.seed * 9);
      const base = m.chain(.{m.translate(ctr), m.rotY(yaw)});
      try g.parts.emit(s.def().mesh, m.chain(.{base, m.scale3(m.v3(breathe, 2 - breathe, breathe))}), .{.glow = 0.25 + 1.1 * a, .flutter = 0.6, .phase = s.seed});
      switch (s.kind) {
        .research_bloom => {
          const bob = 0.12 * @sin(tf * 1.4 + s.seed * 5);
          try g.parts.emit(.research_orb, m.chain(.{m.translate(ctr + m.v3(0, 2.05 + bob, 0)), m.rotY(tf * (0.4 + 2.5 * a)), m.rotX(0.3 * @sin(tf))}), .{.glow = 0.7 + 1.5 * a, .phase = s.seed});
        },
        .conduit => if (s.held) |item| {
          const v = st.dirVec(s.dir);
          const k = s.move_t - 0.5;
          const p = ctr + m.v3(@as(f32, @floatFromInt(v[0])) * k, 0.27 + 0.03 * @sin(tf * 8), @as(f32, @floatFromInt(v[1])) * k);
          const col = item.info().col;
          try g.parts.emit(.item_pod, m.translate(p), .{.glow = 0.8, .tint = .{@as(f32, @floatFromInt(col[0])) / 255, @as(f32, @floatFromInt(col[1])) / 255, @as(f32, @floatFromInt(col[2])) / 255, 1}});
        },
        else => {},
      }
    }
  }

  /// a tinted, pulsing preview of the structure about to be grown.
  fn emitGhost(g:*Game, tf:f32) !void {
    const h = g.hover orelse return;
    const k = st.kindOf(hotbar[g.hot]) orelse return;
    if (g.show_inv or g.show_research) return;
    const def = st.defs.get(k);
    const size:f32 = @floatFromInt(def.size);
    const ok = g.canPut(h) and g.player.inReach(h[0], h[1]) and g.player.inv.count(def.item) > 0;
    const ctr = m.v3(@as(f32, @floatFromInt(h[0])) + size / 2, g.heightAt(h[0], h[1]) + 0.02, @as(f32, @floatFromInt(h[1])) + size / 2);
    const tint:[4]f32 = if (ok) .{0.6, 1.4, 0.8, 0.7} else .{1.6, 0.4, 0.4, 0.8};
    try g.parts.emit(def.mesh, m.chain(.{m.translate(ctr), m.rotY(-@as(f32, @floatFromInt(g.place_dir)) * std.math.pi / 2.0), m.scale3(m.splat(0.96))}), .{.glow = 0.6 + 0.4 * @sin(tf * 5), .tint = tint});
  }

  /// resource nodes within `nr` tiles of the camera focus.
  fn emitNodes(g:*Game, nr:i32) !void {
    const cx:i32 = @intFromFloat(@floor(g.cam.target[0]));
    const cz:i32 = @intFromFloat(@floor(g.cam.target[2]));
    const lo = ck.Coord.ofTile(cx - nr, cz - nr);
    const hi = ck.Coord.ofTile(cx + nr, cz + nr);
    var cy = lo.y;
    while (cy <= hi.y) : (cy += 1) {
      var cxx = lo.x;
      while (cxx <= hi.x) : (cxx += 1) {
        const c = g.world.get(.{.x = cxx, .y = cy}) orelse continue;
        for (0..ck.N) |t| {
          if (c.res[t] == 0) continue;
          const wx = c.originX() + @as(i32, @intCast(t % ck.SIZE));
          const wz = c.originY() + @as(i32, @intCast(t / ck.SIZE));
          const hsh = rng.unit(rng.hash2(0xD0D, wx, wz));
          const sc = 0.55 + 0.45 * @as(f32, @floatFromInt(c.res[t])) / 26;
          const id:meshlib.Id = switch (c.kind[t]) { .moss => .node_fibre, .ley => .node_ley, else => .node_grit };
          try g.parts.emit(id, m.chain(.{
            m.translate(m.v3(@as(f32, @floatFromInt(wx)) + 0.5, c.height[t], @as(f32, @floatFromInt(wz)) + 0.5)),
            m.rotY(hsh * std.math.tau), m.scale3(m.splat(sc)),
          }), .{.glow = if (id == .node_ley) 0.7 else 0, .phase = hsh});
        }
      }
    }
  }

  /// plant a starter garden around the player and fast-forward (showcase/testing).
  pub fn demo(g:*Game, seconds:f32) !void {
    const cx:i32 = @intFromFloat(@floor(g.player.pos[0]));
    const cz:i32 = @intFromFloat(@floor(g.player.pos[2]));
    var dz:i32 = -4;
    while (dz <= 4) : (dz += 1) {
      var dx:i32 = -6;
      while (dx <= 6) : (dx += 1) {
        if (@abs(dx) <= 1 and @abs(dz) <= 1) continue;
        const sp:species.Id = if (dx > 2) .thornleech else if (dx < -2 or @mod(dz, 2) == 0) .lumenroot else continue;
        _ = try g.plants.place(g.gpa, &g.world, cx + dx, cz + dz, sp, g.rng.float());
      }
    }
    // the first automation: a lumenroot harvested by conduits into a cache,
    // a germinator and research bloom already fed, new plant forms around
    for ([_]prog.Id{.ley_sight, .drift_spores, .root_communion, .canopy_weaving}) |id| g.prog.done.insert(id);
    _ = try g.structs.place(g.gpa, &g.world, cx - 2, cz - 3, .conduit, 0, 0.1);
    _ = try g.structs.place(g.gpa, &g.world, cx - 1, cz - 3, .conduit, 0, 0.2);
    _ = try g.structs.place(g.gpa, &g.world, cx, cz - 3, .sap_cache, 0, 0.3);
    if (try g.structs.place(g.gpa, &g.world, cx - 2, cz + 5, .germinator, 0, 0.4)) {
      const j = g.structs.at(&g.world, cx - 2, cz + 5).?;
      _ = g.structs.insert(&g.prog, j, .fibre, 20);
      _ = g.structs.insert(&g.prog, j, .starlight, 20);
    }
    if (try g.structs.place(g.gpa, &g.world, cx + 1, cz + 5, .research_bloom, 0, 0.5)) {
      g.prog.select(.hungering_tendrils);
      const j = g.structs.at(&g.world, cx + 1, cz + 5).?;
      _ = g.structs.insert(&g.prog, j, .essence, 20);
      _ = g.structs.insert(&g.prog, j, .grit, 20);
    }
    _ = try g.plants.place(g.gpa, &g.world, cx - 6, cz + 6, .hollowheart, 0.7);
    _ = try g.plants.place(g.gpa, &g.world, cx - 5, cz - 1, .driftwisp, 0.8);
    _ = try g.plants.place(g.gpa, &g.world, cx - 4, cz + 2, .driftwisp, 0.9);

    var t:f32 = 0;
    while (t < seconds) : (t += TICK) {
      g.prog.absorb(try g.eco.tick(g.gpa, &g.plants, &g.world, g.prog.mods(), TICK), TICK);
      g.structs.tick(&g.world, &g.plants, &g.prog, TICK);
    }
    _ = g.player.inv.add(.grit, 34);
    _ = g.player.inv.add(.fibre, 21);
    _ = g.player.inv.add(.starlight, 7);
    _ = g.player.inv.add(.seed_lumenroot, 5);
    _ = g.player.inv.add(.conduit, 6);
  }

  /// fill a side x side field with random species (perf testing).
  pub fn stress(g:*Game, side:i32) !void {
    const cx:i32 = @intFromFloat(@floor(g.player.pos[0]));
    const cz:i32 = @intFromFloat(@floor(g.player.pos[2]));
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
};
