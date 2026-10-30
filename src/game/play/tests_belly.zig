//! play tested: a germinator's panel, carrying and discarding stacks.
const lib = @import("../../lib.zig");
const std = lib.std;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const ck = lib.ck;
const items = lib.items;
const Input = engine.platform.input.Input;
const ctl = lib.controls;
const craft = lib.craft;
const st = lib.structures;
const hud = lib.hud;
const DEFAULT_SEED = lib.play.DEFAULT_SEED;
const Game = lib.play.game.Game;
const Mode = lib.play.Mode;
const TEST_SCREEN = lib.play.tests_menu.TEST_SCREEN;
const TICK = lib.play.TICK;
const click = lib.play.tests_menu.click;

test "a germinator's panel: choose its seed, put in only what it weaves from, move stacks across" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  const screen = TEST_SCREEN;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  const x, const z = m.tileAt(g.player.pos);
  var fp = m.footprint(x + 1, z, 2);
  while (fp.next()) |p| {
    const c = g.world.chunkOfTile(p[0], p[1]).?;
    const t = ck.localIndex(p[0], p[1]);
    c.kind[t] = .soil;
    c.res[t] = 0;
    c.occ[t] = .none;
  }
  try testing.expect(try g.structs.place(gpa, &g.world, x + 1, z, .germinator, 0, 0));
  const id = g.structs.at(&g.world, x + 1, z).?;
  g.player.inv = .{};
  g.player.inv.slot[0] = .{.item = .fibre, .n = 30};
  g.player.inv.slot[1] = .{.item = .grit, .n = 5};
  g.mode = .structure;
  g.open = .{x + 1, z};
  try testing.expect(g.opened() != null);

  // set to thornleech, it takes no fibre: the stack stays in hand
  const thorn = for (craft.seeds) |r| {
    if (craft.hand[r].out == .seed_thornleech) break r;
  } else unreachable;
  try click.on(&g, &in, hud.row(.structure, .{.recipe = thorn}), screen);
  try testing.expectEqual(@as(?u8, thorn), st.chosen(g.structs.get(id)));
  try click.on(&g, &in, hud.row(.belly, .{.slot = 0}), screen);
  try click.on(&g, &in, hud.row(.belly, .{.store = 0}), screen);
  try testing.expect(g.holds(.{.slot = 0}));
  try testing.expect(g.structs.get(id).inv.slot[0] == null);
  try click.on(&g, &in, .panel, screen);
  // grit it takes, the whole stack
  try click.on(&g, &in, hud.row(.belly, .{.slot = 1}), screen);
  try click.on(&g, &in, hud.row(.belly, .{.store = 2}), screen);
  try testing.expectEqual(@as(u32, 5), g.structs.get(id).inv.count(.grit));
  try testing.expect(g.held == null and g.player.inv.slot[1] == null);
  // a locked seed is not chosen
  const vesper = for (craft.seeds) |r| {
    if (craft.hand[r].out == .seed_vesper) break r;
  } else unreachable;
  try click.on(&g, &in, hud.row(.structure, .{.recipe = vesper}), screen);
  try testing.expectEqual(@as(?u8, thorn), st.chosen(g.structs.get(id)));
  // back to lumenroot: fibre goes in up to what it stocks, the rest in hand
  try click.on(&g, &in, hud.row(.structure, .{.recipe = craft.seeds[0]}), screen);
  try click.on(&g, &in, hud.row(.belly, .{.slot = 0}), screen);
  try click.on(&g, &in, hud.row(.belly, .{.store = 0}), screen);
  try testing.expectEqual(@as(u32, 20), g.structs.get(id).inv.count(.fibre));
  try testing.expectEqual(@as(u32, 10), g.player.inv.count(.fibre));
  try click.on(&g, &in, .panel, screen);
  // with take held, a click moves a stack straight back
  ctl.hold(&in, .take, true);
  try click.on(&g, &in, hud.row(.belly, .{.store = 2}), screen);
  ctl.hold(&in, .take, false);
  try testing.expectEqual(@as(u32, 5), g.player.inv.count(.grit));
  try testing.expectEqual(@as(u32, 0), g.structs.get(id).inv.count(.grit));
  // out of reach, the panel closes
  g.player.pos += m.v3(40, 0, 0);
  try g.update(&in, TICK, screen);
  try testing.expectEqual(Mode.roam, g.mode);
}

