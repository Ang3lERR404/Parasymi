//! a rudimentary mesh editor: sculpts one seamless surface out of forms
//! (engine gfx/sculpt.zig: ellipsoids, rounded cones, rounded boxes, each
//! melted into the ones before it or carved out of them), meshed again as
//! it is edited and shown on the game's own renderer, alone on the
//! generated ground (no wolf, plants or structures), and keeps it as text
//! in `src/mesh/<name>.mesh`. The game does not read these yet. From the
//! repo root:
//!   zig build meshedit -- [--mesh=<name>]
//! (`--gizmo=move|turn|size` starts the gizmo so; `--shot` saves one frame
//! to `shots/meshedit.png` and closes, for checking it headless.)
//! Each form is placed by `pos`, turned by `rot` (degrees, y then x then
//! z) and sized by `size` (radii; a cone's x and z its radii at its foot
//! and its tip, y half its length; a box's half extents); `round` rounds a
//! box, `melt` is how far it melts into what is before it, `col` its colour.
//! The selected form carries a gizmo (tools/gizmo.zig): `1` moves it
//! (arrows along each axis, the centre across the view), `2` turns it
//! (a ring for each of its turns), `3` sizes it (along its own axes).
//! The camera orbits the sculpt freely (middle drag, over the top and
//! under it alike; the wheel zooms); `.` eases it onto the selected form.
//!
//! decision: a developer's tool, not the game: its few words and keys are
//! written here, not in the strings or controls files (the camera's orbit
//! still follows the game's binding).
const std = ps.std;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;
const Writer = Io.Writer;
const eql = std.mem.eql;
const startsWith = std.mem.startsWith;
const stringToEnum = std.meta.stringToEnum;
const splitScalar = std.mem.splitScalar;
const tokenizeScalar = std.mem.tokenizeScalar;
const trim = std.mem.trim;
const parseFloat = std.fmt.parseFloat;
const bufPrint = std.fmt.bufPrint;
const log = std.log;
const testing = std.testing;
const engine = ps.engine;
const glfw = engine.glfw;
const m = engine.core.math;
const color = engine.core.color;
const clip = engine.anim.clip;
const sculpt = engine.gfx.sculpt;
const Input = engine.platform.input.Input;
const Key = engine.platform.input.Key;
const Draw = engine.ui.draw.Draw;
const Color = engine.ui.draw.Color;
const camera = engine.render.camera;
const ps = @import("parasymi");
const gizmo = @import("gizmo.zig");
const play = ps.play;
const Game = play.Game;
const renderer = ps.renderer;
const Renderer = renderer.Renderer;
const loading = ps.loading;
const meshgen = ps.meshgen;
const meshlib = ps.meshlib;
const ctl = ps.controls;
const s = ps.style;

const V3 = m.V3;
const v3 = m.v3;

