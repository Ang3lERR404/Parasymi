//! ROOT CONDUIT: the first logistics. One item at a time it pulls from
//! whatever is behind it (a structure's output, or a mature plant, which
//! harvests it) and passes it forward to the next conduit or structure.
const m = @import("../../core/math.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const prog = @import("../progression.zig");
const color = @import("../../core/color.zig");
const Parts = @import("../parts.zig").Parts;
const Draw = @import("../../ui/draw.zig").Draw;

pub const def:st.Def = .{.name = "ROOT CONDUIT", .item = .conduit, .size = 1, .mesh = .conduit};

/// tiles per second an item travels along conduits
const SPEED:f32 = 2.5;

pub const State = struct {
  /// the item in transit and how far along it is (0..1)
  held:?items.Item = null,
  move_t:f32 = 0,
};

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const ss = ctx.ss;
  const s = ss.get(i);
  const v = m.dirVec(s.dir);
  if (s.state.conduit.held == null) {
    s.state.conduit.move_t = 0;
    const bx = s.x - v[0];
    const by = s.y - v[1];
    var got:?items.Item = null;
    if (ss.at(ctx.w, bx, by)) |j| {
      if (ss.get(j).kind() == .conduit) return false; // conduits push, they never pull
      const item = ss.output(j) orelse return false;
      _ = ss.get(j).inv.take(item, 1);
      got = item;
    } else if (ctx.plants.at(ctx.w, bx, by)) |p| {
      got = st.harvestOne(ctx.plants, p);
    }
    ss.get(i).state.conduit.held = got;
    return got != null;
  }
  const c = &s.state.conduit;
  c.move_t = @min(1, c.move_t + dt * SPEED);
  if (c.move_t < 1) return true;
  const item = c.held.?;
  const j = ss.at(ctx.w, s.x + v[0], s.y + v[1]) orelse return false;
  const t = ss.get(j);
  if (t.kind() == .conduit) {
    const back = m.dirVec(t.dir);
    // never hand back into a conduit facing us
    if (t.state.conduit.held != null or (back[0] == -v[0] and back[1] == -v[1])) return false;
    t.state.conduit = .{.held = item};
    ss.get(i).state.conduit.held = null;
    return true;
  }
  if (ss.insert(ctx.g, j, item, 1) == 1) ss.get(i).state.conduit.held = null;
  return true;
}

pub fn release(s:*st.Structure) ?items.Item {
  const h = s.state.conduit.held;
  s.state.conduit.held = null;
  return h;
}

/// the item in transit, gliding along the conduit.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  const item = s.state.conduit.held orelse return;
  const v = m.dirVec(s.dir);
  const k = s.state.conduit.move_t - 0.5;
  const p = ctr + m.v3(m.f(v[0]) * k, 0.27 + 0.03 * @sin(tf * 8), m.f(v[1]) * k);
  const col = item.info().col;
  try out.emit(.item_pod, m.translate(p), .{
    .glow = 0.8,
    .tint = color.toF(col, 1),
  });
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  _ = try d.print(x, y, 1.4, .{235, 240, 225, 255}, "CARRIES {s}", .{if (s.state.conduit.held) |it| it.info().name else "NOTHING"});
}
