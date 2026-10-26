//! a rudimentary animation editor: keys a clip (engine anim/clip.zig) for
//! the wolf's skeleton, or for one plant or structure alone, shown live on
//! the game's own renderer, and keeps it as text in `src/anim/<name>.anim`.
//! The game does not play clips back yet. From the repo root:
//!   zig build animedit -- --wolf | --plant=<species> | --structure=<kind> [--clip=<name>]
//! (`--at=<s>` starts the playhead there; `--shot` saves one frame to
//! `shots/animedit.png` and closes, for checking it headless.)
//! Every f32 of the wolf's `Pose` (or a specimen's `Look`) is a channel;
//! dragging a channel's value keys it at the playhead.
//!
//! decision: a developer's tool, not the game: its few words and keys are
//! written here, not in the strings or controls files (the camera's orbit
//! still follows the game's binding).
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;
const Writer = Io.Writer;
const eql = std.mem.eql;
const startsWith = std.mem.startsWith;
const stringToEnum = std.meta.stringToEnum;
const bufPrint = std.fmt.bufPrint;
const log = std.log;
const engine = @import("engine");
const glfw = engine.glfw;
const m = engine.core.math;
const clip = engine.anim.clip;
const Input = engine.platform.input.Input;
const Key = engine.platform.input.Key;
const Draw = engine.ui.draw.Draw;
const Color = engine.ui.draw.Color;
const ps = @import("parasymi");
const play = ps.play;
const Game = play.Game;
const skel = ps.skeleton;
const specimen = ps.specimen;
const renderer = ps.renderer;
const Renderer = renderer.Renderer;
const loading = ps.loading;
const ctl = ps.controls;
const s = ps.style;

const PoseCh = clip.Channels(skel.Pose);
const LookCh = clip.Channels(specimen.Look);

/// clips are kept here (from the repo root)
const DIR = "src/anim";
/// `--shot` writes here, this many frames in (the world settled)
const SHOT = "shots/animedit.png";
const SHOT_FRAMES = 30;
const EXT = ".anim";
/// a stalled frame counts as at most this long (s)
const MAX_DT:f64 = 0.1;
/// the playhead snaps to frames of this rate
const FPS:f32 = 30;
/// a new clip runs this long (s); the length changes by `LENGTH_STEP`
/// down to `LENGTH_MIN`
const LENGTH:f32 = 2;
const LENGTH_STEP:f32 = 0.25;
const LENGTH_MIN:f32 = 0.25;
/// a drag changes a value this much per pixel (shift: `FINE` of it)
const DRAG_RATE:f32 = 0.005;
const FINE:f32 = 0.2;
/// the camera looks at this height over the wolf's feet, from this far
/// and this high (rad) to start
const LOOK_UP:f32 = 0.6;
const CAM_DIST:f32 = 3.2;
const CAM_PITCH:f32 = m.rad(18);
/// a plant or structure is seen from this far plus `CAM_PER` a tile of its size
const CAM_THING:f32 = 1.6;
const CAM_PER:f32 = 2.4;
/// layout (px): the channel list, the timeline along the bottom
const PAD:f32 = 16;
const TEXT:f32 = s.text_small;
const ROW:f32 = 18;
const LIST_Y:f32 = 100;
const LIST_W:f32 = 380;
const VALUE_X:f32 = 270;
const LINE_H:f32 = 20;
const TL_H:f32 = 44;
const TL_BOTTOM:f32 = 40;
const KEY_R:f32 = 5;
const SEL_KEY_R:f32 = 8;
/// colours: selected, keyed, unkeyed, the playhead, keys, panels
const SEL:Color = s.gold;
const KEYED:Color = s.white;
const BARE:Color = s.dim;
const HEAD:Color = s.growth;
const KEY_DIM:Color = .{190, 210, 190, 220};
const PANEL:Color = s.membrane;

const HELP = [_][]const u8{
  "space play   left/right frame (shift: key to key)   home start   pgup/pgdn length",
  "up/down channel   drag value: key it (shift fine)   k key   a key all   x unkey   r rest",
  "ctrl+s save   middle drag orbit   wheel zoom (over the list: scroll)",
};

const Subject = union(enum) {
  wolf,
  thing:specimen.Subject,

  /// its word in the clip (`wolf`, `plant:<species>`, `structure:<kind>`)
  fn word(sj:Subject, buf:[]u8) []const u8 {
    return switch (sj) {
      .wolf => "wolf",
      .thing => |t| switch (t) {
        .plant => |sp| bufPrint(buf, "plant:{t}", .{sp}) catch unreachable,
        .structure => |k| bufPrint(buf, "structure:{t}", .{k}) catch unreachable,
      },
    };
  }
  /// the clip's name unless `--clip=` says
  fn name(sj:Subject) []const u8 {
    return switch (sj) {
      .wolf => "wolf",
      .thing => |t| switch (t) {
        .plant => |sp| @tagName(sp),
        .structure => |k| @tagName(k),
      },
    };
  }
};

