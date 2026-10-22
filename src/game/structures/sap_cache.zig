//! SAP CACHE: plain storage. Takes anything, gives anything.
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const prog = @import("../progression.zig");
const Draw = @import("../../ui/draw.zig").Draw;

pub const def:st.Def = .{.name = "SAP CACHE", .item = .sap_cache, .size = 1, .mesh = .sap_cache};

pub fn wants(_:*const st.Structure, _:*const prog.Progression, _:items.Item) u32 { return 1 << 16; }

/// newest stack first.
pub fn output(s:*const st.Structure) ?items.Item {
  var k:usize = st.SLOTS;
  while (k > 0) {
    k -= 1;
    if (s.inv.slot[k]) |it| return it.item;
  }
  return null;
}

pub fn describe(_:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) !void {
  _ = try d.text(x, y, 1.4, .{150, 170, 150, 255}, "HOLDS ANYTHING. FEED (F), TAKE (SHIFT+F)");
}
