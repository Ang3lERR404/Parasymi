//! a rudimentary mesh editor: sculpts one seamless surface out of forms
//! (engine gfx/sculpt.zig: ellipsoids, rounded cones, rounded boxes, each
//! melted into the ones before it or carved out of them), meshed again as
//! it is edited and shown on the game's own renderer beside the wolf, and
//! keeps it as text in `src/mesh/<name>.mesh`. The game does not read
//! these yet. From the repo root:
//!   zig build meshedit -- [--mesh=<name>]
//! (`--shot` saves one frame to `shots/meshedit.png` and closes, for
//! checking it headless.)
//! Each form is placed by `pos`, turned by `rot` (degrees, y then x then
//! z) and sized by `size` (radii; a cone's x and z its radii at its foot
//! and its tip, y half its length; a box's half extents); `round` rounds a
//! box, `melt` is how far it melts into what is before it, `col` its colour.
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
const ps = @import("parasymi");
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
/// a new form stands this far from the one it was made from
const NEW_OFF = v3(0.1, 0, 0);
/// the sculpt stands this far to the wolf's side; the camera looks at this
/// height over it, from this far and this high (rad) to start
const BESIDE = v3(1.2, 0, 0);
const LOOK_UP:f32 = 0.35;
const CAM_DIST:f32 = 2.6;
const CAM_PITCH:f32 = m.rad(20);
/// the library slot the sculpt is drawn from: nothing else is drawn from
/// it here (the wolf's own slots aside, every other is emptied)
const SLOT_ID:meshlib.Id = meshlib.ids[0];
/// what the wolf is made of, built once
const WOLF = [_]meshlib.Id{ .wolf_body, .wolf_ears, .belly_lump, .wolf_belly, .wolf_pec_l, .wolf_pec_r, .wolf_rump_l, .wolf_rump_r, .paw_pad, .paw_bean };
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
/// a form's handle in view: its radius, the selected one's, and how near
/// a click picks it (px)
const HANDLE_R:f32 = 4;
const SEL_HANDLE_R:f32 = 7;
const PICK:f32 = 14;
/// colours: selected, set, dim, carving, panels
const SEL:Color = s.gold;
const PLAIN:Color = s.white;
const BARE:Color = s.dim;
const CARVE:Color = s.growth;
const PANEL:Color = s.membrane;

