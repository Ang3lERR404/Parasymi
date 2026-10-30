//! the mesh editor's input: keys, the value list and gizmo drags.
const std = ps.std;
const Allocator = std.mem.Allocator;
const engine = ps.engine;
const m = engine.core.math;
const Input = engine.platform.input.Input;
const Key = engine.platform.input.Key;
const ps = @import("parasymi");
const gizmo = @import("../gizmo.zig");

const V3 = m.V3;
const v3 = m.v3;
const meshedit = @import("../meshedit.zig");
const CELL_MIN = meshedit.settings.CELL_MIN;
const CELL_STEP = meshedit.settings.CELL_STEP;
const Ch = meshedit.settings.Ch;
const Editor = meshedit.editor.Editor;
const FINE = meshedit.settings.FINE;
const LIST_ROWS = meshedit.settings.LIST_ROWS;
const LIST_W = meshedit.settings.LIST_W;
const LIST_Y = meshedit.settings.LIST_Y;
const NEW_OFF = meshedit.settings.NEW_OFF;
const PAD = meshedit.settings.PAD;
const PICK = meshedit.settings.PICK;
const Piece = meshedit.doc.Piece;
const ROW = meshedit.settings.ROW;
const Vals = meshedit.settings.Vals;
const listRows = meshedit.settings.listRows;
const nextShade = meshedit.settings.nextShade;
const overUi = meshedit.settings.overUi;
const valuesY = meshedit.settings.valuesY;

/// one frame's keys and mouse; `handles` where each form's handle is on
/// screen (null behind the eye), the gizmo seen through `view` with the
/// sculpt at `origin`
pub fn handle(e:*Editor, in:*const Input, handles:[]const ?[2]f32, view:gizmo.View, origin:V3) Allocator.Error!void {
  const shift = in.down(.{ .key = .left_shift }) or in.down(.{ .key = .right_shift });
  const ctrl = in.down(.{ .key = .left_control }) or in.down(.{ .key = .right_control });
  const hit = struct {
    fn f(i:*const Input, k:Key) bool { return i.pressed(.{ .key = k }); }
  }.f;
  const gpa = e.gpa;

  if (hit(in, .n)) {
    var p:Piece = if (e.pieces().len > 0) e.pieces()[e.sel] else .{};
    if (e.pieces().len > 0) p.v.pos += NEW_OFF;
    const at = if (e.pieces().len > 0) e.sel + 1 else 0;
    try e.doc.pieces.insert(gpa, at, p);
    e.sel = at;
    e.changed();
  }
  if (e.pieces().len > 0) {
    if (hit(in, .delete)) {
      _ = e.doc.pieces.orderedRemove(e.sel);
      e.sel -|= @intFromBool(e.sel >= e.pieces().len);
      e.changed();
    }
  }
  if (e.pieces().len > 0) {
    const ps_ = e.pieces();
    if (hit(in, .tab)) e.sel = (e.sel + 1) % ps_.len;
    if (hit(in, .page_up) and e.sel > 0) {
      std.mem.swap(Piece, &ps_[e.sel], &ps_[e.sel - 1]);
      e.sel -= 1;
      e.changed();
    }
    if (hit(in, .page_down) and e.sel + 1 < ps_.len) {
      std.mem.swap(Piece, &ps_[e.sel], &ps_[e.sel + 1]);
      e.sel += 1;
      e.changed();
    }
    const p = &ps_[e.sel];
    if (hit(in, .t)) {
      p.kind = switch (p.kind) { .ellipsoid => .cone, .cone => .box, .box => .ellipsoid };
      e.changed();
    }
    if (hit(in, .c)) {
      p.carve = !p.carve;
      e.changed();
    }
    if (hit(in, .m)) {
      p.shade = nextShade(p.shade, if (shift) .back else .on);
      e.changed();
    }
    if (hit(in, .up) and e.ch > 0) e.ch -= 1;
    if (hit(in, .down) and e.ch + 1 < Ch.count) e.ch += 1;
    if (hit(in, .r)) e.set(Ch.get(&Vals{}, e.ch));
    if (hit(in, .period)) e.focus = true;
  }
  if (hit(in, .one)) e.mode = .move;
  if (hit(in, .two)) e.mode = .turn;
  if (hit(in, .three)) e.mode = .size;
  if (hit(in, .left_bracket)) {
    e.doc.cell = @max(CELL_MIN, e.doc.cell - CELL_STEP);
    e.changed();
  }
  if (hit(in, .right_bracket)) {
    e.doc.cell += CELL_STEP;
    e.changed();
  }
  if (ctrl and hit(in, .s)) e.save();

  // the mouse: a press on a form row selects it, on a value row selects
  // it and drags it, on the gizmo drags its handle, on a handle in view
  // selects its form
  const mx = in.mouse[0];
  const my = in.mouse[1];
  const vy = valuesY(listRows(e.pieces().len));
  const g = e.gizmoAt(origin);
  const ui = overUi(listRows(e.pieces().len), mx, my);
  e.hot = if (e.drag == .gizmo) e.part else if (g != null and !ui) g.?.pick(view, in.mouse) else null;
  if (in.pressed(.{ .button = .left })) {
    if (mx < PAD + LIST_W and my >= LIST_Y and my < vy) {
      const r:usize = @intFromFloat(@floor((my - LIST_Y) / ROW));
      if (e.top + r < e.pieces().len) e.sel = e.top + r;
    } else if (mx < PAD + LIST_W and my >= vy and my < vy + m.f(Ch.count) * ROW and e.pieces().len > 0) {
      e.ch = @intFromFloat(@floor((my - vy) / ROW));
      e.drag = .value;
    } else if (e.hot) |part| {
      e.part = part;
      e.drag = .gizmo;
    } else {
      var best:f32 = PICK;
      for (handles, 0..) |h, i| if (h) |at| {
        const d = m.len(v3(at[0] - mx, at[1] - my, 0));
        if (d < best) {
          best = d;
          e.sel = i;
        }
      };
    }
  }
  if (!in.down(.{ .button = .left })) e.drag = .none;
  if (e.pieces().len == 0) e.drag = .none;
  if (e.drag == .value and in.mouse_delta[0] != 0) {
    e.set(Ch.get(&e.pieces()[e.sel].v, e.ch) + in.mouse_delta[0] * e.rate() * (if (shift) FINE else 1));
  }
  if (e.drag == .gizmo and (in.mouse_delta[0] != 0 or in.mouse_delta[1] != 0)) if (g) |gz| {
    const from = [2]f32{ mx - in.mouse_delta[0], my - in.mouse_delta[1] };
    e.dragGizmo(gz, view, from, in.mouse, if (shift) FINE else 1);
  };
  if (e.drag != .gizmo) e.part = null;
  // the selection kept in view
  if (e.sel < e.top) e.top = e.sel;
  if (e.sel >= e.top + LIST_ROWS) e.top = e.sel + 1 - LIST_ROWS;
}
