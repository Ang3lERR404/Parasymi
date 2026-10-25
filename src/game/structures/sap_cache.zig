//! SAP CACHE: plain storage. Takes anything, gives anything.
const std = @import("std");
const Allocator = std.mem.Allocator;
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const icon_kit = @import("../icon.zig");
const txt = @import("../text.zig");
const prog = @import("../progression.zig");
const style = @import("../style.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const Color = @import("../../ui/draw.zig").Color;
const m = @import("../../core/math.zig");
const color = @import("../../core/color.zig");
const Parts = @import("../parts.zig").Parts;
const pod = @import("../../gfx/meshes/sap_cache.zig");

pub const def:st.Def = .{ .item = .sap_cache, .size = 1, .mesh = .sap_cache, .store = true, .sap = 0.3, .sway = 0.5, .tall = 0.9, .grow = 4, .splined = true };

/// effectively unlimited: conduits and diggers will always hand off to a cache
const WANTS_MAX:u32 = 1 << 16;
/// what hangs inside: a ring of `RING` of the pod's radius, turning slowly,
/// stacked upward from just over the pod's heart, each shape bobbing;
/// a stack of `SHAPE_FULL` hangs largest
const TURN:f32 = 0.15;
const RING:f32 = 0.45;
const LIFT:f32 = 0.02;
const STACK:f32 = 0.1;
const BOB:f32 = 0.015;
const BOB_RATE:f32 = 0.7;
const SHAPE_R:f32 = 0.06;
const SHAPE_GROW:f32 = 0.04;
const SHAPE_FULL:f32 = 20;
const GLOW:f32 = 0.2;

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

/// what it holds hangs in its resin, one dark shape per stack (larger for
/// a larger stack), turning slowly around the pod's heart.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  var n:usize = 0;
  for (s.inv.slot) |slot| { if (slot != null) n += 1; }
  var k:usize = 0;
  for (s.inv.slot) |slot| {
    const it = slot orelse continue;
    const a = m.ratio(k, n) * m.tau + tf * TURN + s.seed * 6;
    const ring = if (n == 1) 0 else pod.POD_R[0] * RING;
    const y = pod.POD_AT[1] + LIFT + STACK * m.ratio(k, @max(n, 2) - 1) + BOB * @sin(tf * BOB_RATE + m.f(k) * 2);
    const r = SHAPE_R + SHAPE_GROW * m.clamp01(m.f(it.n) / SHAPE_FULL);
    const at = m.v3(@cos(a) * ring, y, @sin(a) * ring) * s.grownScale();
    try out.emit(.belly_lump, m.chain(&.{m.translate(ctr + at), m.scale3(m.splat3(r * s.grown))}), .{
      .glow = GLOW, .phase = s.seed, .tint = color.Rgba8.of(it.item.info().col).toF4(),
      // it sways with the pod it hangs in
      .sway = def.sway, .tall = def.tall, .drop = at[1],
    });
    k += 1;
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
