//! the hotbar: one pod per placeable item, with counts and the selection's name.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const bufPrint = std.fmt.bufPrint;
const play = @import("../play.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("style.zig");

const facing = [_][]const u8{"EAST", "SOUTH", "WEST", "NORTH"};

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const n = play.hotbar.len;
  const gap:f32 = 64;
  const x0 = W / 2 - gap * m.f(n - 1) / 2;
  const hy = H - 86;
  for (play.hotbar, 0..) |item, i| {
    const x = x0 + gap * m.f(i);
    const sel = i == g.hot;
    const col = if (play.known(g, item)) item.info().col else s.unknown;
    if (sel) try d.glow(x, hy, 40, .{col[0], col[1], col[2], 110});
    try d.pod(x, hy, if (sel) 24 else 20, col, if (sel) 1 else 0.25, m.f(i) * 0.37);
    const cnt = g.player.inv.count(item);
    var buf:[8]u8 = undefined;
    const label = bufPrint(&buf, "{d}", .{cnt}) catch "";
    _ = try d.text(x - Draw.width(label, 1.75) / 2, hy - 7, 1.75, if (cnt > 0) s.white else s.dim, label);
    _ = try d.print(x - 4, hy + 28, 1.2, s.dim, "{d}", .{i + 1});
  }
  const item = play.hotbar[g.hot];
  var buf:[64]u8 = undefined;
  const label = if (!play.known(g, item)) "NOT YET UNDERSTOOD"
    else if (item == .conduit) bufPrint(&buf, "{s} FACING {s}", .{item.info().name, facing[g.place_dir]}) catch item.info().name
    else item.info().name;
  _ = try d.text(W / 2 - Draw.width(label, 1.5) / 2, hy - 50, 1.5, s.gold, label);
}
