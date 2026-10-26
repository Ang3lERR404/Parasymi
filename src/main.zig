//! Parasymi: a garden of magically infused plants, parasitic and symbiotic,
//! growing toward something beyond comprehension.
//!
//! layers (each only imports the ones above it):
//!   core -> platform -> gfx -> world -> sim -> game/render/ui -> main
const lib = @import("lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const parseFloat = std.fmt.parseFloat;
const parseInt = std.fmt.parseInt;
const eql = std.mem.eql;
const eqlDeep = std.meta.eql;
const startsWith = std.mem.startsWith;
const asBytes = std.mem.asBytes;
const Init = std.process.Init;
const log = std.log;
const engine = lib.engine;
const glfw = engine.glfw;
const Input = engine.platform.input.Input;
const Display = engine.platform.display.Display;
const renderer = lib.renderer;
const Renderer = renderer.Renderer;
const play = lib.play;
const Game = play.Game;
const view = lib.view;
const setups = lib.setups;
const save = lib.save;
const txt = lib.txt;
const controls = lib.controls;
const options = lib.options;
const home = lib.home;
const orbit = lib.orbit;
const loading = lib.loading;
const specimen = lib.specimen;
const species = lib.species;
const st = lib.structures;
const stringToEnum = std.meta.stringToEnum;
const Loading = loading.Loading;
const World = lib.world.World;
const png = lib.engine.core.png;
const bufPrint = std.fmt.bufPrint;
const Dir = Io.Dir;
const sep_str = std.fs.path.sep_str;
const Options = options.Options;
const m = lib.engine.core.math;
const sound = lib.sound;
const Sounds = engine.platform.audio.Output(sound.Sounds);

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
  // the world's seed: `--seed=`, else one of its own (see below)
  var seed:?u64 = null;
  // `--inspect[=player|<species>|<structure>|x,z]` turns the camera round
  // it, saving screenshots, then closes; `--shots=`, `--orbit=` (seconds a
  // turn), `--dist=`, `--pitch=` (degrees) shape it
  var inspect:?orbit.Focus = null;
  var turn:orbit.Orbit = .{};
  // `--plant=<species>` / `--structure=<kind>` stands it alone (its
  // meshes alone built), `--state=` held or looped (grow, mature, 0.4,
  // 0.2..0.8; plants wither, flow, drain, dark, live; structures idle,
  // active; default grow), `--period=` seconds a loop
  var lone:?specimen.Specimen = null;
  var state:specimen.State = .grow;
  var period:?f32 = null;
  // `--panel=<belly|research|paused|options|gardens|naming>` holds that panel open
  // (and keeps the HUD in `--inspect` shots)
  var panel:?play.Mode = null;
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
    if (startsWith(u8, a, "--plant=")) lone = .{.what = .{.plant = stringToEnum(species.Id, a["--plant=".len..]) orelse return error.BadPlant}};
    if (startsWith(u8, a, "--structure=")) lone = .{.what = .{.structure = stringToEnum(st.Kind, a["--structure=".len..]) orelse return error.BadStructure}};
    if (startsWith(u8, a, "--state=")) state = try specimen.State.parse(a["--state=".len..]);
    if (startsWith(u8, a, "--period=")) period = try parseFloat(f32, a["--period=".len..]);
    if (startsWith(u8, a, "--panel=")) panel = switch (stringToEnum(play.Mode, a["--panel=".len..]) orelse return error.BadPanel) {
      inline .belly, .research, .paused, .options, .gardens, .naming => |p| p,
      else => return error.BadPanel,
    };
  }
  if (lone) |*l| {
    if (!state.suits(l.what)) return error.BadState;
    l.state = state;
    if (period) |t| l.period = @max(t, 0.1);
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

  const r = try Renderer.init(gpa, window, opts.vsync, opts.aa, .{.only = if (lone) |*l| try l.only(init.arena.allocator()) else null});
  defer r.deinit();
  opts.aa = r.antialiasing();

  // the loading screen shows while every mesh grows (on a thread of its
  // own), the world wakes and its ground is meshed. Until the world is
  // woken its chunks are counted as many as stream in round the gardener.
  var load_screen = Loading.init(gpa);
  defer load_screen.deinit();
  var last = glfw.getTime();
  const forms = renderer.meshProgress(r)[1];
  const whole = forms + 1 + play.STREAM_CHUNKS;
  while (!try renderer.meshesReady(r)) {
    if (!try loadFrame(&load_screen, r, &input, &last, .forms, .{.done = renderer.meshProgress(r)[0], .total = whole})) return;
  }
  if (!try loadFrame(&load_screen, r, &input, &last, .world, .{.done = forms, .total = whole})) return;

  // decision: every start grows a world of its own, unless `--seed=` names
  // one; the test gardens (`--demo`, `--stress`, one thing alone) keep the
  // stock world, so they and their screenshots stay alike run to run. A
  // loaded garden brings its own seed.
  const world = seed orelse if (demo or stress or lone != null) play.DEFAULT_SEED else fresh: {
    var s:u64 = undefined;
    io.random(asBytes(&s));
    break :fresh s;
  };
  log.info("world seed 0x{x}", .{world});
  var game = try Game.init(gpa, world);
  defer game.deinit();
  // the world's heavy work (chunks generated and meshed, plants relinked)
  // is split over the pool
  game.world.io = io;
  game.opts = opts;
  game.most_samples = r.maxSamples();
  // the garden's sound; without a device it plays on in silence
  const sounds:?*Sounds = Sounds.open(gpa, io, .init(world, sound.RATE), .{.name = txt.s.window.title, .rate = sound.RATE}) catch |e| none: {
    log.warn("no sound: {t}", .{e});
    break :none null;
  };
  defer if (sounds) |o| o.close(gpa, io);
  // what is in effect; the window opens windowed, so a fullscreen setting
  // is applied on the first frame
  var applied = opts;
  applied.fullscreen = false;
  if (lone) |l| {
    // alone in a fresh world: no garden loaded, sown or saved
    game.specimen = l;
    try game.specimen.?.sow(&game);
  } else {
    if (load) {
      relist(gpa, io, &game);
      if (game.gardens.items.len > 0) _ = try restore(gpa, io, &game, r, game.gardens.items[0].name);
    }
    if (demo) try setups.demo(&game, DEMO_FORWARD);
    if (stress) try setups.stress(&game, STRESS_SIDE);
  }
  if (tod) |t| game.sky.tod = t;
  if (inspect) |f| {
    turn.focus = f;
    Dir.cwd().createDirPath(io, SHOTS) catch |e| log.err("{s}: {t}", .{SHOTS, e});
  }
  if (!try ground(&load_screen, r, &input, &last, &game.world, forms + 1)) return;
  // play's clock runs on from the screen's, so it fades off without a jump
  game.ui_time = load_screen.time;

  // what the sound was last told of the view
  var in_eyes = false;
  while (!window.shouldClose()) {
    glfw.pollEvents();
    input.update();

    const now = glfw.getTime();
    // a stalled frame must not fling animation or movement
    const dt = @min(now - last, MAX_FRAME_DT);
    last = now;

    const screen = r.extent();
    try game.update(&input, @floatCast(dt), screen);
    for (game.player.footfalls()) |ff| if (ff) |f| if (sounds) |o| {
      o.send(.{.step = f}) catch |e| log.warn("footstep: {t}", .{e});
    };
    // out of the wolf's eyes its sap is heard settling
    if (game.cam.inEyes() != in_eyes) if (sounds) |o| {
      o.send(.{.eyes = !in_eyes}) catch |e| log.warn("eyes: {t}", .{e});
      in_eyes = !in_eyes;
    };
    if (game.request) |rq| {
      game.request = null;
      // a lone thing's world is never saved, and no garden replaces it
      if (game.specimen != null) {
        if (rq == .quit) window.setShouldClose(true);
        continue;
      }
      switch (rq) {
        .save => if (game.slot) |n| keep(gpa, io, &game, n),
        .save_as => |n| keep(gpa, io, &game, n),
        .autosave => keep(gpa, io, &game, save.Name.of(save.AUTO).?),
        .delete => |n| letGo(gpa, io, &game, n),
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
          // a garden never named is kept as the autosave
          keep(gpa, io, &game, game.slot orelse save.Name.of(save.AUTO).?);
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
    try renderer.syncWorld(r, &game.world, MESH_BUDGET, renderer.MESH_MS);
    game.render_stats = r.stats;

    if (panel) |p| game.mode = p;
    var scene = try view.scene(&game, screen);
    if (inspect != null and panel == null) {
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

/// save the garden as `name`; saved by hand (not the autosave) it becomes
/// the garden being played. A failure is said.
fn keep(gpa:Allocator, io:Io, game:*Game, name:save.Name) void {
  game.since_save = 0;
  save.save(game, gpa, io, name) catch |e| return game.prog.say(txt.s.msg.save_failed, .{e});
  if (name.is(save.AUTO)) {
    game.prog.say(txt.s.msg.autosaved, .{});
  } else {
    game.slot = name;
    game.prog.say(txt.s.msg.saved, .{name.slice()});
  }
  if (game.mode == .gardens) relist(gpa, io, game);
}

/// let the saved garden `name` go; played on, the garden has no name
/// again. A failure is said.
fn letGo(gpa:Allocator, io:Io, game:*Game, name:save.Name) void {
  save.remove(io, name) catch |e| return game.prog.say(txt.s.msg.delete_failed, .{e});
  if (game.slot) |sl| if (sl.same(name)) {
    game.slot = null;
  };
  game.prog.say(txt.s.msg.deleted, .{name.slice()});
  relist(gpa, io, game);
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
  try renderer.dropWorld(r);
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
    try renderer.syncWorld(r, w, m.maxInt(u32), LOAD_MESH_MS);
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
