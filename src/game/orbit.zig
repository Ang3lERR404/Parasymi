//! `--inspect`: the camera fixed on one thing (the wolf, the nearest plant
//! of a species or structure of a kind, or a tile), turning slowly round
//! it and asking for a screenshot at evenly spaced bearings; once every
//! shot is taken the game closes. For looking at visual work unattended.
const std = @import("std");
const stringToEnum = std.meta.stringToEnum;
const parseInt = std.fmt.parseInt;
const indexOfScalar = std.mem.indexOfScalar;
const bufPrint = std.fmt.bufPrint;
const eql = std.mem.eql;
const testing = std.testing;
const m = @import("../core/math.zig");
const species = @import("../sim/species.zig");
const st = @import("structures.zig");
const play = @import("play.zig");
const Game = play.Game;

/// the point looked at sits this far above a thing's ground (the wolf's
/// follow height; floaters add their hover)
const FOCUS_UP:f32 = 0.6;

/// what the camera turns round
pub const Focus = union(enum) {
  player,
  /// the nearest to the wolf (the wolf itself while there is none)
  species:species.Id,
  structure:st.Kind,
  tile:[2]i32,

  /// `player`, a species or structure name, or `x,z`
  pub fn parse(s:[]const u8) error{BadFocus}!Focus {
    if (eql(u8, s, "player")) return .player;
    if (stringToEnum(species.Id, s)) |id| return .{.species = id};
    if (stringToEnum(st.Kind, s)) |k| return .{.structure = k};
    const comma = indexOfScalar(u8, s, ',') orelse return error.BadFocus;
    const x = parseInt(i32, s[0..comma], 0) catch return error.BadFocus;
    const z = parseInt(i32, s[comma + 1 ..], 0) catch return error.BadFocus;
    return .{.tile = .{x, z}};
  }

  /// for file names
  pub fn name(f:Focus, buf:[]u8) []const u8 {
    return switch (f) {
      .player => "player",
      .species => |id| @tagName(id),
      .structure => |k| @tagName(k),
      .tile => |t| bufPrint(buf, "{d}_{d}", .{t[0], t[1]}) catch "tile",
    };
  }
};

pub const Orbit = struct {
  focus:Focus = .player,
  /// seconds per turn, and shots spread evenly over it
  period:f32 = 24,
  shots:u32 = 8,
  /// distance from the focus and pitch above the horizon (radians)
  dist:f32 = 9,
  pitch:f32 = m.rad(35.0),
  /// seconds before the turn (and the first shot) starts: streaming,
  /// meshing and growth settle
  settle:f32 = 3,
  t:f32 = 0,
  taken:u32 = 0,

  /// place the camera for this frame (after `Game.update`); true while a
  /// shot is due (it stays due until `took`)
  pub fn step(o:*Orbit, g:*Game, dt:f32) bool {
    o.t += dt;
    const yaw = o.turn() * m.tau;
    const at = o.point(g);
    const c = &g.cam;
    c.target = at;
    c.dist = o.dist;
    c.yaw = yaw;
    c.pitch = o.pitch;
    // decision: a free view aimed straight at the focus, so it sits at the
    // frame's centre at any pitch (following lifts the gaze below rest)
    const cp = @cos(o.pitch);
    const out = m.v3(@sin(yaw) * cp, @sin(o.pitch), @cos(yaw) * cp);
    c.view = .{.free = .{.pos = at + out * m.splat3(o.dist), .yaw = yaw, .pitch = -o.pitch}};
    // the garden is not saved over while it is looked at, and the mouse
    // marks no tile
    g.since_save = 0;
    g.hover = null;
    return o.due();
  }

  pub fn took(o:*Orbit) void { o.taken += 1; }
  pub fn done(o:*const Orbit) bool { return o.taken >= o.shots; }

  /// how far round it has turned (turns)
  fn turn(o:*const Orbit) f32 { return @max(o.t - o.settle, 0) / o.period; }
  /// the next shot's bearing is reached
  fn due(o:*const Orbit) bool {
    return !o.done() and o.t >= o.settle and o.turn() * m.f(o.shots) >= m.f(o.taken);
  }

  fn point(o:*const Orbit, g:*const Game) m.V3 {
    const wolf = g.player.pos + m.v3(0, FOCUS_UP, 0);
    switch (o.focus) {
      .player => return wolf,
      .tile => |t| return m.tileCentre(t[0], t[1], g.heightAt(t[0], t[1]) + FOCUS_UP),
      .species => |id| {
        const s = g.plants.list.slice();
        var best:?m.V3 = null;
        var near:f32 = m.inf(f32);
        for (s.items(.sp), s.items(.x), s.items(.y)) |sp, x, y| if (sp == id) {
          const def = species.get(sp);
          const c = m.footprintCentre(x, y, if (def.floating) 1 else def.size, g.heightAt(x, y) + FOCUS_UP + if (def.floating) def.hover else 0);
          const d = m.len(c - wolf);
          if (d < near) { near = d; best = c; }
        };
        return best orelse wolf;
      },
      .structure => |k| {
        var best:?m.V3 = null;
        var near:f32 = m.inf(f32);
        for (g.structs.list.items) |*s| if (s.kind() == k) {
          const def = s.def();
          const c = m.footprintCentre(s.x, s.y, def.size, g.heightAt(s.x, s.y) + FOCUS_UP + def.hover);
          const d = m.len(c - wolf);
          if (d < near) { near = d; best = c; }
        };
        return best orelse wolf;
      },
    }
  }
};

test "a focus is the wolf, a species, a structure or a tile" {
  try testing.expect(try Focus.parse("player") == .player);
  try testing.expect(try Focus.parse("diamond") == .structure);
  const t = try Focus.parse("-4,12");
  try testing.expectEqual([2]i32{-4, 12}, t.tile);
  try testing.expectError(error.BadFocus, Focus.parse("nowhere"));
  var buf:[24]u8 = undefined;
  try testing.expectEqualStrings("-4_12", t.name(&buf));
}

test "shots are due evenly round one turn, after the settle" {
  var o:Orbit = .{.period = 8, .shots = 4, .settle = 1};
  var due:u32 = 0;
  var t:f32 = 0;
  while (t < 10) : (t += 0.25) {
    o.t = t;
    if (o.due()) {
      // a quarter turn apart
      try testing.expectApproxEqAbs(m.f(o.taken) / 4, o.turn(), 0.05);
      due += 1;
      o.took();
    }
  }
  try testing.expectEqual(@as(u32, 4), due);
  try testing.expect(o.done());
}
