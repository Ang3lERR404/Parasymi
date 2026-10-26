//! MONFRIS: a weftstone and a driftbraid grown into one 2x2 tree that
//! weaves the advanced tier (`craft.advanced`), which nothing else can:
//! its panel picks the weave, as a germinator's does. It is fed by the
//! Vultrixi tethered to it, at most `TETHERS`, each bringing it one kind of
//! what that weave needs (so an advanced weave has at most six kinds), or
//! by hand from its panel; what it weaves it hands to the structures
//! beside it, or keeps for the gardener.
// decision: what it is fed by conduits it takes too (a conduit hands in
// through `wants` like anything else); only Vultrixi reach out for it
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const indexOfScalar = std.mem.indexOfScalar;
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
const craft = lib.craft;
const style = lib.style;
const Parts = lib.parts.Parts;
const Look = lib.parts.Look;
const Draw = lib.engine.ui.draw.Draw;
const Color = lib.engine.ui.draw.Color;
const mesh = lib.monfris;

const V3 = m.V3;
const v3 = m.v3;

/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .belly_lump, .item_pod };

pub const def:st.Def = .{ .item = .monfris, .size = 2, .mesh = .monfris, .store = true, .grow = 10, .sway = 0.2, .tall = 1.7, .sap = 0.3 };

/// most Vultrixi tethered to one monfris (an advanced weave needs at
/// most this many kinds)
pub const TETHERS = 6;
/// how many weaves' worth of each ingredient it stocks
const STOCK = 2;
/// it weaves this much faster than a germinator weaves its own
const SPEED:f32 = 1;
/// what it holds hangs in its sac, in a ring, bobbing; what it weaves forms
/// at the sac's heart
const RING:f32 = 0.5;
const LUMP_R:f32 = 0.026;
const LUMP_GROW:f32 = 0.02;
const BOB:f32 = 0.012;
const TURN:f32 = 0.2;
const GLOW:f32 = 0.2;
const FORMING_SIZE:f32 = 0.55;
const FORMING_GLOW:f32 = 0.8;

comptime {
  // every advanced weave fits the tethers it may have
  for (craft.advanced) |r| std.debug.assert(craft.hand[r].in.len <= TETHERS);
}

pub const State = struct {
  /// which advanced weave (index into craft.hand) it weaves
  recipe:u8 = craft.advanced[0],
  weave:craft.Crafter = .{},
  /// how many Vultrixi are tethered to it (counted each tick)
  tethered:u8 = 0,
};

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  _ = st.handOff(ctx, i);
  const self = ctx.ss.get(i);
  const h = &self.state.monfris;
  h.tethered = @intCast(tethers(ctx.ss, .{self.x, self.y}));
  const r = craft.hand[h.recipe];
  if (!h.weave.busy() and r.unlocked(ctx.g) and craft.Crafter.can(self.inv.bag(), r)) _ = h.weave.push(self.inv.bag(), h.recipe);
  _ = h.weave.tick(self.inv.bag(), dt * SPEED);
  return h.weave.busy();
}

/// what its weave needs, `STOCK` weaves' worth.
pub fn wants(s:*const st.Structure, _:*const prog.Progression, item:items.Item) u32 {
  for (craft.hand[s.state.monfris.recipe].in) |ing| {
    if (ing.item == item) return @as(u32, ing.n) * STOCK -| s.inv.count(item);
  }
  return 0;
}

/// whether an advanced weave makes `item` (what it lets go of).
fn made(item:items.Item) bool {
  for (craft.advanced) |r| if (craft.hand[r].out == item) return true;
  return false;
}

pub fn output(s:*const st.Structure) ?items.Item {
  for (s.inv.slot) |slot| if (slot) |it| if (made(it.item)) return it.item;
  return null;
}
pub fn gives(s:*const st.Structure, item:items.Item) bool { return made(item) and s.inv.count(item) > 0; }

/// its panel offers the advanced tier.
pub fn recipes() []const u8 { return &craft.advanced; }
pub fn chosen(s:*const st.Structure) ?u8 { return s.state.monfris.recipe; }

/// set what it weaves, if the gardener understands it (a weave under way
/// finishes first).
pub fn choose(s:*st.Structure, g:*prog.Progression, r:u8) void {
  const out = txt.item(craft.hand[r].out).name;
  if (!craft.hand[r].unlocked(g)) return g.say(txt.s.msg.not_understood, .{out});
  if (indexOfScalar(u8, &craft.advanced, r) == null or s.state.monfris.recipe == r) return;
  s.state.monfris.recipe = r;
  g.say(txt.s.msg.monfris_weaves, .{out});
}

/// a Vultrixi waiting to be tethered is tethered here (`ss.pairing`, set by
/// configuring it), while it has room for one more.
pub fn configure(ss:*st.Structures, id:st.Id, g:*prog.Progression) void {
  const p = ss.pairing orelse return;
  const v = ss.floaterAt(p[0], p[1]) orelse return;
  if (ss.get(v).kind() != .vultrixi) return;
  ss.pairing = null;
  const s = ss.get(id);
  const here = [2]i32{s.x, s.y};
  var n:u32 = 0;
  for (ss.list.items, 0..) |*o, j| if (o.kind() == .vultrixi and j != v.idx()) {
    if (o.state.vultrixi.dest) |d| if (d[0] == here[0] and d[1] == here[1]) { n += 1; };
  };
  if (n >= TETHERS) return g.say(txt.s.msg.tether_full, .{});
  ss.get(v).state.vultrixi.dest = here;
  g.say(txt.s.msg.tethered, .{});
}

