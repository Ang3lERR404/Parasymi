//! mesh: SHADOW. a flat unit disc on the ground (y = 0), part `.shadow`,
//! tu.x its radial fraction so the shader can soften its edge. Laid under
//! things that float, so they read as hanging in the air.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const mg = @import("../meshgen.zig");
const color = @import("engine").core.color;

const RINGS = 4;
const STEPS = 16;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const R = RINGS + 1;
  const C = STEPS + 1;
  var pts:[R * C]m.V3 = undefined;
  var ns:[R * C]m.V3 = undefined;
  var cs:[R * C]color.Rgba8 = undefined;
  var us:[R * C]f32 = undefined;
  for (0..R) |i| for (0..C) |j| {
    const k = m.ratio(i, RINGS);
    const a = m.ratio(j, STEPS) * m.tau;
    pts[i * C + j] = m.v3(@cos(a) * k, 0, @sin(a) * k);
    ns[i * C + j] = m.v3(0, 1, 0);
    cs[i * C + j] = color.black.toRgba8(255);
    us[i * C + j] = k;
  };
  // tu.x carries the radial fraction (patch writes `us` to tu.y): move it over
  const start = b.mark();
  try mg.patch(b, R, C, &pts, &ns, &cs, &us, 0, .shadow);
  for (b.v.items[start..]) |*v| v.tu = .{v.tu[1], 0};
}
