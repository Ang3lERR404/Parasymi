//! RESEARCH BLOOM: the lab. Studies the chosen technology, eating the
//! per-unit ingredients it is fed, one unit at a time. Its orb spins faster
//! while it works.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const icon_kit = @import("../icon.zig");
const txt = @import("../text.zig");
const prog = @import("../progression.zig");
const style = @import("../style.zig");
const Parts = @import("../parts.zig").Parts;
const Draw = @import("../../ui/draw.zig").Draw;
const Color = @import("../../ui/draw.zig").Color;

pub const def:st.Def = .{ .item = .research_bloom, .size = 2, .mesh = .research_bloom, .store = true, .sway = 0.8, .tall = 2.0, .grow = 8 };

/// most of one ingredient it will hold
const STOCK = 20;
/// the orb: hangs this high over the flower, bobbing; forms over the last
/// quarter of growth; spins at a fixed tempo and rocks harder with work
const ORB_HEIGHT:f32 = 2.05;
const ORB_BOB:f32 = 0.12;
const ORB_BOB_RATE:f32 = 1.4;
const ORB_FORMS:f32 = 0.75;
const ORB_SPIN:f32 = 0.5;
const ORB_ROCK:f32 = 0.15;
const ORB_ROCK_ACTIVE:f32 = 0.25;
const ORB_GLOW:f32 = 0.7;
const ORB_GLOW_ACTIVE:f32 = 1.5;
const ORB_SAP:f32 = 0.7;

pub const State = struct {
  lab:prog.Lab = .{},
};

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  ctx.g.labTick(&self.state.research_bloom.lab, self.inv.bag(), dt);
  return self.state.research_bloom.lab.busy;
}

pub fn wants(s:*const st.Structure, g:*const prog.Progression, item:items.Item) u32 {
  const id = g.current orelse return 0;
  for (prog.tree.get(id).per_unit) |ing| {
    if (ing.item == item) return STOCK -| s.inv.count(item);
  }
  return 0;
}

/// the orb hovering over the bloom: bobs, turns, and sways with the
/// flower under it. It turns at a fixed tempo (one that followed the work
/// jumped every time the work changed); the work makes it rock harder.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  const a = s.activity;
  const bob = ORB_BOB * @sin(tf * ORB_BOB_RATE + s.seed * 5);
  // the orb forms last, once the flower has opened
  const form = m.smooth(m.clamp01((s.grown - ORB_FORMS) / (1 - ORB_FORMS)));
  if (form <= 0) return;
  const lift = (ORB_HEIGHT + bob) * s.grownScale()[1];
  try out.emit(.research_orb, m.chain(&.{
    m.translate(ctr + m.v3(0, lift, 0)),
    m.scale3(m.splat3(form)),
    m.rotY(tf * ORB_SPIN + s.seed * m.tau),
    m.rotX((ORB_ROCK + ORB_ROCK_ACTIVE * a) * @sin(tf)),
  }), .{ .glow = ORB_GLOW + ORB_GLOW_ACTIVE * a, .phase = s.seed, .fade = ORB_SAP, .sway = def.sway, .tall = def.tall, .drop = lift });
}

pub fn describe(_:*const st.Structure, d:*Draw, g:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const id = g.current orelse {
    _ = try d.text(x, y, style.text_body, style.dim, txt.s.describe.choose_study);
    return;
  };
  const r = prog.tree.get(id);
  _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.studies, .{txt.research(id).name});
  try d.tendril(x + style.desc_bar_x, y + 2, style.desc_bar_w, style.bar_h, style.research_tendril, m.ratio(g.progress.get(id), r.units), 0.3);
}

/// its bulb: a sprout opening into a violet flower (it studies).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const top:icon_kit.P = .{0, 0.68};
  try ic.stem(.{.{0, icon_kit.TOP}, .{0.12, 0.35}, .{-0.12, 0.55}, top}, 0.11, icon_kit.stem_col);
  try ic.leaf(.{0.04, 0.32}, 0.25, 0.3, 0.17, icon_kit.sprout, 0.9);
  try ic.glow(top, 0.32, icon_glow);
  for (0..ICON_PETALS) |i| {
    try ic.leaf(top, m.half_pi + m.tau * m.ratio(i, ICON_PETALS), 0.3, 0.2, icon_petal, 1);
  }
  try ic.stamens(top, m.half_pi, 0.8, 5, 0.22, icon_filament);
  try ic.bud(top, 0.08, icon_core, 1);
  try ic.coat(col);
}
const ICON_PETALS = 5;
const icon_petal:Color = .{200, 150, 255, 255};
const icon_core:Color = .{255, 215, 130, 255};
const icon_filament:Color = .{230, 215, 250, 255};
const icon_glow:Color = .{200, 160, 255, 80};