/// how many Vultrixi are tethered to the monfris on `at`
pub fn tethers(ss:*const st.Structures, at:[2]i32) u32 {
  var n:u32 = 0;
  for (ss.list.items) |*o| if (o.kind() == .vultrixi) {
    if (o.state.vultrixi.dest) |d| if (d[0] == at[0] and d[1] == at[1]) { n += 1; };
  };
  return n;
}

/// what it holds hanging in its sac, and what it weaves forming at its heart.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  if (s.grown < 1) return;
  const base = s.place(ctr);
  const h = &s.state.monfris;
  var n:usize = 0;
  for (s.inv.slot) |slot| { if (slot != null) n += 1; }
  var j:usize = 0;
  for (s.inv.slot) |slot| {
    const it = slot orelse continue;
    const a = m.ratio(j, n) * m.tau + tf * TURN + s.seed * 6;
    const ring = if (n == 1) 0 else mesh.SAC_R[0] * RING;
    const at = mesh.SAC_AT + v3(@cos(a) * ring, -mesh.SAC_R[1] * 0.3 + BOB * @sin(tf * 1.2 + m.f(j) * 2), @sin(a) * ring);
    const r = LUMP_R + LUMP_GROW * m.ratio(it.n, items.STACK);
    try out.emit(.belly_lump, m.mul(base, m.chain(&.{m.translate(at), m.scale3(m.splat3(r))})), Look{
      .glow = GLOW, .phase = s.seed, .tint = color.Rgba8.of(it.item.info().col).toF4(),
      .sway = def.sway, .tall = def.tall, .drop = at[1],
    });
    j += 1;
  }
  if (h.weave.busy()) {
    const r = craft.hand[h.weave.queue[0]];
    const at = mesh.SAC_AT + v3(0, mesh.SAC_R[1] * 0.15, 0);
    try out.emit(.item_pod, m.mul(base, m.chain(&.{m.translate(at), m.rotY(tf), m.scale3(m.splat3(FORMING_SIZE * (0.3 + 0.7 * h.weave.progress())))})), Look{
      .glow = FORMING_GLOW, .phase = s.seed, .tint = color.Rgba8.of(r.out.info().col).toF4(),
      .sway = def.sway, .tall = def.tall, .drop = at[1],
    });
  }
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const h = &s.state.monfris;
  const name = txt.item(craft.hand[h.recipe].out).name;
  if (h.weave.busy()) {
    _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.loom_weaves, .{name, h.tethered});
    try d.tendril(x + style.desc_bar_x, y + 2, style.desc_bar_w, style.bar_h, style.gold, h.weave.progress(), 0.3);
  } else {
    _ = try d.print(x, y, style.text_body, style.dim, txt.s.describe.loom_waits, .{name, h.tethered});
  }
}

/// its bulb: four strands out of the seed twining into one trunk under a
/// sac, a woven seed forming in it, tethers running in to it from either
/// side with motes along them (it is fed from round it).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const sac:icon_kit.P = .{0, 0.7};
  for (0..4) |i| {
    const sx = m.lerp(-0.3, 0.3, m.ratio(i, 3));
    try ic.stem(.{.{sx, icon_kit.TOP}, .{sx * 0.6, 0.28}, .{-sx * 0.3, 0.42}, .{0, 0.55}}, 0.06, if (i % 2 == 0) icon_green else icon_pale);
  }
  for ([_]f32{-1, 1}, 0..) |sx, i| {
    const run = [4]icon_kit.P{.{0.85 * sx, 0.95}, .{0.6 * sx, 1.0}, .{0.3 * sx, 0.85}, sac};
    try ic.stem(run, 0.02, icon_tether);
    try ic.bud(.{0.85 * sx, 0.95}, 0.06, icon_vult, 0.6);
    const k = @mod(ic.t * 0.6 + ic.phase + m.f(i) * 0.5, 1);
    try ic.bud(icon_kit.curve(run, k), 0.04, icon_mote, @sin(k * m.pi));
  }
  try ic.glow(sac, 0.26, icon_sac_glow);
  try ic.bud(sac, 0.18, icon_sac, 0.4);
  try ic.kernel(sac, 0.13, icon_seed);
  try ic.coat(col);
}
const icon_green:Color = .{80, 150, 95, 255};
const icon_pale:Color = .{185, 180, 205, 255};
const icon_tether:Color = .{200, 195, 220, 255};
const icon_vult:Color = .{225, 205, 230, 255};
const icon_mote:Color = .{245, 210, 150, 255};
const icon_sac:Color = .{215, 150, 125, 210};
const icon_sac_glow:Color = .{170, 140, 230, 70};
const icon_seed:Color = .{200, 160, 255, 255};