test "a click lifts a stack, the next puts it down; dropped on the hotbar it assigns" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  const screen = TEST_SCREEN;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  for (g.bar) |b| try testing.expect(b == null);
  g.mode = .belly;
  g.player.inv = .{};
  g.player.inv.slot[0] = .{.item = .fibre, .n = 30};
  g.player.inv.slot[1] = .{.item = .conduit, .n = 3};
  g.player.inv.slot[2] = .{.item = .fibre, .n = 80};

  // sort by hand: into an empty slot, then trade places
  try click.on(&g, &in, hud.row(.belly, .{.slot = 0}), screen);
  try testing.expectEqual(@as(?items.Item, .fibre), g.carried());
  try click.on(&g, &in, hud.row(.belly, .{.slot = 5}), screen);
  try testing.expect(g.held == null and g.player.inv.slot[0] == null);
  try testing.expectEqual(@as(u16, 30), g.player.inv.slot[5].?.n);
  try click.on(&g, &in, hud.row(.belly, .{.slot = 5}), screen);
  try click.on(&g, &in, hud.row(.belly, .{.slot = 1}), screen);
  try testing.expectEqual(items.Item.fibre, g.player.inv.slot[1].?.item);
  try testing.expectEqual(items.Item.conduit, g.player.inv.slot[5].?.item);
  // onto a stack of the same: as much as fits, the rest stays in hand
  try click.on(&g, &in, hud.row(.belly, .{.slot = 1}), screen);
  try click.on(&g, &in, hud.row(.belly, .{.slot = 2}), screen);
  try testing.expectEqual(items.STACK, g.player.inv.slot[2].?.n);
  try testing.expectEqual(@as(u16, 10), g.player.inv.slot[1].?.n);
  try testing.expect(g.holds(.{.slot = 1}));
  try click.on(&g, &in, hud.row(.belly, .{.slot = 1}), screen);
  try testing.expect(g.held == null);

  // onto the hotbar: the slot takes the item, the stack stays in the belly
  try click.on(&g, &in, hud.row(.belly, .{.slot = 5}), screen);
  try click.on(&g, &in, hud.row(.hotbar, .{.slot = 3}), screen);
  try testing.expectEqual(@as(?items.Item, .conduit), g.bar[3]);
  try testing.expectEqual(@as(u32, 3), g.player.inv.count(.conduit));
  // hotbar items trade places, and come off when dropped elsewhere
  try click.on(&g, &in, hud.row(.hotbar, .{.slot = 3}), screen);
  try click.on(&g, &in, hud.row(.hotbar, .{.slot = 0}), screen);
  try testing.expect(g.bar[3] == null and g.bar[0] == .conduit);
  g.mode = .roam;
  try click.on(&g, &in, hud.row(.hotbar, .{.slot = 0}), screen);
  try testing.expectEqual(@as(?items.Item, .conduit), g.selected());
  g.mode = .belly;
  try click.on(&g, &in, hud.row(.hotbar, .{.slot = 0}), screen);
  try click.on(&g, &in, .panel, screen);
  try testing.expect(g.bar[0] == null and g.selected() == null);
}

test "discard throws away a belly stack, hovered or carried, never a structure's" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  const screen = TEST_SCREEN;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  g.mode = .belly;
  g.player.inv = .{};
  g.player.inv.slot[0] = .{.item = .fibre, .n = 30};
  g.player.inv.slot[1] = .{.item = .grit, .n = 7};
  g.bar[0] = .grit;

  // under the cursor
  try click.press(&g, &in, hud.row(.belly, .{.slot = 0}), screen, .discard);
  try testing.expect(g.player.inv.slot[0] == null);
  try testing.expectEqual(@as(u32, 7), g.player.inv.count(.grit));
  // carried: lifted, then thrown away wherever the cursor is
  try click.on(&g, &in, hud.row(.belly, .{.slot = 1}), screen);
  try click.press(&g, &in, hud.row(.hotbar, .{.slot = 0}), screen, .discard);
  try testing.expect(g.held == null and g.player.inv.used() == 0);
  // the hotbar keeps its item; with the belly closed nothing goes
  try testing.expectEqual(@as(?items.Item, .grit), g.bar[0]);
  g.player.inv.slot[2] = .{.item = .fibre, .n = 5};
  g.mode = .roam;
  in.advance();
  ctl.hold(&in, .discard, true);
  try g.update(&in, TICK, screen);
  try testing.expectEqual(@as(u32, 5), g.player.inv.count(.fibre));
}
