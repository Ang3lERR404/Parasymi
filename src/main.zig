//! Parasymi: a garden of magically infused plants, parasitic and symbiotic,
//! growing toward something beyond comprehension.
//!
//! layers (each only imports the ones above it):
//!   core -> platform -> gfx -> world -> sim -> game/render/ui -> main
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const parseFloat = std.fmt.parseFloat;
const parseInt = std.fmt.parseInt;
const eql = std.mem.eql;
const eqlDeep = std.meta.eql;
const startsWith = std.mem.startsWith;
const Init = std.process.Init;
const log = std.log;
const glfw = @import("zglfw");
const Input = @import("platform/input.zig").Input;
const Display = @import("platform/display.zig").Display;
const renderer = @import("render/renderer.zig");
const Renderer = renderer.Renderer;
const play = @import("game/play.zig");
const Game = play.Game;
const view = @import("game/view.zig");
const setups = @import("game/setups.zig");
const save = @import("game/save.zig");
const txt = @import("game/text.zig");
const controls = @import("game/controls.zig");
const options = @import("game/options.zig");
const home = @import("game/home.zig");
const orbit = @import("game/orbit.zig");
const loading = @import("game/loading.zig");
const Loading = loading.Loading;
const World = @import("world/world.zig").World;
const png = @import("core/png.zig");
const bufPrint = std.fmt.bufPrint;
const Dir = Io.Dir;
const sep_str = std.fs.path.sep_str;
const Options = options.Options;
const m = @import("core/math.zig");

/// a stalled frame (window drag, hitch) counts as at most this long (s)
const MAX_FRAME_DT:f64 = 0.1;
/// `--demo` fast-forwards its garden this many seconds; `--stress` sows a
/// field this many tiles on a side
const DEMO_FORWARD = 25;
const STRESS_SIDE = 120;
/// most streamed chunks meshed in one frame (`MESH_MS` also caps it)
const MESH_BUDGET = 6;
/// behind the loading screen a frame meshes the ground for this long (ms)
const LOAD_MESH_MS:f64 = 25;
/// `--inspect` writes its screenshots here, under the working directory
/// (kept out of git)
const SHOTS = "shots";

