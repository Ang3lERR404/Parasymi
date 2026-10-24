//! angled top-down camera: pans over the ground plane, zooms along its view
//! ray, turns (yaw) and tilts (pitch) between near-horizontal and near-overhead.
//! For close inspection it can also fly free, then ease back to following.
const std = @import("std");
const testing = std.testing;
const m = @import("../core/math.zig");

/// pitch limits and resting angle, radians above the horizon: never fully
/// level, never straight down.
pub const MIN_PITCH:f32 = m.rad(30.0);
pub const MAX_PITCH:f32 = m.rad(85.0);
pub const REST_PITCH:f32 = m.rad(55.0);
/// field of view at the lowest pitch (radians, vertical)
const WIDE_FOVY:f32 = 1.0;
/// the free camera: its field of view, how long it takes to ease back to
/// following, and how fast it flies, looks and rolls
const FREE_FOVY:f32 = 0.8;
const RETURN_TIME:f32 = 0.3;
pub const FLY:f32 = 3;
pub const LOOK:f32 = 0.0025;
pub const ROLL:f32 = 1.2;
/// the resting view: distance, vertical field of view, aspect
const REST_DIST:f32 = 32;
const REST_FOVY:f32 = 0.6;
const REST_ASPECT:f32 = 16.0 / 9.0;
/// clip planes: near for following and free flight; far grows with distance
const NEAR:f32 = 0.1;
const FREE_NEAR:f32 = 0.05;
const FAR_PER_DIST:f32 = 6;
const FAR_MIN:f32 = 120;
/// below rest the gaze lifts by this share of half the field of view
const LIFT:f32 = 0.45;
/// draw reach: distance times this (plus more as the camera lowers), plus a margin
const REACH_HIGH:f32 = 2.2;
const REACH_LOW:f32 = 3.5;
const REACH_MARGIN:f32 = 12;
/// each wheel notch scales the distance by this, within these bounds
const ZOOM_STEP:f32 = 0.88;
const MIN_DIST:f32 = 4;
const MAX_DIST:f32 = 120;
const UP = m.v3(0, 1, 0);

/// a free-flying view: anywhere, any orientation (no limits on pitch or yaw)
pub const Free = struct {
  pos:m.V3,
  yaw:f32,
  pitch:f32,
  roll:f32 = 0,
  /// the window holds the cursor for mouse look
  captured:bool = false,

  pub fn forward(f:*const Free) m.V3 {
    const cp = @cos(f.pitch);
    return m.v3(-@sin(f.yaw) * cp, @sin(f.pitch), -@cos(f.yaw) * cp);
  }
  /// independent of pitch, so looking past straight up or down never flips
  pub fn right(f:*const Free) m.V3 { return m.v3(@cos(f.yaw), 0, -@sin(f.yaw)); }
  pub fn up(f:*const Free) m.V3 {
    const u = m.cross(f.right(), f.forward());
    return u * m.splat3(@cos(f.roll)) + f.right() * m.splat3(@sin(f.roll));
  }
};

pub const View = union(enum) {
  /// following the target (the normal game camera)
  follow,
  free:Free,
  /// easing from a free view back to following
  returning:struct { from:Free, t:f32 = 0 },
};

