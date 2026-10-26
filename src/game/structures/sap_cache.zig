//! SAP CACHE: plain storage. Takes anything, gives anything. What goes in
//! drops in through the lid at its mouth, which opens for it, and hangs in
//! the resin; what comes out rises out the same way.
const std = @import("std");
const Allocator = std.mem.Allocator;
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const icon_kit = @import("../icon.zig");
const txt = @import("../text.zig");
const prog = @import("../progression.zig");
const style = @import("../style.zig");
const Draw = @import("engine").ui.draw.Draw;
const Color = @import("engine").ui.draw.Color;
const m = @import("engine").core.math;
const color = @import("engine").core.color;
const Parts = @import("../parts.zig").Parts;
const Look = @import("../parts.zig").Look;
const growth = @import("../../gfx/growth.zig");
const pod = @import("../../gfx/meshes/sap_cache.zig");

/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .belly_lump, .item_pod, .sap_cache_lid };

pub const def:st.Def = .{ .item = .sap_cache, .size = 1, .mesh = .sap_cache, .store = true, .sap = 0.3, .sway = 0.5, .tall = 0.9, .grow = 4 };

/// effectively unlimited: conduits and diggers will always hand off to a cache
const WANTS_MAX:u32 = 1 << 16;
/// what hangs inside: a ring of `RING` of the gourd's radius, turning
/// slowly, stacked upward from just under its heart, each shape bobbing;
/// a stack of `SHAPE_FULL` hangs largest
const TURN:f32 = 0.15;
const RING:f32 = 0.45;
const LIFT:f32 = -0.05;
const STACK:f32 = 0.12;
const BOB:f32 = 0.015;
const BOB_RATE:f32 = 0.7;
const SHAPE_R:f32 = 0.055;
const SHAPE_GROW:f32 = 0.04;
const SHAPE_FULL:f32 = 20;
const GLOW:f32 = 0.2;
/// something going in or coming out takes this long (s) through the mouth;
/// another starts only once one is this far along
const PASS:f32 = 0.9;
const AGAIN:f32 = 0.6;
/// going in, it is dropped in from this far over the mouth, is through it
/// by `THROUGH` of its way and sinks to its stack, which swells a little
/// as it takes it in; coming out, it is out of the mouth at `THROUGH_OUT`
/// and lifts away this far
const DROP:f32 = 0.16;
const THROUGH:f32 = 0.3;
const THROUGH_OUT:f32 = 0.6;
const LIFT_OUT:f32 = 0.2;
const MOTE:f32 = 0.32;
const MOTE_GLOW:f32 = 0.6;
const GULP:f32 = 0.3;
/// the lid's sepals stand round the mouth this far out and open this far
/// (radians) as something passes
const LID_RING:f32 = 0.022;
const LID_OPEN:f32 = 1.15;

pub const State = struct {
  /// what each slot held at the last tick
  seen:[st.SLOTS]?items.Stack = @splat(null),
  /// the last thing gone in (how far along, 0..1, 1 done; what; into which
  /// slot) and the last come out
  in_t:f32 = 1,
  in_item:items.Item = .essence,
  in_slot:u8 = 0,
  out_t:f32 = 1,
  out_item:items.Item = .essence,
};

pub fn wants(_:*const st.Structure, _:*const prog.Progression, _:items.Item) u32 { return WANTS_MAX; }

/// newest stack first.
pub fn output(s:*const st.Structure) ?items.Item {
  var k:usize = st.SLOTS;
  while (k > 0) {
    k -= 1;
    if (s.inv.slot[k]) |it| return it.item;
  }
  return null;
}

/// anything it holds.
pub fn gives(s:*const st.Structure, item:items.Item) bool { return s.inv.count(item) > 0; }

/// it does no work; it only watches what goes in and comes out, so its
/// mouth opens for each.
pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  const c = &self.state.sap_cache;
  c.in_t = @min(1, c.in_t + dt / PASS);
  c.out_t = @min(1, c.out_t + dt / PASS);
  for (self.inv.slot, &c.seen, 0..) |slot, *seen, k| {
    const n:u16 = if (slot) |it| it.n else 0;
    const was:u16 = if (seen.*) |it| it.n else 0;
    if (n > was and c.in_t >= AGAIN) {
      c.in_t = 0;
      c.in_item = slot.?.item;
      c.in_slot = @intCast(k);
    }
    if (n < was and c.out_t >= AGAIN) {
      c.out_t = 0;
      c.out_item = seen.*.?.item;
    }
    seen.* = slot;
  }
  return false;
}

/// how far open its lid stands while something is `t` (0..1) through the
/// mouth, opening ahead of it and closing behind it
fn opening(t:f32, through:f32) f32 {
  return m.smooth(m.clamp01((t - through + 0.3) / 0.25)) * (1 - m.smooth(m.clamp01((t - through - 0.1) / 0.35)));
}