const Drag = enum { none, timeline, value };

const Editor = struct {
  gpa:Allocator,
  io:Io,
  subject:Subject,
  path:[]const u8,
  clip:clip.Clip,
  /// what is shown: the clip sampled at the playhead over the values set
  /// by hand where a channel has no keys
  pose:skel.Pose = .{},
  look:specimen.Look = .{},
  t:f32 = 0,
  playing:bool = false,
  /// the channels shown (indices into `PoseCh` or `LookCh`), the one
  /// selected (into `shown`) and the first row in view
  shown:[]const usize,
  sel:usize = 0,
  top:usize = 0,
  drag:Drag = .none,
  dirty:bool = false,
  note:[96]u8 = undefined,
  note_len:usize = 0,

  fn wolf(e:*const Editor) bool { return e.subject == .wolf; }

  fn chName(e:*const Editor, i:usize) []const u8 {
    return if (e.wolf()) PoseCh.names[e.shown[i]] else LookCh.names[e.shown[i]];
  }
  fn value(e:*const Editor, i:usize) f32 {
    return if (e.wolf()) PoseCh.get(&e.pose, e.shown[i]) else LookCh.get(&e.look, e.shown[i]);
  }
  fn setValue(e:*Editor, i:usize, v:f32) void {
    if (e.wolf()) PoseCh.set(&e.pose, e.shown[i], v) else LookCh.set(&e.look, e.shown[i], m.clamp01(v));
  }
  /// its value at rest (the default pose or look)
  fn rest(e:*const Editor, i:usize) f32 {
    return if (e.wolf()) PoseCh.get(&skel.Pose{}, e.shown[i]) else LookCh.get(&specimen.Look{}, e.shown[i]);
  }

  /// every keyed channel set from the clip at the playhead
  fn sample(e:*Editor) void {
    for (0..e.shown.len) |i| if (e.clip.sample(e.chName(i), e.t)) |v| e.setValue(i, v);
  }

  fn key(e:*Editor, i:usize) Allocator.Error!void {
    try e.clip.put(e.chName(i), e.t, e.value(i));
    e.dirty = true;
  }

  fn say(e:*Editor, comptime fmt:[]const u8, args:anytype) void {
    e.note_len = if (bufPrint(&e.note, fmt, args)) |w| w.len else |_| e.note.len;
  }

  fn save(e:*Editor) void {
    const io = e.io;
    var out:Writer.Allocating = .init(e.gpa);
    defer out.deinit();
    e.clip.write(&out.writer) catch return e.say("save failed: out of memory", .{});
    Dir.cwd().createDirPath(io, DIR) catch |er| return e.say("save failed: {t}", .{er});
    Dir.cwd().writeFile(io, .{ .sub_path = e.path, .data = out.written() }) catch |er| return e.say("save failed: {t}", .{er});
    e.dirty = false;
    e.say("saved {s}", .{e.path});
  }

  fn snap(t:f32) f32 { return @round(t * FPS) / FPS; }

  /// one frame's keys and mouse (`over` the list or the timeline)
  fn handle(e:*Editor, in:*const Input, screen:[2]f32, dt:f32) Allocator.Error!void {
    const shift = in.down(.{ .key = .left_shift }) or in.down(.{ .key = .right_shift });
    const ctrl = in.down(.{ .key = .left_control }) or in.down(.{ .key = .right_control });
    const hit = struct {
      fn f(i:*const Input, k:Key) bool { return i.pressed(.{ .key = k }); }
    }.f;

    if (hit(in, .space)) e.playing = !e.playing;
    if (e.playing) {
      e.t += dt;
      if (e.t >= e.clip.length) e.t = @mod(e.t, e.clip.length);
    }
    for ([_]Key{ .left, .right }, [_]f32{ -1, 1 }) |k, dir| if (hit(in, k)) {
      e.playing = false;
      e.t = if (shift) e.clip.nextKey(e.t, dir) orelse e.t else m.clamp(snap(e.t) + dir / FPS, 0, e.clip.length);
    };
    if (hit(in, .home)) e.t = 0;
    if (hit(in, .page_up)) e.clip.length += LENGTH_STEP;
    if (hit(in, .page_down)) e.clip.length = @max(LENGTH_MIN, e.clip.length - LENGTH_STEP);
    if (hit(in, .page_up) or hit(in, .page_down)) {
      e.t = @min(e.t, e.clip.length);
      e.dirty = true;
    }
    if (hit(in, .up) and e.sel > 0) e.sel -= 1;
    if (hit(in, .down) and e.sel + 1 < e.shown.len) e.sel += 1;
    if (hit(in, .k)) try e.key(e.sel);
    if (hit(in, .a)) for (0..e.shown.len) |i| try e.key(i);
    if (hit(in, .x) or hit(in, .delete)) {
      if (e.clip.remove(e.chName(e.sel), e.t)) e.dirty = true;
    }
    if (hit(in, .r)) {
      e.setValue(e.sel, e.rest(e.sel));
      if (e.clip.track(e.chName(e.sel)) != null) try e.key(e.sel);
    }
    if (ctrl and hit(in, .s)) e.save();

    // the mouse: a press on the timeline scrubs, on a row selects it and
    // drags its value
    const rows = e.fits(screen);
    const mx = in.mouse[0];
    const my = in.mouse[1];
    if (in.pressed(.{ .button = .left })) {
      if (inTimeline(screen, mx, my)) {
        e.drag = .timeline;
        e.playing = false;
      } else if (mx < PAD + LIST_W and my >= LIST_Y) {
        const r:usize = @intFromFloat(@floor((my - LIST_Y) / ROW));
        if (r < rows and e.top + r < e.shown.len) {
          e.sel = e.top + r;
          e.drag = .value;
        }
      }
    }
    if (!in.down(.{ .button = .left })) e.drag = .none;
    switch (e.drag) {
      .none => {},
      .timeline => e.t = snap(m.clamp01((mx - PAD) / (screen[0] - 2 * PAD)) * e.clip.length),
      .value => if (in.mouse_delta[0] != 0) {
        const rate = DRAG_RATE * (if (shift) FINE else 1);
        e.setValue(e.sel, e.value(e.sel) + in.mouse_delta[0] * rate);
        try e.key(e.sel);
      },
    }
    if (overList(screen, mx, my) and in.scroll != 0) {
      const most = e.shown.len -| rows;
      const step:i32 = @intFromFloat(-in.scroll * 3);
      e.top = @intCast(m.clamp(@as(i32, @intCast(e.top)) + step, 0, @as(i32, @intCast(most))));
    }
    // the selection kept in view
    if (e.sel < e.top) e.top = e.sel;
    if (e.sel >= e.top + rows) e.top = e.sel + 1 - rows;
  }

  /// how many rows fit
  fn fits(_:*const Editor, screen:[2]f32) usize {
    const h = screen[1] - LIST_Y - TL_BOTTOM - TL_H - 3 * PAD;
    return @intFromFloat(@max(1, @floor(h / ROW)));
  }

  fn draw(e:*const Editor, d:*Draw, screen:[2]f32) Allocator.Error!void {
    const W = screen[0];
    const H = screen[1];
    d.clear();
    var y:f32 = PAD;
    for (HELP) |h| {
      _ = try d.text(PAD, y, TEXT, BARE, h);
      y += LINE_H;
    }
    var pb:[160]u8 = undefined;
    _ = try d.text(W - PAD - 420, PAD, s.text_label, SEL, bufPrint(&pb, "{s}{s}", .{ e.path, if (e.dirty) " *" else "" }) catch e.path);
    if (e.note_len > 0) _ = try d.text(W - PAD - 420, PAD + LINE_H + 4, TEXT, KEYED, e.note[0..e.note_len]);

    // the channel list
    const rows = e.fits(screen);
    try d.membrane(PAD, LIST_Y - 6, LIST_W, m.f(@min(rows, e.shown.len)) * ROW + 12, PANEL, 0.3);
    for (0..rows) |r| {
      const i = e.top + r;
      if (i >= e.shown.len) break;
      const ry = LIST_Y + m.f(r) * ROW;
      const keyed = e.clip.track(e.chName(i)) != null and e.clip.track(e.chName(i)).?.keys.items.len > 0;
      const col = if (i == e.sel) SEL else if (keyed) KEYED else BARE;
      if (i == e.sel) try d.glow(PAD + 8, ry + 7, 10, s.menu_hover);
      _ = try d.text(PAD + 18, ry, TEXT, col, e.chName(i));
      var vb:[24]u8 = undefined;
      const vs = bufPrint(&vb, "{d:.3}", .{e.value(i)}) catch "?";
      _ = try d.text(PAD + VALUE_X, ry, TEXT, col, vs);
      if (keyed and e.clip.track(e.chName(i)).?.at(e.t) != null) try d.pod(PAD + LIST_W - 14, ry + 7, 4, col, 1, 0);
    }
    if (e.top > 0) _ = try d.text(PAD + LIST_W - 30, LIST_Y - 20, TEXT, BARE, "...");
    if (e.top + rows < e.shown.len) _ = try d.text(PAD + LIST_W - 30, LIST_Y + m.f(rows) * ROW, TEXT, BARE, "...");

    // the timeline: every key dim, the selected channel's bright, the playhead
    const tx = PAD;
    const tw = W - 2 * PAD;
    const ty = H - TL_BOTTOM - TL_H;
    try d.membrane(tx, ty, tw, TL_H, PANEL, 0.7);
    const at = struct {
      fn f(x0:f32, w:f32, len:f32, t:f32) f32 { return x0 + w * t / len; }
    }.f;
    var sec:f32 = 0;
    while (sec <= e.clip.length + clip.SAME) : (sec += 0.5) {
      var sb:[16]u8 = undefined;
      _ = try d.text(at(tx, tw, e.clip.length, sec) - 4, ty + TL_H + 6, TEXT, BARE, bufPrint(&sb, "{d}", .{sec}) catch "?");
    }
    for (e.clip.tracks.items) |tr| for (tr.keys.items) |k| {
      try d.pod(at(tx, tw, e.clip.length, k.t), ty + TL_H / 2, KEY_R, KEY_DIM, 0, 0);
    };
    if (e.clip.track(e.chName(e.sel))) |tr| for (tr.keys.items) |k| {
      try d.pod(at(tx, tw, e.clip.length, k.t), ty + TL_H / 2, SEL_KEY_R, SEL, 1, 0);
    };
    const hx = at(tx, tw, e.clip.length, e.t);
    try d.limb(.{ hx, ty - 6 }, .{ hx, ty + TL_H + 2 }, 3, 2, HEAD, 0);
    var hb:[96]u8 = undefined;
    _ = try d.text(tx, ty - 26, TEXT, HEAD, bufPrint(&hb, "{s} {d:.2} / {d:.2} s   frame {d}   channel {s}", .{
      if (e.playing) "playing" else "paused", e.t, e.clip.length, @as(u32, @intFromFloat(@round(e.t * FPS))), e.chName(e.sel),
    }) catch "?");
  }
};

