//! pure-logic test root: no window, no GPU.
test {
  _ = @import("core/math.zig");
  _ = @import("core/registry.zig");
  _ = @import("core/text.zig");
  _ = @import("game/text.zig");
  _ = @import("game/controls.zig");
  _ = @import("platform/input.zig");
  _ = @import("core/rng.zig");
  _ = @import("core/noise.zig");
  _ = @import("world/gen.zig");
  _ = @import("world/world.zig");
  _ = @import("sim/ecology.zig");
  _ = @import("sim/items.zig");
  _ = @import("game/progression.zig");
  _ = @import("game/craft.zig");
  _ = @import("sim/plants.zig");
  _ = @import("game/structures.zig");
  _ = @import("game/seeds.zig");
  _ = @import("game/play.zig");
  _ = @import("game/player.zig");
  _ = @import("game/save.zig");
  _ = @import("game/options.zig");
  _ = @import("gfx/meshgen.zig");
  _ = @import("gfx/meshes/wolf_skeleton.zig");
  _ = @import("gfx/meshes/wolf_belly.zig");
  _ = @import("render/camera.zig");
}
