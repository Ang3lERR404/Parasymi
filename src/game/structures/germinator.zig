//! GERMINATOR: weaves seeds by itself from what it is fed, running the same
//! recipes the wolf weaves by hand (only the seed ones), at its own pace.
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const prog = @import("../progression.zig");
const craft = @import("../craft.zig");
const style = @import("../style.zig");
const Draw = @import("../../ui/draw.zig").Draw;

pub const def:st.Def = .{ .name = "GERMINATOR", .item = .germinator, .size = 2, .mesh = .germinator, .sway = 0.9, .tall = 1.05, .grow = 6 };

/// weave speed multiplier relative to hand-weaving
const SPEED:f32 = 0.6;
/// most of one ingredient it will hold
const STOCK = 20;

pub const State = struct {
  /// which recipe (index into craft.hand) it weaves
  recipe:u8 = 0,
  weave:craft.Crafter = .{},
};

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  const g = &self.state.germinator;
  const r = craft.hand[g.recipe];
  if (!g.weave.busy() and r.unlocked(ctx.g) and craft.Crafter.can(self.inv.bag(), r)) _ = g.weave.push(self.inv.bag(), g.recipe);
  _ = g.weave.tick(self.inv.bag(), dt * SPEED);
  return g.weave.busy();
}

pub fn wants(s:*const st.Structure, _:*const prog.Progression, item:items.Item) u32 {
  for (craft.hand[s.state.germinator.recipe].in) |ing| {
    if (ing.item == item) return STOCK -| s.inv.count(item);
  }
  return 0;
}

/// only finished weaves leave.
pub fn output(s:*const st.Structure) ?items.Item {
  const out = craft.hand[s.state.germinator.recipe].out;
  return if (s.inv.count(out) > 0) out else null;
}

/// cycle through the seed recipes the gardener understands.
pub fn configure(s:*st.Structure, g:*prog.Progression) void {
  const gs = &s.state.germinator;
  if (gs.weave.busy()) return;
  var r = gs.recipe;
  for (0..craft.hand.len) |_| {
    r = @intCast((r + 1) % craft.hand.len);
    if (craft.isSeedRecipe(r) and craft.hand[r].unlocked(g)) break;
  }
  gs.recipe = r;
  g.say("GERMINATOR NOW WEAVES {s}", .{craft.hand[r].out.info().name});
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const gs = &s.state.germinator;
  _ = try d.print(x, y, 1.4, style.white, "WEAVES {s} (C)", .{craft.hand[gs.recipe].out.info().name});
  try d.tendril(x + 250, y + 2, 110, 12, style.gold, gs.weave.progress(), 0.3);
}

// a fresh germinator starts on recipe 0, which must be a seed weave
comptime { assert(craft.isSeedRecipe(0)); }