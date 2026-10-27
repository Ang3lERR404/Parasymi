//! `--plant=<species>` / `--structure=<kind>`: one plant or structure alone
//! in the world, held in one state or looping one animation (`--state=`,
//! `--period=`), for testing how it grows, looks and works. Nothing else is
//! put down or drawn (no wolf or motes; a plant has no nodes or structures
//! round it, a structure keeps the world's resource nodes, which it may
//! work), and the renderer builds only the meshes it draws (`only`). Not
//! part of play: it sets the thing's state itself.
const lib = @import("../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const stringToEnum = std.meta.stringToEnum;
const parseFloat = std.fmt.parseFloat;
const indexOf = std.mem.indexOf;
const eql = std.mem.eql;
const values = std.enums.values;
const indexOfScalar = std.mem.indexOfScalar;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const ck = lib.ck;
const species = lib.species;
const items = lib.items;
const meshlib = lib.meshlib;
const meshgen = lib.meshgen;
const renderer = lib.renderer;
const st = lib.structures;
const prog = lib.progression;
const resources = lib.resources;
const Parts = lib.parts.Parts;
const play = lib.play;
const actions = lib.actions;
const turn = lib.turn;
const Game = play.Game;
const diag = lib.diagnostics;

/// a loop's animation runs `period` seconds, then holds its end this long
/// before it starts again
const HOLD:f32 = 1.5;
/// seconds a loop runs unless `--period` says: an active structure's runs
/// long enough for a weave or a study unit
const PERIOD:f32 = 8;
const ACTIVE_PERIOD:f32 = 30;
/// turning, it turns a quarter this often (s) unless `--period` says
const TURN_PERIOD:f32 = turn.TIME + 1;
/// live, a grown (or dead) plant is sown afresh this long after
const REGROW:f32 = 4;
/// held, a plant never grows on its own
const NEVER:f32 = 1e9;
/// a tile to sow on: searched this far round the wolf
const SEARCH:i32 = 8;
/// active, a structure is handed one of what it wants this often (s), and
/// what it made is taken from it; a carrier lets go of what it carries
/// this long after taking it (nothing stands ahead to take it)
const FEED:f32 = 0.4;
const CARRY:f32 = 2;
/// the specimen's seed (its variant, its phase)
const SEED:f32 = 0.37;

/// what stands alone
pub const Subject = union(enum) {
  plant:species.Id,
  structure:st.Kind,
};

pub const State = union(enum) {
  /// grows from nothing to grown, again and again
  grow,
  /// growth from one share to another, again and again
  span:[2]f32,
  /// held at one share of growth (`mature`: grown)
  held:f32,
  /// a plant grown, its health failing to nothing, again and again (a
  /// radiant plant comes loose, its light dims)
  wither,
  /// a plant grown, sap rising through it and ebbing (flow), round and round
  flow,
  /// a plant grown, its mana draining to empty, again and again
  drain,
  /// a plant grown, a celestial bloom's network dark
  dark,
  /// a plant sown and left to the ecology as in play; sown afresh once grown
  live,
  /// a structure grown and working: fed what it wants, what it makes taken
  /// away, put down afresh each loop (its emitted pieces as in play)
  active,
  /// grown, turned a quarter (R) each loop: a rooted one uproots itself on
  /// its roots, turns and digs back in; a floater only turns
  turn,
  /// shown as set from outside (the animation editor, tools/animedit.zig)
  look:Look,

  /// a name, a share of growth (`0.4`) or a span (`0.2..0.8`)
  pub fn parse(s:[]const u8) error{BadState}!State {
    if (eql(u8, s, "mature") or eql(u8, s, "idle")) return .{.held = 1};
    if (stringToEnum(enum { grow, wither, flow, drain, dark, live, active, turn }, s)) |k| return switch (k) {
      .grow => .grow, .wither => .wither, .flow => .flow, .drain => .drain, .dark => .dark, .live => .live, .active => .active, .turn => .turn,
    };
    if (indexOf(u8, s, "..")) |dots| {
      const a = parseFloat(f32, s[0..dots]) catch return error.BadState;
      const b = parseFloat(f32, s[dots + 2 ..]) catch return error.BadState;
      return .{.span = .{m.clamp01(a), m.clamp01(b)}};
    }
    return .{.held = m.clamp01(parseFloat(f32, s) catch return error.BadState)};
  }

  /// whether a subject can show it (growth states suit both; plants
  /// wither, flow, drain, darken and live; structures work)
  pub fn suits(s:State, what:Subject) bool {
    return switch (s) {
      .grow, .span, .held, .turn, .look => true,
      .wither, .flow, .drain, .dark, .live => what == .plant,
      .active => what == .structure,
    };
  }
};

/// what it shows this moment (a structure: `growth` only)
pub const Look = struct { growth:f32 = 1, mana:f32 = 1, flow:f32 = 0, health:f32 = 1, radiating:bool = true };

pub const Specimen = struct {
  what:Subject,
  state:State = .grow,
  /// seconds one loop's animation runs (unset: `PERIOD`, `ACTIVE_PERIOD`)
  period:?f32 = null,
  t:f32 = 0,
  /// active: seconds to the next feeding, and since its carried item came
  feed_t:f32 = 0,
  carry_t:f32 = 0,
  /// the tile it stands on (found by `sow`)
  at:[2]i32 = .{0, 0},

  /// the meshes to build: the species' (and a floater's shadow), or what
  /// the structure draws and the resource nodes round it
  pub fn only(s:*const Specimen, arena:Allocator) Allocator.Error!renderer.Only {
    switch (s.what) {
      .plant => |sp| return .{.species = sp, .parts = &.{.shadow, .turn_root, .turn_root_pale}},
      .structure => |k| {
        var list:std.ArrayList(meshlib.Id) = .empty;
        try list.appendSlice(arena, st.meshes(k));
        try list.appendSlice(arena, &.{.turn_root, .turn_root_pale});
        for (values(ck.Kind)) |t| if (resources.of(t)) |n| try list.append(arena, n.mesh);
        return .{.parts = list.items};
      },
    }
  }

  /// put it down on the free tile nearest the wolf (a structure beside a
  /// resource node if one is near, for it may work it) and stand the wolf
  /// (and the camera) over it
  pub fn sow(s:*Specimen, g:*Game) Allocator.Error!void {
    if (s.state == .active) study(g);
    const cx, const cz = m.tileAt(g.player.pos);
    var found = false;
    for ([_]bool{true, false}) |by_node| {
      var r:i32 = 0;
      find: while (r < SEARCH) : (r += 1) {
        var it = m.ring(r);
        while (it.next()) |o| {
          const x = cx + o[0];
          const z = cz + o[1];
          if (!s.fits(g, x, z) or (by_node and !nodeNear(g, x, z))) continue;
          s.at = .{x, z};
          found = true;
          break :find;
        }
      }
      if (found or s.what == .plant) break;
    }
    if (!found) switch(s.what) {
      .structure => |k| {
        s.at = .{cz, cx};
        const sdef = st.defs.get(k);
        const size = sdef.size;
        const fallback = st.firstGround(k);
        const c0 = g.world.chunkOfTile(cx, cz) orelse return;
        const h0 = c0.height[ck.localIndex(cx, cz)];
        for(0..size,0..size) |dx,dz| {
          const lx = cx + @as(i32, @intCast(dx));
          const lz = cz + @as(i32, @intCast(dz));
          if (g.world.chunkOfTile(lx, lz)) |c| {
            const t = ck.localIndex(lx, lz);
            c.kind[t] = fallback;
            c.height[t] = h0;
          }
        }
      },
      else => {}
    };
    try s.put(g);
    const size:u8, const up:f32 = switch (s.what) {
      .plant => |sp| .{if (species.get(sp).floating) 1 else species.get(sp).size, 0},
      .structure => |k| .{st.defs.get(k).size, st.defs.get(k).hover},
    };
    g.player.pos = m.footprintCentre(s.at[0], s.at[1], size, g.heightAt(s.at[0], s.at[1]));
    g.cam.target = g.player.pos + m.v3(0, up, 0);
  }

  fn fits(s:*const Specimen, g:*const Game, x:i32, z:i32) bool {
    return switch (s.what) {
      .plant => |sp| g.plants.canPlace(&g.world, x, z, sp),
      .structure => |k| g.structs.canPlace(&g.world, x, z, k),
    };
  }

  fn put(s:*Specimen, g:*Game) Allocator.Error!void {
    const l = s.look();
    switch (s.what) {
      .plant => |sp| _ = try g.plants.placeEx(g.gpa, &g.world, s.at[0], s.at[1], .{
        .x = s.at[0], .y = s.at[1], .chunk = undefined, .tile = undefined, .sp = sp, .seed = SEED,
        .growth = if (s.state == .live) 0 else l.growth, .span = if (s.state == .live) 0 else NEVER,
      }),
      .structure => |k| {
        const ok = try g.structs.place(g.gpa, &g.world, s.at[0], s.at[1], k, 0, SEED);
        if (!ok) diag.whyNot(&g.structs, &g.world, s.at[0], s.at[1], k);
        if (g.structs.list.items.len > 0) g.structs.list.items[0].grown = l.growth;
      },
    }
  }

  /// one tick before the world's: held, it is set as its state says and
  /// the world's tick is left out (whether this tick is handled); live or
  /// active, the world runs (`after` it)
  pub fn hold(s:*Specimen, g:*Game, dt:f32) Allocator.Error!bool {
    if (s.state == .live or s.state == .active) return false;
    s.t += dt;
    const l = s.look();
    // turning: a quarter each loop, as R does it in play
    if (s.state == .turn) {
      s.feed_t -= dt;
      if (s.feed_t <= 0) {
        s.feed_t = s.loop();
        _ = actions.turnAt(g, s.at, false);
      }
    }
    switch (s.what) {
      .plant => |sp| {
        // uprooted: back it comes
        if (g.plants.len() == 0) try s.put(g);
        const def = species.get(sp);
        const p = g.plants.list.slice();
        p.items(.growth)[0] = l.growth;
        p.items(.mana)[0] = l.mana * def.mana_cap;
        p.items(.flow)[0] = l.flow;
        p.items(.health)[0] = l.health;
        p.items(.span)[0] = NEVER;
        const rad = &g.eco.radiance.radiating;
        try rad.resize(g.gpa, g.plants.len());
        rad.items[0] = def.radiance > 0 and l.radiating;
      },
      .structure => {
        if (g.structs.list.items.len == 0) try s.put(g);
        // it notices its neighbours (a conduit its arches) but never works
        lib.structures.Structures.linkWith(g.structCtx(.{}));
        if (g.structs.list.items.len == 0) return false;
        const one = &g.structs.list.items[0];
        one.grown = l.growth;
        one.activity = 0;
      },
    }
    return true;
  }

  /// after the world's tick. A live plant, once grown (or gone) and left a
  /// while, is sown afresh; an active structure is fed, emptied of what it
  /// made, and put down afresh each loop.
  pub fn after(s:*Specimen, g:*Game, dt:f32) Allocator.Error!void {
    switch (s.state) {
      .live => {
        const gone = g.plants.len() == 0;
        if (!gone and g.plants.list.items(.growth)[0] < 1) return;
        s.t += dt;
        if (s.t < REGROW) return;
        s.t = 0;
        if (!gone) g.plants.remove(&g.world, .of(0));
        try s.put(g);
      },
      .active => {
        s.t += dt;
        const gone = g.structs.list.items.len == 0;
        if (gone or s.t >= s.loop()) {
          s.t = 0;
          // what it put down (a polyp's diamond) goes with it
          while (g.structs.list.items.len > 0) {
            var gone_s = g.structs.remove(&g.world, .of(g.structs.list.items.len - 1));
            gone_s.deinit(g.gpa);
          }
          try s.put(g);
        }
        s.feed_t -= dt;
        s.carry_t += dt;
        if (s.feed_t > 0) return;
        s.feed_t = FEED;
        feed(s, g);
      },
      else => {},
    }
  }

  /// one of the next thing it wants handed in (a carrier takes it in from
  /// behind), what it made taken away; a carrier lets go of what it has
  /// carried a while
  fn feed(s:*Specimen, g:*Game) void {
    const id:st.Id = .of(0);
    const one = g.structs.get(id);
    if (one.def().carrier) {
      if (s.carry_t >= CARRY) _ = st.release(one);
    } else if (g.structs.output(id)) |made| {
      if (g.structs.wants(&g.prog, id, made) == 0) _ = one.inv.take(made, 1);
    }
    const all = values(items.Item);
    // a different kind each time, round all it takes
    const from:usize = @intFromFloat(@mod(g.time * 7 + m.f(g.ticks), m.f(all.len)));
    for (0..all.len) |i| {
      const item = all[(from + i) % all.len];
      if (!one.def().carrier and g.structs.wants(&g.prog, id, item) == 0) continue;
      if (g.structs.handIn(&g.prog, id, item, 2)) {
        s.carry_t = 0;
        return;
      }
      if (one.def().carrier) return;
    }
  }

  /// seconds one loop runs
  fn loop(s:*const Specimen) f32 {
    return s.period orelse switch (s.state) {
      .active => ACTIVE_PERIOD,
      .turn => TURN_PERIOD,
      else => PERIOD,
    };
  }

  /// how far through this loop's animation (0..1; 1 through the hold)
  fn share(s:*const Specimen) f32 {
    const p = s.loop();
    return m.clamp01(@mod(s.t, p + HOLD) / p);
  }

  fn look(s:*const Specimen) Look {
    const k = s.share();
    return switch (s.state) {
      .grow => .{.growth = k},
      .span => |ab| .{.growth = m.lerp(ab[0], ab[1], k)},
      .held => |h| .{.growth = h},
      .wither => .{.health = 1 - k},
      .flow => .{.flow = 0.5 - 0.5 * @cos(s.t / s.loop() * m.tau)},
      .drain => .{.mana = 1 - k},
      .dark => .{.radiating = false},
      .live => .{.growth = 0},
      .look => |l| l,
      .active, .turn => .{},
    };
  }
};

/// an arsthraxia studies what is chosen: the first open study that takes
/// ingredients
fn study(g:*Game) void {
  if (g.prog.current != null) return;
  for (values(prog.Id)) |id| if (g.prog.status(id) == .open and prog.tree.get(id).per_unit.len > 0) {
    g.prog.current = id;
    return;
  };
}

/// a resource node beside (x, z), edge to edge (what a digger digs, and
/// one of the eight tiles a lithophage drains)
fn nodeNear(g:*const Game, x:i32, z:i32) bool {
  for (m.dirs) |d| {
    const v = m.dirVec(d);
    const c = g.world.chunkOfTile(x + v.x, z + v.z) orelse continue;
    const t = ck.localIndex(x + v.x, z + v.z);
    if (c.res[t] > 0 and resources.of(c.kind[t]) != null) return true;
  }
  return false;
}

test "a state is a name, a share of growth or a span" {
  try testing.expect(try State.parse("grow") == .grow);
  try testing.expectEqual(@as(f32, 1), (try State.parse("mature")).held);
  try testing.expectEqual(@as(f32, 0.4), (try State.parse("0.4")).held);
  try testing.expectEqual([2]f32{0.2, 0.8}, (try State.parse("0.2..0.8")).span);
  try testing.expectError(error.BadState, State.parse("sideways"));
  try testing.expect((try State.parse("active")).suits(.{.structure = .germinator}));
  try testing.expect(!(try State.parse("wither")).suits(.{.structure = .germinator}));
}

test "a loop runs its period, holds its end, then starts again" {
  var s:Specimen = .{.what = .{.plant = .lumenroot}, .period = 4};
  s.t = 2;
  try testing.expectApproxEqAbs(@as(f32, 0.5), s.look().growth, 1e-5);
  s.t = 4 + HOLD * 0.5;
  try testing.expectEqual(@as(f32, 1), s.look().growth);
  s.t = 4 + HOLD + 1;
  try testing.expectApproxEqAbs(@as(f32, 0.25), s.look().growth, 1e-5);
}

test "held, the plant shows its state and nothing else grows it" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, play.DEFAULT_SEED);
  defer g.deinit();
  g.specimen = .{.what = .{.plant = .vesper}, .state = .{.held = 0.5}};
  try g.specimen.?.sow(&g);
  try testing.expectEqual(@as(usize, 1), g.plants.len());
  // a vesper out of radiance would wither: held, it does not
  for (0..120) |_| try g.step();
  try testing.expectEqual(@as(usize, 1), g.plants.len());
  try testing.expectEqual(@as(f32, 0.5), g.plants.list.items(.growth)[0]);
  try testing.expectEqual(@as(f32, 1), g.plants.list.items(.health)[0]);
}

