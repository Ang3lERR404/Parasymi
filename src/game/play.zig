//! the playable layer: owns world + sim + progression + the player and runs a
//! frame: input -> actions (actions.zig), fixed-tick simulation, and what gets
//! drawn (view.zig). Nothing is pooled globally: items live in the player and
//! in structures, essence and seeds live in plants until harvested.
const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const eqlDeep = std.meta.eql;
const m = @import("../core/math.zig");
const Rng = @import("../core/rng.zig").Rng;
const ck = @import("../world/chunk.zig");
const gen = @import("../world/gen.zig");
const World = @import("../world/world.zig").World;
const species = @import("../sim/species.zig");
const Plants = @import("../sim/plants.zig").Plants;
const ecology = @import("../sim/ecology.zig");
const Ecology = ecology.Ecology;
const items = @import("../sim/items.zig");
const prog = @import("progression.zig");
const txt = @import("text.zig");
const Input = @import("../platform/input.zig").Input;
const ctl = @import("controls.zig");
const camera = @import("../render/camera.zig");
const Camera = camera.Camera;
const renderer = @import("../render/renderer.zig");
const vertex = @import("../gfx/vertex.zig");
const Draw = @import("../ui/draw.zig").Draw;
const sky_mod = @import("sky.zig");
const Player = @import("player.zig").Player;
const Parts = @import("parts.zig").Parts;
const craft = @import("craft.zig");
const st = @import("structures.zig");
const actions = @import("actions.zig");
const convergence = @import("convergence.zig");
const hud = @import("hud.zig");

pub const TICK = 1.0 / 60.0;
/// the world every new game grows from, unless `--seed=` says otherwise
pub const DEFAULT_SEED:u64 = 0x5EED_0F_11FE;
/// the window's size when it opens
pub const WINDOW = [2]u16{ 1600, 900 };
const STREAM_RADIUS = 4;
/// nothing is drawn further than this from the camera target (inside the
/// streamed radius, so a low camera never runs off the generated world)
pub const DRAW_LIMIT:f32 = (STREAM_RADIUS - 0.5) * ck.SIZE;

/// max chunks to stream in a single call (initial load is generous,
/// per-frame is tight to avoid hitches)
const STREAM_INIT = 1 << 10;
const STREAM_FRAME = 4;

/// camera feel parameters (tune here, not scattered through update)
const YAW_SPEED:f32 = 1.5;
const TILT_SPEED:f32 = 1.2;
const FOLLOW_LERP:f32 = 6;
/// the camera follows a point this far above the wolf's feet
const FOLLOW_HEIGHT:f32 = 0.6;
/// how quickly the shown frame and sim timings follow the measured ones
pub const TIMING_EASE:f32 = 0.05;
/// free camera: Shift multiplies the fly speed; the wheel dollies this much a notch
const FLY_FAST:f32 = 3;
const DOLLY_PER_NOTCH:f32 = 0.4;

/// the simulation never runs more than this many catch-up ticks a frame
const MAX_CATCHUP = 8;
/// the spawn search spirals out to this radius in steps of this many tiles
const SPAWN_SEARCH = 400;
const SPAWN_STEP = 3;

/// ray-march parameters for ground picking
const PICK_STEP:f32 = 0.1;
const PICK_RANGE_MULT:f32 = 4;

/// everything the wolf can put into the world, in hotbar slot order
/// (`ctl.slots`).
pub const hotbar = [_]items.Item{
  .seed_lumenroot, .seed_thornleech, .seed_vesper, .seed_driftwisp, .seed_hollowheart,
  .conduit, .sap_cache, .germinator, .research_bloom, .root_digger, .seed_bloom, .polyp,
};
comptime { std.debug.assert(hotbar.len == ctl.slots.len); }

/// can the gardener place this hotbar item yet (seed understood / always for bulbs)?
pub fn known(g:*const Game, item:items.Item) bool {
  return if (item.plants()) |sp| g.prog.canPlant(sp) else true;
}

pub const Request = enum { save, load, fullscreen, quit };

