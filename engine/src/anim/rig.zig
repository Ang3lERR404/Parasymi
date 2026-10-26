//! skeletal animation, the generic half: a joint's turn, blending turns the
//! short way round, two-bone inverse kinematics, and the matrices a GPU
//! skins with. A game's skeleton (its bones, their offsets and its forward
//! kinematics) and its limb solvers, built on `twoBone`, are its own.
const std = @import("std");
const testing = std.testing;
const m = @import("../core/math.zig");

const V3 = m.V3;
const M4 = m.M4;

/// a joint's turn: about X (pitch), then Y (twist), then Z (roll), applied
/// as Y * X * Z
pub const Turn = struct {
  x:f32 = 0,
  y:f32 = 0,
  z:f32 = 0,

  pub fn m4(t:Turn) M4 { return m.chain(&.{ m.rotY(t.y), m.rotX(t.x), m.rotZ(t.z) }); }

  /// `a` turned toward `b` by share `k`, each angle the short way round
  pub fn blend(a:Turn, b:Turn, k:f32) Turn {
    return .{ .x = a.x + m.angleDiff(a.x, b.x) * k, .y = a.y + m.angleDiff(a.y, b.y) * k, .z = a.z + m.angleDiff(a.z, b.z) * k };
  }
};

/// how far short of straight, and of folded flat, a two-bone chain is held
/// (so its angles never meet a singular pose)
const SLACK:f32 = 1e-3;

/// a two-bone chain (links `a` from the root to the middle joint, `b` from
/// it to the end) reaching a point `reach` from its root, as the triangle
/// the two links and the line to the end make
pub const Triangle = struct {
  /// the distance it reaches: the one asked for, held within what the
  /// links can span
  reach:f32,
  /// the angle at the root between link `a` and the line to the end
  root:f32,
  /// the angle at the end between link `b` and the line back to the root
  end:f32,
  /// how far the middle joint bends from straight (0 straight)
  bend:f32,
};

/// the triangle a two-bone chain makes reaching `reach` (law of cosines)
pub fn twoBone(a:f32, b:f32, reach:f32) Triangle {
  const d = m.clamp(reach, @abs(a - b) + SLACK, a + b - SLACK);
  return .{
    .reach = d,
    .root = m.acos((a * a + d * d - b * b) / (2 * a * d)),
    .end = m.acos((b * b + d * d - a * a) / (2 * b * d)),
    .bend = m.acos((d * d - a * a - b * b) / (2 * a * b)),
  };
}

/// each bone's frame inverted: from the bind pose's frames, what carries a
/// vertex built in the bind pose back into its bone
pub fn inverses(comptime N:usize, frames:[N]M4) [N]M4 {
  var out:[N]M4 = undefined;
  for (&out, frames) |*o, f| o.* = m.inverseRigid(f);
  return out;
}

/// the matrices a GPU skins with: each carries a vertex from the bind pose
/// (`bind_inv` from `inverses`) to its bone's frame in `world`
pub fn skin(comptime N:usize, world:[N]M4, bind_inv:*const [N]M4) [N]M4 {
  var out:[N]M4 = undefined;
  for (&out, world, bind_inv) |*o, w, inv| o.* = m.chain(&.{ w, inv });
  return out;
}

test "a two-bone chain reaches its target, bends straight at full reach" {
  const a:f32 = 0.5;
  const b:f32 = 0.4;
  // the target along +Y: link a leaves at `root` off it, link b turns back
  // from link a by `bend`, and the end lands on the target
  const t = twoBone(a, b, 0.6);
  const mid = m.v3(@sin(t.root), @cos(t.root), 0) * m.splat3(a);
  const end = mid + m.v3(@sin(t.root - t.bend), @cos(t.root - t.bend), 0) * m.splat3(b);
  try testing.expectApproxEqAbs(@as(f32, 0), end[0], 1e-4);
  try testing.expectApproxEqAbs(@as(f32, 0.6), end[1], 1e-4);
  try testing.expectApproxEqAbs(m.pi, t.root + t.end + (m.pi - t.bend), 1e-4);
  // out of reach: held just short of straight, never past it
  const far = twoBone(a, b, 2);
  try testing.expect(far.reach < a + b and far.bend < 0.1);
  const near = twoBone(a, b, 0);
  try testing.expect(near.reach > @abs(a - b));
}

test "the skin of the bind pose is the identity" {
  const frames = [2]M4{ m.translate(m.v3(1, 2, 3)), m.chain(&.{ m.translate(m.v3(0, 1, 0)), m.rotX(0.7) }) };
  const s = skin(2, frames, &inverses(2, frames));
  for (s) |mat| inline for (0..4) |c| inline for (0..4) |r| {
    try testing.expectApproxEqAbs(m.identity[c][r], mat[c][r], 1e-5);
  };
}

test "turns blend the short way round" {
  const a:Turn = .{ .x = 3.0 };
  const b:Turn = .{ .x = -3.0 };
  const h = Turn.blend(a, b, 0.5);
  try testing.expect(@abs(@abs(h.x) - m.pi) < 0.05);
}
