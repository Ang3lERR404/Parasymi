//! ROOT CONDUIT: the first logistics. One item at a time it pulls from
//! whatever is behind it (a structure's output, or a mature plant, which
//! harvests it) and passes it forward to the next conduit or structure.
//! It also sends a root out to any plant beside it (left, right or behind)
//! and, once that root has reached it, harvests that plant too.
const m = @import("../../core/math.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const prog = @import("../progression.zig");
const color = @import("../../core/color.zig");
const style = @import("../style.zig");
const Parts = @import("../parts.zig").Parts;
const Draw = @import("../../ui/draw.zig").Draw;
const root = @import("../../gfx/meshes/conduit.zig");

/// decision: a conduit grows (out from its middle to its edges) but does
/// not sway: its root hugs the ground and joins the next conduit's, and a
/// bend per conduit would split the joins along a chain
pub const def:st.Def = .{ .name = "ROOT CONDUIT", .item = .conduit, .size = 1, .mesh = .conduit, .grow = 1.5, .carrier = true };

/// tiles per second an item travels along conduits
const SPEED:f32 = 2.5;
/// how quickly a root grows out to a plant beside it (fraction per second),
/// and withers back when the plant is gone
const ROOT_GROW:f32 = 0.6;
const ROOT_WITHER:f32 = 1.5;
/// a side root grows long first, then thickens from `TAP_GIRTH` of its girth
const TAP_GIRTH:f32 = 0.35;
const TAP_FLUTTER:f32 = 0.3;
/// the carried item rides this high over the root, bobbing a little
const RIDE:f32 = 0.1;
const RIDE_BOB:f32 = 0.01;
const RIDE_BOB_RATE:f32 = 2.2;
const RIDE_GLOW:f32 = 0.8;

pub const State = struct {
  /// the item in transit and how far along it is (0..1)
  held:?items.Item = null,
  move_t:f32 = 0,
  /// how far the root toward each neighbouring tile has grown (0..1),
  /// indexed by world direction; the front one never grows
  reach:[4]f32 = .{0, 0, 0, 0},
  /// which side root harvests next, so neighbours take turns
  turn:u8 = 0,
};

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
    if (ss.get(j).kind() == .conduit) return null; // conduits push, they never pull
    const item = ss.output(j) orelse return null;
    _ = ss.get(j).inv.take(item, 1);
    return item;
  }
  for (0..taps.len) |k| {
    const d = taps[(c.turn + k) % taps.len];
    if (c.reach[d] < 1) continue;
    const v = m.dirVec(d);
    const p = ctx.plants.at(ctx.w, self.x + v.x, self.y + v.z) orelse continue;
    if (st.harvestOne(ctx.plants, p)) |item| {
      c.turn = @intCast((c.turn + k + 1) % taps.len);
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

  if (t.kind() == .conduit) {
    const back = m.dirVec(t.dir);
    // never hand back into a conduit facing us
    if (t.state.conduit.held != null or (back.x == -v.x and back.z == -v.z)) return false;
    t.state.conduit.held = item;
    t.state.conduit.move_t = 0;
    self.state.conduit.held = null;
    return true;
  }

  if (ss.insert(ctx.g, j, item, 1) == 1) self.state.conduit.held = null;
  return true;
}

pub fn release(s:*st.Structure) ?items.Item {
  const h = s.state.conduit.held;
  s.state.conduit.held = null;
  return h;
}

/// the roots it has sent out to plants beside it, and the item in transit,
/// gliding along it.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  for (s.state.conduit.reach, 0..) |r, d| {
    if (r <= 0) continue;
    // a root grows out from the conduit: longer first, then thicker
    const len = m.smooth(r) * m.smooth(s.grown);
    const girth = TAP_GIRTH + (1 - TAP_GIRTH) * m.smooth(m.clamp01(r * 1.5 - 0.5));
    try out.emit(.conduit_tap, m.chain(&.{m.translate(ctr), m.rotY(m.dirYaw(@intCast(d))), m.scale3(m.v3(len, girth, girth))}), .{.flutter = TAP_FLUTTER, .phase = s.seed, .fade = st.SAP});
  }
  const item = s.state.conduit.held orelse return;
  const v = m.dirVec(s.dir);
  const k = s.state.conduit.move_t - 0.5;
  // it rides along the root, over its hump and down through its dip
  const p = ctr + m.v3(m.f(v.x) * k, root.rise(k + 0.5) + RIDE + RIDE_BOB * @sin(tf * RIDE_BOB_RATE + s.seed * 6), m.f(v.z) * k);
  const col = item.info().col;
  try out.emit(.item_pod, m.translate(p), .{
    .glow = RIDE_GLOW,
    .tint = color.Rgba8.of(col).toF4(),
  });
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  _ = try d.print(x, y, style.text_body, style.white, "CARRIES {s}", .{if (s.state.conduit.held) |it| it.info().name else "NOTHING"});
}