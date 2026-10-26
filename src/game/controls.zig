//! what every key and mouse button does, loaded once at startup from
//! `PATH` (`controls.cfg`) and never read again. Game code asks about an
//! `Action`, never a key: `ctl.pressed(in, .harvest)`.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const EnumArray = std.enums.EnumArray;
const log = std.log;
const trim = std.mem.trim;
const splitScalar = std.mem.splitScalar;
const values = std.enums.values;
const testing = std.testing;
const ctext = @import("engine").core.text;
const input = @import("engine").platform.input;
const Input = input.Input;
const Bind = input.Bind;
const home = @import("home.zig");

pub const PATH = "controls.cfg";
/// the bindings as built: what an edited file leaves out falls back to these
const DEFAULT = @embedFile("controls.cfg");
/// the cfg is a few kilobytes; anything near this is not one.
const MAX_CFG:usize = 1 << 16;
/// most alternatives one action can be bound to.
pub const MAX_BINDS = 4;

pub const Action = enum {
  move_forward, move_back, move_left, move_right,
  /// held with movement
  run,
  /// held: dragging the mouse orbits the camera round the wolf
  orbit,
  /// held: free_cam toggles the free camera, rise sinks
  alt,
  /// held: plant what is in hand; on a structure, interact; click a panel
  /// row; in the free camera, look
  use,
  /// interact with a structure (as `use` on it), harvest a plant
  interact,
  /// pressed or held: the universal remove (uproot a plant, take up a
  /// structure, gather from a resource node); clear a hotbar slot
  remove,
  /// take up the seed or bulb of what stands under the cursor
  pick,
  harvest,
  /// held with harvest: take from a structure instead of feeding it
  take,
  configure,
  /// turn what stands under the cursor, else the next thing put down
  rotate,
  /// held with rotate: turn the other way (counter-clockwise)
  counter,
  /// with the belly open: throw away the belly stack under the cursor (or carried)
  discard,
  belly,
  research,
  /// hotbar slots in order (see `slots`)
  slot_1, slot_2, slot_3, slot_4, slot_5, slot_6, slot_7, slot_8, slot_9, slot_10, slot_11, slot_12, slot_13,
  /// with alt
  free_cam,
  fly_fast, rise, roll_left, roll_right,
  /// close a panel, else pause
  back,
  /// while paused
  quit, options, gardens,
  save, load, fullscreen, debug,
};

/// the actions that pick hotbar slots, slot 0 first.
pub const slots = [_]Action{ .slot_1, .slot_2, .slot_3, .slot_4, .slot_5, .slot_6, .slot_7, .slot_8, .slot_9, .slot_10, .slot_11, .slot_12, .slot_13 };

pub const Binds = struct {
  list:[MAX_BINDS]Bind = undefined,
  len:u8 = 0,
  pub fn items(b:*const Binds) []const Bind { return b.list[0..b.len]; }
};

/// the cfg as written: each action a list of key and button names.
const Source = struct { bind:EnumArray(Action, []const u8) = .initFill("") };

/// the loaded bindings; empty until `load` (headless tests `fill` them).
// decision: one process-wide table, set once at startup and read-only
// after, like `txt.s`.
pub var map:EnumArray(Action, Binds) = .initFill(.{});

pub const Error = error{ NoControls, BadControls } || Allocator.Error;

/// reads and parses `PATH` (in `home`, made from the game's own when
/// missing) over the game's own bindings. Called once, at startup, before
/// the first frame.
pub fn load(gpa:Allocator, io:Io) Error!void {
  const src = try home.stock(gpa, io, PATH, DEFAULT);
  defer gpa.free(src);
  fill(&.{DEFAULT, src}) catch |e| switch (e) {
    error.OutOfMemory => return error.OutOfMemory,
    else => {
      log.warn("{s}: ignoring the edited bindings", .{PATH});
      try fill(&.{DEFAULT});
    },
  };
}

/// parses each cfg source of `texts` into `map` in turn, an action bound
/// in a later one replacing an earlier's (nothing of `texts` is kept).
pub fn fill(texts:[]const []const u8) Error!void {
  var bad_buf:[256]u8 = undefined;
  var bad:Io.Writer = .fixed(&bad_buf);
  var src:Source = .{};
  for (texts) |text| ctext.parse(Source, &src, text, &bad) catch |e| {
    log.err("{s}: {t}: {s}", .{PATH, e, bad.buffered()});
    return error.BadControls;
  };
  var out:EnumArray(Action, Binds) = .initFill(.{});
  var it = src.bind.iterator();
  while (it.next()) |e| {
    const b = out.getPtr(e.key);
    var names = splitScalar(u8, e.value.*, ctext.LIST_SEP);
    while (names.next()) |raw| {
      const name = trim(u8, raw, " \t");
      const one = Bind.parse(name) orelse {
        log.err("{s}: {t}: no key or button '{s}'", .{PATH, e.key, name});
        return error.BadControls;
      };
      if (b.len == MAX_BINDS) {
        log.err("{s}: {t}: more than {d} bindings", .{PATH, e.key, MAX_BINDS});
        return error.BadControls;
      }
      b.list[b.len] = one;
      b.len += 1;
    }
  }
  map = out;
}

pub fn unload() void { map = .initFill(.{}); }

/// is any key or button bound to `a` held?
pub fn down(in:*const Input, a:Action) bool {
  for (map.getPtrConst(a).items()) |b| if (in.down(b)) return true;
  return false;
}
/// did a key or button bound to `a` go down this frame?
pub fn pressed(in:*const Input, a:Action) bool {
  for (map.getPtrConst(a).items()) |b| if (in.pressed(b)) return true;
  return false;
}
/// headless tests: hold `a`'s first binding down (or let it go).
pub fn hold(in:*Input, a:Action, on:bool) void {
  in.hold(map.getPtrConst(a).list[0], on);
}

test "the controls file binds every action" {
  defer unload();
  try fill(&.{@embedFile("controls.cfg")});
  for (values(Action)) |a| try testing.expect(map.get(a).len > 0);
  try testing.expectEqual(Bind{ .button = .left }, map.get(.use).list[0]);
}
