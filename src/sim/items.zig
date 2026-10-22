//! physical items and inventories. There is no global stockpile: every item
//! lives in some inventory (the player, later structures) or in the world.
const std = @import("std");
const species = @import("species.zig");

pub const Item = enum(u8) {
  grit, fibre, ley_shard, starlight, essence,
  seed_lumenroot, seed_thornleech, seed_vesper, seed_driftwisp, seed_hollowheart,
  // structure bulbs: woven, then planted to grow a structure
  conduit, sap_cache, germinator, research_bloom,

  pub fn info(i:Item) Info { return infos.get(i); }

  pub fn seedOf(sp:species.Id) Item {
    return switch (sp) {
      .lumenroot => .seed_lumenroot, .thornleech => .seed_thornleech, .vesper => .seed_vesper,
      .driftwisp => .seed_driftwisp, .hollowheart => .seed_hollowheart,
    };
  }
  pub fn plants(i:Item) ?species.Id {
    return switch (i) {
      .seed_lumenroot => .lumenroot, .seed_thornleech => .thornleech, .seed_vesper => .vesper,
      .seed_driftwisp => .driftwisp, .seed_hollowheart => .hollowheart,
      else => null,
    };
  }
};

pub const Info = struct { name:[]const u8, short:[]const u8, col:[4]u8, stack:u16 = 50 };

const infos = std.enums.EnumArray(Item, Info).init(.{
  .grit = .{.name = "MINERAL GRIT", .short = "GR", .col = .{150, 140, 130, 255}},
  .fibre = .{.name = "ROOT FIBRE", .short = "FB", .col = .{120, 170, 90, 255}},
  .ley_shard = .{.name = "LEY SHARD", .short = "LY", .col = .{170, 120, 255, 255}, .stack = 20},
  .starlight = .{.name = "STARLIGHT", .short = "ST", .col = .{255, 245, 190, 255}, .stack = 20},
  .essence = .{.name = "ESSENCE", .short = "ES", .col = .{255, 215, 120, 255}},
  .seed_lumenroot = .{.name = "LUMENROOT SEED", .short = "LS", .col = .{120, 240, 220, 255}, .stack = 20},
  .seed_thornleech = .{.name = "THORNLEECH SEED", .short = "TS", .col = .{240, 90, 120, 255}, .stack = 20},
  .seed_vesper = .{.name = "VESPER SEED", .short = "VS", .col = .{200, 170, 255, 255}, .stack = 10},
  .seed_driftwisp = .{.name = "DRIFTWISP SPORE", .short = "DW", .col = .{190, 210, 255, 255}, .stack = 10},
  .seed_hollowheart = .{.name = "HOLLOWHEART SEED", .short = "HH", .col = .{230, 170, 100, 255}, .stack = 5},
  .conduit = .{.name = "ROOT CONDUIT", .short = "RC", .col = .{150, 120, 80, 255}},
  .sap_cache = .{.name = "SAP CACHE", .short = "SC", .col = .{210, 160, 70, 255}, .stack = 10},
  .germinator = .{.name = "GERMINATOR", .short = "GM", .col = .{140, 220, 140, 255}, .stack = 5},
  .research_bloom = .{.name = "RESEARCH BLOOM", .short = "RB", .col = .{200, 150, 255, 255}, .stack = 5},
});

pub const Stack = struct { item:Item, n:u16 };

/// an amount of an item consumed by a recipe or research unit.
pub const Ingredient = struct { item:Item, n:u16 };

pub fn Inventory(comptime slots:usize) type {
  return struct {
    const Self = @This();
    slot:[slots]?Stack = @splat(null),

    /// adds as many as fit; returns how many were added.
    pub fn add(inv:*Self, item:Item, n:u16) u16 {
      var left = n;
      const max = item.info().stack;
      for (&inv.slot) |*s| if (s.*) |*st| if (st.item == item and st.n < max) {
        const k = @min(left, max - st.n);
        st.n += k;
        left -= k;
        if (left == 0) return n;
      };
      for (&inv.slot) |*s| if (s.* == null) {
        const k = @min(left, max);
        s.* = .{.item = item, .n = k};
        left -= k;
        if (left == 0) return n;
      };
      return n - left;
    }

    pub fn count(inv:*const Self, item:Item) u32 {
      var c:u32 = 0;
      for (inv.slot) |s| if (s) |st| if (st.item == item) { c += st.n; };
      return c;
    }

    /// removes exactly `n` or nothing.
    pub fn take(inv:*Self, item:Item, n:u32) bool {
      if (inv.count(item) < n) return false;
      var left = n;
      var i = slots;
      while (i > 0 and left > 0) {
        i -= 1;
        if (inv.slot[i]) |*st| if (st.item == item) {
          const k:u16 = @intCast(@min(left, st.n));
          st.n -= k;
          left -= k;
          if (st.n == 0) inv.slot[i] = null;
        };
      }
      return true;
    }

    /// 0..1, how full the inventory is (by stack fraction).
    pub fn fill(inv:*const Self) f32 {
      var f:f32 = 0;
      for (inv.slot) |s| if (s) |st| { f += @as(f32, @floatFromInt(st.n)) / @as(f32, @floatFromInt(st.item.info().stack)); };
      return f / @as(f32, @floatFromInt(slots));
    }
  };
}

test "inventory stacks and takes" {
  var inv:Inventory(4) = .{};
  try std.testing.expectEqual(@as(u16, 70), inv.add(.grit, 70));
  try std.testing.expectEqual(@as(u32, 70), inv.count(.grit));
  try std.testing.expect(inv.take(.grit, 60));
  try std.testing.expectEqual(@as(u32, 10), inv.count(.grit));
  try std.testing.expect(!inv.take(.grit, 11));
  // 3 free slots of 20 starlight each
  try std.testing.expectEqual(@as(u16, 60), inv.add(.starlight, 200));
}
