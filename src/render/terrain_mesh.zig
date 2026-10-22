//! chunk -> terraced tile mesh. Each tile is a flat top plus walls down to any
//! lower neighbour. Border neighbours come from the generator directly, so a
//! chunk can be meshed without its neighbours being loaded.
const std = @import("std");
const m = @import("../core/math.zig");
const Allocator = std.mem.Allocator;
const ck = @import("../world/chunk.zig");
const gen = @import("../world/gen.zig");
const rng = @import("../core/rng.zig");
const color = @import("../core/color.zig");
const TV = @import("../gfx/vertex.zig").Terrain;

fn baseColor(k:ck.Kind) [3]f32 {
  return switch (k) {
    .water => .{0.10, 0.22, 0.35},
    .soil => .{0.36, 0.27, 0.19},
    .moss => .{0.20, 0.36, 0.20},
    .stone => .{0.42, 0.42, 0.46},
    .ley => .{0.30, 0.24, 0.45},
  };
}

fn quad(out:*std.ArrayList(TV), gpa:Allocator, p:[4][3]f32, n:[3]f32, c:[4]u8, info:[4]u8) Allocator.Error!void {
  const idx = [_]usize{0, 1, 2, 0, 2, 3};
  for (idx) |i| try out.append(gpa, .{.pos = p[i], .nrm = n, .col = c, .info = info});
}

pub fn build(gpa:Allocator, seed:u64, c:*const ck.Chunk, out:*std.ArrayList(TV)) Allocator.Error!void {
  out.clearRetainingCapacity();
  const ox = c.originX();
  const oy = c.originY();
  for (0..ck.SIZE) |ly| for (0..ck.SIZE) |lx| {
    const i = ly * ck.SIZE + lx;
    const wx = ox + @as(i32, @intCast(lx));
    const wy = oy + @as(i32, @intCast(ly));
    const h = c.height[i];
    const k = c.kind[i];
    const jitter = 0.9 + 0.2 * rng.unit(rng.hash2(seed ^ 0xC0101, wx, wy));
    const ley:u8 = @intFromFloat(m.clamp(c.ley_cap[i] / 4.2, 0, 1) * 255);
    const info:[4]u8 = .{@intFromEnum(k), ley, 1, 0};
    const x0 = m.f(wx);
    const z0 = m.f(wy);
    const x1 = x0 + 1;
    const z1 = z0 + 1;
    try quad(out, gpa, .{.{x0, h, z0}, .{x0, h, z1}, .{x1, h, z1}, .{x1, h, z0}}, .{0, 1, 0}, color.shade(baseColor(k), jitter), info);

    // walls toward lower neighbours (+x, -x, +z, -z)
    const dirs = [_][2]i32{.{1, 0}, .{-1, 0}, .{0, 1}, .{0, -1}};
    for (dirs) |d| {
      const nx = @as(i32, @intCast(lx)) + d[0];
      const ny = @as(i32, @intCast(ly)) + d[1];
      const nh = if (nx >= 0 and nx < ck.SIZE and ny >= 0 and ny < ck.SIZE)
        c.height[@as(usize, @intCast(ny)) * ck.SIZE + @as(usize, @intCast(nx))]
      else
        gen.heightAt(seed, wx + d[0], wy + d[1]);
      if (nh >= h) continue;
      const wc = color.shade(baseColor(if (k == .water) .water else .stone), 0.55 * jitter);
      const winfo:[4]u8 = .{@intFromEnum(k), 0, 0, 0};
      const n:[3]f32 = .{m.f(d[0]), 0, m.f(d[1])};
      const p:[4][3]f32 = switch (d[0] * 2 + d[1]) {
        2 => .{.{x1, h, z1}, .{x1, nh, z1}, .{x1, nh, z0}, .{x1, h, z0}},
        -2 => .{.{x0, h, z0}, .{x0, nh, z0}, .{x0, nh, z1}, .{x0, h, z1}},
        1 => .{.{x0, h, z1}, .{x0, nh, z1}, .{x1, nh, z1}, .{x1, h, z1}},
        else => .{.{x1, h, z0}, .{x1, nh, z0}, .{x0, nh, z0}, .{x0, h, z0}},
      };
      try quad(out, gpa, p, n, wc, winfo);
    }
  };
}
