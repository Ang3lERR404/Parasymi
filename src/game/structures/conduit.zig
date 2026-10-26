//! ROOT CONDUIT: the first logistics. One item at a time it pulls from
//! whatever is behind it (a structure's output, or a mature plant, which
//! harvests it) and passes it forward to the next conduit or structure.
//! It also sends a root out to any plant beside it (left, right or behind)
//! and, once that root has reached it, harvests that plant too.
//! Its root digs up out of the soil at the edge it is fed from, arches
//! over its tile and digs back in at its front, so chains join under the
//! ground however they turn; what it carries runs through its core.
const m = @import("engine").core.math;
const std = @import("std");
const Allocator = std.mem.Allocator;
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const icon_kit = @import("../icon.zig");
const txt = @import("../text.zig");
const prog = @import("../progression.zig");
const color = @import("engine").core.color;
const style = @import("../style.zig");
const Parts = @import("../parts.zig").Parts;
const Draw = @import("engine").ui.draw.Draw;
const Color = @import("engine").ui.draw.Color;
const meshlib = @import("../../gfx/meshlib.zig");

/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .conduit_left, .conduit_right, .conduit_tap };

/// decision: a conduit grows (along its arch's growth spline, up out of
/// the soil and back in) but does not sway: its arches join the next conduit's under the ground, and a bend
/// per conduit would pull them apart. It draws its own arches (`emit`),
/// one per edge it is fed from; `mesh` (the straight one) is its preview.
pub const def:st.Def = .{ .item = .conduit, .size = 1, .mesh = .conduit, .grow = 1.5, .carrier = true, .bare = true, .tall = 0.25 };

/// its arch by the edge it comes in at, counted from the way it faces
/// (1 the side +Z of it in its own frame, 2 behind, 3 the other side)
const ARCH = [4]?meshlib.Id{null, .conduit_left, .conduit, .conduit_right};
const BEHIND:m.Dir = 2;
/// essence waiting for room ahead shows here, where the root goes down
const WAIT_AT:f32 = 0.86;
const FLUTTER:f32 = 0.5;

/// tiles per second an item travels along conduits
const SPEED:f32 = 2.5;
/// how quickly a root grows out to a plant beside it (fraction per second),
/// and withers back when the plant is gone
const ROOT_GROW:f32 = 0.6;
const ROOT_WITHER:f32 = 1.5;
const TAP_FLUTTER:f32 = 0.3;

pub const State = struct {
  /// the item in transit and how far along it is (0..1)
  held:?items.Item = null,
  move_t:f32 = 0,
  /// how far the root toward each neighbouring tile has grown (0..1),
  /// indexed by world direction; the front one never grows
  reach:[4]f32 = .{0, 0, 0, 0},
  /// which side root harvests next, so neighbours take turns
  turn:u8 = 0,
  /// the edges roots come in at (bit per edge counted from the way it
  /// faces, see `ARCH`), and the one the item in transit came in by
  feeds:u8 = 1 << BEHIND,
  came:m.Dir = BEHIND,
};

fn bit(r:m.Dir) u8 { return @as(u8, 1) << r; }

/// which edges its root comes in at: from each conduit facing into it, and
/// from behind when anything else stands there (it pulls from it) or
/// nothing feeds it at all.
pub fn link(ctx:st.Ctx, i:st.Id) void {
  const self = ctx.ss.get(i);
  var feeds:u8 = 0;
  for ([_]m.Dir{1, 2, 3}) |r| {
    const d = self.dir +% r;
    const v = m.dirVec(d);
    const j = ctx.ss.at(ctx.w, self.x + v.x, self.y + v.z) orelse continue;
    const t = ctx.ss.get(j);
    if (t.def().carrier) {
      if (t.dir == d +% 2) feeds |= bit(r);
    } else if (r == BEHIND) feeds |= bit(r);
  }
  self.state.conduit.feeds = if (feeds == 0) bit(BEHIND) else feeds;
}

/// the directions a conduit sends roots: behind, then its two sides.
fn tapDirs(d:m.Dir) [3]m.Dir { return .{d +% 2, d +% 1, d +% 3}; }

/// grow roots toward the plants beside a conduit, wither those with none.
fn growRoots(ctx:st.Ctx, self:*st.Structure, dt:f32) void {
  const c = &self.state.conduit;
  for (tapDirs(self.dir)) |d| {
    const v = m.dirVec(d);
    const there = ctx.plants.at(ctx.w, self.x + v.x, self.y + v.z) != null;
    const r = &c.reach[d];
    r.* = if (there) @min(1, r.* + dt * ROOT_GROW) else @max(0, r.* - dt * ROOT_WITHER);
  }
  c.reach[self.dir] = 0;
}

