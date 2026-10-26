//! DRIFTBRAID: a braided conduit and a sporecaster grown into one, that
//! trades both ways. Paired with another driftbraid (the configure key on
//! it, then on the other), each turns what it is fed into spore carriers
//! drifting, however far, into the other's pore, and takes in what the
//! other sends. What came by spore is kept apart from what it was fed: it
//! sends on only what it was fed, and lets go (to its neighbours, or to
//! conduits pulling) only what came by spore, so nothing is sent straight
//! back. Spores behave as a sporecaster's: one whose driftbraid is gone
//! turns home, one whose driftbraid is full hangs over it.
// decision: what came by spore is a count per kind over the one inventory
// (`kept`), not slots of its own: items leave a structure through its
// inventory alone. A count it has lost track of (the gardener lifting it
// out by hand, a conduit pulling) is trimmed to what is there each tick.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const EnumArray = std.enums.EnumArray;
const testing = std.testing;
const m = lib.engine.core.math;
const color = lib.engine.core.color;
const ck = lib.ck;
const World = lib.world.World;
const items = lib.items;
const Plants = lib.plants.Plants;
const st = lib.structures;
const icon_kit = lib.icon;
const txt = lib.txt;
const prog = lib.progression;
const style = lib.style;
const Parts = lib.parts.Parts;
const Look = lib.parts.Look;
const Draw = lib.engine.ui.draw.Draw;
const Color = lib.engine.ui.draw.Color;
const mesh = lib.driftbraid;
const caster = lib.sporecaster_structure;

const V3 = m.V3;
const v3 = m.v3;

/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .belly_lump, .spore_carrier };

/// paired both ways: each trades with the other
pub const pairs:st.Pairs = .{ .way = .both_ways };

pub const def:st.Def = .{ .item = .driftbraid, .size = 1, .mesh = .driftbraid, .store = true, .grow = 7, .sway = 0.4, .tall = 0.9, .sap = 0.3, .far = true };

/// most it holds, fed and received together; spores as a sporecaster's
pub const HOLD = 40;
const LOAD = caster.LOAD;
const LAUNCH = caster.LAUNCH;
const AIR = caster.AIR;
const SPEED = caster.SPEED;
const SPORE_FADE:f32 = 0.35;
const SPORE_GLOW:f32 = 0.6;
const SPORE_SIZE:f32 = 1.7;
const HANG:f32 = 0.35;
/// what it holds hangs in its sac, in a ring, bobbing
const RING:f32 = 0.45;
const LUMP_R:f32 = 0.02;
const LUMP_GROW:f32 = 0.02;
const BOB:f32 = 0.01;
const TURN:f32 = 0.25;
const GLOW:f32 = 0.2;

pub const State = struct {
  spores:[AIR]?caster.Spore = @splat(null),
  t:f32 = 0,
  /// how many of each kind it holds came by spore
  kept:EnumArray(items.Item, u16) = .initFill(0),
};

fn braidAt(ss:*st.Structures, w:*const World, at:[2]i32) ?st.Id {
  const j = ss.at(w, at[0], at[1]) orelse return null;
  return if (ss.get(j).kind() == .driftbraid) j else null;
}

/// pair it (`pairStep`): the first configured waits, the next trades with
/// it, both ways (each leaving whatever it traded with before). Configured
/// twice over, it stops trading.
pub fn configure(ss:*st.Structures, id:st.Id, g:*prog.Progression) void {
  switch (ss.pairStep(id)) {
    .waiting => g.say(txt.s.msg.braid_choose, .{}),
    .cut => g.say(txt.s.msg.braid_still, .{}),
    .paired => g.say(txt.s.msg.braid_paired, .{}),
  }
}

/// what it holds of `item` that it was fed (and may send)
fn fed(s:*const st.Structure, item:items.Item) u32 { return s.inv.count(item) -| s.state.driftbraid.kept.get(item); }