pub const Camera = struct {
  target:m.V3 = m.v3(0, 1, 0),
  dist:f32 = REST_DIST,
  yaw:f32 = 0,
  pitch:f32 = REST_PITCH,
  fovy:f32 = REST_FOVY,
  aspect:f32 = REST_ASPECT,
  view:View = .follow,

  pub fn eye(c:*const Camera) m.V3 {
    const cp = @cos(c.pitch);
    return c.target + m.v3(@sin(c.yaw) * cp, @sin(c.pitch), @cos(c.yaw) * cp) * m.splat3(c.dist);
  }

  pub fn viewProj(c:*const Camera) m.M4 {
    const far = c.dist * FAR_PER_DIST + FAR_MIN;
    const follow_dir = m.norm(c.aim() - c.eye());
    return switch (c.view) {
      .follow => m.mul(m.perspective(c.fov(), c.aspect, NEAR, far), m.lookAt(c.eye(), c.aim(), UP)),
      .free => |f| m.mul(m.perspective(FREE_FOVY, c.aspect, FREE_NEAR, far), m.lookAt(f.pos, f.pos + f.forward(), f.up())),
      .returning => |r| blk: {
        const w = 1 - m.smooth(m.clamp01(r.t / RETURN_TIME));
        const e = c.viewEye();
        const dir = m.norm(m.lerpV(follow_dir, r.from.forward(), w));
        const up = m.norm(m.lerpV(UP, r.from.up(), w));
        break :blk m.mul(m.perspective(m.lerp(c.fov(), FREE_FOVY, w), c.aspect, FREE_NEAR, far), m.lookAt(e, e + dir, up));
      },
    };
  }

  /// where the view actually is (the orbit eye, or wherever it flies).
  pub fn viewEye(c:*const Camera) m.V3 {
    return switch (c.view) {
      .follow => c.eye(),
      .free => |f| f.pos,
      .returning => |r| m.lerpV(c.eye(), r.from.pos, 1 - m.smooth(m.clamp01(r.t / RETURN_TIME))),
    };
  }

  /// leave following: fly from exactly where the camera is, looking the same way.
  pub fn startFree(c:*Camera) void {
    const e = c.eye();
    const d = m.norm(c.aim() - e);
    c.view = .{.free = .{.pos = e, .yaw = m.atan2(-d[0], -d[2]), .pitch = m.asin(d[1])}};
  }

  /// ease back to following from wherever it flew.
  pub fn endFree(c:*Camera) void {
    switch (c.view) {
      .free => |f| c.view = .{.returning = .{.from = f}},
      .follow, .returning => {},
    }
  }

  pub fn tick(c:*Camera, dt:f32) void {
    switch (c.view) {
      .returning => |*r| {
        r.t += dt;
        if (r.t >= RETURN_TIME) c.view = .follow;
      },
      .follow, .free => {},
    }
  }

  /// steer a free view: turn by `look` (radians), move by `move` (right,
  /// up, forward, world units), roll, and dolly along the view.
  pub fn fly(c:*Camera, look:[2]f32, move:m.V3, roll:f32, dolly:f32) void {
    switch (c.view) {
      .free => |*f| {
        f.yaw += look[0];
        f.pitch += look[1];
        f.roll += roll;
        f.pos += f.right() * m.splat3(move[0]) + f.up() * m.splat3(move[1]) + f.forward() * m.splat3(move[2] + dolly);
      },
      .follow, .returning => {},
    }
  }

  /// 0 at the resting pitch and above, 1 at the lowest.
  fn lowness(c:*const Camera) f32 { return m.clamp01((REST_PITCH - c.pitch) / (REST_PITCH - MIN_PITCH)); }

  /// vertical field of view: it widens as the camera drops, so the wolf and
  /// the horizon fit in one frame.
  pub fn fov(c:*const Camera) f32 { return m.lerp(c.fovy, WIDE_FOVY, c.lowness()); }

  /// where the camera looks: the target from rest upward; below rest the
  /// gaze lifts toward the horizon, keeping the target in the lower frame,
  /// so the sky opens up as it drops (about a third of the view at 30).
  fn aim(c:*const Camera) m.V3 {
    const down = c.pitch - LIFT * (c.fov() / 2) * @sqrt(c.lowness());
    const fwd = m.v3(-@sin(c.yaw), 0, -@cos(c.yaw));
    return c.eye() + fwd * m.splat3(@cos(down)) - m.v3(0, @sin(down), 0);
  }

  /// screen-space pan direction mapped onto the ground plane.
  pub fn pan(c:*Camera, right:f32, fwd:f32) void {
    const r = m.v3(@cos(c.yaw), 0, -@sin(c.yaw));
    const f = m.v3(-@sin(c.yaw), 0, -@cos(c.yaw));
    c.target += r * m.splat3(right) + f * m.splat3(fwd);
  }

  pub fn tilt(c:*Camera, by:f32) void { c.pitch = m.clamp(c.pitch + by, MIN_PITCH, MAX_PITCH); }

  /// how far around the target the world is worth drawing: further the
  /// lower the camera looks, never beyond what is streamed in.
  pub fn reach(c:*const Camera, limit:f32) f32 {
    return @min(c.dist * (REACH_HIGH + REACH_LOW * (1 - @sin(c.pitch))) + REACH_MARGIN, limit);
  }

  pub fn zoom(c:*Camera, steps:f32) void {
    c.dist = m.clamp(c.dist * m.pow(f32, ZOOM_STEP, steps), MIN_DIST, MAX_DIST);
  }

  /// world-space ray through a pixel.
  pub fn ray(c:*const Camera, px:f32, py:f32, w:f32, h:f32) struct { o:m.V3, d:m.V3 } {
    const inv = m.inverse(c.viewProj());
    const nx = px / w * 2 - 1;
    const ny = py / h * 2 - 1;
    const a = m.mulV(inv, .{nx, ny, 0, 1});
    const b = m.mulV(inv, .{nx, ny, 1, 1});
    const pa = m.v3(a[0] / a[3], a[1] / a[3], a[2] / a[3]);
    const pb = m.v3(b[0] / b[3], b[1] / b[3], b[2] / b[3]);
    return .{.o = pa, .d = m.norm(pb - pa)};
  }
};


test "the free camera starts where the follow view is and eases home" {
  var c:Camera = .{.target = m.v3(3, 1, -2)};
  const e = c.eye();
  const d = m.norm(c.aim() - e);
  c.startFree();
  try testing.expect(m.len(c.viewEye() - e) < 1e-5);
  try testing.expect(m.len(c.view.free.forward() - d) < 1e-4);
  // fly up and over the top: pitch is not clamped and nothing degenerates
  c.fly(.{0, 3}, m.v3(0.5, 0, 1), 0.3, 0);
  try testing.expect(c.view.free.pitch > m.half_pi);
  try testing.expect(m.len(c.view.free.up()) > 0.99);
  c.endFree();
  c.tick(0.15);
  try testing.expect(c.view == .returning);
  c.tick(0.2);
  try testing.expect(c.view == .follow);
  try testing.expect(m.len(c.viewEye() - e) < 1e-5);
}