/// pull one item: from what is behind (a structure, or a plant its root
/// has reached), else from a plant beside it whose root has reached it.
fn pull(ctx:st.Ctx, self:*st.Structure) ?items.Item {
  const ss = ctx.ss;
  const c = &self.state.conduit;
  const taps = tapDirs(self.dir);
  const bv = m.dirVec(taps[0]);
  if (ss.at(ctx.w, self.x + bv.x, self.y + bv.z)) |j| {
    if (ss.get(j).def().carrier) return null; // carriers push, they are never pulled
    const item = ss.output(j) orelse return null;
    _ = ss.get(j).inv.take(item, 1);
    c.came = BEHIND;
    return item;
  }
  for (0..taps.len) |k| {
    const d = taps[(c.turn + k) % taps.len];
    if (c.reach[d] < 1) continue;
    const v = m.dirVec(d);
    const p = ctx.plants.at(ctx.w, self.x + v.x, self.y + v.z) orelse continue;
    if (st.harvestOne(ctx.plants, p)) |item| {
      c.turn = @intCast((c.turn + k + 1) % taps.len);
      c.came = d -% self.dir;
      return item;
    }
  }
  return null;
}

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const ss = ctx.ss;
  const self = ss.get(i);
  const v = m.dirVec(self.dir);

  growRoots(ctx, self, dt);

  if (self.state.conduit.held == null) {
    self.state.conduit.move_t = 0;
    const got = pull(ctx, self);
    self.state.conduit.held = got;
    return got != null;
  }

  const c = &self.state.conduit;
  c.move_t = @min(1, c.move_t + dt * SPEED);
  if (c.move_t < 1) return true;

  const item = c.held.?;
  const fx = self.x + v.x;
  const fz = self.y + v.z;
  const j = ss.at(ctx.w, fx, fz) orelse return false;
  const t = ss.get(j);

  if (t.def().carrier) {
    const back = m.dirVec(t.dir);
    // never hand back into a carrier facing us
    if (back.x == -v.x and back.z == -v.z) return false;
  }
  // (it comes in at the edge facing this one)
  if (!ss.handIn(ctx.g, j, item, (self.dir +% 2) -% t.dir)) return !t.def().carrier;
  self.state.conduit.held = null;
  return true;
}

/// take an item handed in at `edge` (counted from the way it faces) into
/// its core, if nothing runs through it.
pub fn receive(s:*st.Structure, _:*const prog.Progression, item:items.Item, edge:m.Dir) bool {
  const c = &s.state.conduit;
  if (c.held != null) return false;
  c.held = item;
  c.move_t = 0;
  c.came = edge;
  return true;
}

pub fn release(s:*st.Structure) ?items.Item {
  const h = s.state.conduit.held;
  s.state.conduit.held = null;
  return h;
}

/// its arches, one up out of the soil from each edge it is fed at, the
/// item in transit running through the core of the one it came in by; and
/// the roots it has sent out to plants beside it. Each grows along its
/// growth spline: an arch with the conduit, a side root as it reaches.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, _:f32) Allocator.Error!void {
  const c = &s.state.conduit;
  const place = m.chain(&.{m.translate(ctr), m.rotY(m.dirYaw(s.dir))});
  // (essence pulled from a plant beside it, with no arch there, runs
  // through the first)
  const by = if (c.feeds & bit(c.came) != 0) c.came else @as(m.Dir, @intCast(@ctz(c.feeds)));
  const along = if (c.move_t >= 1) WAIT_AT else c.move_t;
  const col = if (c.held) |it| color.Rgba8.of(it.info().col).toF4() else [4]f32{0, 0, 0, 0};
  for (ARCH, 0..) |id, r| {
    if (c.feeds & bit(@intCast(r)) == 0) continue;
    const carry = if (c.held != null and r == by) along else -1;
    try out.emit(id.?, place, .{.glow = s.activity, .flutter = FLUTTER, .phase = s.seed, .grown = s.grown, .carry = carry, .carry_col = .{col[0], col[1], col[2]}});
  }
  for (c.reach, 0..) |r, d| {
    if (r <= 0) continue;
    // a root grows out from the conduit along its spline as it reaches,
    // thickening once there (and withers back down it)
    try out.emit(.conduit_tap, m.chain(&.{m.translate(ctr), m.rotY(m.dirYaw(@intCast(d)))}), .{.flutter = TAP_FLUTTER, .phase = s.seed, .grown = r * s.grown});
  }
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.carries, .{if (s.state.conduit.held) |it| txt.item(it).name else txt.s.describe.nothing});
}

/// its bulb: a root arching out of the seed and diving back in beside it,
/// a bead of essence running along it (it carries things one way).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const arch = [4]icon_kit.P{.{0, icon_kit.TOP}, .{-0.15, 0.62}, .{0.78, 0.9}, .{0.7, 0.02}};
  try ic.stem(arch, 0.13, icon_kit.root_col);
  try ic.leaf(.{-0.04, 0.32}, 2.5, 0.32, 0.18, icon_kit.sprout, 0.9);
  const k = @mod(ic.t * ICON_RUN + ic.phase, 1);
  try ic.bud(icon_kit.curve(arch, k), 0.09, icon_bead, @sin(k * m.pi));
  try ic.coat(col);
}
const icon_bead:Color = .{255, 215, 120, 255};
/// beads along the arch a second
const ICON_RUN:f32 = 0.45;
