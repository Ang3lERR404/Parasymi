//! the hotbar: a row of husks hanging from a vine, each empty or holding an item the gardener
//! dropped on it from the belly, with the belly's count of it and the
//! selection's name. Click selects; with the belly open, click lifts and
//! puts down.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const m = lib.engine.core.math;
const play = lib.play;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const txt = lib.txt;
const st = lib.structures;
const items = lib.items;
const icon = lib.icon;
const belly = lib.hud_belly;
const Slot = lib.hud_slot.Slot;
const hud = lib.hud;
const Input = lib.engine.platform.input.Input;

const gap = s.slot_gap;
const pod_r:f32 = 20;
const pod_r_sel:f32 = 24;
const glow_alpha:u8 = 110;
/// how see-through a seed not yet understood is
const unknown_alpha:u8 = 110;
/// the vine's seed and growth key
const vine_seed:f32 = 5.5;
/// the selection's name sits this far above the husks, clear of the vine
const label_up:f32 = 70;

/// a hotbar slot
pub const Pick = union(enum) { slot:usize };

/// with the belly's slots open a slot lifts and puts down, else it is
/// selected; the other button takes its item off. Not while the world is
/// frozen.
pub fn click(g:*play.Game, p:Pick, press:hud.Press, _:*const Input) void {
  if (!g.mode.live()) return;
  const i = switch (p) { .slot => |i| i };
  switch (press) {
    .use => if (g.mode.sorting()) g.clickBar(i) else { g.hot = i; },
    .remove => g.bar[i] = null,
    .discard => {},
  }
}

/// its item (not one lifted from it)
pub fn shows(g:*const play.Game, p:Pick) ?items.Item {
  const i = switch (p) { .slot => |i| i };
  return if (g.holds(.{.bar = i})) null else g.bar[i];
}

/// whether placing `item` puts down a structure that faces a way (R turns it).
fn turns(item:items.Item) bool {
  const k = st.kindOf(item) orelse return false;
  return st.defs.get(k).carrier;
}

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const n = play.BAR;
  const x0 = W / 2 - gap * m.f(n - 1) / 2;
  const hy = H - 86;
  const t = g.uiT();
  const vine = belly.rowVine(d, x0 - gap / 2, hy, n, vine_seed);
  try vine.draw(d, t);

  for (g.bar, 0..) |slot, i| {
    const x = x0 + gap * m.f(i);
    const sel = i == g.hot;
    // lifted onto the cursor, it is shown there instead
    const item = if (g.holds(.{.bar = i})) null else slot;
    const col = if (item) |it| it.info().col else s.gold;
    var sl = Slot.around(.{x, hy}, gap, gap, hud.row(.hotbar, .{.slot = i}),(if (sel) pod_r_sel else pod_r) / gap);
    sl.grown = vine.reached(x);
    sl.lit = if (sel) 1 else 0.25;
    sl.halo = if (sel) .{col[0], col[1], col[2], glow_alpha} else null;
    sl.phase = m.f(i) * 0.37;
    _ = try d.text(x - 4, hy + 28, s.text_small, s.dim, txt.nth(txt.s.hud.hotbar_keys, i));
    if (!try sl.draw(g, d)) continue;
    const it = item orelse continue;
    const alpha = if (play.known(g, it)) 255 else unknown_alpha;
    try icon.draw(d, it, sl.center(), sl.radius(), t, sl.phase, if (sel) 1 else 0.6, alpha);
    try icon.count(d, sl.center(), sl.radius(), g.player.inv.count(it));
  }

  const item = g.selected() orelse return;
  var buf:[64]u8 = undefined;
  const name = txt.item(item).name;
  const label = if (!play.known(g, item)) txt.s.hud.not_understood
    else if (turns(item)) txt.bufRender(&buf, txt.s.hud.facing_label, .{name, txt.nth(txt.s.hud.facing, g.place_dir)})
    else name;
  _ = try d.text(W / 2 - Draw.width(label, s.text_sub) / 2, hy - label_up, s.text_sub, s.gold, label);
}
