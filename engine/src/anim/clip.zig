//! keyframed animation, the generic half: a clip is a set of named
//! channels, each a run of keys (time, value) eased between, and the text
//! it is kept in. `Channels(T)` reads and writes every f32 of a plain
//! struct (nested structs, arrays, vectors) as a channel of its own, named
//! by its path (`arms.0.root.x`), so a whole pose or look can be keyed.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const tokenizeScalar = std.mem.tokenizeScalar;
const splitScalar = std.mem.splitScalar;
const trim = std.mem.trim;
const eql = std.mem.eql;
const parseFloat = std.fmt.parseFloat;
const testing = std.testing;
const m = @import("../core/math.zig");

/// keys this close in time are the same key
pub const SAME:f32 = 1e-4;
/// the first line of a clip's text
pub const HEADER = "# clip";

pub const Key = struct { t:f32, v:f32 };

/// one channel's keys, in time order
pub const Track = struct {
  name:[]const u8,
  keys:std.ArrayList(Key) = .empty,

  /// its value at `t`: held before the first key and after the last,
  /// eased in and out between two (null without keys)
  pub fn sample(tr:*const Track, t:f32) ?f32 {
    const k = tr.keys.items;
    if (k.len == 0) return null;
    if (t <= k[0].t) return k[0].v;
    for (k[1..], 1..) |b, i| if (t < b.t) {
      const a = k[i - 1];
      return m.lerp(a.v, b.v, m.smooth((t - a.t) / (b.t - a.t)));
    };
    return k[k.len - 1].v;
  }

  /// the key at `at` (within `SAME`), if there is one
  pub fn at(tr:*const Track, t:f32) ?usize {
    for (tr.keys.items, 0..) |k, i| if (@abs(k.t - t) < SAME) return i;
    return null;
  }
};

pub const ParseError = error{ BadClip, OutOfMemory };

pub const Clip = struct {
  gpa:Allocator,
  /// what it animates (the game's word for it)
  subject:[]const u8,
  /// seconds it runs
  length:f32 = 2,
  tracks:std.ArrayList(Track) = .empty,

  pub fn init(gpa:Allocator, subject:[]const u8) Allocator.Error!Clip {
    return .{ .gpa = gpa, .subject = try gpa.dupe(u8, subject) };
  }

  pub fn deinit(c:*Clip) void {
    for (c.tracks.items) |*tr| {
      c.gpa.free(tr.name);
      tr.keys.deinit(c.gpa);
    }
    c.tracks.deinit(c.gpa);
    c.gpa.free(c.subject);
  }

  pub fn track(c:*const Clip, name:[]const u8) ?*Track {
    for (c.tracks.items) |*tr| if (eql(u8, tr.name, name)) return tr;
    return null;
  }

  /// `name` keyed to `v` at `t` (an existing key there takes the value)
  pub fn put(c:*Clip, name:[]const u8, t:f32, v:f32) Allocator.Error!void {
    const tr = c.track(name) orelse add: {
      const owned = try c.gpa.dupe(u8, name);
      errdefer c.gpa.free(owned);
      try c.tracks.append(c.gpa, .{ .name = owned });
      break :add &c.tracks.items[c.tracks.items.len - 1];
    };
    if (tr.at(t)) |i| {
      tr.keys.items[i].v = v;
      return;
    }
    var i:usize = 0;
    while (i < tr.keys.items.len and tr.keys.items[i].t < t) i += 1;
    try tr.keys.insert(c.gpa, i, .{ .t = t, .v = v });
  }

  /// `name`'s key at `t` taken out; whether there was one
  pub fn remove(c:*Clip, name:[]const u8, t:f32) bool {
    const tr = c.track(name) orelse return false;
    const i = tr.at(t) orelse return false;
    _ = tr.keys.orderedRemove(i);
    return true;
  }

  pub fn sample(c:*const Clip, name:[]const u8, t:f32) ?f32 {
    return if (c.track(name)) |tr| tr.sample(t) else null;
  }

  /// the nearest key time after (`dir` 1) or before (-1) `t` on any track
  pub fn nextKey(c:*const Clip, t:f32, dir:f32) ?f32 {
    var best:?f32 = null;
    for (c.tracks.items) |tr| for (tr.keys.items) |k| {
      const d = (k.t - t) * dir;
      if (d > SAME and (best == null or d < (best.? - t) * dir)) best = k.t;
    };
    return best;
  }

  /// its text: a header, `subject`, `length`, then a `key <channel> <time>
  /// <value>` line for each key
  pub fn write(c:*const Clip, w:*Writer) Writer.Error!void {
    try w.print("{s}\nsubject {s}\nlength {d}\n", .{ HEADER, c.subject, c.length });
    for (c.tracks.items) |tr| for (tr.keys.items) |k| try w.print("key {s} {d} {d}\n", .{ tr.name, k.t, k.v });
  }

  /// a clip from its text (`#` starts a comment)
  pub fn parse(gpa:Allocator, text:[]const u8) ParseError!Clip {
    var c = try Clip.init(gpa, "");
    errdefer c.deinit();
    var lines = splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
      const line = trim(u8, raw, " \t\r");
      if (line.len == 0 or line[0] == '#') continue;
      var it = tokenizeScalar(u8, line, ' ');
      const word = it.next() orelse continue;
      if (eql(u8, word, "subject")) {
        const s = it.next() orelse return error.BadClip;
        gpa.free(c.subject);
        c.subject = "";
        c.subject = try gpa.dupe(u8, s);
      } else if (eql(u8, word, "length")) {
        c.length = parseFloat(f32, it.next() orelse return error.BadClip) catch return error.BadClip;
      } else if (eql(u8, word, "key")) {
        const name = it.next() orelse return error.BadClip;
        const t = parseFloat(f32, it.next() orelse return error.BadClip) catch return error.BadClip;
        const v = parseFloat(f32, it.next() orelse return error.BadClip) catch return error.BadClip;
        try c.put(name, t, v);
      } else return error.BadClip;
    }
    return c;
  }
};