/// what has the wolf's attention; only one at a time.
pub const Mode = enum {
  /// out in the garden: moving, gathering, placing
  roam,
  /// the belly is open (Tab): weaving by hand
  belly,
  /// the research list is open (T)
  research,
  /// the world is frozen and the pause menu is open (Esc)
  paused,
  /// the free camera is flying for inspection (Ctrl+F); the wolf stands idle
  inspect,

  /// the world keeps moving underneath (everything but the pause menu)
  pub fn live(md:Mode) bool { return md != .paused; }
};

const Error = Allocator.Error;

pub const Game = struct {
  gpa:Allocator,
  world:World,
  plants:Plants = .{},
  structs:st.Structures = .{},
  eco:Ecology = .{},
  /// the standing fields of celestial energy (halos), gathered each tick
  fields:std.ArrayList(ecology.Field) = .empty,
  converge:convergence.Seeker = .{},
  prog:prog.Progression = .{},
  cam:Camera = .{},
  sky:sky_mod.Sky = .{},
  stars:sky_mod.Starfall,
  player:Player,
  rng:Rng,
  parts:Parts,
  ui:Draw,
  /// what a click on the HUD would land on, as drawn last frame
  rows:hud.Rows = .{},
  /// the HUD area under the mouse this frame (panels show what it points at)
  pointed:?hud.Pick = null,
  sapling:hud.Sapling = .{},
  weave:craft.Crafter = .{},

  mode:Mode = .roam,
  /// something only main can do (it owns the window and the file system).
  request:?Request = null,
  /// keeps running while paused, so the UI still breathes.
  ui_time:f64 = 0,

  hot:usize = 0,
  /// facing for the next structure placed (R rotates)
  place_dir:m.Dir = 0,
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
  inst:[renderer.PLANT_MESHES]std.ArrayList(vertex.PlantInstance) = @splat(.empty),
  far:std.ArrayList(*ck.Chunk) = .empty,
  render_stats:renderer.Stats = .{},

  pub fn init(gpa:Allocator, seed:u64) Error!Game {
    var g:Game = .{
      .gpa = gpa,
      .world = World.init(gpa, seed),
      .rng = Rng.init(seed ^ 0xA11CE),
      .stars = .{ .rng = Rng.init(seed ^ 0x57A2) },
      .player = .{ .pos = m.v3(0.5, 0, 0.5) },
      .parts = Parts.init(gpa),
      .ui = .{ .gpa = gpa },
    };
    // start on dry land: spiral out from the origin until a fertile tile shows up.
    var r:i32 = 0;
    find: while (r < SPAWN_SEARCH) : (r += SPAWN_STEP) {
      var a:i32 = -r;
      while (a <= r) : (a += SPAWN_STEP) {
        const z = r - @divFloor(r, 2);
        const s = gen.sample(seed, a, z);
        if (s.kind.fertile()) {
          g.player.pos = m.tileCentre(a, z, s.height);
          break :find;
        }
      }
    }
    g.cam.target = g.player.pos;
    try g.world.stream(g.focus(), STREAM_RADIUS, STREAM_INIT);
    g.prog.say(txt.s.msg.wake, .{});
    g.prog.say(txt.s.msg.night_hint, .{});
    return g;
  }

  pub fn deinit(g:*Game) void {
    for (&g.inst) |*l| l.deinit(g.gpa);
    g.far.deinit(g.gpa);
    g.parts.deinit();
    g.ui.deinit();
    g.stars.deinit(g.gpa);
    g.eco.deinit(g.gpa);
    g.fields.deinit(g.gpa);
    g.plants.deinit(g.gpa);
    g.structs.deinit(g.gpa);
    g.world.deinit();
  }

  pub fn focus(g:*const Game) ck.Coord {
    const t = m.tileAt(g.player.pos);
    return ck.Coord.ofTile(t[0], t[1]);
  }

  pub fn heightAt(g:*const Game, wx:i32, wy:i32) f32 {
    if (g.world.chunkOfTile(wx, wy)) |c| return c.height[ck.localIndex(wx, wy)];
    return gen.heightAt(g.world.seed, wx, wy);
  }

  /// march the mouse ray until it dips below the terraced ground.
  fn pick(g:*const Game, in:*const Input, screen:[2]f32) ?[2]i32 {
    const ray = g.cam.ray(in.mouse[0], in.mouse[1], screen[0], screen[1]);
    var t:f32 = 0;
    const max_t = g.cam.dist * PICK_RANGE_MULT;
    while (t < max_t) : (t += PICK_STEP) {
      const p = ray.o + ray.d * m.splat3(t);
      const tile = m.tileAt(p);
      if (p[1] <= g.heightAt(tile[0], tile[1])) return tile;
    }
    return null;
  }

  pub fn update(g:*Game, in:*const Input, dt:f32, screen:[2]f32) Error!void {
    g.ui_time += dt;
    g.frame_ms += (dt * m.MS_PER_S - g.frame_ms) * TIMING_EASE;
    g.cam.aspect = screen[0] / @max(screen[1], 1);

    // system keys work everywhere; Esc closes a panel first, then pauses
    if (ctl.pressed(in, .save)) g.request = .save;
    if (ctl.pressed(in, .load)) g.request = .load;
    if (ctl.pressed(in, .fullscreen)) g.request = .fullscreen;
    if (ctl.pressed(in, .back)) switch (g.mode) {
      .roam => g.mode = .paused,
      .belly, .research, .paused => g.mode = .roam,
      .inspect => g.inspect(in, false),
    };
    if (!g.mode.live()) {
      if (ctl.pressed(in, .quit)) g.request = .quit;
      return;
    }

    g.time += dt;
    g.sky.update(dt);

    // decision: alt + free_cam (Ctrl+F) toggles the free inspection camera
    // (harvest alone, F, harvests)
    const alt = ctl.down(in, .alt);
    if (alt and ctl.pressed(in, .free_cam)) g.inspect(in, g.mode != .inspect);
    const inspecting = g.mode == .inspect;
    g.cam.tick(dt);

    // panels and selection
    if (!inspecting) {
      if (ctl.pressed(in, .belly)) g.mode = if (g.mode == .belly) .roam else .belly;
      if (ctl.pressed(in, .research)) g.mode = if (g.mode == .research) .roam else .research;
    }
    if (ctl.pressed(in, .debug)) g.debug = !g.debug;
    if (ctl.pressed(in, .rotate)) g.place_dir +%= 1;
    // slot keys pick the hotbar slot, whichever panel is open
    if (!inspecting) for (ctl.slots, 0..) |a, i| {
      if (ctl.pressed(in, a)) g.hot = i;
    };

    // a click lands on the HUD panel under the mouse before the world: rows
    // choose research or weave a recipe; a panel's backdrop just absorbs it
    const ui_hit = if (inspecting) null else g.rows.at(in.mouse);
    g.pointed = ui_hit;
    if (ctl.pressed(in, .use)) if (ui_hit) |hit| switch (hit) {
      .panel => {},
      .research => |id| g.prog.select(id),
      .weave => |i| actions.weaveByHand(g, i),
    };

    // movement relative to the camera
    var mx:f32 = 0;
    var mz:f32 = 0;
    // decision: Ctrl+W/S tilts the camera (Shift is already sprint); W/S do
    // not move the wolf while Ctrl is held.
    if (inspecting) {
      g.fly(in, dt);
    } else {
      if (ctl.down(in, .move_left)) mx -= 1;
      if (ctl.down(in, .move_right)) mx += 1;
    }
    if (inspecting) {} else if (alt) {
      if (ctl.down(in, .move_forward)) g.cam.tilt(dt * TILT_SPEED);
      if (ctl.down(in, .move_back)) g.cam.tilt(-dt * TILT_SPEED);
    } else {
      if (ctl.down(in, .move_forward)) mz += 1;
      if (ctl.down(in, .move_back)) mz -= 1;
    }
    const yaw = g.cam.yaw;
    var wish = [2]f32{@cos(yaw) * mx - @sin(yaw) * mz, -@sin(yaw) * mx - @cos(yaw) * mz};
    const wl = @sqrt(wish[0] * wish[0] + wish[1] * wish[1]);
    if (wl > 1) wish = .{ wish[0] / wl, wish[1] / wl };

    if (!inspecting) {
      if (ctl.down(in, .yaw_left)) g.cam.yaw -= dt * YAW_SPEED;
      if (ctl.down(in, .yaw_right)) g.cam.yaw += dt * YAW_SPEED;
      if (in.scroll != 0) g.cam.zoom(in.scroll);
    }

    // interaction with the hovered tile (none while inspecting)
    g.hover = if (inspecting) null else g.pick(in, screen);
    var working = false;
    var work:?m.V3 = null;
    g.plant_cd -= dt;
    g.linger -= dt;
    if (!ctl.down(in, .use)) {
      g.gather_t = 0;
      g.full_warned = false;
    }
    if (g.hover) |h| if (g.player.inReach(h[0], h[1])) if (g.world.chunkOfTile(h[0], h[1])) |c| {
      const t = ck.localIndex(h[0], h[1]);
      const on_struct = g.structs.at(&g.world, h[0], h[1]);
      if (ctl.down(in, .use) and on_struct == null and ui_hit == null) {
        if (c.res[t] > 0 and c.occ[t] == .none) working = actions.gather(g, c, t, dt)
        else if (g.plant_cd <= 0) try actions.put(g, h);
      }
      if (ctl.pressed(in, .harvest) and !alt) {
        if (on_struct) |j| {
          if (ctl.down(in, .take)) actions.takeFrom(g, j) else actions.feed(g, j);
        } else actions.harvest(g, h);
      }
      if (ctl.pressed(in, .configure)) if (on_struct) |j| st.configure(g.structs.get(j), &g.prog);
      if (ctl.pressed(in, .uproot)) {
        if (on_struct) |j| actions.unbuild(g, j)
        else if (g.plants.removeAt(&g.world, h[0], h[1])) _ = g.player.inv.add(.fibre, 1);
        g.linger = actions.LINGER_PUT;
      }
      if (working or g.linger > 0) work = m.tileCentre(h[0], h[1], c.height[t]);
    };
    // weaving: hands work at the chest while the queue runs
    if (g.weave.tick(g.player.inv.bag(), dt)) |made| g.prog.say(txt.s.msg.wove, .{txt.item(made).name});
    if (g.weave.busy() and !working) work = g.player.pos + m.v3(@sin(g.player.facing), 0, @cos(g.player.facing));
    // a one-off gesture keeps facing where it happened
    if (work == null and g.linger > 0) work = g.player.work;
    g.player.work = work;

    g.player.move(wish, ctl.down(in, .run), &g.world, dt);
    g.player.animate(dt);
    const follow = g.player.pos + m.v3(0, FOLLOW_HEIGHT, 0);
    g.cam.target += (follow - g.cam.target) * m.splat3(@min(1, dt * FOLLOW_LERP));

    try g.stars.update(g.gpa, &g.sky, g.player.pos, &g.world, dt);
    actions.catchStarlight(g, dt);

    // stream the world around the player; chunks holding what we grew stay
    try g.world.stream(g.focus(), STREAM_RADIUS, STREAM_FRAME);
    try g.world.far(g.focus(), STREAM_RADIUS, &g.far);
    for (g.far.items) |c| try g.world.unload(c);
  }

  /// enter or leave the free camera. Leaving gives the cursor back and eases
  /// the view home.
  fn inspect(g:*Game, in:*const Input, on:bool) void {
    if (on) {
      g.mode = .inspect;
      g.cam.startFree();
      return;
    }
    g.mode = .roam;
    if (g.cam.view == .free and g.cam.view.free.captured) in.capture(false);
    g.cam.endFree();
  }

  /// the free camera: click to hold the cursor and look around, WASD to fly
  /// (Shift faster), Q/E to roll, the wheel to dolly. Space and Ctrl+Space
  /// rise and sink.
  fn fly(g:*Game, in:*const Input, dt:f32) void {
    const f = switch (g.cam.view) {
      .free => |*f| f,
      .follow, .returning => return,
    };
    // the frame the cursor is taken its jump is not a look
    var look:[2]f32 = .{ 0, 0 };
    if (ctl.pressed(in, .use) and !f.captured) {
      in.capture(true);
      f.captured = true;
    } else if (f.captured or ctl.down(in, .use)) {
      look = .{ -in.mouse_delta[0] * camera.LOOK, -in.mouse_delta[1] * camera.LOOK };
    }
    const speed = camera.FLY * dt * @as(f32, if (ctl.down(in, .fly_fast)) FLY_FAST else 1);
    var move = m.v3(0, 0, 0);
    if (ctl.down(in, .move_forward)) move[2] += speed;
    if (ctl.down(in, .move_back)) move[2] -= speed;
    if (ctl.down(in, .move_right)) move[0] += speed;
    if (ctl.down(in, .move_left)) move[0] -= speed;
    if (ctl.down(in, .rise)) move[1] += if (ctl.down(in, .alt)) -speed else speed;
    var roll:f32 = 0;
    if (ctl.down(in, .roll_left)) roll -= camera.ROLL * dt;
    if (ctl.down(in, .roll_right)) roll += camera.ROLL * dt;
    g.cam.fly(look, move, roll, in.scroll * DOLLY_PER_NOTCH);
  }

  /// fixed-step simulation; never more than `MAX_CATCHUP` ticks per frame.
  pub fn simulate(g:*Game, frame_dt:f64) Error!void {
    if (!g.mode.live()) return;
    g.acc = @min(g.acc + frame_dt, TICK * MAX_CATCHUP);
    while (g.acc >= TICK) : (g.acc -= TICK) try g.step();
  }

  /// one fixed tick of everything that lives: ecology, convergence,
  /// progression, structures.
  /// (see the test below for the headless harness)
  pub fn step(g:*Game) Error!void {
    var mods = g.prog.mods();
    mods.night = 1 - g.sky.daylight();
    try st.fields(&g.structs, g.gpa, &g.fields);
    mods.fields = g.fields.items;
    const ev = try g.eco.tick(g.gpa, &g.plants, &g.world, mods, TICK);
    try g.converge.tick(g.gpa, &g.world, &g.plants, &g.structs, &g.prog);
    g.prog.absorb(ev, TICK);
    g.structs.tick(&g.world, &g.plants, &g.prog, TICK);
    g.ticks += 1;
  }
};

