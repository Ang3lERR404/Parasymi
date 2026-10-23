//! RESEARCH BLOOM: the lab. Studies the chosen technology, eating the
//! per-unit ingredients it is fed, one unit at a time. Its orb spins faster
//! while it works.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const prog = @import("../progression.zig");
const style = @import("../style.zig");
const Parts = @import("../parts.zig").Parts;
const Draw = @import("../../ui/draw.zig").Draw;

pub const def:st.Def = .{ .name = "RESEARCH BLOOM", .item = .research_bloom, .size = 2, .mesh = .research_bloom, .sway = 0.8, .tall = 2.0, .grow = 8 };

/// most of one ingredient it will hold
const STOCK = 20;

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
  const bob = 0.12 * @sin(tf * 1.4 + s.seed * 5);
  // the orb forms last, once the flower has opened
  const form = m.smooth(m.clamp01((s.grown - 0.75) / 0.25));
  if (form <= 0) return;
  const lift = (2.05 + bob) * s.grownScale()[1];
  try out.emit(.research_orb, m.chain(&.{
    m.translate(ctr + m.v3(0, lift, 0)),
    m.scale3(m.splat3(form)),
    m.rotY(tf * 0.5 + s.seed * m.tau),
    m.rotX((0.15 + 0.25 * a) * @sin(tf)),
  }), .{ .glow = 0.7 + 1.5 * a, .phase = s.seed, .fade = 0.7, .sway = def.sway, .tall = def.tall, .drop = lift });
}

pub fn describe(_:*const st.Structure, d:*Draw, g:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const id = g.current orelse {
    _ = try d.text(x, y, 1.4, style.dim, "CHOOSE WHAT TO STUDY (T)");
    return;
  };
  const r = prog.tree.get(id);
  _ = try d.print(x, y, 1.4, style.white, "STUDIES {s}", .{r.name});
  try d.tendril(x + 250, y + 2, 110, 12, style.research_tendril, m.ratio(g.progress.get(id), r.units), 0.3);
}