/// every f32 in `T` as a channel: its name (path) and how to read and
/// write it. Other fields (bools, ints) are left out.
pub fn Channels(comptime T:type) type {
  return struct {
    pub const count = countOf(T);
    pub const names:[count][]const u8 = namesOf(T, "");

    pub fn get(x:*const T, i:usize) f32 {
      var copy = x.*;
      return walk(T, &copy, i, null);
    }
    pub fn set(x:*T, i:usize, v:f32) void { _ = walk(T, x, i, v); }
    /// the channel named `name`
    pub fn find(name:[]const u8) ?usize {
      for (names, 0..) |n, i| if (eql(u8, n, name)) return i;
      return null;
    }
  };
}

fn countOf(comptime U:type) usize {
  return switch (@typeInfo(U)) {
    .float => if (U == f32) 1 else 0,
    .@"struct" => |s| blk: {
      var n:usize = 0;
      for (s.fields) |fl| n += countOf(fl.type);
      break :blk n;
    },
    .array => |a| a.len * countOf(a.child),
    .vector => |v| if (v.child == f32) v.len else 0,
    else => 0,
  };
}

const AXES = [_][]const u8{ "x", "y", "z", "w" };

fn namesOf(comptime U:type, comptime prefix:[]const u8) [countOf(U)][]const u8 {
  @setEvalBranchQuota(100_000);
  var out:[countOf(U)][]const u8 = undefined;
  const dot = if (prefix.len == 0) "" else prefix ++ ".";
  switch (@typeInfo(U)) {
    .float => if (U == f32) {
      out[0] = prefix;
    },
    .@"struct" => |s| {
      var n:usize = 0;
      for (s.fields) |fl| {
        const sub = namesOf(fl.type, dot ++ fl.name);
        for (sub, 0..) |nm, i| out[n + i] = nm;
        n += sub.len;
      }
    },
    .array => |a| {
      const per = countOf(a.child);
      for (0..a.len) |j| {
        const sub = namesOf(a.child, dot ++ std.fmt.comptimePrint("{d}", .{j}));
        for (sub, 0..) |nm, i| out[j * per + i] = nm;
      }
    },
    .vector => |v| if (v.child == f32) {
      for (0..v.len) |j| out[j] = dot ++ AXES[j];
    },
    else => {},
  }
  return out;
}