test "a structure alone draws only the meshes it declares" {
  const gpa = testing.allocator;
  for (values(st.Kind)) |k| for ([_]State{.grow, .active}) |state| {
    var g = try Game.init(gpa, play.DEFAULT_SEED);
    defer g.deinit();
    g.specimen = .{.what = .{.structure = k}, .state = state, .period = 20};
    try g.specimen.?.sow(&g);
    try testing.expectEqual(@as(usize, 1), g.structs.list.items.len);
    const declared = st.meshes(k);
    var parts = Parts.init(gpa);
    defer parts.deinit();
    // a loop and a half, its pieces looked at four times a second
    var t:f32 = 0;
    while (t < 30) : (t += 0.25) {
      for (0..@intFromFloat(0.25 / play.TICK)) |_| try g.step();
      parts.clear();
      for (g.structs.list.items) |*s| {
        const ctr = m.footprintCentre(s.x, s.y, s.def().size, g.heightAt(s.x, s.y));
        try st.emit(s, &parts, ctr, t);
      }
      for (parts.lists, 0..) |l, slot| if (l.items.len > 0) {
        const id:meshlib.Id = @enumFromInt(slot / meshgen.LODS);
        if (indexOfScalar(meshlib.Id, declared, id) == null) {
          std.debug.print("{t} emits {t}, not in its `meshes`\n", .{k, id});
          return error.UndeclaredMesh;
        }
      };
    }
  };
}
