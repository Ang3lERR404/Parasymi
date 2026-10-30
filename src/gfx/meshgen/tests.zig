//! the garden's meshes tested: blades and growth keys.
const lib = @import("../../lib.zig");
const std = lib.std;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const color = engine.core.color;

const V3 = m.V3;
const Builder = lib.meshgen.Builder;
const KEYS = lib.meshgen.KEYS;
const Key = lib.meshgen.Key;
const blade = lib.meshgen.blades.blade;
const growthKey = lib.meshgen.growthKey;
const plant = lib.meshgen.shoots.plant;

test "a blade has a body: both faces, wound outward, its vein on the cupped face" {
  var b:Builder = .{.gpa = testing.allocator};
  defer b.deinit();
  const c = color.rgb(0.3, 0.6, 0.2).toRgba8(255);
  try blade(&b, m.v3(0, 0, 0), m.v3(1, 0, 0), 1, 0.2, 0.3, c, c, 1, .leaf);
  var up:usize = 0;
  var down:usize = 0;
  var tri:usize = 0;
  while (tri < b.v.items.len) : (tri += 3) {
    const v = b.v.items[tri .. tri + 3];
    const p:[3]V3 = .{v[0].pos, v[1].pos, v[2].pos};
    const n:V3 = @as(V3, v[0].nrm) + @as(V3, v[1].nrm) + @as(V3, v[2].nrm);
    const g = m.cross(p[1] - p[0], p[2] - p[0]);
    if (m.len(g) < 1e-9) continue;
    try testing.expect(m.dot(g, n) > 0);
    if (m.norm(g)[1] > 0.5) up += 1;
    if (m.norm(g)[1] < -0.5) down += 1;
  }
  try testing.expect(up > 0 and down > 0);
  // the vein's crest is paler than the blade, and stands on the face looking up
  var pale = false;
  for (b.v.items) |vx| if (vx.col.r > c.r + 10) {
    pale = true;
    try testing.expect(vx.nrm[1] > 0);
  };
  try testing.expect(pale);
}

test "a confluence's growth keys share one vertex layout and grow taller" {
  var b:Builder = .{.gpa = testing.allocator};
  defer b.deinit();
  var counts:[KEYS]usize = undefined;
  var tops:[KEYS]f32 = undefined;
  for (0..KEYS) |v| {
    b.v.clearRetainingCapacity();
    try plant(&b, .confluence, @intCast(v));
    counts[v] = b.v.items.len;
    var hi:f32 = 0;
    for (b.v.items) |x| hi = @max(hi, x.pos[1]);
    tops[v] = hi;
  }
  for (counts[1..]) |c| try testing.expectEqual(counts[0], c);
  for (tops[1..], tops[0 .. KEYS - 1]) |t, prev| try testing.expect(t >= prev);
  // keys cover growth end to end; between keys the blend is the fraction
  try testing.expectEqual(Key{.v = 0, .f = 0}, growthKey(.confluence, 0).?);
  const end = growthKey(.confluence, 1).?;
  try testing.expect(end.v == KEYS - 2 and end.f == 1);
  try testing.expect(growthKey(.lumenroot, 0.5) == null);
}
