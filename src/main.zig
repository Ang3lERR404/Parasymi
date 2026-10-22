//! Parasymi: a garden of magically infused plants, parasitic and symbiotic,
//! growing toward something beyond comprehension.
//!
//! layers (each only imports the ones above it):
//!   core -> platform -> gfx -> world -> sim -> game/render/ui -> main
const std = @import("std");
const glfw = @import("zglfw");
const Input = @import("platform/input.zig").Input;
const Renderer = @import("render/renderer.zig").Renderer;
const Game = @import("game/play.zig").Game;

pub fn main(init:std.process.Init) !void {
  const gpa = init.gpa;
  const args = try init.minimal.args.toSlice(init.arena.allocator());
  var vsync = true;
  var demo = false;
  var stress = false;
  var tod:?f32 = null;
  var seed:u64 = 0x5EED_0F_11FE;
  for (args[1..]) |a| {
    if (std.mem.eql(u8, a, "--novsync")) vsync = false;
    if (std.mem.eql(u8, a, "--demo")) demo = true;
    if (std.mem.eql(u8, a, "--stress")) stress = true;
    if (std.mem.startsWith(u8, a, "--tod=")) tod = try std.fmt.parseFloat(f32, a[6..]);
    if (std.mem.startsWith(u8, a, "--seed=")) seed = try std.fmt.parseInt(u64, a[7..], 0);
  }

  try glfw.init();
  defer glfw.terminate();
  if (!glfw.isVulkanSupported()) return error.VulkanUnsupported;
  glfw.windowHint(.client_api, .no_api);
  const window = try glfw.createWindow(1600, 900, "Parasymi", null, null);
  defer window.destroy();

  var input:Input = .{.win = window};
  input.attach();

  const r = try Renderer.init(gpa, window, vsync);
  defer r.deinit();

  var game = try Game.init(gpa, seed);
  defer game.deinit();
  if (demo) try game.demo(25);
  if (stress) try game.stress(120);
  if (tod) |t| game.sky.tod = t;

  var last = glfw.getTime();
  while (!window.shouldClose()) {
    glfw.pollEvents();
    input.update();
    if (input.pressed(.escape)) window.setShouldClose(true);

    const now = glfw.getTime();
    const dt = now - last;
    last = now;

    const screen = r.extent();
    try game.update(&input, @floatCast(dt), screen);
    const t0 = glfw.getTime();
    try game.simulate(dt);
    game.sim_ms += (@as(f32, @floatCast((glfw.getTime() - t0) * 1000)) - game.sim_ms) * 0.05;
    try r.syncWorld(&game.world, 6);
    game.render_stats = r.stats;

    const scene = try game.scene(screen);
    const resized = input.resized;
    input.resized = false;
    try r.draw(&scene, resized);
  }
}
