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
  var vsync = true;
  var demo = false;
  var stress = false;
  var load = false;
  var tod:?f32 = null;
  var seed:u64 = play.DEFAULT_SEED;
  for (args[1..]) |a| {
    if (eql(u8, a, "--novsync")) vsync = false;
    if (eql(u8, a, "--demo")) demo = true;
    if (eql(u8, a, "--stress")) stress = true;
    if (eql(u8, a, "--load")) load = true;
    if (startsWith(u8, a, "--tod=")) tod = try parseFloat(f32, a["--tod=".len..]);
    if (startsWith(u8, a, "--seed=")) seed = try parseInt(u64, a["--seed=".len..], 0);
  }

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

  const r = try Renderer.init(gpa, window, vsync);
  defer r.deinit();

  var game = try Game.init(gpa, seed);
  defer game.deinit();
  if (load) try restore(gpa, io, &game, r);
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
        .save => if (save.save(&game, gpa, io)) game.prog.say(txt.s.msg.saved, .{}) else |e| game.prog.say(txt.s.msg.save_failed, .{e}),
        .load => try restore(gpa, io, &game, r),
        .fullscreen => display.toggle() catch |e| game.prog.say(txt.s.msg.no_fullscreen, .{e}),
        .quit => {
          save.save(&game, gpa, io) catch |e| log.err("save failed: {t}", .{e});
          window.setShouldClose(true);
        },
      }
    }
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

/// replace the running game with the saved one (keeping it on failure).
fn restore(gpa:Allocator, io:Io, game:*Game, r:*Renderer) !void {
  var loaded = save.load(gpa, io) catch |e| {
    game.prog.say(txt.s.msg.no_save, .{e});
    return;
  };
  // the old world's meshes belong to chunks that are about to disappear
  try r.dropWorld();
  game.deinit();
  game.* = loaded;
  loaded = undefined;
}
