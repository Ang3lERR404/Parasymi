//! SAP CACHE: plain storage. Takes anything, gives anything.
const std = @import("std");
const Allocator = std.mem.Allocator;
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const prog = @import("../progression.zig");
const style = @import("../style.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const m = @import("../../core/math.zig");
const color = @import("../../core/color.zig");
const Parts = @import("../parts.zig").Parts;
const pod = @import("../../gfx/meshes/sap_cache.zig");

pub const def:st.Def = .{ .name = "SAP CACHE", .item = .sap_cache, .size = 1, .mesh = .sap_cache, .sap = 0.3 };

/// effectively unlimited: conduits and diggers will always hand off to a cache
const WANTS_MAX:u32 = 1 << 16;

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
    const a = m.ratio(k, n) * m.tau + tf * 0.15 + s.seed * 6;
    const ring = if (n == 1) 0 else pod.POD_R[0] * 0.45;
    const y = pod.POD_AT[1] + 0.02 + 0.1 * m.ratio(k, @max(n, 2) - 1) + 0.015 * @sin(tf * 0.7 + m.f(k) * 2);
    const r = 0.06 + 0.04 * m.clamp01(m.f(it.n) / 20);
    try out.emit(.belly_lump, m.chain(&.{m.translate(ctr + m.v3(@cos(a) * ring, y, @sin(a) * ring)), m.scale3(m.splat3(r))}), .{
      .glow = 0.2, .phase = s.seed, .tint = color.Rgba8.of(it.item.info().col).toF4(),
    });
    k += 1;
  }
}

pub fn describe(_:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  _ = try d.text(x, y, 1.4, style.dim, "HOLDS ANYTHING. FEED (F), TAKE (SHIFT+F)");
}