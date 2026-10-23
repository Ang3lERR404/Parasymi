//! physical items and inventories. There is no global stockpile: every item
//! lives in some inventory (the player, later structures) or in the world.
const std = @import("std");
const m = @import("../core/math.zig");
const EnumArray = std.enums.EnumArray;
const testing = std.testing;
const species = @import("species.zig");

pub const Item = enum(u8) {
  grit, fibre, ley_shard, starlight, essence,
  /// condensed only where the lineages have merged: the next tier's study.
  convergence_essence,
  seed_lumenroot, seed_thornleech, seed_vesper, seed_driftwisp, seed_hollowheart,
  // structure bulbs: woven, then planted to grow a structure
  conduit, sap_cache, germinator, research_bloom, root_digger,
  // later additions go last, so stored item ids never shift
  seed_bloom,

  pub fn info(i:Item) Info { return infos.get(i); }

  pub fn plants(i:Item) ?species.Id { return species.fromSeed(i); }
};

/// names are player-facing text (`game/text.zig`).
pub const Info = struct { col:[4]u8, stack:u16 = 50 };

const infos = EnumArray(Item, Info).init(.{
  .grit = .{.col = .{150, 140, 130, 255}},
  .fibre = .{.col = .{120, 170, 90, 255}},
  .ley_shard = .{.col = .{170, 120, 255, 255}, .stack = 20},
  .starlight = .{.col = .{255, 245, 190, 255}, .stack = 20},
  .essence = .{.col = .{255, 215, 120, 255}},
  .convergence_essence = .{.col = .{220, 150, 255, 255}, .stack = 20},
  .seed_lumenroot = .{.col = .{120, 240, 220, 255}, .stack = 20},
  .seed_thornleech = .{.col = .{240, 90, 120, 255}, .stack = 20},
  .seed_vesper = .{.col = .{200, 170, 255, 255}, .stack = 10},
  .seed_driftwisp = .{.col = .{190, 210, 255, 255}, .stack = 10},
  .seed_hollowheart = .{.col = .{230, 170, 100, 255}, .stack = 5},
  .conduit = .{.col = .{150, 120, 80, 255}},
  .sap_cache = .{.col = .{210, 160, 70, 255}, .stack = 10},
  .germinator = .{.col = .{140, 220, 140, 255}, .stack = 5},
  .research_bloom = .{.col = .{200, 150, 255, 255}, .stack = 5},
  .root_digger = .{.col = .{190, 140, 90, 255}, .stack = 10},
  .seed_bloom = .{.col = .{140, 255, 215, 255}, .stack = 5},
});

pub const Stack = struct { item:Item, n:u16 };

/// an amount of an item consumed by a recipe or research unit.
pub const Ingredient = struct { item:Item, n:u16 };

/// any inventory seen through its slots, whatever its size. Recipes and
/// research take a Bag so they work on the wolf's belly and structures alike.
pub const Bag = struct {
  slot:[]?Stack,

  /// adds as many as fit; returns how many were added.
  pub fn add(b:Bag, item:Item, n:u16) u16 {
    var left = n;
    const max = item.info().stack;
    for (b.slot) |*s| if (s.*) |*st| if (st.item == item and st.n < max) {
      const k = @min(left, max - st.n);
      st.n += k;
      left -= k;
      if (left == 0) return n;
    };
    for (b.slot) |*s| if (s.* == null) {
      const k = @min(left, max);
      s.* = .{.item = item, .n = k};
      left -= k;
      if (left == 0) return n;
    };
    return n - left;
  }

  pub fn count(b:Bag, item:Item) u32 { return countIn(b.slot, item); }

  /// removes exactly `n` or nothing.
  pub fn take(b:Bag, item:Item, n:u32) bool {
    if (b.count(item) < n) return false;
    var left = n;
    var i = b.slot.len;
    while (i > 0 and left > 0) {
      i -= 1;
      if (b.slot[i]) |*st| if (st.item == item) {
        const k:u16 = @intCast(@min(left, st.n));
        st.n -= k;
        left -= k;
        if (st.n == 0) b.slot[i] = null;
      };
    }
    return true;
  }
};

fn countIn(slot:[]const ?Stack, item:Item) u32 {
  var c:u32 = 0;
  for (slot) |s| if (s) |st| if (st.item == item) { c += st.n; };
  return c;
}

pub fn Inventory(comptime slots:usize) type {
  return struct {
    const Self = @This();
    slot:[slots]?Stack = @splat(null),

    pub fn bag(inv:*Self) Bag { return .{.slot = &inv.slot}; }
    pub fn add(inv:*Self, item:Item, n:u16) u16 { return inv.bag().add(item, n); }
    pub fn take(inv:*Self, item:Item, n:u32) bool { return inv.bag().take(item, n); }
    pub fn count(inv:*const Self, item:Item) u32 { return countIn(&inv.slot, item); }

    /// slots holding anything.
    pub fn used(inv:*const Self) usize {
      var c:usize = 0;
      for (inv.slot) |s| if (s != null) { c += 1; };
      return c;
    }

    /// every item held, whatever it is.
    pub fn total(inv:*const Self) u32 {
      var c:u32 = 0;
      for (inv.slot) |s| if (s) |st| { c += st.n; };
      return c;
    }

    /// 0..1, how full the inventory is (by stack fraction).
    pub fn fill(inv:*const Self) f32 {
      var f:f32 = 0;
      for (inv.slot) |s| if (s) |st| { f += m.ratio(st.n, st.item.info().stack); };
      return f / m.f(slots);
    }
  };
}

test "inventory stacks and takes" {
  var inv:Inventory(4) = .{};
  try testing.expectEqual(@as(u16, 70), inv.add(.grit, 70));
  try testing.expectEqual(@as(u32, 70), inv.count(.grit));
  try testing.expect(inv.take(.grit, 60));
  try testing.expectEqual(@as(u32, 10), inv.count(.grit));
  try testing.expect(!inv.take(.grit, 11));
  // 3 free slots of 20 starlight each
  try testing.expectEqual(@as(u16, 60), inv.add(.starlight, 200));
}
