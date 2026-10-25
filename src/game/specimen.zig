//! `--plant=<species>`: one plant alone in the world, held in one state or
//! looping one animation (`--state=`, `--period=`), for testing how a
//! species grows and looks. Nothing else is put down or drawn (no wolf,
//! nodes, motes or structures), and the renderer builds that species'
//! meshes only. Not part of play: it sets the plant's state itself.
const std = @import("std");
const Allocator = std.mem.Allocator;
const stringToEnum = std.meta.stringToEnum;
const parseFloat = std.fmt.parseFloat;
const indexOf = std.mem.indexOf;
const eql = std.mem.eql;
const testing = std.testing;
const m = @import("../core/math.zig");
const species = @import("../sim/species.zig");
const play = @import("play.zig");
const Game = play.Game;

/// a loop's animation runs `period` seconds, then holds its end this long
/// before it starts again
const HOLD:f32 = 1.5;
/// live, a grown (or dead) plant is sown afresh this long after
const REGROW:f32 = 4;
/// held, a plant never grows on its own
const NEVER:f32 = 1e9;
/// a tile to sow on: searched this far round the wolf
const SEARCH:i32 = 8;

pub const State = union(enum) {
  /// grows from nothing to grown, again and again
  grow,
  /// growth from one share to another, again and again
  span:[2]f32,
  /// held at one share of growth (`mature`: grown)
  held:f32,
  /// grown, its health failing to nothing, again and again (a radiant
  /// plant comes loose, its light dims)
  wither,
  /// grown, sap rising through it and ebbing (flow), round and round
  flow,
  /// grown, its mana draining to empty, again and again
  drain,
  /// grown, a celestial bloom's network dark
  dark,
  /// sown and left to the ecology as in play; sown afresh once grown
  live,

  /// a name, a share of growth (`0.4`) or a span (`0.2..0.8`)
  pub fn parse(s:[]const u8) error{BadState}!State {
    if (eql(u8, s, "mature")) return .{.held = 1};
    if (stringToEnum(enum { grow, wither, flow, drain, dark, live }, s)) |k| return switch (k) {
      .grow => .grow, .wither => .wither, .flow => .flow, .drain => .drain, .dark => .dark, .live => .live,
    };
    if (indexOf(u8, s, "..")) |dots| {
      const a = parseFloat(f32, s[0..dots]) catch return error.BadState;
      const b = parseFloat(f32, s[dots + 2 ..]) catch return error.BadState;
      return .{.span = .{m.clamp01(a), m.clamp01(b)}};
    }
    return .{.held = m.clamp01(parseFloat(f32, s) catch return error.BadState)};
  }
};

/// what the plant shows this moment
const Look = struct { growth:f32 = 1, mana:f32 = 1, flow:f32 = 0, health:f32 = 1, radiating:bool = true };

