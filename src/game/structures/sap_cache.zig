//! SAP CACHE: plain storage. Takes anything, gives anything.
const std = @import("std");
const Allocator = std.mem.Allocator;
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const prog = @import("../progression.zig");
const style = @import("../style.zig");
const Draw = @import("../../ui/draw.zig").Draw;

pub const def:st.Def = .{ .name = "SAP CACHE", .item = .sap_cache, .size = 1, .mesh = .sap_cache };

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

pub fn describe(_:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  _ = try d.text(x, y, 1.4, style.dim, "HOLDS ANYTHING. FEED (F), TAKE (SHIFT+F)");
}