const HELP = [_][]const u8{
  "n new form (from the selected)   del remove   pgup/pgdn move in the list   t shape   c carve   tab next form",
  "up/down value   drag value (shift fine)   r value at rest   [ ] cells   click a handle: select   ctrl+s save",
  "middle drag orbit   wheel zoom",
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

const Drag = enum { none, value };

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
  dirty:bool = false,
  /// the surface wants meshing again, and how long since it last was
  stale:bool = true,
  since:f32 = 0,
  /// what is shown was meshed coarser, while dragging
  coarse:bool = false,
  note:[96]u8 = undefined,
  note_len:usize = 0,

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
  fn set(e:*Editor, v:f32) void {
    const p = &e.pieces()[e.sel];
    const name = Ch.names[e.ch];
    const kept = if (startsWith(u8, name, "size")) @max(SIZE_MIN, v) else if (startsWith(u8, name, "col")) m.clamp01(v) else if (eql(u8, name, "melt") or eql(u8, name, "round")) @max(0, v) else v;
    Ch.set(&p.v, e.ch, kept);
    e.changed();
  }

  fn rate(e:*const Editor) f32 {
    const name = Ch.names[e.ch];
    return if (startsWith(u8, name, "rot")) DRAG_DEG else if (startsWith(u8, name, "col")) DRAG_COL else DRAG_LEN;
  }

  /// one frame's keys and mouse; `handles` where each form's handle is on
  /// screen (null behind the eye)
  fn handle(e:*Editor, in:*const Input, handles:[]const ?[2]f32) Allocator.Error!void {
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
    }
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
    // it and drags it, on a handle in view selects its form
    const mx = in.mouse[0];
    const my = in.mouse[1];
    const vy = valuesY(listRows(e.pieces().len));
    if (in.pressed(.{ .button = .left })) {
      if (mx < PAD + LIST_W and my >= LIST_Y and my < vy) {
        const r:usize = @intFromFloat(@floor((my - LIST_Y) / ROW));
        if (e.top + r < e.pieces().len) e.sel = e.top + r;
      } else if (mx < PAD + LIST_W and my >= vy and my < vy + m.f(Ch.count) * ROW and e.pieces().len > 0) {
        e.ch = @intFromFloat(@floor((my - vy) / ROW));
        e.drag = .value;
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
    // the selection kept in view
    if (e.sel < e.top) e.top = e.sel;
    if (e.sel >= e.top + LIST_ROWS) e.top = e.sel + 1 - LIST_ROWS;
  }

  fn draw(e:*Editor, d:*Draw, screen:[2]f32, handles:[]const ?[2]f32) Allocator.Error!void {
    const W = screen[0];
    d.clear();
    var y:f32 = PAD;
    for (HELP) |h| {
      _ = try d.text(PAD, y, TEXT, BARE, h);
      y += LINE_H;
    }
    var pb:[160]u8 = undefined;
    _ = try d.text(W - PAD - 420, PAD, s.text_label, SEL, bufPrint(&pb, "{s}{s}", .{ e.path, if (e.dirty) " *" else "" }) catch e.path);
    var cb:[64]u8 = undefined;
    _ = try d.text(W - PAD - 420, PAD + LINE_H + 4, TEXT, PLAIN, bufPrint(&cb, "cells {d:.4} m   {d} forms", .{ e.doc.cell, e.pieces().len }) catch "?");
    if (e.note_len > 0) _ = try d.text(W - PAD - 420, PAD + 2 * (LINE_H + 4), TEXT, PLAIN, e.note[0..e.note_len]);

    // the forms
    const rows = listRows(e.pieces().len);
    try d.membrane(PAD, LIST_Y - 6, LIST_W, m.f(rows) * ROW + 12, PANEL, 0.3);
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
      try d.membrane(PAD, vy - 6, LIST_W, m.f(Ch.count) * ROW + 12, PANEL, 0.6);
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
      try d.pod(at[0], at[1], if (i == e.sel) SEL_HANDLE_R else HANDLE_R, col, 1, 0);
    };
  }
};

/// how many form rows show (at least one, at most `LIST_ROWS`)
fn listRows(n:usize) usize { return m.clamp(n, 1, LIST_ROWS); }
/// where the values start, under `rows` form rows
fn valuesY(rows:usize) f32 { return LIST_Y + m.f(rows) * ROW + 12 + GAP; }

fn overUi(rows:usize, x:f32, y:f32) bool {
  return x < PAD + LIST_W and y >= LIST_Y - 6 and y < valuesY(rows) + m.f(Ch.count) * ROW + 6;
}

/// `p` (world) on screen, or null behind the eye
fn onScreen(vp:m.M4, p:V3, screen:[2]f32) ?[2]f32 {
  const c = m.mulV(vp, .{ p[0], p[1], p[2], 1 });
  if (c[3] <= 1e-4) return null;
  return .{ (c[0] / c[3] * 0.5 + 0.5) * screen[0], (c[1] / c[3] * 0.5 + 0.5) * screen[1] };
}