/// hand one of what came by spore to a neighbour that wants it
fn handReceived(ctx:st.Ctx, i:st.Id) void {
  const self = ctx.ss.get(i);
  const item = output(self) orelse return;
  for (m.dirs) |d| {
    const v = m.dirVec(d);
    const j = ctx.ss.at(ctx.w, self.x + v.x, self.y + v.z) orelse continue;
    if (j == i or ctx.ss.get(j).def().carrier) continue;
    if (ctx.ss.insert(ctx.g, j, item, 1) == 1) {
      _ = self.inv.take(item, 1);
      self.state.driftbraid.kept.getPtr(item).* -= 1;
      return;
    }
  }
}

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  {
    const self = ctx.ss.get(i);
    var it = self.state.driftbraid.kept.iterator();
    while (it.next()) |e| e.value.* = @min(e.value.*, self.inv.count(e.key));
  }
  handReceived(ctx, i);
  const self = ctx.ss.get(i);
  const db = &self.state.driftbraid;
  var busy = false;
  for (&db.spores) |*slot| {
    const sp = &(slot.* orelse continue);
    busy = true;
    const far = @max(m.len(m.v3(m.f(sp.to[0] - self.x), 0, m.f(sp.to[1] - self.y))), 1);
    if (sp.home) {
      sp.t -= dt * SPEED / far;
      if (sp.t > 0) continue;
      // back home it is what it was fed again
      _ = self.inv.add(sp.item, sp.n);
      slot.* = null;
      continue;
    }
    if (sp.t < 1) {
      sp.t = @min(1, sp.t + dt * SPEED / far);
      continue;
    }
    const j = braidAt(ctx.ss, ctx.w, sp.to) orelse {
      sp.home = true;
      continue;
    };
    const took = ctx.ss.insert(ctx.g, j, sp.item, sp.n);
    ctx.ss.get(j).state.driftbraid.kept.getPtr(sp.item).* += took;
    sp.n -= @intCast(took);
    if (sp.n == 0) slot.* = null;
  }
  if (ctx.ss.getPartner(i) == null) return busy;
  const to = self.partner().?.tile();
  sc: {
    db.t += dt;
    if (db.t < LAUNCH) break :sc;
    // the kind it was fed most of, a load of it
    var best:?items.Item = null;
    var most:u32 = 0;
    for (self.inv.slot) |s| if (s) |it| {
      const n = fed(self, it.item);
      if (n > most) {
        most = n;
        best = it.item;
      }
    };
    const item = best orelse break :sc;
    for (&db.spores) |*slot| {
      if (slot.* != null) continue;
      const n:u8 = @intCast(@min(most, LOAD));
      _ = self.inv.take(item, n);
      slot.* = .{.item = item, .n = n, .to = to, .to_h = caster.groundAt(ctx.w, to)};
      db.t = 0;
      busy = true;
      break;
    }
  }
  return busy;
}

/// uprooted: what its spores carry comes back into its slots with them.
pub fn release(s:*st.Structure) ?items.Item {
  for (&s.state.driftbraid.spores) |*slot| if (slot.*) |sp| {
    _ = s.inv.add(sp.item, sp.n);
    slot.* = null;
  };
  return null;
}

/// anything, while it has room.
pub fn wants(s:*const st.Structure, _:*const prog.Progression, _:items.Item) u32 { return HOLD -| s.inv.total(); }

/// the first thing it holds that came by spore.
pub fn output(s:*const st.Structure) ?items.Item {
  for (s.inv.slot) |slot| if (slot) |it| if (s.state.driftbraid.kept.get(it.item) > 0) return it.item;
  return null;
}
pub fn gives(s:*const st.Structure, item:items.Item) bool { return s.state.driftbraid.kept.get(item) > 0 and s.inv.count(item) > 0; }

/// its spores drifting over (or home), and what it holds hanging in its sac.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  const db = &s.state.driftbraid;
  const base = s.place(ctr);
  const pore = m.mulPoint(base, mesh.PORE);
  for (db.spores, 0..) |slot, k| {
    const sp = slot orelse continue;
    const dest = m.footprintCentre(sp.to[0], sp.to[1], 1, sp.to_h) + mesh.PORE;
    const ph = s.seed + m.f(k) * 0.37;
    const at = caster.flight(pore, dest, sp.t, ph, tf);
    const ahead = caster.flight(pore, dest, if (sp.home) sp.t - 0.02 else sp.t + 0.02, ph, tf);
    const hang = if (!sp.home and sp.t >= 1) v3(0, HANG + 0.05 * @sin(tf * 2 + m.f(k)), 0) else v3(0, 0, 0);
    const dir = if (m.len(ahead - at) > m.EPS) m.norm(ahead - at) else v3(0, 1, 0);
    const col = color.Rgba8.of(sp.item.info().col).toF4();
    try out.emit(.spore_carrier, m.chain(&.{m.translate(at + hang), m.alignY(dir), m.scale3(m.splat3(SPORE_SIZE))}), .{
      .glow = SPORE_GLOW, .phase = ph, .fade = SPORE_FADE, .tint = .{col[0], col[1], col[2], 0}, .flutter = 0.5,
    });
  }
  if (s.grown < 1) return;
  var n:usize = 0;
  for (s.inv.slot) |slot| { if (slot != null) n += 1; }
  var j:usize = 0;
  for (s.inv.slot) |slot| {
    const it = slot orelse continue;
    const a = m.ratio(j, n) * m.tau + tf * TURN + s.seed * 6;
    const ring = if (n == 1) 0 else mesh.SAC_R[0] * RING;
    const at = mesh.SAC_AT + v3(@cos(a) * ring, BOB * @sin(tf * 1.2 + m.f(j) * 2), @sin(a) * ring);
    const r = LUMP_R + LUMP_GROW * m.ratio(it.n, HOLD);
    try out.emit(.belly_lump, m.mul(base, m.chain(&.{m.translate(at), m.scale3(m.splat3(r))})), Look{
      .glow = GLOW, .phase = s.seed, .tint = color.Rgba8.of(it.item.info().col).toF4(),
      .sway = def.sway, .tall = def.tall, .drop = at[1],
    });
    j += 1;
  }
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const db = &s.state.driftbraid;
  var air:u32 = 0;
  for (db.spores) |sp| { if (sp != null) air += 1; }
  var got:u32 = 0;
  for (db.kept.values) |n| got += n;
  if (s.partner()) |p| {
    const to = p.tile();
    _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.trades, .{to[0] - s.x, to[1] - s.y, air, s.inv.total() -| got, got, HOLD});
  } else {
    _ = try d.print(x, y, style.text_body, style.dim, txt.s.describe.untraded, .{s.inv.total(), HOLD});
  }
}

