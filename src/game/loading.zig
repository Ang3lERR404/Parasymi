//! the loading screen: a living night with the garden's name and a tendril
//! growing across it as far as what is made goes, leaves opening along it
//! as it passes them, under it what is being made and how much is made and
//! left. Shown while the meshes grow (on their own thread), the world wakes
//! and its ground is meshed; then it fades off the first frames of play.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const renderer = @import("../render/renderer.zig");
const Camera = @import("engine").render.camera.Camera;
const draw_mod = @import("engine").ui.draw;
const Draw = draw_mod.Draw;
const Color = draw_mod.Color;
const Sky = @import("sky.zig").Sky;
const s = @import("style.zig");
const txt = @import("text.zig");

/// what is being made, in order (`txt.s.loading.stages` names each)
pub const Stage = enum { forms, world, ground };

/// how much is made of how much, all stages together
pub const Progress = struct { done:u32, total:u32 };

/// the night: its colour (opaque) and seed
const NIGHT:Color = .{14, 12, 22, 255};
const NIGHT_SEED:f32 = 0.37;
/// the tendril: share of the screen's width (at most `BAR_MAX` px), how
/// thick, how far below the middle; the name sits `TITLE_UP` over it, the
/// stage and counts `LABEL_DOWN` under it
const BAR_SHARE:f32 = 0.42;
const BAR_MAX:f32 = 720;
const BAR_H:f32 = 18;
const BAR_DOWN:f32 = 40;
const TITLE_UP:f32 = 110;
const LABEL_DOWN:f32 = 34;
const BAR_SEED:f32 = 0.2;
/// the tendril's sway as ui.frag draws it (its `tendril`): waves along it,
/// how fast they run, how far they reach (a share of its thickness), so the
/// leaves stay on it
const WAVES:f32 = 18;
const WAVE_RATE:f32 = 2;
const WAVE_SEED:f32 = 7;
const WAVE_REACH:f32 = 0.18;
/// leaves along it, alternating sides: how many, how long and broad, how
/// far each leans back from upright, and the share of the tendril it takes
/// the front to open one fully
const LEAVES = 11;
const LEAF_LEN:f32 = 40;
const LEAF_WIDE:f32 = 16;
const LEAF_LEAN:f32 = 0.55;
const LEAF_OPENS:f32 = 0.06;
/// the glow at the tendril's growing tip
const TIP_GLOW:Color = .{255, 215, 130, 110};
/// a leaf not yet reached: a dim closed bud
const BUD:Color = .{60, 90, 60, 200};
/// the shown share eases toward what is made at this rate (1/s), so the
/// tendril grows rather than jumps
const EASE:f32 = 9;
/// the screen fades off play over this long (s)
const FADE:f32 = 0.6;
/// the night sky the world passes draw behind it (hidden by the night, but
/// a real view so nothing in them is degenerate): midnight
const TOD:f32 = 0;
/// shader time wraps this often (s) so f32 keeps its precision
const TIME_WRAP:f64 = 3600;
/// no hovered tile: a position far off any tile
const NO_HOVER:f32 = 1e9;

