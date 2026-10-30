//! the animation editor's state: the clip, the selected channel and key, saving.
const std = ps.std;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;
const Writer = Io.Writer;
const bufPrint = std.fmt.bufPrint;
const engine = ps.engine;
const m = engine.core.math;
const clip = engine.anim.clip;
const ps = @import("parasymi");
const gizmo = @import("../gizmo.zig");
const skel = ps.skeleton;
const specimen = ps.specimen;

const PoseCh = clip.Channels(skel.Pose);
const LookCh = clip.Channels(specimen.Look);
const animedit = @import("../animedit.zig");
const DIR = animedit.settings.DIR;
const Drag = animedit.rigging.Drag;
const FPS = animedit.settings.FPS;
const JOINT_PICK = animedit.settings.JOINT_PICK;
const Joint = animedit.rigging.Joint;
const LIST_W = animedit.settings.LIST_W;
const LIST_Y = animedit.settings.LIST_Y;
const PAD = animedit.settings.PAD;
const Rig = animedit.rigging.Rig;
const Subject = animedit.rigging.Subject;
const TL_BOTTOM = animedit.settings.TL_BOTTOM;
const TL_H = animedit.settings.TL_H;
const gizmoOf = animedit.rigging.gizmoOf;
const jointOf = animedit.rigging.jointOf;
const joints = animedit.rigging.joints;

