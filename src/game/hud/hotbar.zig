//! the hotbar: one pod per placeable item, with counts and the selection's name.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const bufPrint = std.fmt.bufPrint;
const play = @import("../play.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("../style.zig");

const gap:f32 = 64;
const pod_r:f32 = 20;
const pod_r_sel:f32 = 24;
const glow_alpha:u8 = 110;

/// display names for each Direction value, in enum order.
const facing = [_][]const u8{"EAST", "SOUTH", "WEST", "NORTH"};

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const n = play.hotbar.len;
  const x0 = W / 2 - gap * m.f(n - 1) / 2;
  const hy = H - 86;

  for (play.hotbar, 0..) |item, i| {
    const x = x0 + gap * m.f(i);
    const sel = i == g.hot;
    const col = if (play.known(g, item)) item.info().col else s.unknown;
    if (sel) {
      const glow_col = [4]u8{ col[0], col[1], col[2], glow_alpha };
      try d.glow(x, hy, 40, glow_col);
    }
    try d.pod(x, hy, if (sel) pod_r_sel else pod_r, col, if (sel) 1 else 0.25, m.f(i) * 0.37);
    const cnt = g.player.inv.count(item);
    var buf:[8]u8 = undefined;
    const label = bufPrint(&buf, "{d}", .{cnt}) catch "0";
    _ = try d.text(x - Draw.width(label, s.text_label) / 2, hy - 7, s.text_label, if (cnt > 0) s.white else s.dim, label);
    _ = try d.text(x - 4, hy + 28, s.text_small, s.dim, play.hotbar_keys[i]);
  }

  const item = play.hotbar[g.hot];
  var buf:[64]u8 = undefined;
  const label = if (!play.known(g, item)) "NOT YET UNDERSTOOD"
    else if (item == .conduit) bufPrint(&buf, "{s} FACING {s}", .{item.info().name, facing[g.place_dir]}) catch item.info().name
    else item.info().name;
  _ = try d.text(W / 2 - Draw.width(label, s.text_sub) / 2, hy - 50, s.text_sub, s.gold, label);
}   