//! GERMINATOR: weaves seeds by itself from what it is fed, running the same
//! recipes the wolf weaves by hand (only the seed ones), at its own pace.
const std = @import("std");
const m = @import("../../core/math.zig");
const assert = std.debug.assert;
const indexOfScalar = std.mem.indexOfScalar;
const Allocator = std.mem.Allocator;
const items = @import("../../sim/items.zig");
const st = @import("../structures.zig");
const icon_kit = @import("../icon.zig");
const txt = @import("../text.zig");
const prog = @import("../progression.zig");
const craft = @import("../craft.zig");
const style = @import("../style.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const Color = @import("../../ui/draw.zig").Color;

pub const def:st.Def = .{ .item = .germinator, .size = 2, .mesh = .germinator, .store = true, .sway = 0.9, .tall = 1.05, .grow = 6 };

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

/// only finished weaves leave: any seed, so one woven before the recipe
/// was changed still goes.
pub fn output(s:*const st.Structure) ?items.Item {
  for (s.inv.slot) |slot| if (slot) |it| if (it.item.plants() != null) return it.item;
  return null;
}

/// its panel offers every seed weave.
pub fn recipes() []const u8 { return &craft.seeds; }
pub fn chosen(s:*const st.Structure) ?u8 { return s.state.germinator.recipe; }

/// set the seed it weaves, if the gardener understands it. A weave under
/// way finishes first (its ingredients are already in it).
pub fn choose(s:*st.Structure, g:*prog.Progression, r:u8) void {
  assert(craft.isSeedRecipe(r));
  const out = txt.item(craft.hand[r].out).name;
  if (!craft.hand[r].unlocked(g)) return g.say(txt.s.msg.not_understood, .{out});
  if (s.state.germinator.recipe == r) return;
  s.state.germinator.recipe = r;
  g.say(txt.s.msg.germinator_weaves, .{out});
}

/// cycle through the seed recipes the gardener understands.
pub fn configure(s:*st.Structure, g:*prog.Progression) void {
  const at = indexOfScalar(u8, &craft.seeds, s.state.germinator.recipe) orelse 0;
  for (1..craft.seeds.len + 1) |k| {
    const r = craft.seeds[(at + k) % craft.seeds.len];
    if (craft.hand[r].unlocked(g)) return choose(s, g, r);
  }
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const gs = &s.state.germinator;
  _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.weaves, .{txt.item(craft.hand[gs.recipe].out).name});
  try d.tendril(x + style.desc_bar_x, y + 2, style.desc_bar_w, style.bar_h, style.gold, gs.weave.progress(), 0.3);
}

// a fresh germinator starts on recipe 0, which must be a seed weave
comptime { assert(craft.isSeedRecipe(0)); }

/// its bulb: a sprout whose two cupped leaves cradle a new seed (it weaves seeds).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  try ic.stem(.{.{0, icon_kit.TOP}, .{0, 0.3}, .{0.06, 0.4}, .{0, 0.5}}, 0.11, icon_kit.stem_col);
  try ic.glow(.{0, 0.72}, 0.28, icon_glow);
  try ic.kernel(.{0, 0.74}, 0.42, icon_seed);
  try ic.leaf(.{0, 0.48}, 0.4, 0.46, 0.3, icon_kit.sprout, 0.55);
  try ic.leaf(.{0, 0.48}, m.pi - 0.4, 0.46, 0.3, icon_kit.sprout, 0.55);
  try ic.coat(col);
}
const icon_seed:Color = .{120, 240, 220, 255};
const icon_glow:Color = .{150, 255, 200, 70};