pub const Editor = struct {
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
  /// the gizmo's handle held, and the one under the mouse
  part:?gizmo.Part = null,
  hot:?gizmo.Part = null,
  dirty:bool = false,
  /// the camera is asked onto the selected joint (or the subject)
  focus:bool = false,
  note:[96]u8 = undefined,
  note_len:usize = 0,

  /// the selected channel's joint and its gizmo (the wolf's alone)
  pub fn gizmoAt(e:*const Editor, rg:*const Rig) ?struct { j:Joint, g:gizmo.Gizmo } {
    if (!e.wolf()) return null;
    const j = joints[jointOf(e.shown[e.sel]) orelse return null];
    return .{ .j = j, .g = gizmoOf(j, &e.pose, &rg.bones, rg.heading) };
  }

  /// channel `ch` of the pose changed by `by` and keyed (the wolf shows
  /// every channel, so `ch` is its row too)
  pub fn nudge(e:*Editor, ch:usize, by:f32) Allocator.Error!void {
    e.setValue(ch, e.value(ch) + by);
    try e.key(ch);
  }

  /// a drag of the held handle from `from` to `to` (px), `k` of it
  pub fn dragGizmo(e:*Editor, j:Joint, g:gizmo.Gizmo, rg:*const Rig, from:[2]f32, to:[2]f32, k:f32) Allocator.Error!void {
    const part = e.part orelse return;
    switch (part) {
      // the hips moved across the view: back into wolf space
      .free => {
        const by = g.across(rg.view, from, to) * m.splat3(k);
        for (j.chans, g.axes) |c, a| try e.nudge(c.?, m.dot(by, a.?));
      },
      .x, .y, .z => {
        const i = @intFromEnum(part);
        const c = j.chans[i] orelse return;
        try e.nudge(c, g.along(rg.view, i, from, to) * k);
        e.sel = c;
      },
    }
  }

  /// the joint whose dot is under `mouse`; again on the selected one, the
  /// next under it
  pub fn pickJoint(e:*const Editor, rg:*const Rig, mouse:[2]f32) ?usize {
    const cur = jointOf(e.shown[e.sel]);
    var best:?usize = null;
    var near:f32 = JOINT_PICK;
    var after:?usize = null;
    var cur_under = false;
    for (joints, 0..) |j, i| {
      const at = rg.view.project(m.origin(rg.bones[@intFromEnum(j.bone)])) orelse continue;
      const d = m.len(m.v3(at[0] - mouse[0], at[1] - mouse[1], 0));
      if (d >= JOINT_PICK) continue;
      if (cur != null and i == cur.?) cur_under = true;
      if (cur != null and i > cur.? and after == null) after = i;
      if (d < near) {
        near = d;
        best = i;
      }
    }
    if (cur_under) {
      if (after) |a| return a;
      // round to the first under the mouse
      for (joints, 0..) |j, i| {
        const at = rg.view.project(m.origin(rg.bones[@intFromEnum(j.bone)])) orelse continue;
        if (m.len(m.v3(at[0] - mouse[0], at[1] - mouse[1], 0)) < JOINT_PICK) return i;
      }
    }
    return best;
  }

  pub fn wolf(e:*const Editor) bool { return e.subject == .wolf; }

  pub fn chName(e:*const Editor, i:usize) []const u8 {
    return if (e.wolf()) PoseCh.names[e.shown[i]] else LookCh.names[e.shown[i]];
  }
  pub fn value(e:*const Editor, i:usize) f32 {
    return if (e.wolf()) PoseCh.get(&e.pose, e.shown[i]) else LookCh.get(&e.look, e.shown[i]);
  }
  pub fn setValue(e:*Editor, i:usize, v:f32) void {
    if (e.wolf()) PoseCh.set(&e.pose, e.shown[i], v) else LookCh.set(&e.look, e.shown[i], m.clamp01(v));
  }
  /// its value at rest (the default pose or look)
  pub fn rest(e:*const Editor, i:usize) f32 {
    return if (e.wolf()) PoseCh.get(&skel.Pose{}, e.shown[i]) else LookCh.get(&specimen.Look{}, e.shown[i]);
  }

  /// every keyed channel set from the clip at the playhead
  pub fn sample(e:*Editor) void {
    for (0..e.shown.len) |i| if (e.clip.sample(e.chName(i), e.t)) |v| e.setValue(i, v);
  }

  pub fn key(e:*Editor, i:usize) Allocator.Error!void {
    try e.clip.put(e.chName(i), e.t, e.value(i));
    e.dirty = true;
  }

  pub fn say(e:*Editor, comptime fmt:[]const u8, args:anytype) void {
    e.note_len = if (bufPrint(&e.note, fmt, args)) |w| w.len else |_| e.note.len;
  }

  pub fn save(e:*Editor) void {
    const io = e.io;
    var out:Writer.Allocating = .init(e.gpa);
    defer out.deinit();
    e.clip.write(&out.writer) catch return e.say("save failed: out of memory", .{});
    Dir.cwd().createDirPath(io, DIR) catch |er| return e.say("save failed: {t}", .{er});
    Dir.cwd().writeFile(io, .{ .sub_path = e.path, .data = out.written() }) catch |er| return e.say("save failed: {t}", .{er});
    e.dirty = false;
    e.say("saved {s}", .{e.path});
  }

  pub fn snap(t:f32) f32 { return @round(t * FPS) / FPS; }

  pub const handle = animedit.editing.handle;
  pub const fits = animedit.panel.fits;
  pub const draw = animedit.panel.draw;
};

pub fn inTimeline(screen:[2]f32, x:f32, y:f32) bool {
  const ty = screen[1] - TL_BOTTOM - TL_H;
  return y >= ty - 8 and y <= ty + TL_H + 8 and x >= PAD - 8 and x <= screen[0] - PAD + 8;
}
pub fn overList(screen:[2]f32, x:f32, y:f32) bool {
  return x < PAD + LIST_W and y >= LIST_Y and y < screen[1] - TL_BOTTOM - TL_H - PAD;
}

pub const all_pose = blk: {
  var a:[PoseCh.count]usize = undefined;
  for (&a, 0..) |*o, i| o.* = i;
  break :blk a;
};
pub const all_look = blk: {
  var a:[LookCh.count]usize = undefined;
  for (&a, 0..) |*o, i| o.* = i;
  break :blk a;
};
/// a structure shows only its growth
pub const growth_only = [_]usize{LookCh.find("growth").?};