/// its bulb: a twined stalk out of the seed holding a sac, spores drifting
/// off it one way and back into it the other (it trades both ways).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  for ([_]f32{1, -1}, [_]Color{icon_green, icon_pale}) |way, c| {
    try ic.stem(.{.{-0.1, icon_kit.TOP}, .{-0.1 + 0.08 * way, 0.25}, .{-0.1 - 0.08 * way, 0.45}, .{-0.1, 0.58}}, 0.07, c);
  }
  try ic.glow(.{-0.1, 0.72}, 0.25, icon_sac_glow);
  try ic.bud(.{-0.1, 0.72}, 0.17, icon_sac, 0.4);
  for ([_]f32{-1, 1}) |sx| try ic.stem(.{.{-0.1, 0.86}, .{-0.1 + 0.18 * sx, 0.98}, .{-0.1 + 0.3 * sx, 0.9}, .{-0.1 + 0.28 * sx, 0.78}}, 0.04, icon_frond);
  const out = [4]icon_kit.P{.{-0.1, 0.9}, .{0.2, 1.1}, .{0.6, 0.9}, .{0.75, 0.3}};
  const back = [4]icon_kit.P{.{0.8, 0.2}, .{0.75, 0.75}, .{0.35, 0.7}, .{0, 0.78}};
  for (0..2) |k| {
    const t = @mod(ic.t * 0.5 + ic.phase + m.f(k) / 2, 1);
    try ic.bud(icon_kit.curve(out, t), 0.055, icon_spore, @sin(t * m.pi));
    try ic.bud(icon_kit.curve(back, t), 0.05, icon_spore_back, @sin(t * m.pi));
  }
  try ic.coat(col);
}
const icon_green:Color = .{80, 150, 95, 255};
const icon_pale:Color = .{185, 180, 205, 255};
const icon_frond:Color = .{175, 160, 210, 255};
const icon_sac:Color = .{220, 150, 110, 210};
const icon_sac_glow:Color = .{170, 140, 230, 70};
const icon_spore:Color = .{235, 225, 255, 255};
const icon_spore_back:Color = .{245, 200, 140, 255};

// ---- tests ----

const TEST_DT:f32 = 0.05;

fn fixture(w:*World) !void {
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..30) |x| for (0..2) |y| {
    const t = y * ck.SIZE + x;
    c.kind[t] = .soil;
    c.height[t] = 1;
    c.res[t] = 0;
  };
}

fn run(ss:*st.Structures, w:*World, plants:*Plants, g:*prog.Progression, seconds:f32) !void {
  var t:f32 = 0;
  while (t < seconds) : (t += TEST_DT) try ss.tick(testing.allocator, w, plants, g, TEST_DT);
}

test "driftbraids pair both ways and trade what each is fed, never sending it back" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 0, 0, .driftbraid, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 26, 1, .driftbraid, 0, 0));
  const a = ss.at(&w, 0, 0).?;
  const b = ss.at(&w, 26, 1).?;
  st.configure(&ss, a, &g);
  st.configure(&ss, b, &g);
  try testing.expectEqual(b, ss.getPartner(a).?);
  try testing.expectEqual(a, ss.getPartner(b).?);
  _ = ss.insert(&g, a, .essence, 12);
  _ = ss.insert(&g, b, .grit, 9);
  // nothing fed may leave by conduit
  try testing.expect(ss.output(a) == null and !ss.gives(a, .essence));
  try run(&ss, &w, &plants, &g, 30);
  try testing.expectEqual(@as(u32, 12), ss.get(b).inv.count(.essence));
  try testing.expectEqual(@as(u32, 9), ss.get(a).inv.count(.grit));
  try testing.expectEqual(@as(u32, 0), ss.get(a).inv.count(.essence));
  try testing.expectEqual(@as(u32, 0), ss.get(b).inv.count(.grit));
  // what came by spore is what it lets go
  try testing.expect(ss.output(a) == .grit and ss.gives(b, .essence));
  // configured twice over, both stop trading
  st.configure(&ss, a, &g);
  st.configure(&ss, a, &g);
  try testing.expect(ss.get(a).partner() == null and ss.get(b).partner() == null);
}

test "what a driftbraid received is handed on to its neighbours" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 0, 0, .driftbraid, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 20, 0, .driftbraid, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 21, 0, .sap_cache, 0, 0));
  st.configure(&ss, ss.at(&w, 0, 0).?, &g);
  st.configure(&ss, ss.at(&w, 20, 0).?, &g);
  _ = ss.insert(&g, ss.at(&w, 0, 0).?, .fibre, 10);
  try run(&ss, &w, &plants, &g, 30);
  try testing.expectEqual(@as(u32, 10), ss.get(ss.at(&w, 21, 0).?).inv.count(.fibre));
}