fn inTimeline(screen:[2]f32, x:f32, y:f32) bool {
  const ty = screen[1] - TL_BOTTOM - TL_H;
  return y >= ty - 8 and y <= ty + TL_H + 8 and x >= PAD - 8 and x <= screen[0] - PAD + 8;
}
fn overList(screen:[2]f32, x:f32, y:f32) bool {
  return x < PAD + LIST_W and y >= LIST_Y and y < screen[1] - TL_BOTTOM - TL_H - PAD;
}

const all_pose = blk: {
  var a:[PoseCh.count]usize = undefined;
  for (&a, 0..) |*o, i| o.* = i;
  break :blk a;
};
const all_look = blk: {
  var a:[LookCh.count]usize = undefined;
  for (&a, 0..) |*o, i| o.* = i;
  break :blk a;
};
/// a structure shows only its growth
const growth_only = [_]usize{LookCh.find("growth").?};

pub fn main(init:std.process.Init) !void {
  const gpa = init.gpa;
  const io = init.io;
  const arena = init.arena.allocator();
  const args = try init.minimal.args.toSlice(arena);

  var subject:?Subject = null;
  var name:?[]const u8 = null;
  var start:f32 = 0;
  var shot = false;
  for (args[1..]) |a| {
    if (eql(u8, a, "--wolf")) subject = .wolf;
    if (startsWith(u8, a, "--plant=")) subject = .{ .thing = .{ .plant = stringToEnum(ps.species.Id, a["--plant=".len..]) orelse return error.BadPlant } };
    if (startsWith(u8, a, "--structure=")) subject = .{ .thing = .{ .structure = stringToEnum(ps.structures.Kind, a["--structure=".len..]) orelse return error.BadStructure } };
    if (startsWith(u8, a, "--clip=")) name = a["--clip=".len..];
    if (startsWith(u8, a, "--at=")) start = try std.fmt.parseFloat(f32, a["--at=".len..]);
    if (eql(u8, a, "--shot")) shot = true;
  }
  const sj = subject orelse {
    log.err("usage: zig build animedit -- --wolf | --plant=<species> | --structure=<kind> [--clip=<name>]", .{});
    return error.NoSubject;
  };
  const path = try std.fmt.allocPrint(arena, DIR ++ "/{s}" ++ EXT, .{name orelse sj.name()});

  // the clip: as kept, else a fresh one
  var wb:[64]u8 = undefined;
  const word = sj.word(&wb);
  const c = load: {
    const text = Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 22)) catch |er| switch (er) {
      error.FileNotFound => {
        var fresh = try clip.Clip.init(gpa, word);
        fresh.length = LENGTH;
        break :load fresh;
      },
      else => return er,
    };
    defer gpa.free(text);
    break :load try clip.Clip.parse(gpa, text);
  };
  var e:Editor = .{
    .gpa = gpa,
    .io = io,
    .subject = sj,
    .path = path,
    .clip = c,
    .shown = switch (sj) {
      .wolf => &all_pose,
      .thing => |t| if (t == .plant) &all_look else &growth_only,
    },
  };
  defer e.clip.deinit();
  e.t = m.clamp(start, 0, e.clip.length);
  if (!eql(u8, e.clip.subject, word)) {
    log.err("{s} animates {s}, not {s}", .{ path, e.clip.subject, word });
    return error.WrongSubject;
  }

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
  const window = try glfw.createWindow(play.WINDOW[0], play.WINDOW[1], "Parasymi animation editor", null, null);
  defer window.destroy();
  var input:Input = .{ .win = window };
  input.attach();

  var lone:?specimen.Specimen = switch (sj) {
    .wolf => null,
    .thing => |t| .{ .what = t, .state = .{ .look = .{} } },
  };
  const r = try Renderer.init(gpa, window, opts.vsync, opts.aa, .{ .only = if (lone) |*l| try l.only(arena) else null });
  defer r.deinit();

  // every mesh grows, then the world wakes and its ground is meshed,
  // behind the game's loading screen
  var screen_l = loading.Loading.init(gpa);
  defer screen_l.deinit();
  var last = glfw.getTime();
  const forms = renderer.meshProgress(r)[1];
  const whole = forms + 1 + play.STREAM_CHUNKS;
  while (!try renderer.meshesReady(r)) {
    if (!try loadFrame(&screen_l, r, &input, &last, .forms, .{ .done = renderer.meshProgress(r)[0], .total = whole })) return;
  }
  var game = try Game.init(gpa, play.DEFAULT_SEED);
  defer game.deinit();
  game.world.io = io;
  game.opts = opts;
  if (lone) |l| {
    game.specimen = l;
    try game.specimen.?.sow(&game);
  }
  game.cam.dist = switch (sj) {
    .wolf => CAM_DIST,
    .thing => |t| CAM_THING + CAM_PER * m.f(switch (t) {
      .plant => |sp| ps.species.get(sp).size,
      .structure => |k| ps.structures.defs.get(k).size,
    }),
  };
  game.cam.pitch = CAM_PITCH;
  while (game.world.unmeshed() > 0) {
    if (!try loadFrame(&screen_l, r, &input, &last, .ground, .{ .done = whole - game.world.unmeshed(), .total = whole })) return;
    try renderer.syncWorld(r, &game.world, m.maxInt(u32), renderer.MESH_MS * 8);
  }

  var ui:Draw = .{ .gpa = gpa };
  defer ui.deinit();

  var frames:u32 = 0;
  while (!window.shouldClose()) {
    glfw.pollEvents();
    input.update();
    frames += 1;
    const now = glfw.getTime();
    const dt:f32 = @floatCast(@min(now - last, MAX_DT));
    last = now;
    const screen = r.extent();

    try e.handle(&input, screen, dt);
    e.sample();
    switch (sj) {
      .wolf => game.player.posed = e.pose,
      .thing => game.specimen.?.state = .{ .look = e.look },
    }

    // the camera orbits and zooms as in play; nothing else of play runs
    // but the world's tick (which holds a specimen as it is set)
    game.ui_time += dt;
    game.time += dt;
    game.cam.aspect = screen[0] / @max(screen[1], 1);
    game.cam.tick(dt);
    const over_ui = overList(screen, input.mouse[0], input.mouse[1]) or inTimeline(screen, input.mouse[0], input.mouse[1]);
    if (ctl.down(&input, .orbit) and !game.cam.inEyes()) game.cam.orbit(input.mouse_delta);
    if (input.scroll != 0 and !over_ui) game.cam.zoom(input.scroll, game.player.eyes());
    game.player.animate(&game.world, dt);
    game.cam.see(game.player.eyes());
    game.cam.target = game.player.pos + m.v3(0, LOOK_UP, 0);
    try game.simulate(dt);
    try renderer.syncWorld(r, &game.world, 6, renderer.MESH_MS);

    var scene = try ps.view.scene(&game, screen);
    try e.draw(&ui, screen);
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