/// meshes are kept here (from the repo root)
const DIR = "src/mesh";
const EXT = ".mesh";
/// the first line of a mesh's text
const HEADER = "# mesh";
/// `--shot` writes here, this many frames in (the world settled)
const SHOT = "shots/meshedit.png";
const SHOT_FRAMES = 30;
/// a stalled frame counts as at most this long (s)
const MAX_DT:f64 = 0.1;
/// the surface's cells (m): to start, the step `[`/`]` take, the least,
/// and the most cells across the whole sculpt (past that they widen)
const CELL:f32 = 0.01;
const CELL_STEP:f32 = 0.0025;
const CELL_MIN:f32 = 0.0025;
const MAX_CELLS:f32 = 256;
/// the least a form's size may be (m)
const SIZE_MIN:f32 = 0.005;
/// while a value is dragged the surface is meshed again at most this often
/// (s), its cells this many times wider (full detail once it is let go)
const REMESH:f32 = 0.08;
const DRAG_COARSE:f32 = 2;
/// a drag changes a length this much per pixel, a turn (degrees) and a
/// colour these (shift: `FINE` of it)
const DRAG_LEN:f32 = 0.002;
const DRAG_DEG:f32 = 0.5;
const DRAG_COL:f32 = 0.004;
const FINE:f32 = 0.2;
/// where the gizmo's values start among a form's channels
const POS = Ch.find("pos.x").?;
const ROT = Ch.find("rot.x").?;
const SIZE = Ch.find("size.x").?;
/// a new form stands this far from the one it was made from
const NEW_OFF = v3(0.1, 0, 0);
/// the camera looks at this height over the sculpt's ground, from this far
/// and this high (rad) to start; the wheel zooms it this much a notch,
/// between these (m); it eases half way to where it is sent in this (s)
const LOOK_UP:f32 = 0.3;
const CAM_DIST:f32 = 1.6;
const CAM_PITCH:f32 = m.rad(20);
const ZOOM_STEP:f32 = 0.88;
const DIST_MIN:f32 = 0.08;
const DIST_MAX:f32 = 40;
const EASE:f32 = 0.06;
/// `.` frames a form from this many times its largest size, at least this
const FOCUS_FIT:f32 = 4;
const FOCUS_MIN:f32 = 0.15;
/// the library slot the sculpt is drawn from: nothing else is drawn
const SLOT_ID:meshlib.Id = meshlib.ids[0];
/// no wolf: its paws' contact shadows far off any tile
const NO_FEET:f32 = 1e9;
/// layout (px): the form list, the selected form's values under it
const PAD:f32 = 16;
const TEXT:f32 = s.text_small;
const ROW:f32 = 18;
const LIST_Y:f32 = 100;
const LIST_W:f32 = 300;
const LIST_ROWS = 12;
const VALUE_X:f32 = 150;
const LINE_H:f32 = 20;
const GAP:f32 = 14;
/// a form's handle in view (the selected one shows its gizmo instead): its
/// radius, and how near a click picks it (px)
const HANDLE_R:f32 = 4;
const PICK:f32 = 14;
/// colours: selected, set, dim, carving, panels
const SEL:Color = s.gold;
const PLAIN:Color = s.white;
const BARE:Color = s.dim;
const CARVE:Color = s.growth;
const PANEL:Color = s.panel;

const HELP = [_][]const u8{
  "n new form (from the selected)   del remove   pgup/pgdn move in the list   t shape   c carve   tab next form",
  "up/down value   drag value (shift fine)   r value at rest   [ ] cells   click a handle: select   ctrl+s save",
  "gizmo: 1 move   2 turn   3 size   drag its handles (shift fine)   middle drag orbit   wheel zoom   . focus the form",
};

const Kind = enum { ellipsoid, cone, box };

/// a form's numbers, every one a value the editor shows and keeps
const Vals = struct {
  pos:V3 = .{ 0, 0.3, 0 },
  rot:V3 = .{ 0, 0, 0 },
  size:V3 = .{ 0.15, 0.15, 0.15 },
  round:f32 = 0.02,
  melt:f32 = 0.03,
  col:V3 = .{ 0.45, 0.42, 0.3 },
};
const Ch = clip.Channels(Vals);

const Piece = struct {
  kind:Kind = .ellipsoid,
  carve:bool = false,
  v:Vals = .{},

  /// as the sculpt takes it
  fn form(p:Piece) sculpt.Form {
    const v = p.v;
    const at = m.chain(&.{ m.translate(v.pos), m.rotY(m.rad(v.rot[1])), m.rotX(m.rad(v.rot[0])), m.rotZ(m.rad(v.rot[2])) });
    const z = v3(0, 0, 0);
    return .{
      .shape = switch (p.kind) {
        .ellipsoid => .{ .ellipsoid = .{ .c = z, .r = v.size } },
        .cone => .{ .cone = .{ .a = v3(0, -v.size[1], 0), .b = v3(0, v.size[1], 0), .ra = v.size[0], .rb = v.size[2] } },
        .box => .{ .box = .{ .c = z, .half = v.size, .round = @min(v.round, @reduce(.Min, v.size)) } },
      },
      .at = at,
      .bone = 0,
      .col = color.rgb(v.col[0], v.col[1], v.col[2]).toRgba8(255),
      .k = v.melt,
      .carve = p.carve,
    };
  }

  /// the farthest it reaches from the sculpt's origin (m)
  fn reach(p:Piece) f32 {
    return m.len(p.v.pos) + m.len(p.v.size) + p.v.melt;
  }
};

