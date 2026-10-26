//! immediate-mode 2D batch in pixel coordinates, rebuilt every frame.
//! Nothing here is a box: every shape is an animated distance field evaluated
//! in shaders/ui.frag (vine trellis panels, hanging husk slots, leafy stem
//! bars, seed pods, glows), and glyph bitmaps travel in the vertex stream, so
//! no textures are needed. What grows (a trellis) grows from the frame it is
//! first drawn in: `grown` keeps when each was first seen.
const std = @import("std");
const m = @import("../core/math.zig");
const bufPrint = std.fmt.bufPrint;
const Allocator = std.mem.Allocator;
const font = @import("font.zig");
const ctext = @import("../core/text.zig");
const UV = @import("../gfx/vertex.zig").Ui;

pub const Color = [4]u8;

/// must match the shape switch in shaders/ui.frag.
pub const Shape = enum(u32) {
  /// a panel: a lattice of withies framed by two braided vines that grow
  /// round its rim; param.x = how far grown (0..1), param.y = seed
  trellis,
  /// round seed pod (a bead, a bud, a bullet); param.x = how lit
  pod,
  /// a leafy stem that grows along local x to param.x of its length
  tendril,
  /// soft radial halo
  glow,
  /// tapered stem segment (bark, sap rising); param.x = end/start radius,
  /// param.y = arc length at its start, so texture runs on across segments
  limb,
  /// leaf blade from its base along the quad; param.x = how open (0 is a
  /// closed bud), param.y = seed
  leaf,
  /// a seed on its round end, pointed top up; param.x = how far its seam
  /// has split open, param.y = seed
  grain,
  /// a cut gem, table up; param.x = how much fire, param.y = seed
  gem,
  /// a living night filling the quad: soil-dark, sap veins drifting through
  /// it, spores rising, darker toward its edges; param.y = seed
  night,
  /// a slot: a ribbed husk hanging by its stalk under a calyx; param.x =
  /// how much sap light fills it, param.y = seed
  husk,
};

const shape_mark:u32 = 0xffff_ffff;
/// a glyph's cell: the font's bitmap plus one pixel of spacing each way
const cell_w = font.W + 1;
const cell_h = font.H + 1;
/// a glyph's quad reaches this many cells past its cell each way, room for
/// the leaves its stems put out (must match GLYPH_PAD in shaders/ui.frag)
const glyph_pad = 1;
/// text shimmers along its length by this phase per pixel
const shimmer:f32 = 0.01;
/// how many growing things `grown` keeps track of at once
const max_sprouts = 48;
/// seconds a trellis takes to grow round its panel
pub const trellis_grow:f32 = 0.6;

/// a growing thing: its key, when it was first drawn, whether it was drawn
/// this frame
const Sprout = struct { key:u32, born:f32, seen:bool };

