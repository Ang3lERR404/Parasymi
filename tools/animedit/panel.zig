//! the animation editor's panel: channels, values, the timeline and help.
const std = ps.std;
const Allocator = std.mem.Allocator;
const bufPrint = std.fmt.bufPrint;
const engine = ps.engine;
const m = engine.core.math;
const clip = engine.anim.clip;
const Draw = engine.ui.draw.Draw;
const ps = @import("parasymi");
const skel = ps.skeleton;
const specimen = ps.specimen;
const s = ps.style;

const PoseCh = clip.Channels(skel.Pose);
const LookCh = clip.Channels(specimen.Look);
const animedit = @import("../animedit.zig");
const BARE = animedit.settings.BARE;
const Editor = animedit.editor.Editor;
const FPS = animedit.settings.FPS;
const HEAD = animedit.settings.HEAD;
const HELP = animedit.settings.HELP;
const JOINT = animedit.settings.JOINT;
const JOINT_LIT = animedit.settings.JOINT_LIT;
const JOINT_R = animedit.settings.JOINT_R;
const KEYED = animedit.settings.KEYED;
const KEY_DIM = animedit.settings.KEY_DIM;
const KEY_R = animedit.settings.KEY_R;
const LINE_H = animedit.settings.LINE_H;
const LIST_W = animedit.settings.LIST_W;
const LIST_Y = animedit.settings.LIST_Y;
const PAD = animedit.settings.PAD;
const PANEL = animedit.settings.PANEL;
const ROW = animedit.settings.ROW;
const Rig = animedit.rigging.Rig;
const SEL = animedit.settings.SEL;
const SEL_JOINT_R = animedit.settings.SEL_JOINT_R;
const SEL_KEY_R = animedit.settings.SEL_KEY_R;
const TEXT = animedit.settings.TEXT;
const TL_BOTTOM = animedit.settings.TL_BOTTOM;
const TL_H = animedit.settings.TL_H;
const VALUE_X = animedit.settings.VALUE_X;
const jointOf = animedit.rigging.jointOf;
const joints = animedit.rigging.joints;

/// how many rows fit
pub fn fits(_:*const Editor, screen:[2]f32) usize {
  const h = screen[1] - LIST_Y - TL_BOTTOM - TL_H - 3 * PAD;
  return @intFromFloat(@max(1, @floor(h / ROW)));
}

pub fn draw(e:*const Editor, d:*Draw, screen:[2]f32, rg:*const Rig) Allocator.Error!void {
  const W = screen[0];
  const H = screen[1];
  // the wolf's joints, the selected one's gizmo over them
  if (e.wolf()) {
    const cur = jointOf(e.shown[e.sel]);
    for (joints, 0..) |j, i| if (cur == null or i != cur.?) {
      if (rg.view.project(m.origin(rg.bones[@intFromEnum(j.bone)]))) |at| try d.pod(at[0], at[1], JOINT_R, JOINT, JOINT_LIT, m.f(i));
    };
    if (e.gizmoAt(rg)) |z| {
      if (rg.view.project(z.g.at)) |at| try d.glow(at[0], at[1], SEL_JOINT_R * 2, s.menu_hover);
      try z.g.draw(d, rg.view, e.hot);
    }
  }
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
  try d.trellis(PAD, LIST_Y - 6, LIST_W, m.f(@min(rows, e.shown.len)) * ROW + 12, PANEL, 0.3);
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
  try d.trellis(tx, ty, tw, TL_H, PANEL, 0.7);
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
