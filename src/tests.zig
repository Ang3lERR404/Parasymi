//! pure-logic test root: no window, no GPU.
test {
  _ = @import("core/math.zig");
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
}