pub fn main(init:Init) !void {
  const gpa = init.gpa;
  const io = init.io;
  const args = try init.minimal.args.toSlice(init.arena.allocator());
  // every file of the gardener's lives in their folder, made on first start
  // (with the settings, strings and controls in it); files kept beside the
  // game before move in once
  try home.open(io, init.environ_map);
  defer home.close(io);
  home.adopt(io, options.PATH, options.PATH);
  home.adopt(io, save.LEGACY, home.SAVES ++ sep_str ++ save.LEGACY);
  // the gardener's settings; `--novsync` overrides theirs for this run
  var opts = try options.load(gpa, io);
  var demo = false;
  var stress = false;
  var load = false;
  var tod:?f32 = null;
  var seed:u64 = play.DEFAULT_SEED;
  // `--inspect[=player|<species>|<structure>|x,z]` turns the camera round
  // it, saving screenshots, then closes; `--shots=`, `--orbit=` (seconds a
  // turn), `--dist=`, `--pitch=` (degrees) shape it
  var inspect:?orbit.Focus = null;
  var turn:orbit.Orbit = .{};
  for (args[1..]) |a| {
    if (eql(u8, a, "--inspect")) inspect = .player;
    if (startsWith(u8, a, "--inspect=")) inspect = try orbit.Focus.parse(a["--inspect=".len..]);
    if (startsWith(u8, a, "--shots=")) turn.shots = try parseInt(u32, a["--shots=".len..], 0);
    if (startsWith(u8, a, "--orbit=")) turn.period = try parseFloat(f32, a["--orbit=".len..]);
    if (startsWith(u8, a, "--dist=")) turn.dist = try parseFloat(f32, a["--dist=".len..]);
    if (startsWith(u8, a, "--pitch=")) turn.pitch = m.rad(try parseFloat(f32, a["--pitch=".len..]));
    if (eql(u8, a, "--novsync")) opts.vsync = false;
    if (eql(u8, a, "--demo")) demo = true;
    if (eql(u8, a, "--stress")) stress = true;
    if (eql(u8, a, "--load")) load = true;
    if (startsWith(u8, a, "--tod=")) tod = try parseFloat(f32, a["--tod=".len..]);
    if (startsWith(u8, a, "--seed=")) seed = try parseInt(u64, a["--seed=".len..], 0);
  }

  // the only read of the controls file: no key or button is named in code.
  // First, so the strings can show what each action is bound to.
  try controls.load(gpa, io);
  defer controls.unload();
  // the only read of the strings file: everything shown comes from it
  try txt.load(gpa, io);
  defer txt.unload(gpa);

  try glfw.init();
  defer glfw.terminate();
  if (!glfw.isVulkanSupported()) return error.VulkanUnsupported;
  glfw.windowHint(.client_api, .no_api);
  const window = try glfw.createWindow(play.WINDOW[0], play.WINDOW[1], try init.arena.allocator().dupeZ(u8, txt.s.window.title), null, null);
  defer window.destroy();

  var input:Input = .{.win = window};
  input.attach();
  var display:Display = .{.win = window};

  const r = try Renderer.init(gpa, window, opts.vsync, opts.aa);
  defer r.deinit();
  opts.aa = r.antialiasing();

  // the loading screen shows while every mesh grows (on a thread of its
  // own), the world wakes and its ground is meshed. Until the world is
  // woken its chunks are counted as many as stream in round the gardener.
  var load_screen = Loading.init(gpa);
  defer load_screen.deinit();
  var last = glfw.getTime();
  const forms = r.meshProgress()[1];
  const whole = forms + 1 + play.STREAM_CHUNKS;
  while (!try r.meshesReady()) {
    if (!try loadFrame(&load_screen, r, &input, &last, .forms, .{.done = r.meshProgress()[0], .total = whole})) return;
  }
  if (!try loadFrame(&load_screen, r, &input, &last, .world, .{.done = forms, .total = whole})) return;

  var game = try Game.init(gpa, seed);
  defer game.deinit();
  // the world's heavy work (chunks generated and meshed, plants relinked)
  // is split over the pool
  game.world.io = io;
  game.opts = opts;
  game.most_samples = r.maxSamples();
  // what is in effect; the window opens windowed, so a fullscreen setting
  // is applied on the first frame
  var applied = opts;
  applied.fullscreen = false;
  if (load) {
    relist(gpa, io, &game);
    if (game.gardens.items.len > 0) _ = try restore(gpa, io, &game, r, game.gardens.items[0].name);
  }
  if (demo) try setups.demo(&game, DEMO_FORWARD);
  if (stress) try setups.stress(&game, STRESS_SIDE);
  if (tod) |t| game.sky.tod = t;
  if (inspect) |f| {
    turn.focus = f;
    Dir.cwd().createDirPath(io, SHOTS) catch |e| log.err("{s}: {t}", .{SHOTS, e});
  }
  if (!try ground(&load_screen, r, &input, &last, &game.world, forms + 1)) return;
  // play's clock runs on from the screen's, so it fades off without a jump
  game.ui_time = load_screen.time;

  while (!window.shouldClose()) {
    glfw.pollEvents();
    input.update();

    const now = glfw.getTime();
    // a stalled frame must not fling animation or movement
    const dt = @min(now - last, MAX_FRAME_DT);
    last = now;

    const screen = r.extent();
    try game.update(&input, @floatCast(dt), screen);
    if (game.request) |rq| {
      game.request = null;
      switch (rq) {
        .save => keep(gpa, io, &game, game.slot),
        .save_as => |n| keep(gpa, io, &game, n),
        .autosave => keep(gpa, io, &game, save.Name.of(save.AUTO).?),
        .load => {
          // the garden being played as last saved, else the newest
          const n = game.slot orelse newest: {
            relist(gpa, io, &game);
            if (game.gardens.items.len == 0) {
              game.prog.say(txt.s.msg.no_save, .{error.NoSave});
              break :newest null;
            }
            break :newest game.gardens.items[0].name;
          };
          if (n) |nn| if (try restore(gpa, io, &game, r, nn)) {
            if (!try reground(&load_screen, r, &input, &last, &game)) break;
          };
        },
        .load_from => |n| if (try restore(gpa, io, &game, r, n)) {
          if (!try reground(&load_screen, r, &input, &last, &game)) break;
        },
        .list => relist(gpa, io, &game),
        .quit => {
          keep(gpa, io, &game, game.slot);
          window.setShouldClose(true);
        },
      }
    }
    if (!eqlDeep(game.opts, applied)) try apply(io, &game, r, &display, &applied);
    // inspecting, the camera turns round the focus and the HUD is hidden
    const shoot = if (inspect != null) turn.step(&game, @floatCast(dt)) else false;
    const t0 = glfw.getTime();
    try game.simulate(dt);
    game.sim_ms += (@as(f32, @floatCast((glfw.getTime() - t0) * m.MS_PER_S)) - game.sim_ms) * play.TIMING_EASE;
    try r.syncWorld(&game.world, MESH_BUDGET, renderer.MESH_MS);
    game.render_stats = r.stats;

    var scene = try view.scene(&game, screen);
    if (inspect != null) {
      scene.ui = &.{};
    } else if (load_screen.fading()) {
      // the loading screen fades off the first frames of play, over the HUD
      load_screen.fadeStep(@floatCast(dt));
      load_screen.time = game.ui_time;
      try load_screen.draw(&game.ui, screen[0], screen[1]);
      scene.ui = game.ui.v.items;
    }
    const resized = input.resized;
    input.resized = false;
    r.capture = shoot;
    try r.draw(&scene, resized);
    if (r.shot()) |sh| {
      snap(gpa, io, sh, &turn);
      if (turn.done()) window.setShouldClose(true);
    }
  }
}