pub const Loading = struct {
  ui:Draw,
  /// its own clock (handed to play when it starts, so nothing jumps)
  time:f64 = 0,
  /// the share shown, easing toward what is made
  shown:f32 = 0,
  /// 1 while loading, falling to 0 over play's first frames
  fade:f32 = 1,
  stage:Stage = .forms,
  at:Progress = .{.done = 0, .total = 1},

  pub fn init(gpa:Allocator) Loading { return .{.ui = .{.gpa = gpa}}; }
  pub fn deinit(l:*Loading) void { l.ui.deinit(); }

  /// a frame of loading: `at` is how far it has come
  pub fn step(l:*Loading, stage:Stage, at:Progress, dt:f32) void {
    l.stage = stage;
    l.at = at;
    l.time += dt;
    const want = share(at);
    l.shown = @min(want, l.shown + (want - l.shown) * m.clamp01(dt * EASE));
  }

  /// a frame of play once loaded: the screen fades off it
  pub fn fadeStep(l:*Loading, dt:f32) void {
    l.fade = @max(0, l.fade - dt / FADE);
    l.shown = 1;
    l.at.done = l.at.total;
  }

  pub fn fading(l:*const Loading) bool { return l.fade > 0; }

  /// shown again from the start (a garden loaded in play)
  pub fn again(l:*Loading) void {
    l.fade = 1;
    l.shown = 0;
  }

  /// the screen drawn into `d` (over what is there), at its fade
  pub fn draw(l:*const Loading, d:*Draw, W:f32, H:f32) Allocator.Error!void {
    const a = l.fade;
    const t:f32 = @floatCast(@mod(l.time, TIME_WRAP));
    try d.night(W, H, fade(NIGHT, a), NIGHT_SEED);

    const name = txt.s.window.title;
    const cy = H / 2;
    _ = try d.text(W / 2 - Draw.width(name, s.text_banner * 2) / 2, cy - TITLE_UP, s.text_banner * 2, fade(s.gold, a), name);

    const bw = @min(W * BAR_SHARE, BAR_MAX);
    const bx = (W - bw) / 2;
    const by = cy + BAR_DOWN;
    // leaves first, so the tendril lies over their bases
    for (0..LEAVES) |i| {
      const k = (m.f(i) + 0.5) / LEAVES;
      const side:f32 = if (i % 2 == 0) -1 else 1;
      const open = m.smooth(m.clamp01((l.shown - k) / LEAF_OPENS));
      const wave = @sin(k * WAVES + t * WAVE_RATE + BAR_SEED * WAVE_SEED) * BAR_H * WAVE_REACH;
      const base = [2]f32{bx + k * bw, by + BAR_H / 2 + wave};
      // swept forward, the way it grows, lifting as they open
      const ang = side * (m.tau / 4.0 - LEAF_LEAN * (1 - 0.3 * open));
      try d.leaf(base, ang, LEAF_LEN * (0.35 + 0.65 * open), LEAF_WIDE * (0.6 + 0.4 * open), fade(if (open > 0) s.leaf else BUD, a), open, m.f(i) * 0.37);
    }
    try d.tendril(bx, by, bw, BAR_H, fade(s.growth, a), l.shown, BAR_SEED);
    if (l.shown > 0) try d.glow(bx + l.shown * bw, by + BAR_H / 2, BAR_H * 2.2, fade(TIP_GLOW, a));

    const ly = by + BAR_H + LABEL_DOWN;
    const stage = txt.nth(txt.s.loading.stages, @intFromEnum(l.stage));
    _ = try d.text(bx, ly, s.text_label, fade(s.white, a), stage);
    var buf:[32]u8 = undefined;
    const pct = txt.bufRender(&buf, txt.s.loading.percent, .{@as(u32, @intFromFloat(@floor(share(l.at) * 100)))});
    _ = try d.text(bx + bw - Draw.width(pct, s.text_label), ly, s.text_label, fade(s.gold, a), pct);
    var lb:[64]u8 = undefined;
    const done = @min(l.at.done, l.at.total);
    const left = txt.bufRender(&lb, txt.s.loading.left, .{done, l.at.total - done});
    _ = try d.text(W / 2 - Draw.width(left, s.text_small) / 2, ly + LABEL_DOWN, s.text_small, fade(s.dim, a), left);
  }

  /// a loading frame: nothing of the world (none of it is made yet) under
  /// the screen, a midnight sky behind it for the world passes
  pub fn scene(l:*Loading, screen:[2]f32) Allocator.Error!renderer.Scene {
    l.ui.clear();
    try l.draw(&l.ui, screen[0], screen[1]);
    const cam:Camera = .{.aspect = screen[0] / @max(screen[1], 1)};
    const sky:Sky = .{.tod = TOD};
    const eye = cam.viewEye();
    const ld = sky.lightDir();
    const c = sky.color(0);
    const reach = cam.dist;
    const tf:f32 = @floatCast(@mod(l.time, TIME_WRAP));
    return .{
      .push = .{
        .vp = cam.viewProj(),
        .eye_time = .{eye[0], eye[1], eye[2], tf},
        .fog = .{c[0], c[1], c[2], 1 / reach},
        .misc = .{0, 0, NO_HOVER, NO_HOVER},
        .sun = .{ld[0], ld[1], ld[2], sky.daylight()},
        .view = .{cam.target[0], cam.target[2], reach, reach},
        .feet = @splat(.{0, 0, 0, 0}),
      },
      .clear = c,
      .instances = @splat(&.{}),
      .parts = @splat(&.{}),
      .bones = &.{},
      .lights = &.{},
      .ui = l.ui.v.items,
      .ui_time = tf,
    };
  }
};

/// how much of the whole is made, 0..1
fn share(at:Progress) f32 {
  if (at.total == 0) return 1;
  return m.clamp01(m.f(at.done) / m.f(at.total));
}

/// `c` with its alpha scaled by `a`
fn fade(c:Color, a:f32) Color {
  return .{c[0], c[1], c[2], m.unorm8(m.f(c[3]) / 255 * a)};
}
