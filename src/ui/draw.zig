//! immediate-mode 2D batch: text and rects in pixel coordinates, rebuilt every
//! frame. Glyph bitmaps travel in the vertex stream, so no textures are needed.
const std = @import("std");
const font = @import("font.zig");
const UV = @import("../gfx/vertex.zig").Ui;

pub const Color = [4]u8;

pub const Draw = struct {
  gpa:std.mem.Allocator,
  v:std.ArrayList(UV) = .empty,

  pub fn deinit(d:*Draw) void { d.v.deinit(d.gpa); }
  pub fn clear(d:*Draw) void { d.v.clearRetainingCapacity(); }

  fn quad(d:*Draw, x:f32, y:f32, w:f32, h:f32, uw:f32, uh:f32, col:Color, bits:[2]u32) !void {
    const p = [4][2]f32{.{x, y}, .{x + w, y}, .{x + w, y + h}, .{x, y + h}};
    const uv = [4][2]f32{.{0, 0}, .{uw, 0}, .{uw, uh}, .{0, uh}};
    for ([_]usize{0, 1, 2, 0, 2, 3}) |i| try d.v.append(d.gpa, .{.pos = p[i], .uv = uv[i], .col = col, .bits = bits});
  }

  pub fn rect(d:*Draw, x:f32, y:f32, w:f32, h:f32, col:Color) !void {
    try d.quad(x, y, w, h, 1, 1, col, font.solid);
  }

  /// returns the x after the last glyph.
  pub fn text(d:*Draw, x:f32, y:f32, s:f32, col:Color, str:[]const u8) !f32 {
    var cx = x;
    for (str) |ch| {
      if (ch != ' ') try d.quad(cx, y, 6 * s, 8 * s, 6, 8, col, font.bits(ch));
      cx += 6 * s;
    }
    return cx;
  }

  pub fn print(d:*Draw, x:f32, y:f32, s:f32, col:Color, comptime fmt:[]const u8, args:anytype) !f32 {
    var buf:[256]u8 = undefined;
    const str:[]const u8 = std.fmt.bufPrint(&buf, fmt, args) catch &buf;
    return d.text(x, y, s, col, str);
  }
};
