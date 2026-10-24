//! mesh: BLOOM THREAD. soft rays sent between two celestial blooms: a flat
//! ribbon, its length running up +Y over 0..1 (tu.x), its width across x
//! from -1 to 1 (tu.y). part.vert (curve mode) carries it from one bloom's
//! core to the other's as a spindle and turns its width to face the eye,
//! so it reads from every side, never a wire; part.frag fills it with a
//! faint haze, soft streaks swelling from sender to receiver and tiny
//! drifting motes, the rainbow running from one end to the other. Part
//! `.thread`. Listed last: it blends over everything.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");

const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const warm = color.rgb(1.0, 0.9, 0.7).toRgba8(255);
  const N = 48;
  const across = [_]f32{-1, 0, 1};
  for (0..N - 1) |i| for (0..across.len - 1) |j| {
    const k0 = m.ratio(i, N - 1);
    const k1 = m.ratio(i + 1, N - 1);
    const q = [4][2]f32{.{k0, across[j]}, .{k0, across[j + 1]}, .{k1, across[j + 1]}, .{k1, across[j]}};
    for ([_]usize{0, 1, 2, 0, 2, 3}) |c| try b.put(v3(q[c][1], q[c][0], 0), v3(0, 0, 1), warm, q[c][0], q[c][1], .thread);
  };
}