pub const Draw = struct {
  gpa:Allocator,
  v:std.ArrayList(UV) = .empty,
  /// the frame's time (seconds, as the shader's), set by `clear`
  now:f32 = 0,
  sprouts:[max_sprouts]Sprout = undefined,
  n_sprouts:usize = 0,

  pub fn deinit(d:*Draw) void { d.v.deinit(d.gpa); }
  /// starts a frame at time `now`: what was not drawn last frame is
  /// forgotten, so it grows afresh when drawn again.
  pub fn clear(d:*Draw, now:f32) void {
    d.v.clearRetainingCapacity();
    d.now = now;
    var n:usize = 0;
    for (d.sprouts[0..d.n_sprouts]) |sp| {
      if (!sp.seen) continue;
      d.sprouts[n] = .{.key = sp.key, .born = sp.born, .seen = false};
      n += 1;
    }
    d.n_sprouts = n;
  }

  /// how far (0..1, over `secs`) the thing keyed `key` has grown since it
  /// was first drawn without a frame's break; fully grown if too many grow.
  pub fn grown(d:*Draw, key:f32, secs:f32) f32 {
    const k:u32 = @bitCast(key);
    for (d.sprouts[0..d.n_sprouts]) |*sp| if (sp.key == k) {
      sp.seen = true;
      return m.clamp01((d.now - sp.born) / secs);
    };
    if (d.n_sprouts == max_sprouts) return 1;
    d.sprouts[d.n_sprouts] = .{.key = k, .born = d.now, .seen = true};
    d.n_sprouts += 1;
    return 0;
  }

  fn quad(d:*Draw, x0:f32, y0:f32, w:f32, h:f32, uw:f32, uh:f32, col:Color, bits:[2]u32, param:[2]f32) Allocator.Error!void {
    // snap to whole pixels so edges never land between texels and crawl
    const x = @round(x0);
    const y = @round(y0);
    const p = [4][2]f32{.{x, y}, .{x + w, y}, .{x + w, y + h}, .{x, y + h}};
    const uv = [4][2]f32{.{0, 0}, .{uw, 0}, .{uw, uh}, .{0, uh}};
    for ([_]usize{0, 1, 2, 0, 2, 3}) |i| {
      try d.v.append(d.gpa, .{.pos = p[i], .uv = uv[i], .size = .{w, h}, .col = col, .bits = bits, .param = param});
    }
  }

  /// a quad laid along unit direction `u` from `a`: local x runs along it
  /// (len), y across (thick), both padded like `shape`.
  fn along(d:*Draw, kind:Shape, a:[2]f32, u:[2]f32, len:f32, thick:f32, col:Color, param:[2]f32) Allocator.Error!void {
    const pad:f32 = 28;
    const w = len + 2 * pad;
    const h = thick + 2 * pad;
    const uv = [4][2]f32{.{0, 0}, .{w, 0}, .{w, h}, .{0, h}};
    var p:[4][2]f32 = undefined;
    for (uv, &p) |q, *o| {
      const x = q[0] - pad;
      const y = q[1] - h / 2;
      o.* = .{a[0] + u[0] * x - u[1] * y, a[1] + u[1] * x + u[0] * y};
    }
    for ([_]usize{0, 1, 2, 0, 2, 3}) |i| {
      try d.v.append(d.gpa, .{.pos = p[i], .uv = uv[i], .size = .{w, h}, .col = col, .bits = .{shape_mark, @intFromEnum(kind)}, .param = param});
    }
  }

  /// shapes get a margin so wobble/glow can spill past the nominal bounds.
  fn shape(d:*Draw, kind:Shape, x:f32, y:f32, w:f32, h:f32, col:Color, param:[2]f32) Allocator.Error!void {
    const pad:f32 = 28;
    try d.quad(x - pad, y - pad, w + 2 * pad, h + 2 * pad, w + 2 * pad, h + 2 * pad, col, .{shape_mark, @intFromEnum(kind)}, param);
  }

  /// a panel `w` x `h` (its bed `col`); `seed` sets its vines and keys its
  /// growth (`grown`), so panels drawn at once take different seeds.
  pub fn trellis(d:*Draw, x:f32, y:f32, w:f32, h:f32, col:Color, seed:f32) Allocator.Error!void {
    try d.shape(.trellis, x, y, w, h, col, .{d.grown(seed, trellis_grow), seed});
  }
  /// a slot of radius `r` hanging at (cx, cy), its stalk rising above it.
  pub fn husk(d:*Draw, cx:f32, cy:f32, r:f32, col:Color, lit:f32, seed:f32) Allocator.Error!void {
    try d.shape(.husk, cx - r, cy - r, 2 * r, 2 * r, col, .{lit, seed});
  }
  pub fn pod(d:*Draw, cx:f32, cy:f32, r:f32, col:Color, lit:f32, seed:f32) Allocator.Error!void {
    try d.shape(.pod, cx - r, cy - r, 2 * r, 2 * r, col, .{lit, seed});
  }
  pub fn tendril(d:*Draw, x:f32, y:f32, w:f32, h:f32, col:Color, value:f32, seed:f32) Allocator.Error!void {
    try d.shape(.tendril, x, y, w, h, col, .{m.clamp(value, 0, 1), seed});
  }
  /// a tendril from `a` along screen angle `ang` (0 right, y down), `len`
  /// long and `h` thick, grown to `value` of its length.
  pub fn stem(d:*Draw, a:[2]f32, ang:f32, len:f32, h:f32, col:Color, value:f32, seed:f32) Allocator.Error!void {
    try d.along(.tendril, a, .{@cos(ang), @sin(ang)}, len, h, col, .{m.clamp01(value), seed});
  }
  pub fn glow(d:*Draw, cx:f32, cy:f32, r:f32, col:Color) Allocator.Error!void {
    try d.shape(.glow, cx - r, cy - r, 2 * r, 2 * r, col, .{0, 0});
  }

  /// a stem from `a` (radius r0) to `b` (radius r1 <= r0), round at both
  /// ends so consecutive segments join; `s0` is the arc length at `a`.
  pub fn limb(d:*Draw, a:[2]f32, b:[2]f32, r0:f32, r1:f32, col:Color, s0:f32) Allocator.Error!void {
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const l = @sqrt(dx * dx + dy * dy);
    const u:[2]f32 = if (l > m.EPS) .{dx / l, dy / l} else .{1, 0};
    try d.along(.limb, a, u, l, 2 * r0, col, .{if (r0 > m.EPS) r1 / r0 else 1, s0});
  }
  /// a leaf (or, closed, a bud) growing from `base` at screen angle `ang`.
  pub fn leaf(d:*Draw, base:[2]f32, ang:f32, len:f32, wid:f32, col:Color, open:f32, seed:f32) Allocator.Error!void {
    try d.along(.leaf, base, .{@cos(ang), @sin(ang)}, len, wid, col, .{m.clamp01(open), seed});
  }
  /// a seed `w` x `h` centred on (cx, cy), split open by `crack`.
  pub fn grain(d:*Draw, cx:f32, cy:f32, w:f32, h:f32, col:Color, crack:f32, phase:f32) Allocator.Error!void {
    try d.shape(.grain, cx - w / 2, cy - h / 2, w, h, col, .{m.clamp01(crack), phase});
  }
  /// the night over the whole `w` x `h` screen (opaque at full alpha)
  pub fn night(d:*Draw, w:f32, h:f32, col:Color, seed:f32) Allocator.Error!void {
    try d.shape(.night, 0, 0, w, h, col, .{0, seed});
  }
  pub fn gem(d:*Draw, cx:f32, cy:f32, r:f32, col:Color, fire:f32, phase:f32) Allocator.Error!void {
    try d.shape(.gem, cx - r, cy - r, 2 * r, 2 * r, col, .{fire, phase});
  }

  /// returns the x after the last glyph.
  pub fn text(d:*Draw, x:f32, y:f32, s:f32, col:Color, str:[]const u8) Allocator.Error!f32 {
    var cx = x;
    for (str) |ch| {
      const pw = cell_w + 2 * glyph_pad;
      const ph = cell_h + 2 * glyph_pad;
      if (ch != ' ') try d.quad(cx - glyph_pad * s, y - glyph_pad * s, pw * s, ph * s, pw, ph, col, font.bits(ch), .{0, cx * shimmer});
      cx += cell_w * s;
    }
    return cx;
  }

  pub fn width(str:[]const u8, s:f32) f32 { return m.f(str.len) * cell_w * s; }

  /// `tpl` is a runtime template (`core/text.zig`), truncated to 256 bytes.
  pub fn print(d:*Draw, x:f32, y:f32, s:f32, col:Color, tpl:[]const u8, args:anytype) Allocator.Error!f32 {
    var buf:[256]u8 = undefined;
    return d.text(x, y, s, col, ctext.bufRender(&buf, tpl, args));
  }

  /// a bare count.
  pub fn number(d:*Draw, x:f32, y:f32, s:f32, col:Color, n:u32) Allocator.Error!f32 {
    var buf:[24]u8 = undefined;
    return d.text(x, y, s, col, bufPrint(&buf, "{d}", .{n}) catch &buf);
  }
};

test "a trellis grows from the frame it is first drawn, afresh after a break" {
  var d:Draw = .{.gpa = std.testing.allocator};
  defer d.deinit();
  d.clear(10);
  try std.testing.expectEqual(@as(f32, 0), d.grown(0.5, 1));
  d.clear(10.5);
  try std.testing.expectApproxEqAbs(@as(f32, 0.5), d.grown(0.5, 1), 1e-6);
  // another key keeps its own clock
  try std.testing.expectEqual(@as(f32, 0), d.grown(0.7, 1));
  d.clear(12);
  try std.testing.expectEqual(@as(f32, 1), d.grown(0.5, 1));
  // a frame without it: it is forgotten, and grows again
  d.clear(13);
  d.clear(14);
  try std.testing.expectEqual(@as(f32, 0), d.grown(0.5, 1));
}