/// what a mesh's text holds: its cells and its forms, in order
const Doc = struct {
  cell:f32 = CELL,
  pieces:std.ArrayList(Piece) = .empty,

  fn deinit(d:*Doc, gpa:Allocator) void { d.pieces.deinit(gpa); }

  fn write(d:*const Doc, w:*Writer) Writer.Error!void {
    try w.print(HEADER ++ "\ncell {d}\n", .{d.cell});
    for (d.pieces.items) |p| {
      try w.print("form {t}{s}\n", .{ p.kind, if (p.carve) " carve" else "" });
      for (Ch.names, 0..) |n, i| try w.print("{s} {d}\n", .{ n, Ch.get(&p.v, i) });
    }
  }

  const ParseError = error{ BadMesh, OutOfMemory };

  fn parse(gpa:Allocator, text:[]const u8) ParseError!Doc {
    var d:Doc = .{};
    errdefer d.deinit(gpa);
    var lines = splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
      const line = trim(u8, raw, " \t\r");
      if (line.len == 0 or line[0] == '#') continue;
      var it = tokenizeScalar(u8, line, ' ');
      const word = it.next() orelse continue;
      if (eql(u8, word, "cell")) {
        d.cell = @max(CELL_MIN, parseFloat(f32, it.next() orelse return error.BadMesh) catch return error.BadMesh);
      } else if (eql(u8, word, "form")) {
        const kind = stringToEnum(Kind, it.next() orelse return error.BadMesh) orelse return error.BadMesh;
        const carve = if (it.next()) |c| eql(u8, c, "carve") else false;
        try d.pieces.append(gpa, .{ .kind = kind, .carve = carve });
      } else {
        const i = Ch.find(word) orelse return error.BadMesh;
        if (d.pieces.items.len == 0) return error.BadMesh;
        const v = parseFloat(f32, it.next() orelse return error.BadMesh) catch return error.BadMesh;
        Ch.set(&d.pieces.items[d.pieces.items.len - 1].v, i, v);
      }
    }
    return d;
  }

  /// its surface into `b`, cells `cell` across (wider where the sculpt is
  /// too big for that many; `DRAG_COARSE` times them while `coarse`);
  /// nothing when no form adds anything
  fn mesh(d:*const Doc, gpa:Allocator, io:?Io, coarse:bool, b:*meshgen.Builder) Allocator.Error!void {
    var solid = false;
    var far:f32 = 0;
    for (d.pieces.items) |p| {
      solid = solid or !p.carve;
      far = @max(far, p.reach());
    }
    if (!solid) return;
    var sc:sculpt.Sculpt = .{ .gpa = gpa, .parents = &.{null}, .io = io };
    defer sc.deinit();
    for (d.pieces.items) |p| try sc.add(p.form());
    const h = @max(d.cell, 2 * far / MAX_CELLS) * (if (coarse) DRAG_COARSE else 1);
    try sc.mesh(meshgen.gen, b, h, 0.5, .stem);
  }
};

const Drag = enum { none, value, gizmo };

/// the editor's camera: a free view turning round `target` from `dist`
/// away, with no limit on its pitch (over the top and under the sculpt
/// alike); zooms and focusing ease it to `goal` and `goal_dist`
const Orbit = struct {
  target:V3,
  goal:V3,
  dist:f32 = CAM_DIST,
  goal_dist:f32 = CAM_DIST,
  yaw:f32 = 0,
  pitch:f32 = CAM_PITCH,

  fn init(at:V3) Orbit { return .{ .target = at, .goal = at }; }

  /// drag round by `px` pixels, as the game's camera turns
  fn turn(o:*Orbit, px:[2]f32) void {
    o.yaw = @mod(o.yaw - px[0] * camera.ORBIT, m.tau);
    o.pitch = @mod(o.pitch + px[1] * camera.ORBIT, m.tau);
  }

  fn zoom(o:*Orbit, steps:f32) void {
    o.goal_dist = m.clamp(o.goal_dist * m.pow(f32, ZOOM_STEP, steps), DIST_MIN, DIST_MAX);
  }

  /// look at `at`, near enough that something `size` across fills the view
  fn focus(o:*Orbit, at:V3, size:f32) void {
    o.goal = at;
    o.goal_dist = m.clamp(@max(size * FOCUS_FIT, FOCUS_MIN), DIST_MIN, DIST_MAX);
  }

  /// ease on by `dt` and place `c` (a free view aimed at the target)
  fn step(o:*Orbit, c:*camera.Camera, dt:f32) void {
    const k = 1 - m.pow(f32, 0.5, dt / EASE);
    o.target = m.lerpV(o.target, o.goal, k);
    o.dist = m.lerp(o.dist, o.goal_dist, k);
    c.target = o.target;
    c.dist = o.dist;
    c.yaw = o.yaw;
    const cp = @cos(o.pitch);
    const out = v3(@sin(o.yaw) * cp, @sin(o.pitch), @cos(o.yaw) * cp);
    c.view = .{ .free = .{ .pos = o.target + out * m.splat3(o.dist), .yaw = o.yaw, .pitch = -o.pitch } };
  }
};