/// channel `i` of `x` (its value; set to `v` first when there is one)
fn walk(comptime U:type, x:*U, i:usize, v:?f32) f32 {
  switch (@typeInfo(U)) {
    .float => if (U == f32) {
      if (v) |nv| x.* = nv;
      return x.*;
    },
    .@"struct" => |s| {
      comptime var base:usize = 0;
      inline for (s.fields) |fl| {
        const n = comptime countOf(fl.type);
        if (n > 0 and i >= base and i < base + n) return walk(fl.type, &@field(x, fl.name), i - base, v);
        base += n;
      }
    },
    .array => |a| {
      const per = comptime countOf(a.child);
      if (per > 0) inline for (0..a.len) |j| {
        if (i >= j * per and i < (j + 1) * per) return walk(a.child, &x[j], i - j * per, v);
      };
    },
    .vector => |vec| if (vec.child == f32) {
      var arr:[vec.len]f32 = x.*;
      if (v) |nv| arr[i] = nv;
      x.* = arr;
      return arr[i];
    },
    else => {},
  }
  unreachable;
}

test "a track eases between its keys and holds past its ends" {
  var c = try Clip.init(testing.allocator, "thing");
  defer c.deinit();
  try c.put("a", 1, 2);
  try c.put("a", 0, 0);
  try c.put("a", 1, 4);
  const tr = c.track("a").?;
  try testing.expectEqual(@as(usize, 2), tr.keys.items.len);
  try testing.expectEqual(@as(f32, 0), c.sample("a", -1).?);
  try testing.expectApproxEqAbs(@as(f32, 2), c.sample("a", 0.5).?, 1e-5);
  try testing.expectEqual(@as(f32, 4), c.sample("a", 3).?);
  try testing.expect(c.sample("b", 0) == null);
  try testing.expectEqual(@as(f32, 1), c.nextKey(0, 1).?);
  try testing.expectEqual(@as(f32, 0), c.nextKey(1, -1).?);
  try testing.expect(c.remove("a", 1));
  try testing.expect(!c.remove("a", 1));
}

test "a clip comes back from its text" {
  const gpa = testing.allocator;
  var c = try Clip.init(gpa, "wolf");
  defer c.deinit();
  c.length = 1.5;
  try c.put("head.x", 0, 0.25);
  try c.put("head.x", 0.75, -0.5);
  try c.put("jaw", 0.5, 0.1);
  var out:Writer.Allocating = .init(gpa);
  defer out.deinit();
  try c.write(&out.writer);
  var back = try Clip.parse(gpa, out.written());
  defer back.deinit();
  try testing.expectEqualStrings("wolf", back.subject);
  try testing.expectEqual(@as(f32, 1.5), back.length);
  try testing.expectEqual(@as(f32, -0.5), back.sample("head.x", 1).?);
  try testing.expectEqual(@as(f32, 0.1), back.sample("jaw", 0).?);
  try testing.expectError(error.BadClip, Clip.parse(gpa, "key head.x zero 1"));
}

test "every f32 of a struct is a channel, named by its path" {
  const S = struct {
    a:f32 = 1,
    on:bool = true,
    p:m.V3 = .{ 2, 3, 4 },
    legs:[2]struct { b:f32 = 5, c:[2]f32 = .{ 6, 7 } } = @splat(.{}),
  };
  const C = Channels(S);
  try testing.expectEqual(@as(usize, 1 + 3 + 2 * 3), C.count);
  try testing.expectEqualStrings("p.y", C.names[2]);
  try testing.expectEqualStrings("legs.1.c.0", C.names[8]);
  var s:S = .{};
  try testing.expectEqual(@as(f32, 3), C.get(&s, 2));
  C.set(&s, 8, -1);
  try testing.expectEqual(@as(f32, -1), s.legs[1].c[0]);
  C.set(&s, 3, 9);
  try testing.expectEqual(@as(f32, 9), s.p[2]);
  try testing.expectEqual(@as(usize, 8), C.find("legs.1.c.0").?);
}