pub const Specimen = struct {
  sp:species.Id,
  state:State = .grow,
  /// seconds one loop's animation runs
  period:f32 = 8,
  t:f32 = 0,
  /// the tile it is sown on (found by `sow`)
  at:[2]i32 = .{0, 0},

  /// sow it on the free tile nearest the wolf and stand the wolf (and the
  /// camera) over it
  pub fn sow(s:*Specimen, g:*Game) Allocator.Error!void {
    const cx, const cz = m.tileAt(g.player.pos);
    var r:i32 = 0;
    find: while (r < SEARCH) : (r += 1) {
      var it = m.ring(r);
      while (it.next()) |o| if (g.plants.canPlace(&g.world, cx + o[0], cz + o[1], s.sp)) {
        s.at = .{cx + o[0], cz + o[1]};
        break :find;
      };
    }
    try s.plant(g);
    const def = species.get(s.sp);
    g.player.pos = m.footprintCentre(s.at[0], s.at[1], if (def.floating) 1 else def.size, g.heightAt(s.at[0], s.at[1]));
    g.cam.target = g.player.pos;
  }

  fn plant(s:*Specimen, g:*Game) Allocator.Error!void {
    const l = s.look();
    _ = try g.plants.placeEx(g.gpa, &g.world, s.at[0], s.at[1], .{
      .x = s.at[0], .y = s.at[1], .chunk = undefined, .tile = undefined, .sp = s.sp, .seed = 0.37,
      .growth = if (s.state == .live) 0 else l.growth, .span = if (s.state == .live) 0 else NEVER,
    });
  }

  /// one tick: held, the plant is set as its state says and the ecology
  /// is left out (whether this tick is handled); live, the ecology runs
  /// (`regrow` after it)
  pub fn hold(s:*Specimen, g:*Game, dt:f32) Allocator.Error!bool {
    if (s.state == .live) return false;
    s.t += dt;
    // uprooted: back it comes
    if (g.plants.len() == 0) try s.plant(g);
    const l = s.look();
    const def = species.get(s.sp);
    const p = g.plants.list.slice();
    p.items(.growth)[0] = l.growth;
    p.items(.mana)[0] = l.mana * def.mana_cap;
    p.items(.flow)[0] = l.flow;
    p.items(.health)[0] = l.health;
    p.items(.span)[0] = NEVER;
    const rad = &g.eco.radiance.radiating;
    try rad.resize(g.gpa, g.plants.len());
    rad.items[0] = def.radiance > 0 and l.radiating;
    return true;
  }

  /// live, after the ecology's tick: once grown (or gone) and left a
  /// while, sown afresh
  pub fn regrow(s:*Specimen, g:*Game, dt:f32) Allocator.Error!void {
    const gone = g.plants.len() == 0;
    if (!gone and g.plants.list.items(.growth)[0] < 1) return;
    s.t += dt;
    if (s.t < REGROW) return;
    s.t = 0;
    if (!gone) g.plants.remove(&g.world, .of(0));
    try s.plant(g);
  }

  /// how far through this loop's animation (0..1; 1 through the hold)
  fn share(s:*const Specimen) f32 {
    return m.clamp01(@mod(s.t, s.period + HOLD) / s.period);
  }

  fn look(s:*const Specimen) Look {
    const k = s.share();
    return switch (s.state) {
      .grow => .{.growth = k},
      .span => |ab| .{.growth = m.lerp(ab[0], ab[1], k)},
      .held => |h| .{.growth = h},
      .wither => .{.health = 1 - k},
      .flow => .{.flow = 0.5 - 0.5 * @cos(s.t / s.period * m.tau)},
      .drain => .{.mana = 1 - k},
      .dark => .{.radiating = false},
      .live => .{.growth = 0},
    };
  }
};

test "a state is a name, a share of growth or a span" {
  try testing.expect(try State.parse("grow") == .grow);
  try testing.expectEqual(@as(f32, 1), (try State.parse("mature")).held);
  try testing.expectEqual(@as(f32, 0.4), (try State.parse("0.4")).held);
  try testing.expectEqual([2]f32{0.2, 0.8}, (try State.parse("0.2..0.8")).span);
  try testing.expectError(error.BadState, State.parse("sideways"));
}

test "a loop runs its period, holds its end, then starts again" {
  var s:Specimen = .{.sp = .lumenroot, .period = 4};
  s.t = 2;
  try testing.expectApproxEqAbs(@as(f32, 0.5), s.look().growth, 1e-5);
  s.t = 4 + HOLD * 0.5;
  try testing.expectEqual(@as(f32, 1), s.look().growth);
  s.t = 4 + HOLD + 1;
  try testing.expectApproxEqAbs(@as(f32, 0.25), s.look().growth, 1e-5);
}

test "held, the plant shows its state and nothing else grows it" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, play.DEFAULT_SEED);
  defer g.deinit();
  g.specimen = .{.sp = .vesper, .state = .{.held = 0.5}};
  try g.specimen.?.sow(&g);
  try testing.expectEqual(@as(usize, 1), g.plants.len());
  // a vesper out of radiance would wither: held, it does not
  for (0..120) |_| try g.step();
  try testing.expectEqual(@as(usize, 1), g.plants.len());
  try testing.expectEqual(@as(f32, 0.5), g.plants.list.items(.growth)[0]);
  try testing.expectEqual(@as(f32, 1), g.plants.list.items(.health)[0]);
}
