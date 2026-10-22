//! pure-logic test root: no window, no GPU.
test {
  _ = @import("core/math.zig");
  _ = @import("core/rng.zig");
  _ = @import("core/noise.zig");
  _ = @import("world/gen.zig");
  _ = @import("world/world.zig");
  _ = @import("sim/ecology.zig");
  _ = @import("game/progression.zig");
}