const Editor = struct {
  gpa:Allocator,
  io:Io,
  path:[]const u8,
  doc:Doc,
  /// the form selected, the value selected in it, the first form row in view
  sel:usize = 0,
  ch:usize = 0,
  top:usize = 0,
  drag:Drag = .none,
  /// what the gizmo does, the handle held, and the one under the mouse
  mode:gizmo.Mode = .move,
  part:?gizmo.Part = null,
  hot:?gizmo.Part = null,
  dirty:bool = false,
  /// the surface wants meshing again, and how long since it last was
  stale:bool = true,
  since:f32 = 0,
  /// what is shown was meshed coarser, while dragging
  coarse:bool = false,
  note:[96]u8 = undefined,
  note_len:usize = 0,
  /// the camera is asked onto the selected form
  focus:bool = false,

  fn pieces(e:*Editor) []Piece { return e.doc.pieces.items; }

  fn say(e:*Editor, comptime fmt:[]const u8, args:anytype) void {
    e.note_len = if (bufPrint(&e.note, fmt, args)) |w| w.len else |_| e.note.len;
  }

  fn changed(e:*Editor) void {
    e.dirty = true;
    e.stale = true;
  }

  fn save(e:*Editor) void {
    const io = e.io;
    var out:Writer.Allocating = .init(e.gpa);
    defer out.deinit();
    e.doc.write(&out.writer) catch return e.say("save failed: out of memory", .{});
    Dir.cwd().createDirPath(io, DIR) catch |er| return e.say("save failed: {t}", .{er});
    Dir.cwd().writeFile(io, .{ .sub_path = e.path, .data = out.written() }) catch |er| return e.say("save failed: {t}", .{er});
    e.dirty = false;
    e.say("saved {s}", .{e.path});
  }

  /// the selected value set to `v`, kept where it makes sense
  fn set(e:*Editor, v:f32) void { e.setCh(e.ch, v); }

  /// the selected form's value `ch` set to `v`, kept where it makes sense
  fn setCh(e:*Editor, ch:usize, v:f32) void {
    const p = &e.pieces()[e.sel];
    const name = Ch.names[ch];
    const kept = if (startsWith(u8, name, "size")) @max(SIZE_MIN, v) else if (startsWith(u8, name, "col")) m.clamp01(v) else if (eql(u8, name, "melt") or eql(u8, name, "round")) @max(0, v) else v;
    Ch.set(&p.v, ch, kept);
    e.changed();
  }

  /// the selected form's value `ch` changed by `by`
  fn nudge(e:*Editor, ch:usize, by:f32) void { e.setCh(ch, Ch.get(&e.pieces()[e.sel].v, ch) + by); }

  /// the selected form's gizmo where it stands (`origin` the sculpt's
  /// place), none without forms
  fn gizmoAt(e:*Editor, origin:V3) ?gizmo.Gizmo {
    if (e.pieces().len == 0) return null;
    const v = e.pieces()[e.sel].v;
    const ry = m.rotY(m.rad(v.rot[1]));
    const rx = m.mul(ry, m.rotX(m.rad(v.rot[0])));
    const full = m.mul(rx, m.rotZ(m.rad(v.rot[2])));
    const X = v3(1, 0, 0);
    const Y = v3(0, 1, 0);
    const Z = v3(0, 0, 1);
    return .{ .at = origin + v.pos, .mode = e.mode, .axes = switch (e.mode) {
      .move => .{ X, Y, Z },
      // each turn about the axis it turns round: y the world's, x after
      // y, z after both
      .turn => .{ m.mulDir(ry, X), Y, m.mulDir(rx, Z) },
      .size => .{ m.mulDir(full, X), m.mulDir(full, Y), m.mulDir(full, Z) },
    } };
  }

  /// a drag of the gizmo's held handle from `from` to `to` (px), `k` of it
  fn dragGizmo(e:*Editor, g:gizmo.Gizmo, view:gizmo.View, from:[2]f32, to:[2]f32, k:f32) void {
    const part = e.part orelse return;
    switch (part) {
      .free => {
        const by:[3]f32 = g.across(view, from, to) * m.splat3(k);
        for (0..3) |i| e.nudge(POS + i, by[i]);
        e.ch = POS;
      },
      .x, .y, .z => {
        const i = @intFromEnum(part);
        const by = g.along(view, i, from, to) * k;
        e.ch = i + switch (e.mode) { .move => POS, .turn => ROT, .size => SIZE };
        e.nudge(e.ch, if (e.mode == .turn) by / m.rad(1) else by);
      },
    }
  }

  fn rate(e:*const Editor) f32 {
    const name = Ch.names[e.ch];
    return if (startsWith(u8, name, "rot")) DRAG_DEG else if (startsWith(u8, name, "col")) DRAG_COL else DRAG_LEN;
  }

  /// one frame's keys and mouse; `handles` where each form's handle is on
  /// screen (null behind the eye), the gizmo seen through `view` with the
  /// sculpt at `origin`
  fn handle(e:*Editor, in:*const Input, handles:[]const ?[2]f32, view:gizmo.View, origin:V3) Allocator.Error!void {
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

  fn draw(e:*Editor, d:*Draw, screen:[2]f32, handles:[]const ?[2]f32, view:gizmo.View, origin:V3) Allocator.Error!void {
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
};

/// how many form rows show (at least one, at most `LIST_ROWS`)
fn listRows(n:usize) usize { return m.clamp(n, 1, LIST_ROWS); }
/// where the values start, under `rows` form rows
fn valuesY(rows:usize) f32 { return LIST_Y + m.f(rows) * ROW + 12 + GAP; }

fn overUi(rows:usize, x:f32, y:f32) bool {
  return x < PAD + LIST_W and y >= LIST_Y - 6 and y < valuesY(rows) + m.f(Ch.count) * ROW + 6;
}

pub fn main(init:std.process.Init) !void {
  const gpa = init.gpa;
  const io = init.io;
  const arena = init.arena.allocator();
  const args = try init.minimal.args.toSlice(arena);

  var name:[]const u8 = "sculpt";
  var shot = false;
  var mode:gizmo.Mode = .move;
  for (args[1..]) |a| {
    if (startsWith(u8, a, "--mesh=")) name = a["--mesh=".len..];
    if (startsWith(u8, a, "--gizmo=")) mode = stringToEnum(gizmo.Mode, a["--gizmo=".len..]) orelse return error.BadGizmo;
    if (eql(u8, a, "--shot")) shot = true;
  }
  const path = try std.fmt.allocPrint(arena, DIR ++ "/{s}" ++ EXT, .{name});

  // the mesh: as kept, else one form to start from
  const doc = load: {
    const text = Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 22)) catch |er| switch (er) {
      error.FileNotFound => {
        var fresh:Doc = .{};
        try fresh.pieces.append(gpa, .{});
        break :load fresh;
      },
      else => return er,
    };
    defer gpa.free(text);
    break :load try Doc.parse(gpa, text);
  };
  var e:Editor = .{ .gpa = gpa, .io = io, .path = path, .doc = doc, .mode = mode };
  defer e.doc.deinit(gpa);

  // the game's files (controls, strings), as the game reads them
  try ps.home.open(io, init.environ_map);
  defer ps.home.close(io);
  const opts = try ps.options.load(gpa, io);
  try ctl.load(gpa, io);
  defer ctl.unload();
  try ps.txt.load(gpa, io);
  defer ps.txt.unload(gpa);

  try glfw.init();
  defer glfw.terminate();
  if (!glfw.isVulkanSupported()) return error.VulkanUnsupported;
  glfw.windowHint(.client_api, .no_api);
  const window = try glfw.createWindow(play.WINDOW[0], play.WINDOW[1], "Parasymi mesh editor", null, null);
  defer window.destroy();
  var input:Input = .{ .win = window };
  input.attach();

  // the renderer grows next to nothing (the editor puts its own meshes in)
  const r = try Renderer.init(gpa, window, opts.vsync, opts.aa, .{ .only = .{ .parts = &.{SLOT_ID} } });
  defer r.deinit();

  // the meshes grow, then the world wakes and its ground is meshed,
  // behind the game's loading screen
  var screen_l = loading.Loading.init(gpa);
  defer screen_l.deinit();
  var last = glfw.getTime();
  const whole = 2 + play.STREAM_CHUNKS;
  while (!try renderer.meshesReady(r)) {
    if (!try loadFrame(&screen_l, r, &input, &last, .forms, .{ .done = 0, .total = whole })) return;
  }
  // the sculpt alone, meshed again as it changes
  var b:meshgen.Builder = .{ .gpa = gpa };
  defer b.deinit();
  var ranges:[meshlib.SLOTS][2]u32 = @splat(.{ 0, 0 });
  _ = try loadFrame(&screen_l, r, &input, &last, .forms, .{ .done = 1, .total = whole });

  var game = try Game.init(gpa, play.DEFAULT_SEED);
  defer game.deinit();
  game.world.io = io;
  game.opts = opts;
  while (game.world.unmeshed() > 0) {
    if (!try loadFrame(&screen_l, r, &input, &last, .ground, .{ .done = whole - game.world.unmeshed(), .total = whole })) return;
    try renderer.syncWorld(r, &game.world, m.maxInt(u32), renderer.MESH_MS * 8);
  }
  // the sculpt stands where the wolf would have woken (dry ground)
  const origin = game.player.pos;
  var cam = Orbit.init(origin + v3(0, LOOK_UP, 0));

  var ui:Draw = .{ .gpa = gpa };
  defer ui.deinit();
  var handles:std.ArrayList(?[2]f32) = .empty;
  defer handles.deinit(gpa);

  var frames:u32 = 0;
  while (!window.shouldClose()) {
    glfw.pollEvents();
    input.update();
    frames += 1;
    const now = glfw.getTime();
    const dt:f32 = @floatCast(@min(now - last, MAX_DT));
    last = now;
    const screen = r.extent();

    // handles and the gizmo as last frame's camera saw them
    const seen:gizmo.View = .{ .vp = game.cam.viewProj(), .eye = game.cam.viewEye(), .screen = screen };
    handles.clearRetainingCapacity();
    for (e.pieces()) |p| try handles.append(gpa, seen.project(origin + p.v.pos));
    try e.handle(&input, handles.items, seen, origin);
    e.sel = @min(e.sel, e.pieces().len -| 1);

    // the surface meshed again once it changed (while dragging, not every frame)
    e.since += dt;
    // (coarser while dragging, at full detail once let go)
    if (e.drag == .none and e.coarse) e.stale = true;
    if (e.stale and (e.drag == .none or e.since >= REMESH)) {
      const coarse = e.drag != .none;
      b.v.clearRetainingCapacity();
      b.skin.clearRetainingCapacity();
      b.grow.clearRetainingCapacity();
      try e.doc.mesh(gpa, io, coarse, &b);
      const run:[2]u32 = .{ 0, @intCast(b.mark()) };
      for (0..meshgen.LODS) |l| ranges[meshlib.slot(SLOT_ID, @intCast(l))] = run;
      try renderer.setParts(r, &b, ranges, 0);
      e.stale = false;
      e.coarse = coarse;
      e.since = 0;
    }

    // the camera orbits the sculpt freely and zooms; nothing of play runs
    // (no plants grow), only the clocks for the sky and the grass
    game.ui_time += dt;
    game.time += dt;
    game.cam.aspect = screen[0] / @max(screen[1], 1);
    const over_ui = overUi(listRows(e.pieces().len), input.mouse[0], input.mouse[1]);
    if (ctl.down(&input, .orbit)) cam.turn(input.mouse_delta);
    if (input.scroll != 0 and !over_ui) cam.zoom(input.scroll);
    if (e.focus and e.pieces().len > 0) {
      const v = e.pieces()[e.sel].v;
      cam.focus(origin + v.pos, @reduce(.Max, v.size));
    }
    e.focus = false;
    cam.step(&game.cam, dt);
    try renderer.syncWorld(r, &game.world, 6, renderer.MESH_MS);

    // the scene as the game sees it, but only the ground and the sculpt
    var scene = try ps.view.scene(&game, screen);
    for (&scene.parts) |*p| p.* = &.{};
    for (&scene.instances) |*p| p.* = &.{};
    scene.lights = &.{};
    for (&scene.push.feet) |*f| f.* = .{ NO_FEET, NO_FEET, NO_FEET, 0 };
    const inst = [1]ps.vertex.PartInstance{ps.parts.instance(m.translate(origin), .{})};
    scene.parts[meshlib.slot(SLOT_ID, 0)] = &inst;
    // handles drawn where the forms are now (one may have gone or come)
    const view:gizmo.View = .{ .vp = game.cam.viewProj(), .eye = game.cam.viewEye(), .screen = screen };
    handles.clearRetainingCapacity();
    for (e.pieces()) |p| try handles.append(gpa, view.project(origin + p.v.pos));
    ui.clear(@floatCast(game.ui_time));
    try e.draw(&ui, screen, handles.items, view, origin);
    scene.ui = ui.v.items;
    const resized = input.resized;
    input.resized = false;
    r.capture = shot and frames == SHOT_FRAMES;
    try r.draw(&scene, resized);
    if (r.shot()) |sh| {
      const bytes = try engine.core.png.encode(gpa, sh.w, sh.h, sh.px, if (sh.bgra) .bgra else .rgba);
      defer gpa.free(bytes);
      try Dir.cwd().createDirPath(io, "shots");
      try Dir.cwd().writeFile(io, .{ .sub_path = SHOT, .data = bytes });
      log.info("shot {s}", .{SHOT});
      window.setShouldClose(true);
    }
  }
  if (e.dirty) log.warn("{s}: unsaved changes dropped", .{path});
}