/// tests draw to a window of the default size
const TEST_SCREEN = [2]f32{ m.f(WINDOW[0]), m.f(WINDOW[1]) };

test "the wolf stays put without input" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  try @import("setups.zig").demo(&g, 5);
  var in:Input = .{ .win = undefined };
  in.mouse = .{ -1e4, -1e4 };
  const start = g.player.pos;
  for (0..300) |_| {
    try g.update(&in, TICK, TEST_SCREEN);
    try g.simulate(TICK);
  }
  try testing.expectApproxEqAbs(start[0], g.player.pos[0], 0.05);
  try testing.expectApproxEqAbs(start[2], g.player.pos[2], 0.05);
}
test "clicking a research node or weave recipe picks it; number keys only pick the hotbar" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  const screen = TEST_SCREEN;
  try ctl.fill(@embedFile("controls.cfg"));
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  const click = struct {
    /// press the left button over the middle of the first row picking `want`
    fn on(gg:*Game, i:*Input, want:hud.Pick, sc:[2]f32) !void {
      try hud.build(gg, sc);
      for (gg.rows.rect[0..gg.rows.len], gg.rows.pick[0..gg.rows.len]) |q, p| {
        if (!eqlDeep(p, want)) continue;
        i.mouse = .{q[0] + q[2] / 2, q[1] + q[3] / 2};
        i.advance();
        ctl.hold(i, .use, true);
        try gg.update(i, TICK, sc);
        i.advance();
        ctl.hold(i, .use, false);
        return;
      }
      return error.TestUnexpectedResult;
    }
  };

  g.mode = .research;
  try click.on(&g, &in, .{.research = .ley_sight}, screen);
  try testing.expect(g.prog.current == .ley_sight);

  g.mode = .belly;
  _ = g.player.inv.add(.fibre, 2);
  _ = g.player.inv.add(.starlight, 1);
  try testing.expect(craft.hand[0].out == .seed_lumenroot);
  try click.on(&g, &in, .{.weave = 0}, screen);
  try testing.expect(g.weave.busy());

  // with the belly open, a slot key picks the hotbar slot, not a recipe
  in.mouse = .{-1e4, -1e4};
  in.advance();
  ctl.hold(&in, .slot_3, true);
  try g.update(&in, TICK, screen);
  try testing.expectEqual(@as(usize, 2), g.hot);
  try testing.expectEqual(@as(usize, 1), g.weave.len);
}