/// write a captured frame as `shots/<focus>_<n>.png` (failures are logged)
fn snap(gpa:Allocator, io:Io, sh:renderer.Shot, turn:*orbit.Orbit) void {
  defer turn.took();
  var nb:[32]u8 = undefined;
  var pb:[96]u8 = undefined;
  const path = bufPrint(&pb, SHOTS ++ sep_str ++ "{s}_{d}.png", .{turn.focus.name(&nb), turn.taken}) catch unreachable;
  const bytes = png.encode(gpa, sh.w, sh.h, sh.px, if (sh.bgra) .bgra else .rgba) catch |e| return log.err("{s}: {t}", .{path, e});
  defer gpa.free(bytes);
  Dir.cwd().writeFile(io, .{.sub_path = path, .data = bytes}) catch |e| return log.err("{s}: {t}", .{path, e});
  log.info("shot {s}", .{path});
}

/// put the gardener's changed settings into effect (as far as the GPU and
/// monitor allow, which the settings then show) and keep them.
fn apply(io:Io, game:*Game, r:*Renderer, display:*Display, applied:*Options) !void {
  const o = &game.opts;
  try r.antialias(o.aa);
  o.aa = r.antialiasing();
  try r.setVsync(o.vsync);
  const full = display.mode == .fullscreen;
  if (o.fullscreen != full) display.toggle() catch |e| {
    game.prog.say(txt.s.msg.no_fullscreen, .{e});
    o.fullscreen = full;
  };
  options.save(o, io) catch |e| game.prog.say(txt.s.msg.options_unsaved, .{e});
  applied.* = o.*;
}

/// save the garden as `want` (a fresh name if null); saved by hand (not
/// the autosave) it becomes the garden being played. A failure is said.
fn keep(gpa:Allocator, io:Io, game:*Game, want:?save.Name) void {
  game.since_save = 0;
  const name = want orelse fresh: {
    relist(gpa, io, game);
    break :fresh save.fresh(game.gardens.items);
  };
  save.save(game, gpa, io, name) catch |e| return game.prog.say(txt.s.msg.save_failed, .{e});
  if (name.is(save.AUTO)) {
    game.prog.say(txt.s.msg.autosaved, .{});
  } else {
    game.slot = name;
    game.prog.say(txt.s.msg.saved, .{name.slice()});
  }
  if (game.mode == .gardens) relist(gpa, io, game);
}

/// the saved gardens menu's list, made afresh
fn relist(gpa:Allocator, io:Io, game:*Game) void {
  save.list(gpa, io, &game.gardens) catch |e| game.prog.say(txt.s.msg.no_gardens, .{e});
  game.listed();
}

/// replace the running game with the saved garden `name` (keeping it on
/// failure); whether it was.
fn restore(gpa:Allocator, io:Io, game:*Game, r:*Renderer, name:save.Name) !bool {
  var loaded = save.load(gpa, io, name) catch |e| {
    game.prog.say(txt.s.msg.no_save, .{e});
    return false;
  };
  // played on as itself, unless it is the autosave (saved by hand, it
  // becomes a garden of its own)
  loaded.slot = if (name.is(save.AUTO)) null else name;
  // the old world's meshes belong to chunks that are about to disappear
  try r.dropWorld();
  // the settings belong to the gardener, not the garden
  loaded.opts = game.opts;
  loaded.most_samples = game.most_samples;
  loaded.world.io = io;
  game.deinit();
  game.* = loaded;
  loaded = undefined;
  return true;
}

/// one frame of the loading screen, `at` of the way through `stage`;
/// false once the window is closed
fn loadFrame(l:*Loading, r:*Renderer, input:*Input, last:*f64, stage:loading.Stage, at:loading.Progress) !bool {
  glfw.pollEvents();
  input.update();
  if (r.window.shouldClose()) return false;
  const now = glfw.getTime();
  const dt = @min(now - last.*, MAX_FRAME_DT);
  last.* = now;
  l.step(stage, at, @floatCast(dt));
  var scene = try l.scene(r.extent());
  const resized = input.resized;
  input.resized = false;
  try r.draw(&scene, resized);
  return true;
}

/// mesh the world's ground behind the loading screen, `before` units of the
/// whole already made; false once the window is closed
fn ground(l:*Loading, r:*Renderer, input:*Input, last:*f64, w:*World, before:u32) !bool {
  const chunks = w.unmeshed();
  const total = before + chunks;
  while (true) {
    const left = w.unmeshed();
    if (!try loadFrame(l, r, input, last, .ground, .{.done = total - left, .total = total})) return false;
    if (left == 0) return true;
    try r.syncWorld(w, m.maxInt(u32), LOAD_MESH_MS);
  }
}

/// a garden just loaded in play: its ground meshed behind the loading
/// screen, which fades off again; false once the window is closed
fn reground(l:*Loading, r:*Renderer, input:*Input, last:*f64, game:*Game) !bool {
  l.again();
  l.time = game.ui_time;
  last.* = glfw.getTime();
  if (!try ground(l, r, input, last, &game.world, 1)) return false;
  game.ui_time = l.time;
  return true;
}