/// what it holds hangs in its resin, one dark shape per stack (larger for
/// a larger stack), turning slowly round the gourd's heart; what goes in
/// drops in through the lid, which opens for it, and sinks to its stack,
/// what comes out rises out of it. All of it sways with the gourd.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  const c = &s.state.sap_cache;
  const base = s.place(ctr);
  const formed = growth.formed(pod.FORM, s.grown);
  const sway:Look = .{.phase = s.seed, .sway = def.sway, .tall = def.tall, .glow = GLOW};
  var n:usize = 0;
  for (s.inv.slot) |slot| { if (slot != null) n += 1; }
  var k:usize = 0;
  var target = pod.POD_AT;
  for (s.inv.slot, 0..) |slot, si| {
    const it = slot orelse continue;
    const a = m.ratio(k, n) * m.tau + tf * TURN + s.seed * 6;
    const ring = if (n == 1) 0 else pod.POD_R[0] * RING;
    const y = pod.POD_AT[1] + LIFT + STACK * m.ratio(k, @max(n, 2) - 1) + BOB * @sin(tf * BOB_RATE + m.f(k) * 2);
    const at = m.v3(@cos(a) * ring, y, @sin(a) * ring);
    var r = SHAPE_R + SHAPE_GROW * m.clamp01(m.f(it.n) / SHAPE_FULL);
    if (si == c.in_slot and c.in_t < 1) {
      target = at;
      r *= 1 + GULP * @sin(m.pi * m.clamp01((c.in_t - 0.75) / 0.25));
    }
    var look = sway;
    look.tint = color.Rgba8.of(it.item.info().col).toF4();
    look.drop = at[1];
    try out.emit(.belly_lump, m.mul(base, m.chain(&.{m.translate(at), m.scale3(m.splat3(r * formed))})), look);
    k += 1;
  }
  if (s.grown < 1) return;
  // going in: dropped in through the mouth, then sinking to its stack
  if (c.in_t < 1) {
    const t = c.in_t;
    const above = pod.MOUTH + m.v3(0, DROP, 0);
    const p = if (t < THROUGH)
      m.lerpV(above, pod.MOUTH, m.smooth(t / THROUGH))
    else
      m.lerpV(pod.MOUTH, target, m.smooth((t - THROUGH) / (1 - THROUGH)));
    var look = sway;
    look.glow = MOTE_GLOW;
    look.tint = color.Rgba8.of(c.in_item.info().col).toF4();
    look.drop = p[1];
    const size = MOTE * (1 - m.smooth(m.clamp01((t - 0.8) / 0.2)));
    try out.emit(.item_pod, m.mul(base, m.chain(&.{m.translate(p), m.scale3(m.splat3(size))})), look);
  }
  // coming out: up from the gourd's heart, out through the mouth, away
  if (c.out_t < 1) {
    const t = c.out_t;
    const p = if (t < THROUGH_OUT)
      m.lerpV(pod.POD_AT, pod.MOUTH, m.smooth(t / THROUGH_OUT))
    else
      pod.MOUTH + m.v3(0, LIFT_OUT * m.smooth((t - THROUGH_OUT) / (1 - THROUGH_OUT)), 0);
    var look = sway;
    look.glow = MOTE_GLOW;
    look.tint = color.Rgba8.of(c.out_item.info().col).toF4();
    look.drop = p[1];
    const size = MOTE * m.smooth(m.clamp01(t / 0.2)) * (1 - m.smooth(m.clamp01((t - 0.75) / 0.25)));
    try out.emit(.item_pod, m.mul(base, m.chain(&.{m.translate(p), m.scale3(m.splat3(size))})), look);
  }
  // the lid: its sepals turned open about their bases while anything passes
  const open = LID_OPEN * @max(if (c.in_t < 1) opening(c.in_t, THROUGH) else 0, if (c.out_t < 1) opening(c.out_t, THROUGH_OUT) else 0);
  for (0..pod.LID_SEPALS) |j| {
    const a = m.ratio(j, pod.LID_SEPALS) * m.tau + 0.2;
    var look = sway;
    look.drop = pod.MOUTH[1];
    look.grown = s.grown;
    try out.emit(.sap_cache_lid, m.mul(base, m.chain(&.{m.translate(pod.MOUTH), m.rotY(a), m.translate(m.v3(LID_RING, 0, 0)), m.rotZ(-open)})), look);
  }
}

pub fn describe(_:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  _ = try d.text(x, y, style.text_body, style.dim, txt.s.describe.cache);
}

/// its bulb: two sprouts curling into a basket round a bead of amber sap
/// (it holds things).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  try ic.glow(.{0, 0.55}, 0.4, icon_glow);
  try ic.bud(.{0, 0.55}, 0.22, icon_sap, 0.8);
  for ([_]f32{-1, 1}) |sx| {
    try ic.stem(.{.{0, icon_kit.TOP}, .{0.55 * sx, 0.22}, .{0.6 * sx, 0.75}, .{0.3 * sx, 0.9}}, 0.1, icon_kit.stem_col);
    try ic.leaf(.{0.3 * sx, 0.9}, if (sx < 0) 2.7 else 0.45, 0.26, 0.16, icon_kit.sprout, 0.9);
  }
  try ic.coat(col);
}
const icon_sap:Color = .{255, 190, 90, 255};
const icon_glow:Color = .{255, 190, 90, 90};