pub fn main(init:std.process.Init) !void {
  const gpa = init.gpa;
  const io = init.io;
  const arena = init.arena.allocator();
  const args = try init.minimal.args.toSlice(arena);

  var name:[]const u8 = "sculpt";
  var shot = false;
  for (args[1..]) |a| {
    if (startsWith(u8, a, "--mesh=")) name = a["--mesh=".len..];
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
  var e:Editor = .{ .gpa = gpa, .io = io, .path = path, .doc = doc };
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
  // the wolf, for its size beside the sculpt, built once at every level
  // of detail; the sculpt goes after it, meshed again as it changes
  var b:meshgen.Builder = .{ .gpa = gpa };
  defer b.deinit();
  var ranges:[meshlib.SLOTS][2]u32 = @splat(.{ 0, 0 });
  for (0..meshgen.LODS) |l| for (WOLF) |id| try meshlib.buildOne(&b, id, @intCast(l), &ranges);
  b.lod = 0;
  const wolf_end = b.mark();
  _ = try loadFrame(&screen_l, r, &input, &last, .forms, .{ .done = 1, .total = whole });

  var game = try Game.init(gpa, play.DEFAULT_SEED);
  defer game.deinit();
  game.world.io = io;
  game.opts = opts;
  game.cam.dist = CAM_DIST;
  game.cam.pitch = CAM_PITCH;
  while (game.world.unmeshed() > 0) {
    if (!try loadFrame(&screen_l, r, &input, &last, .ground, .{ .done = whole - game.world.unmeshed(), .total = whole })) return;
    try renderer.syncWorld(r, &game.world, m.maxInt(u32), renderer.MESH_MS * 8);
  }
  const origin = game.player.pos + BESIDE;

  var ui:Draw = .{ .gpa = gpa };
  defer ui.deinit();
  var handles:std.ArrayList(?[2]f32) = .empty;
  defer handles.deinit(gpa);
  var keep:[meshlib.SLOTS]bool = @splat(false);
  for (WOLF) |id| for (0..meshgen.LODS) |l| {
    keep[meshlib.slot(id, @intCast(l))] = true;
  };

  var frames:u32 = 0;
  while (!window.shouldClose()) {
    glfw.pollEvents();
    input.update();
    frames += 1;
    const now = glfw.getTime();
    const dt:f32 = @floatCast(@min(now - last, MAX_DT));
    last = now;
    const screen = r.extent();

    // handles as last frame's camera saw them
    const vp = game.cam.viewProj();
    handles.clearRetainingCapacity();
    for (e.pieces()) |p| try handles.append(gpa, onScreen(vp, origin + p.v.pos, screen));
    try e.handle(&input, handles.items);
    e.sel = @min(e.sel, e.pieces().len -| 1);

    // the surface meshed again once it changed (while dragging, not every frame)
    e.since += dt;
    // (coarser while dragging, at full detail once let go)
    if (e.drag == .none and e.coarse) e.stale = true;
    if (e.stale and (e.drag == .none or e.since >= REMESH)) {
      const coarse = e.drag != .none;
      b.v.shrinkRetainingCapacity(wolf_end);
      b.skin.shrinkRetainingCapacity(@min(b.skin.items.len, wolf_end));
      b.grow.shrinkRetainingCapacity(@min(b.grow.items.len, wolf_end));
      try e.doc.mesh(gpa, io, coarse, &b);
      const run:[2]u32 = .{ @intCast(wolf_end), @intCast(b.mark() - wolf_end) };
      for (0..meshgen.LODS) |l| ranges[meshlib.slot(SLOT_ID, @intCast(l))] = run;
      try renderer.setParts(r, &b, ranges, wolf_end);
      e.stale = false;
      e.coarse = coarse;
      e.since = 0;
    }

    // the camera orbits and zooms as in play; nothing else of play runs
    // but the world's tick
    game.ui_time += dt;
    game.time += dt;
    game.cam.aspect = screen[0] / @max(screen[1], 1);
    game.cam.tick(dt);
    const over_ui = overUi(listRows(e.pieces().len), input.mouse[0], input.mouse[1]);
    if (ctl.down(&input, .orbit) and !game.cam.inEyes()) game.cam.orbit(input.mouse_delta);
    if (input.scroll != 0 and !over_ui) game.cam.zoom(input.scroll, game.player.eyes());
    game.player.animate(&game.world, dt);
    game.cam.see(game.player.eyes());
    game.cam.target = origin + v3(0, LOOK_UP, 0);
    try game.simulate(dt);
    try renderer.syncWorld(r, &game.world, 6, renderer.MESH_MS);

    // the scene as the game sees it, but only the wolf and the sculpt
    var scene = try ps.view.scene(&game, screen);
    for (&scene.parts, keep) |*p, k| if (!k) {
      p.* = &.{};
    };
    const inst = [1]ps.vertex.PartInstance{ps.parts.instance(m.translate(origin), .{})};
    scene.parts[meshlib.slot(SLOT_ID, 0)] = &inst;
    // handles drawn where the forms are now (one may have gone or come)
    handles.clearRetainingCapacity();
    for (e.pieces()) |p| try handles.append(gpa, onScreen(game.cam.viewProj(), origin + p.v.pos, screen));
    try e.draw(&ui, screen, handles.items);
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