/// one frame of the loading screen; false once the window is closed
fn loadFrame(l:*loading.Loading, r:*Renderer, input:*Input, last:*f64, stage:loading.Stage, at:loading.Progress) !bool {
  glfw.pollEvents();
  input.update();
  if (r.window.shouldClose()) return false;
  const now = glfw.getTime();
  const dt = @min(now - last.*, MAX_DT);
  last.* = now;
  l.step(stage, at, @floatCast(dt));
  var scene = try l.scene(r.extent());
  const resized = input.resized;
  input.resized = false;
  try r.draw(&scene, resized);
  return true;
}

test {
  _ = gizmo;
}

test "a mesh's text reads back as written" {
  const gpa = testing.allocator;
  var d:Doc = .{ .cell = 0.02 };
  defer d.deinit(gpa);
  try d.pieces.append(gpa, .{});
  try d.pieces.append(gpa, .{ .kind = .box, .carve = true, .v = .{ .pos = .{ 0.1, 0.2, -0.3 }, .round = 0.01 } });
  var out:Writer.Allocating = .init(gpa);
  defer out.deinit();
  try d.write(&out.writer);
  var back = try Doc.parse(gpa, out.written());
  defer back.deinit(gpa);
  try testing.expectEqual(d.cell, back.cell);
  try testing.expectEqual(d.pieces.items.len, back.pieces.items.len);
  for (d.pieces.items, back.pieces.items) |a, z| {
    try testing.expectEqual(a.kind, z.kind);
    try testing.expectEqual(a.carve, z.carve);
    for (0..Ch.count) |i| try testing.expectEqual(Ch.get(&a.v, i), Ch.get(&z.v, i));
  }
}

