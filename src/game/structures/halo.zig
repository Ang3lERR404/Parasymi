//! the halo a diamond projects: not a structure itself, but what the polyp
//! (while its blooms are drawn in and the diamond forms) and the diamond
//! (once it has) both show and hold. The diamond fragments light into a
//! ring floating `R` tiles around it at a bloom's hover: a projection of
//! light rays thrown up and out from the crystal (`halo_projection`) and
//! the ring they make (`halo_ring`), its light split into a spectrum
//! across its width, red at its inner edge, as an ice halo's is, with
//! swells and motes of light running round it as along the blooms' beams.
//! The ring passes through the four points (east, south, west, north) the
//! blooms stood on; an arc is as bright as the points at its ends, a point
//! dimming to `DIM` without a grown bloom on it. The ring is a field of
//! celestial energy over its disc; a formed diamond holds a wider one.
//!
//! How far the halo has come, `k` (0 the blooms leave their points .. 1
//! they meet; past 1, `FORM`s since), goes to the GPU with each instance:
//! the blooms' spiral, the crystal gathering from its shards and the
//! projection reaching out all follow it there (common.glsl `haloSpiral`).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const World = @import("../../world/world.zig").World;
const species = @import("../../sim/species.zig");
const Plants = @import("../../sim/plants.zig").Plants;
const Parts = @import("../parts.zig").Parts;

/// the ring's radius, tiles: the blooms' points lie this far out along the
/// axes, on it
pub const R:i32 = 5;
/// the points in order around the ring (east, south, west, north); arc k
/// runs from point k to k+1
pub const POINTS = [4][2]i32{ .{ 1, 0 }, .{ 0, 1 }, .{ -1, 0 }, .{ 0, -1 } };
/// a bloom holds a point when grown and healthier than this
const ACTIVE_HEALTH:f32 = 0.5;
/// seconds the blooms take to reach the centre
pub const FORM:f32 = 5;
/// the flash where they meet spreads and fades over this many seconds
pub const FLASH:f32 = 1.4;
/// a formed diamond's field reaches this far (the ring's, `R`)
pub const DIAMOND_R:f32 = 7;
/// the diamond floats at the centre of the ring, where the blooms' cross
/// of beams meets: as high as they hang, the ring with it
pub const HOVER:f32 = species.get(.bloom).hover;
/// the projection's least rise (level, its cone would be flat)
const LEVEL:f32 = 0.02;
/// how bright a point's arcs are without a bloom (1 with one), and how
/// quickly they follow
pub const DIM:f32 = 0.3;
const LIGHT_EASE:f32 = 0.4;

pub fn pointAt(x:i32, y:i32, k:usize) [2]i32 {
  return .{ x + POINTS[k][0] * R, y + POINTS[k][1] * R };
}

/// a grown, unwithered celestial bloom at a tile
pub fn active(p:*const Plants, w:*const World, at:[2]i32) bool {
  const id = p.at(w, at[0], at[1]) orelse return false;
  const i = id.idx();
  const s = p.list.slice();
  return species.get(s.items(.sp)[i]).radiance > 0 and s.items(.growth)[i] >= 1 and s.items(.health)[i] > ACTIVE_HEALTH;
}

/// ease each point's light toward whether a grown bloom holds it.
pub fn relight(light:*[4]f32, p:*const Plants, w:*const World, x:i32, y:i32, dt:f32) void {
  for (light, 0..) |*l, k| {
    const want:f32 = if (active(p, w, pointAt(x, y, k))) 1 else DIM;
    l.* += (want - l.*) * @min(1, dt * LIGHT_EASE);
  }
}

/// how many points shine as with a bloom
pub fn lit(light:[4]f32) u32 {
  var n:u32 = 0;
  for (light) |l| { if (l > (1 + DIM) / 2) n += 1; }
  return n;
}

/// the diamond at `at`, its projection and ring (over the ground at
/// `ground`) and, just as it forms, the flash, for a halo `k` along (see
/// the module notes). The diamond is still: it never sways.
pub fn draw(out:*Parts, seed:f32, at:m.V3, ground:m.V3, k:f32, light:[4]f32) Allocator.Error!void {
  const halo = [4]f32{ at[0], at[1], at[2], k };
  try out.emit(.halo_diamond, m.chain(&.{ m.translate(at), m.rotY(seed * m.tau) }), .{ .phase = seed, .halo = halo });
  // the ring floats at a bloom's hover over the ground at the centre, the
  // diamond at its heart, so its rays run level out to it
  const ring = ground + m.v3(0, HOVER, 0);
  const r = m.f(R);
  try out.emit(.halo_projection, m.chain(&.{ m.translate(at), m.scale3(m.v3(r, @max(ring[1] - at[1], LEVEL), r)) }), .{ .glow = 1, .phase = seed, .halo = halo });
  try out.emit(.halo_ring, m.chain(&.{ m.translate(ring), m.scale3(m.v3(r, 1, r)) }), .{ .glow = 1, .phase = seed, .tint = light, .halo = halo });
  const age = (k - 1) * FORM / FLASH;
  if (age >= 0 and age < 1) try out.emit(.halo_flash, m.translate(at), .{ .glow = 1, .flutter = age });
}
