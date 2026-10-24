//! DIAMOND: where a halo's four blooms became one, floating high over the
//! polyp at its ring's heart; or, once Celestial Defragmentation is known,
//! woven and put down over any dry tile. Small and still, a cut crystal that
//! only catches light. It fragments that light into the halo's ring around
//! it (see `halo.zig`), and holds a field of celestial energy wider than it.
//! Put down by hand, it gathers from its shards as it grows in; grown, or
//! born of a halo, it forms with a flash of light. Blooms sown on the
//! ring's four points brighten the arcs beside them. (The world event will
//! start from it.)
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const Field = @import("../../sim/ecology.zig").Field;
const st = @import("../structures.zig");
const txt = @import("../text.zig");
const prog = @import("../progression.zig");
const style = @import("../style.zig");
const Parts = @import("../parts.zig").Parts;
const Draw = @import("../../ui/draw.zig").Draw;
const halo = @import("halo.zig");

// it floats as high as the blooms hang, at the heart of its ring, over
// whatever is under it
pub const def:st.Def = .{ .item = .diamond, .size = 1, .mesh = .halo_diamond, .floating = true, .hover = halo.HOVER, .bare = true, .grow = 8 };

pub const State = struct {
  /// seconds since it formed (grown)
  t:f32 = 0,
  /// per point of its ring: how brightly the arcs beside it shine
  light:[4]f32 = @splat(halo.DIM),
};

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  const d = &self.state.diamond;
  d.t = @min(d.t + dt, halo.FORM + halo.FLASH);
  halo.relight(&d.light, ctx.plants, ctx.w, self.x, self.y, dt);
  return false;
}

pub fn field(s:*const st.Structure) ?Field {
  if (s.grown < 1) return null;
  return .{ .x = s.x, .y = s.y, .radius = halo.DIAMOND_R };
}

/// how far along its halo is: growing in, it gathers as the halo's blooms
/// would bring it together; formed, past 1
fn along(s:*const st.Structure) f32 {
  return if (s.grown < 1) s.grown else 1 + s.state.diamond.t / halo.FORM;
}

pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, _:f32) Allocator.Error!void {
  try halo.draw(out, s.seed, ctr + m.v3(0, def.hover, 0), ctr, along(s), s.state.diamond.light);
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  _ = try d.print(x, y, style.text_body, style.gold, txt.s.describe.diamond, .{halo.lit(s.state.diamond.light)});
}