test "carving alone makes no surface, a form makes a closed one" {
  const gpa = testing.allocator;
  var d:Doc = .{ .cell = 0.02 };
  defer d.deinit(gpa);
  var b:meshgen.Builder = .{ .gpa = gpa };
  defer b.deinit();
  try d.pieces.append(gpa, .{ .carve = true });
  try d.mesh(gpa, null, false, &b);
  try testing.expectEqual(@as(usize, 0), b.v.items.len);
  try d.pieces.append(gpa, .{ .kind = .cone });
  try d.mesh(gpa, null, false, &b);
  try testing.expect(b.v.items.len > 0);
  try testing.expectEqual(@as(usize, 0), b.v.items.len % 3);
}

test "the camera eases onto a focused form and turns past straight up" {
  var o = Orbit.init(v3(0, 0, 0));
  var c:camera.Camera = .{};
  o.focus(v3(1, 2, 3), 0.1);
  for (0..200) |_| o.step(&c, 0.02);
  try testing.expect(m.len(o.target - v3(1, 2, 3)) < 1e-3);
  try testing.expectApproxEqAbs(@max(0.1 * FOCUS_FIT, FOCUS_MIN), o.dist, 1e-3);
  try testing.expectApproxEqAbs(o.dist, m.len(c.view.free.pos - o.target), 1e-3);
  // dragged over the top, the view still looks at the target
  o.pitch = m.rad(120);
  o.step(&c, 0);
  try testing.expect(m.len(c.view.free.pos + c.view.free.forward() * m.splat3(o.dist) - o.target) < 1e-3);
}
