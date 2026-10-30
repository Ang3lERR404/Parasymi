//! the animation editor's input: the timeline, the channel list and joint drags.
const std = ps.std;
const Allocator = std.mem.Allocator;
const engine = ps.engine;
const m = engine.core.math;
const clip = engine.anim.clip;
const Input = engine.platform.input.Input;
const Key = engine.platform.input.Key;
const ps = @import("parasymi");
const skel = ps.skeleton;
const specimen = ps.specimen;

const PoseCh = clip.Channels(skel.Pose);
const LookCh = clip.Channels(specimen.Look);
const animedit = @import("../animedit.zig");
const DRAG_RATE = animedit.settings.DRAG_RATE;
const Editor = animedit.editor.Editor;
const snap = Editor.snap;
const FINE = animedit.settings.FINE;
const FPS = animedit.settings.FPS;
const LENGTH_MIN = animedit.settings.LENGTH_MIN;
const LENGTH_STEP = animedit.settings.LENGTH_STEP;
const LIST_W = animedit.settings.LIST_W;
const LIST_Y = animedit.settings.LIST_Y;
const PAD = animedit.settings.PAD;
const ROW = animedit.settings.ROW;
const Rig = animedit.rigging.Rig;
const inTimeline = animedit.editor.inTimeline;
const joints = animedit.rigging.joints;
const overList = animedit.editor.overList;

/// one frame's keys and mouse (`over` the list or the timeline), the
/// wolf's joints as `rg` sees them
pub fn handle(e:*Editor, in:*const Input, screen:[2]f32, dt:f32, rg:*const Rig) Allocator.Error!void {
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
  if (hit(in, .period)) e.focus = true;

  // the mouse: a press on the timeline scrubs, on a row selects it and
  // drags its value
  const rows = e.fits(screen);
  const mx = in.mouse[0];
  const my = in.mouse[1];
  const gz = e.gizmoAt(rg);
  const ui = overList(screen, mx, my) or inTimeline(screen, mx, my);
  e.hot = if (e.drag == .gizmo) e.part else if (gz != null and !ui) gz.?.g.pick(rg.view, in.mouse) else null;
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
    } else if (e.hot) |part| {
      e.part = part;
      e.drag = .gizmo;
      e.playing = false;
    } else if (e.wolf()) {
      if (e.pickJoint(rg, in.mouse)) |j| e.sel = joints[j].chans[0].?;
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
    .gizmo => if (gz) |z| if (in.mouse_delta[0] != 0 or in.mouse_delta[1] != 0) {
      const from = [2]f32{ mx - in.mouse_delta[0], my - in.mouse_delta[1] };
      try e.dragGizmo(z.j, z.g, rg, from, in.mouse, if (shift) FINE else 1);
    },
  }
  if (e.drag != .gizmo) e.part = null;
  if (overList(screen, mx, my) and in.scroll != 0) {
    const most = e.shown.len -| rows;
    const step:i32 = @intFromFloat(-in.scroll * 3);
    e.top = @intCast(m.clamp(@as(i32, @intCast(e.top)) + step, 0, @as(i32, @intCast(most))));
  }
  // the selection kept in view
  if (e.sel < e.top) e.top = e.sel;
  if (e.sel >= e.top + rows) e.top = e.sel + 1 - rows;
}
