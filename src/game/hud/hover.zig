//! what is under the cursor, on a membrane beside it: a structure (its name
//! and what it is doing), a plant (its name, how far grown and what it
//! gives or draws) or a resource node; bare ground by the top-left, its kind
//! and ley.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const ck = lib.ck;
const species = lib.species;
const play = lib.play;
const st = lib.structures;
const resources = lib.resources;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const txt = lib.txt;

/// bare ground's panel, by the top-left
const panel_x = s.edge;
const panel_y:f32 = 104;
const text_x:f32 = 32;
const text_top:f32 = 116;
/// the card beside the cursor: how far off it, its widths (a structure's
/// line of work is wider), margin, line height, and how far it keeps from
/// the screen's edges
const offset = [2]f32{24, 20};
const card_w:f32 = 400;
const plant_w:f32 = 360;
const node_w:f32 = 240;
const margin:f32 = 14;
const line_h:f32 = 24;
const keep:f32 = 8;
/// where "too far" sits on the name's line, from the card's right
const far_x:f32 = 96;

/// (a structure's open panel shows all of this itself; a HUD panel under
/// the cursor has its own)
pub fn visible(g:*const play.Game) bool { return g.hover != null and g.mode != .structure and g.pointed == null; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const h = g.hover.?;
  const c = g.world.chunkOfTile(h[0], h[1]) orelse return;
  const near = g.player.inReach(h[0], h[1]);
  if (g.structs.at(&g.world, h[0], h[1])) |j| return structure(g, d, W, H, g.structs.get(j), near);
  if (g.plants.at(&g.world, h[0], h[1])) |i| return plant(g, d, W, H, i, near);
  const t = ck.localIndex(h[0], h[1]);
  if (c.res[t] > 0 and c.occ[t] == .none) {
    const item = resources.of(c.kind[t]).?.item;
    const at = try card(g, d, W, H, node_w, 1, near);
    _ = try d.print(at[0], at[1], s.text_label, item.info().col, txt.s.hud.node, .{txt.item(item).name, c.res[t]});
    return;
  }
  try d.membrane(panel_x, panel_y, 360, 60, s.skin, 0.6);
  _ = try d.print(text_x, text_top, s.text_label, s.white, txt.s.hud.tile, .{txt.tile(c.kind[t]), c.ley_cap[t]});
  if (!near) _ = try d.text(text_x + 248, text_top + 2, s.text_note, s.dim, txt.s.hud.too_far);
}

/// a card `w` wide and `lines` lines high beside the cursor, kept on
/// screen; returns where its first line goes. Out of reach, it says so.
fn card(g:*const play.Game, d:*Draw, W:f32, H:f32, w:f32, lines:f32, near:bool) Allocator.Error![2]f32 {
  const ch = line_h * lines + 2 * margin;
  const x = @max(@min(g.mouse[0] + offset[0], W - w - keep), keep);
  const y = @max(@min(g.mouse[1] + offset[1], H - ch - keep), keep);
  try d.membrane(x, y, w, ch, s.skin, 0.7);
  if (!near) _ = try d.text(x + w - far_x, y + margin + 2, s.text_note, s.dim, txt.s.hud.too_far);
  return .{x + margin, y + margin};
}

fn structure(g:*play.Game, d:*Draw, W:f32, H:f32, sp:*const st.Structure, near:bool) Allocator.Error!void {
  const opens = sp.def().store;
  const at = try card(g, d, W, H, card_w, if (opens) 3 else 2, near);
  _ = try d.text(at[0], at[1], s.text_label, s.gold, txt.structure(sp.kind()));
  try st.describe(sp, d, &g.prog, at[0], at[1] + line_h);
  if (opens) _ = try d.text(at[0], at[1] + 2 * line_h, s.text_note, if (near) s.gold else s.dim, txt.s.hud.open_hint);
}

fn plant(g:*play.Game, d:*Draw, W:f32, H:f32, i:ck.PlantId, near:bool) Allocator.Error!void {
  const p = g.plants.list.get(i.idx());
  const def = species.get(p.sp);
  const rad = &g.eco.radiance;
  const known = i.idx() < rad.powered.items.len;
  // a bloom waiting on its network, or a plant that draws radiance, says so
  const waits = (def.radiance > 0 and !(known and rad.radiating.items[i.idx()])) or def.needs_radiance;
  const at = try card(g, d, W, H, plant_w, if (waits) 4 else 3, near);
  const x = at[0];
  var y = at[1];
  _ = try d.text(x, y, s.text_label, s.white, txt.plant(p.sp).name);
  y += line_h;
  try d.tendril(x, y + 4, 140, s.bar_h, s.growth, p.growth, 0.5);
  if (def.stages > 0) {
    const k = def.stage(p.growth);
    const name = txt.nth(txt.plant(p.sp).stages orelse "", k);
    _ = try d.print(x + 152, y, s.text_note, s.dim, txt.s.hud.stage, .{name, k + 1, def.stages, p.growth * 100});
  } else {
    _ = try d.print(x + 152, y, s.text_note, s.dim, txt.s.hud.growth, .{p.growth * 100});
  }
  y += line_h;
  if (def.radiance > 0) {
    // a bloom: it yields nothing; it radiates, or waits on its network
    var links:u32 = 0;
    for (rad.links.items) |l| {
      if (l.a == i or l.b == i) links += 1;
    }
    const lit = known and rad.radiating.items[i.idx()];
    _ = try d.print(x, y, s.text_body, if (lit) s.gold else s.dim, txt.s.hud.bloom, .{if (lit) txt.s.hud.radiating else txt.s.hud.dark, links, p.health * 100});
    if (!lit) _ = try d.text(x, y + line_h, s.text_note, s.dim, txt.s.hud.no_mature);
    return;
  }
  const yields = if (g.prog.yieldKnown(p.sp)) txt.item(def.yields).short else txt.s.hud.unknown_yield;
  _ = try d.print(x, y, s.text_body, s.gold, txt.s.hud.plant, .{yields, p.essence, p.health * 100});
  if (def.needs_radiance) {
    const lit = known and rad.powered.items[i.idx()];
    _ = try d.text(x, y + line_h, s.text_note, if (lit) s.gold else s.dim, if (lit) txt.s.hud.drawing_radiance else txt.s.hud.withering);
  }
}

