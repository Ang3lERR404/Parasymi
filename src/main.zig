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
const Renderer = @import("render/renderer.zig").Renderer;
const play = @import("game/play.zig");
const Game = play.Game;
const view = @import("game/view.zig");
const setups = @import("game/setups.zig");
const save = @import("game/save.zig");
const txt = @import("game/text.zig");
const controls = @import("game/controls.zig");
const options = @import("game/options.zig");
const home = @import("game/home.zig");
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
  for (args[1..]) |a| {
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

  var game = try Game.init(gpa, seed);
  defer game.deinit();
  game.opts = opts;
  game.most_samples = r.maxSamples();
  // what is in effect; the window opens windowed, so a fullscreen setting
  // is applied on the first frame
  var applied = opts;
  applied.fullscreen = false;
  if (load) {
    relist(gpa, io, &game);
    if (game.gardens.items.len > 0) try restore(gpa, io, &game, r, game.gardens.items[0].name);
  }
  if (demo) try setups.demo(&game, DEMO_FORWARD);
  if (stress) try setups.stress(&game, STRESS_SIDE);
  if (tod) |t| game.sky.tod = t;

  var last = glfw.getTime();
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
          if (n) |nn| try restore(gpa, io, &game, r, nn);
        },
        .load_from => |n| try restore(gpa, io, &game, r, n),
        .list => relist(gpa, io, &game),
        .quit => {
          keep(gpa, io, &game, game.slot);
          window.setShouldClose(true);
        },
      }
    }
    if (!eqlDeep(game.opts, applied)) try apply(io, &game, r, &display, &applied);
    const t0 = glfw.getTime();
    try game.simulate(dt);
    game.sim_ms += (@as(f32, @floatCast((glfw.getTime() - t0) * m.MS_PER_S)) - game.sim_ms) * play.TIMING_EASE;
    try r.syncWorld(&game.world, MESH_BUDGET);
    game.render_stats = r.stats;

    const scene = try view.scene(&game, screen);
    const resized = input.resized;
    input.resized = false;
    try r.draw(&scene, resized);
  }
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
/// failure).
fn restore(gpa:Allocator, io:Io, game:*Game, r:*Renderer, name:save.Name) !void {
  var loaded = save.load(gpa, io, name) catch |e| {
    game.prog.say(txt.s.msg.no_save, .{e});
    return;
  };
  // played on as itself, unless it is the autosave (saved by hand, it
  // becomes a garden of its own)
  loaded.slot = if (name.is(save.AUTO)) null else name;
  // the old world's meshes belong to chunks that are about to disappear
  try r.dropWorld();
  // the settings belong to the gardener, not the garden
  loaded.opts = game.opts;
  loaded.most_samples = game.most_samples;
  game.deinit();
  game.* = loaded;
  loaded = undefined;
}
