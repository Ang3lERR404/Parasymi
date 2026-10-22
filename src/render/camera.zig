//! angled top-down camera: pans over the ground plane, zooms along its view
//! ray, turns (yaw) and tilts (pitch) between near-horizontal and near-overhead.
const m = @import("../core/math.zig");

/// pitch limits and resting angle, radians above the horizon: never fully
/// level, never straight down.
pub const MIN_PITCH:f32 = 30.0 * m.pi / 180.0;
pub const MAX_PITCH:f32 = 85.0 * m.pi / 180.0;
pub const REST_PITCH:f32 = 55.0 * m.pi / 180.0;
/// field of view at the lowest pitch (radians, vertical)
const WIDE_FOVY:f32 = 1.0;

pub const Camera = struct {
  target:m.V3 = m.v3(0, 1, 0),
  dist:f32 = 32,
  yaw:f32 = 0,
  pitch:f32 = REST_PITCH,
  fovy:f32 = 0.6,
  aspect:f32 = 16.0 / 9.0,

  pub fn eye(c:*const Camera) m.V3 {
    const cp = @cos(c.pitch);
    return c.target + m.v3(@sin(c.yaw) * cp, @sin(c.pitch), @cos(c.yaw) * cp) * m.splat(c.dist);
  }

  pub fn viewProj(c:*const Camera) m.M4 {
    const far = c.dist * 6 + 120;
    return m.mul(m.perspective(c.fov(), c.aspect, 0.1, far), m.lookAt(c.eye(), c.aim(), m.v3(0, 1, 0)));
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
    const down = c.pitch - 0.45 * (c.fov() / 2) * @sqrt(c.lowness());
    const fwd = m.v3(-@sin(c.yaw), 0, -@cos(c.yaw));
    return c.eye() + fwd * m.splat(@cos(down)) - m.v3(0, @sin(down), 0);
  }

  /// screen-space pan direction mapped onto the ground plane.
  pub fn pan(c:*Camera, right:f32, fwd:f32) void {
    const r = m.v3(@cos(c.yaw), 0, -@sin(c.yaw));
    const f = m.v3(-@sin(c.yaw), 0, -@cos(c.yaw));
    c.target += r * m.splat(right) + f * m.splat(fwd);
  }

  pub fn tilt(c:*Camera, by:f32) void { c.pitch = m.clamp(c.pitch + by, MIN_PITCH, MAX_PITCH); }

  /// how far around the target the world is worth drawing: further the
  /// lower the camera looks, never beyond what is streamed in.
  pub fn reach(c:*const Camera, limit:f32) f32 {
    return @min(c.dist * (2.2 + 3.5 * (1 - @sin(c.pitch))) + 12, limit);
  }

  pub fn zoom(c:*Camera, steps:f32) void {
    c.dist = m.clamp(c.dist * m.pow(f32, 0.88, steps), 4, 120);
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
