//! immediate-mode 2D batch in pixel coordinates, rebuilt every frame.
//! Nothing here is a box: every shape is an animated distance field evaluated
//! in shaders/ui.frag (living membranes, seed pods, growing tendrils, glows),
//! and glyph bitmaps travel in the vertex stream, so no textures are needed.
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
  /// organic panel: wobbling translucent membrane with a pulsing vine rim
  membrane,
  /// round seed-pod slot; param.x = selected/fullness glow
  pod,
  /// horizontal tendril that grows to param.x of its length
  tendril,
  /// soft radial halo
  glow,
};

const shape_mark:u32 = 0xffff_ffff;
/// a glyph's cell: the font's bitmap plus one pixel of spacing each way
const cell_w = font.W + 1;
const cell_h = font.H + 1;
/// text shimmers along its length by this phase per pixel
const shimmer:f32 = 0.01;

pub const Draw = struct {
  gpa:Allocator,
  v:std.ArrayList(UV) = .empty,

  pub fn deinit(d:*Draw) void { d.v.deinit(d.gpa); }
  pub fn clear(d:*Draw) void { d.v.clearRetainingCapacity(); }

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

  /// shapes get a margin so wobble/glow can spill past the nominal bounds.
  fn shape(d:*Draw, kind:Shape, x:f32, y:f32, w:f32, h:f32, col:Color, param:[2]f32) Allocator.Error!void {
    const pad:f32 = 28;
    try d.quad(x - pad, y - pad, w + 2 * pad, h + 2 * pad, w + 2 * pad, h + 2 * pad, col, .{shape_mark, @intFromEnum(kind)}, param);
  }

  pub fn membrane(d:*Draw, x:f32, y:f32, w:f32, h:f32, col:Color, seed:f32) Allocator.Error!void {
    try d.shape(.membrane, x, y, w, h, col, .{0, seed});
  }
  pub fn pod(d:*Draw, cx:f32, cy:f32, r:f32, col:Color, lit:f32, seed:f32) Allocator.Error!void {
    try d.shape(.pod, cx - r, cy - r, 2 * r, 2 * r, col, .{lit, seed});
  }
  pub fn tendril(d:*Draw, x:f32, y:f32, w:f32, h:f32, col:Color, value:f32, seed:f32) Allocator.Error!void {
    try d.shape(.tendril, x, y, w, h, col, .{m.clamp(value, 0, 1), seed});
  }
  pub fn glow(d:*Draw, cx:f32, cy:f32, r:f32, col:Color) Allocator.Error!void {
    try d.shape(.glow, cx - r, cy - r, 2 * r, 2 * r, col, .{0, 0});
  }

  /// returns the x after the last glyph.
  pub fn text(d:*Draw, x:f32, y:f32, s:f32, col:Color, str:[]const u8) Allocator.Error!f32 {
    var cx = x;
    for (str) |ch| {
      if (ch != ' ') try d.quad(cx, y, cell_w * s, cell_h * s, cell_w, cell_h, col, font.bits(ch), .{0, cx * shimmer});
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
  pub fn number(d:*Draw, x:f32, y:f32, s:f32, col:Color, n:anytype) Allocator.Error!f32 {
    var buf:[24]u8 = undefined;
    return d.text(x, y, s, col, bufPrint(&buf, "{d}", .{n}) catch &buf);
  }
};
