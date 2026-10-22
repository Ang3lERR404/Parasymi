//! RESEARCH BLOOM: the lab. Studies the chosen technology, eating the
//! per-unit ingredients it is fed, one unit at a time. Its orb spins faster
//! while it works.
const m = @import("../../core/math.zig");
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const prog = @import("../progression.zig");
const Parts = @import("../parts.zig").Parts;
const Draw = @import("../../ui/draw.zig").Draw;

pub const def:st.Def = .{.name = "RESEARCH BLOOM", .item = .research_bloom, .size = 2, .mesh = .research_bloom};

/// most of one ingredient it will hold
const STOCK = 20;

pub const State = struct { lab:prog.Lab = .{} };

pub fn tick(ctx:st.Ctx, i:u32, dt:f32) bool {
  const s = ctx.ss.get(i);
  ctx.g.labTick(&s.state.research_bloom.lab, &s.inv, dt);
  return s.state.research_bloom.lab.busy;
}

pub fn wants(s:*const st.Structure, g:*const prog.Progression, item:items.Item) u32 {
  const id = g.current orelse return 0;
  for (prog.tree.get(id).per_unit) |ing| {
    if (ing.item == item) return STOCK -| s.inv.count(item);
  }
  return 0;
}

/// the orb hovering over the bloom: bobs, and spins with the work.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) !void {
  const a = s.activity;
  const bob = 0.12 * @sin(tf * 1.4 + s.seed * 5);
  try out.emit(.research_orb, m.chain(.{
    m.translate(ctr + m.v3(0, 2.05 + bob, 0)), m.rotY(tf * (0.4 + 2.5 * a)), m.rotX(0.3 * @sin(tf)),
  }), .{.glow = 0.7 + 1.5 * a, .phase = s.seed});
}

pub fn describe(_:*const st.Structure, d:*Draw, g:*const prog.Progression, x:f32, y:f32) !void {
  const id = g.current orelse {
    _ = try d.text(x, y, 1.4, .{150, 170, 150, 255}, "CHOOSE WHAT TO STUDY (T)");
    return;
  };
  const r = prog.tree.get(id);
  _ = try d.print(x, y, 1.4, .{235, 240, 225, 255}, "STUDIES {s}", .{r.name});
  try d.tendril(x + 250, y + 2, 110, 12, .{200, 160, 255, 255}, m.ratio(g.progress.get(id), r.units), 0.3);
}
