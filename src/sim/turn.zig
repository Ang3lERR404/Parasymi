//! turning what stands in the garden (R): a rooted plant or structure pulls
//! its roots up out of the ground, heaves itself up on them, steps round a
//! quarter and digs them back in facing its new way; a floating (celestial)
//! one only turns where it hangs. Its facing changes at once; how it gets
//! there is timed from when it began (`Turn.at`, game seconds), so nothing
//! ticks it.
const lib = @import("../lib.zig");
const std = lib.std;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;

/// how long one turn takes (s), rooted and floating
pub const TIME:f32 = 1.5;
const FLOAT_TIME:f32 = 0.9;
/// a turn long finished
const NEVER:f64 = -1e9;
/// the rooted turn's beats, shares of `TIME`: the roots come up over
/// `PULL`, the body rises over `RISE`, steps round over `STEP`, sinks
/// over `SINK` while the roots dig back in over `DIG`
const PULL = [2]f32{0, 0.24};
const RISE = [2]f32{0.1, 0.32};
const STEP = [2]f32{0.32, 0.68};
const SINK = [2]f32{0.68, 0.92};
const DIG = [2]f32{0.74, 1};
/// how far it rocks as it heaves itself free and settles (radians), and
/// how many times
const ROCK:f32 = 0.07;
const ROCKS:f32 = 5;

pub const Turn = struct {
  /// the way it faced before
  from:m.Dir = 0,
  at:f64 = NEVER,

  /// 0 as it begins .. 1 done
  pub fn progress(t:Turn, now:f64, rooted:bool) f32 {
    const span:f64 = if (rooted) TIME else FLOAT_TIME;
    return m.clamp01(@floatCast((now - t.at) / span));
  }
  pub fn busy(t:Turn, now:f64, rooted:bool) bool { return t.progress(now, rooted) < 1; }
};

/// how a turning thing is drawn this moment, about its centre
pub const Pose = struct {
  /// yaw still to turn to face its new way (radians; 0 once there)
  spin:f32 = 0,
  /// how far it is lifted (0 rooted .. 1 at the top of its heave)
  lift:f32 = 0,
  /// how far its roots are out of the ground (0 dug in .. 1 out)
  out:f32 = 0,
  /// its rocking: a lean about x and about z (radians)
  rock:[2]f32 = .{0, 0},
  /// 0..1 through its turn
  k:f32 = 1,

  pub fn still(p:Pose) bool { return p.k >= 1; }
};

fn beat(k:f32, b:[2]f32) f32 { return m.smooth(m.clamp01((k - b[0]) / (b[1] - b[0]))); }

/// the pose of `t`, now facing `to`
pub fn pose(t:Turn, to:m.Dir, now:f64, rooted:bool) Pose {
  const k = t.progress(now, rooted);
  if (k >= 1) return .{};
  // the quarters still to turn: one either way, or two
  const d = t.from -% to;
  const q:f32 = if (d == 3) -1 else m.f(d);
  const left = -q * m.half_pi;
  if (!rooted) return .{.spin = left * (1 - m.smooth(k)), .k = k};
  const lift = beat(k, RISE) * (1 - beat(k, SINK));
  const out = beat(k, PULL) * (1 - beat(k, DIG));
  // it rocks most as it tears free and as it settles, not while stepping
  const heave = out * (1 - lift * 0.6);
  const a = ROCKS * m.pi * k;
  return .{
    .spin = left * (1 - beat(k, STEP)), .lift = lift, .out = out, .k = k,
    .rock = .{ROCK * heave * @sin(a), ROCK * heave * @cos(a * 1.3)},
  };
}

test "a turn ends facing its new way, rooted again" {
  const t:Turn = .{.from = 0, .at = 10};
  const mid = pose(t, 1, 10 + TIME / 2, true);
  try testing.expect(mid.lift > 0.9 and mid.out > 0.9);
  try testing.expect(@abs(mid.spin) > 0 and @abs(mid.spin) < m.half_pi);
  const done = pose(t, 1, 10 + TIME, true);
  try testing.expect(done.still() and done.spin == 0 and done.lift == 0 and done.out == 0);
  // the short way round: 3 -> 0 is one quarter, not three
  const wrap = pose(.{.from = 3, .at = 0}, 0, 0, true);
  try testing.expectApproxEqAbs(m.half_pi, @abs(wrap.spin), 1e-5);
  // a floater only turns
  const fl = pose(t, 1, 10 + FLOAT_TIME / 2, false);
  try testing.expect(fl.lift == 0 and fl.out == 0 and fl.spin != 0);
  try testing.expect(!t.busy(10 + TIME, true));
}
