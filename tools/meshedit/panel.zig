//! the mesh editor's panel: the form list, the values and the help.
const std = ps.std;
const Allocator = std.mem.Allocator;
const bufPrint = std.fmt.bufPrint;
const engine = ps.engine;
const m = engine.core.math;
const Draw = engine.ui.draw.Draw;
const ps = @import("parasymi");
const gizmo = @import("../gizmo.zig");
const s = ps.style;

const V3 = m.V3;
const meshedit = @import("../meshedit.zig");
const BARE = meshedit.settings.BARE;
const CARVE = meshedit.settings.CARVE;
const Ch = meshedit.settings.Ch;
const Editor = meshedit.editor.Editor;
const HANDLE_R = meshedit.settings.HANDLE_R;
const HELP = meshedit.settings.HELP;
const LINE_H = meshedit.settings.LINE_H;
const LIST_ROWS = meshedit.settings.LIST_ROWS;
const LIST_W = meshedit.settings.LIST_W;
const LIST_Y = meshedit.settings.LIST_Y;
const PAD = meshedit.settings.PAD;
const PANEL = meshedit.settings.PANEL;
const PLAIN = meshedit.settings.PLAIN;
const ROW = meshedit.settings.ROW;
const SEL = meshedit.settings.SEL;
const SHADE_X = meshedit.settings.SHADE_X;
const TEXT = meshedit.settings.TEXT;
const VALUE_X = meshedit.settings.VALUE_X;
const listRows = meshedit.settings.listRows;
const valuesY = meshedit.settings.valuesY;

pub fn draw(e:*Editor, d:*Draw, screen:[2]f32, handles:[]const ?[2]f32, view:gizmo.View, origin:V3) Allocator.Error!void {
  const W = screen[0];
  var y:f32 = PAD;
  for (HELP) |h| {
    _ = try d.text(PAD, y, TEXT, BARE, h);
    y += LINE_H;
  }
  var pb:[160]u8 = undefined;
  _ = try d.text(W - PAD - 420, PAD, s.text_label, SEL, bufPrint(&pb, "{s}{s}", .{ e.path, if (e.dirty) " *" else "" }) catch e.path);
  var cb:[64]u8 = undefined;
  _ = try d.text(W - PAD - 420, PAD + LINE_H + 4, TEXT, PLAIN, bufPrint(&cb, "cells {d:.4} m   {d} forms   gizmo {t}", .{ e.doc.cell, e.pieces().len, e.mode }) catch "?");
  if (e.note_len > 0) _ = try d.text(W - PAD - 420, PAD + 2 * (LINE_H + 4), TEXT, PLAIN, e.note[0..e.note_len]);

  // the forms
  const rows = listRows(e.pieces().len);
  try d.trellis(PAD, LIST_Y - 6, LIST_W, m.f(rows) * ROW + 12, PANEL, 0.3);
  for (0..rows) |r| {
    const i = e.top + r;
    if (i >= e.pieces().len) break;
    const p = e.pieces()[i];
    const ry = LIST_Y + m.f(r) * ROW;
    if (i == e.sel) try d.glow(PAD + 8, ry + 7, 10, s.menu_hover);
    var lb:[48]u8 = undefined;
    const col = if (i == e.sel) SEL else if (p.carve) CARVE else PLAIN;
    _ = try d.text(PAD + 18, ry, TEXT, col, bufPrint(&lb, "{d}  {t}{s}", .{ i + 1, p.kind, if (p.carve) "  carve" else "" }) catch "?");
    _ = try d.text(PAD + SHADE_X, ry, TEXT, if (i == e.sel) SEL else BARE, @tagName(p.shade));
  }
  if (e.top > 0) _ = try d.text(PAD + LIST_W - 30, LIST_Y - 20, TEXT, BARE, "...");
  if (e.top + LIST_ROWS < e.pieces().len) _ = try d.text(PAD + LIST_W - 30, LIST_Y + LIST_ROWS * ROW, TEXT, BARE, "...");

  // the selected form's values
  const vy = valuesY(rows);
  if (e.pieces().len > 0) {
    const p = e.pieces()[e.sel];
    try d.trellis(PAD, vy - 6, LIST_W, m.f(Ch.count) * ROW + 12, PANEL, 0.6);
    for (Ch.names, 0..) |n, i| {
      const ry = vy + m.f(i) * ROW;
      const col = if (i == e.ch) SEL else PLAIN;
      if (i == e.ch) try d.glow(PAD + 8, ry + 7, 10, s.menu_hover);
      _ = try d.text(PAD + 18, ry, TEXT, col, n);
      var vb:[24]u8 = undefined;
      _ = try d.text(PAD + VALUE_X, ry, TEXT, col, bufPrint(&vb, "{d:.3}", .{Ch.get(&p.v, i)}) catch "?");
    }
  } else _ = try d.text(PAD + 18, vy, TEXT, BARE, "no forms: n makes one");

  // each form's handle where it stands
  for (handles, 0..) |h, i| if (h) |at| {
    const p = e.pieces()[i];
    const col = if (i == e.sel) SEL else if (p.carve) CARVE else PLAIN;
    if (i != e.sel) try d.pod(at[0], at[1], HANDLE_R, col, 1, 0);
  };
  // the selected form's gizmo over everything in view
  if (e.gizmoAt(origin)) |g| try g.draw(d, view, e.hot);
}
