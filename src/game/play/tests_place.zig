//! play tested: turning, picking, opening, removing and putting down.
const lib = @import("../../lib.zig");
const std = lib.std;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const ck = lib.ck;
const items = lib.items;
const Input = engine.platform.input.Input;
const ctl = lib.controls;
const DEFAULT_SEED = lib.play.DEFAULT_SEED;
const Game = lib.play.game.Game;
const Mode = lib.play.Mode;
const TEST_SCREEN = lib.play.tests_menu.TEST_SCREEN;
const TICK = lib.play.TICK;

/// headless: the mouse over the middle of tile `t`, as the camera sees it now
fn aim(g:*const Game, in:*Input, t:[2]i32, sc:[2]f32) void {
  const q = m.mulV(g.cam.viewProj(), .{m.f(t[0]) + 0.5, g.heightAt(t[0], t[1]), m.f(t[1]) + 0.5, 1});
  in.mouse = .{(q[0] / q[3] + 1) / 2 * sc[0], (q[1] / q[3] + 1) / 2 * sc[1]};
}

/// headless: one frame with `a` pressed (held down this frame only) over tile `t`
fn pressAt(g:*Game, in:*Input, t:[2]i32, a:ctl.Action) !void {
  aim(g, in, t, TEST_SCREEN);
  in.advance();
  ctl.hold(in, a, true);
  try g.update(in, TICK, TEST_SCREEN);
  in.advance();
  ctl.hold(in, a, false);
  try g.update(in, TICK, TEST_SCREEN);
}

test "R turns what is under the cursor (Shift back), Q picks its bulb, a click opens it, remove takes it up, held use puts one down" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  const x, const z = m.tileAt(g.player.pos);
  for (0..4) |dx| {
    const tx = x + 1 + @as(i32, @intCast(dx));
    const c = g.world.chunkOfTile(tx, z).?;
    const t = ck.localIndex(tx, z);
    c.kind[t] = .soil;
    c.res[t] = 0;
    c.occ[t] = .none;
  }
  const at = [2]i32{x + 2, z};
  try testing.expect(try g.structs.place(gpa, &g.world, at[0], at[1], .sap_cache, 0, 0));
  g.player.inv = .{};

  // R: a quarter clockwise, rooted, and not again until it has turned
  try pressAt(&g, &in, at, .rotate);
  const id = g.structs.at(&g.world, at[0], at[1]).?;
  try testing.expectEqual(@as(m.Dir, 1), g.structs.get(id).dir);
  try testing.expect(g.structs.get(id).turn.busy(g.time, true));
  try pressAt(&g, &in, at, .rotate);
  try testing.expectEqual(@as(m.Dir, 1), g.structs.get(id).dir);
  // the next thing put down keeps its own facing
  try testing.expectEqual(@as(m.Dir, 0), g.place_dir);
  // once turned, Shift+R turns it back
  g.time += lib.turn.TIME;
  ctl.hold(&in, .counter, true);
  try pressAt(&g, &in, at, .rotate);
  ctl.hold(&in, .counter, false);
  try testing.expectEqual(@as(m.Dir, 0), g.structs.get(id).dir);

  // Q: none in the belly, nothing to pick; with one, onto the hotbar
  try pressAt(&g, &in, at, .pick);
  try testing.expect(g.selected() == null);
  _ = g.player.inv.add(.sap_cache, 1);
  g.hot = 4;
  try pressAt(&g, &in, at, .pick);
  try testing.expectEqual(@as(?items.Item, .sap_cache), g.selected());
  try testing.expectEqual(@as(usize, 4), g.hot);

  // a click on it opens its panel, even with a bulb in hand
  try pressAt(&g, &in, at, .use);
  try testing.expectEqual(Mode.structure, g.mode);
  g.mode = .roam;
  // so does interact
  try pressAt(&g, &in, at, .interact);
  try testing.expectEqual(Mode.structure, g.mode);
  g.mode = .roam;

  // remove takes it up: its bulb comes back
  try pressAt(&g, &in, at, .remove);
  try testing.expect(g.structs.at(&g.world, at[0], at[1]) == null);
  try testing.expectEqual(@as(u32, 2), g.player.inv.count(.sap_cache));

  // held, use puts the bulb in hand down where it fits, turned as R left it
  g.place_dir = 3;
  aim(&g, &in, at, TEST_SCREEN);
  in.advance();
  ctl.hold(&in, .use, true);
  for (0..3) |_| try g.update(&in, TICK, TEST_SCREEN);
  ctl.hold(&in, .use, false);
  const put = g.structs.at(&g.world, at[0], at[1]) orelse return error.TestUnexpectedResult;
  try testing.expectEqual(@as(m.Dir, 3), g.structs.get(put).dir);
  try testing.expectEqual(@as(u32, 1), g.player.inv.count(.sap_cache));
}
