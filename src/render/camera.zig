//! angled top-down camera: pans over the ground plane, zooms along its view ray.
const m = @import("../core/math.zig");

pub const Camera = struct {
  target:m.V3 = m.v3(0, 1, 0),
  dist:f32 = 32,
  yaw:f32 = 0,
  pitch:f32 = 0.95,
  fovy:f32 = 0.6,
  aspect:f32 = 16.0 / 9.0,

  pub fn eye(c:*const Camera) m.V3 {
    const cp = @cos(c.pitch);
    return c.target + m.v3(@sin(c.yaw) * cp, @sin(c.pitch), @cos(c.yaw) * cp) * m.splat(c.dist);
  }

  pub fn viewProj(c:*const Camera) m.M4 {
    const far = c.dist * 6 + 120;
    return m.mul(m.perspective(c.fovy, c.aspect, 0.1, far), m.lookAt(c.eye(), c.target, m.v3(0, 1, 0)));
  }

  /// screen-space pan direction mapped onto the ground plane.
  pub fn pan(c:*Camera, right:f32, fwd:f32) void {
    const r = m.v3(@cos(c.yaw), 0, -@sin(c.yaw));
    const f = m.v3(-@sin(c.yaw), 0, -@cos(c.yaw));
    c.target += r * m.splat(right) + f * m.splat(fwd);
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
