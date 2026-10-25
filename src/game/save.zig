//! saving and restoring the garden. The world itself is never stored: it is
//! regenerated from the seed, and only what the gardener changed is kept:
//! the wolf and its belly, research, the weave queue, every plant and
//! structure, and resource nodes that were gathered.
//!
//! Each garden is a file of its own in `home.SAVES` (`<name>.sav`), chosen
//! in the saved gardens menu; the timer saves into `AUTO`.
//!
//! Format: a small header (magic, version, layout fingerprint) followed by
//! plain-old-data records. The fingerprint changes whenever a stored type's
//! size changes, so an incompatible save is refused instead of misread.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const asBytes = std.mem.asBytes;
const eql = std.mem.eql;
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const parseInt = std.fmt.parseInt;
const sep_str = std.fs.path.sep_str;
const ns_per_s = std.time.ns_per_s;
const testing = std.testing;
const fields = std.meta.fields;
const assert = std.debug.assert;
const sort = std.mem.sort;
const bufPrint = std.fmt.bufPrint;
const home = @import("home.zig");
const m = @import("../core/math.zig");
const Rng = @import("../core/rng.zig").Rng;
const ck = @import("../world/chunk.zig");
const gen = @import("../world/gen.zig");
const species = @import("../sim/species.zig");
const items = @import("../sim/items.zig");
const prog = @import("progression.zig");
const craft = @import("craft.zig");
const st = @import("structures.zig");
const player_mod = @import("player.zig");
const play = @import("play.zig");
const txt = @import("text.zig");

const Game = play.Game;
const Belly = @FieldType(player_mod.Player, "inv");
/// a hotbar slot is stored as its item's id, or this when empty
const NO_ITEM:u8 = 0xff;
const item_count = fields(items.Item).len;
comptime { assert(item_count < NO_ITEM); }

/// where saves were kept before they moved into `home.SAVES`
pub const LEGACY = "parasymi.sav";
/// a saved garden's file extension, and its scratch copy's while written
pub const EXT = ".sav";
const TMP = ".tmp";
/// the garden the timer saves into
pub const AUTO = "autosave";
/// gardens saved fresh are named this and a number
// decision: file names, not text; the saves menu shows them as they are
pub const FRESH = "garden ";
pub const MAX_NAME = 48;
const MAX_PATH = home.SAVES.len + 1 + MAX_NAME + EXT.len + TMP.len;
const MAGIC = "PRSY".*;
const VERSION:u32 = 19;
/// max save file size (64 MB): a garden with millions of plants will never
/// approach this; anything larger is almost certainly a corrupt or malicious file.
const MAX_SAVE:usize = 64 << 20;

/// everything saving and loading can fail with; file-system errors are
/// folded into these at the boundary.
pub const Error = error{
  /// there is no save file yet
  NoSave,
  SaveUnreadable,
  SaveUnwritable,
  NotASave,
  /// written by a build whose stored layout differs
  IncompatibleSave,
  CorruptSave,
} || Allocator.Error;

/// one plant, without its runtime links (rebuilt on load).
const PlantRec = extern struct {
  x:i32,
  y:i32,
  sp:u32,
  growth:f32,
  span:f32,
  mana:f32,
  health:f32,
  seed:f32,
  flow:f32,
  essence:f32,
  dir:u32,
};

/// one chunk whose resource nodes differ from what the generator made.
const NodesRec = struct {
  at:ck.Coord,
  res:[ck.N]ck.Res,
};

const Header = extern struct {
  magic:[4]u8,
  version:u32,
  layout:u64,
  seed:u64,
};

/// changes whenever any stored record's layout changes.
const layout_fingerprint = blk: {
  var h:u64 = 0xA5;
  for ([_]usize{
    @sizeOf(PlantRec), @sizeOf(NodesRec), @sizeOf(st.Structure),
    @sizeOf(prog.Progression), @sizeOf(craft.Crafter), @sizeOf(Belly),
    @sizeOf(Rng), species.count, st.defs.values.len,
  }) |n| h = h *% 0x100000001B3 ^ n;
  break :blk h;
};

const Writer = struct {
  gpa:Allocator,
  buf:std.ArrayList(u8) = .empty,
  fn put(w:*Writer, comptime T:type, v:T) Allocator.Error!void {
    try w.buf.appendSlice(w.gpa, asBytes(&v));
  }
};

const Reader = struct {
  data:[]const u8,
  pos:usize = 0,
  fn get(r:*Reader, comptime T:type) Error!T {
    if (r.pos + @sizeOf(T) > r.data.len) return error.CorruptSave;
    var v:T = undefined;
    @memcpy(asBytes(&v), r.data[r.pos..][0..@sizeOf(T)]);
    r.pos += @sizeOf(T);
    return v;
  }
};

pub fn encode(gpa:Allocator, g:*const Game) Allocator.Error![]u8 {
  var w:Writer = .{ .gpa = gpa };
  errdefer w.buf.deinit(gpa);
  try w.put(Header, .{ .magic = MAGIC, .version = VERSION, .layout = layout_fingerprint, .seed = g.world.seed });

  // the gardener and what it knows
  try w.put(Rng, g.rng);
  try w.put(f32, g.sky.tod);
  try w.put(f64, g.time);
  try w.put(u32, @intCast(g.hot));
  var bar:[play.BAR]u8 = undefined;
  for (g.bar, &bar) |b, *o| o.* = if (b) |it| @intFromEnum(it) else NO_ITEM;
  try w.put([play.BAR]u8, bar);
  try w.put(m.Dir, g.place_dir);
  try w.put(m.V3, g.player.pos);
  try w.put(f32, g.player.facing);
  try w.put(Belly, g.player.inv);
  try w.put(craft.Crafter, g.weave);
  try w.put(prog.Progression, g.prog);

  // everything it grew
  const s = g.plants.list.slice();
  try w.put(u32, @intCast(g.plants.len()));
  for (0..g.plants.len()) |i| try w.put(PlantRec, .{
    .x = s.items(.x)[i], .y = s.items(.y)[i], .sp = @intFromEnum(s.items(.sp)[i]),
    .growth = s.items(.growth)[i], .span = s.items(.span)[i], .mana = s.items(.mana)[i], .health = s.items(.health)[i],
    .seed = s.items(.seed)[i], .flow = s.items(.flow)[i], .essence = s.items(.essence)[i],
    .dir = s.items(.dir)[i],
  });
  try w.put(u32, @intCast(g.structs.list.items.len));
  for (g.structs.list.items) |it| try w.put(st.Structure, it);

  // gathered resource nodes (only chunks that differ from generation)
  var touched:std.ArrayList(*const ck.Chunk) = .empty;
  defer touched.deinit(gpa);
  var it = g.world.map.valueIterator();
  while (it.next()) |c| if (gathered(g.world.seed, c.*)) try touched.append(gpa, c.*);
  try w.put(u32, @intCast(touched.items.len));
  for (touched.items) |c| try w.put(NodesRec, .{ .at = c.at, .res = c.res });

  return w.buf.toOwnedSlice(gpa);
}

fn gathered(seed:u64, c:*const ck.Chunk) bool {
  for (0..ck.N) |t| {
    const wx, const wy = c.tileOf(t);
    const s = gen.sample(seed, wx, wy);
    if (s.res != c.res[t]) return true;
  }
  return false;
}

/// rebuild a game from bytes produced by `encode`.
pub fn decode(gpa:Allocator, data:[]const u8) Error!Game {
  var r:Reader = .{ .data = data };
  const h = try r.get(Header);
  if (!eql(u8, &h.magic, &MAGIC)) return error.NotASave;
  if (h.version != VERSION or h.layout != layout_fingerprint) return error.IncompatibleSave;

  var g = try Game.init(gpa, h.seed);
  errdefer g.deinit();
  g.rng = try r.get(Rng);
  g.sky.tod = try r.get(f32);
  g.time = try r.get(f64);
  g.hot = try r.get(u32);
  if (g.hot >= play.BAR) return error.CorruptSave;
  for (try r.get([play.BAR]u8), &g.bar) |b, *o| o.* = if (b == NO_ITEM) null
    else if (b < item_count) @enumFromInt(b)
    else return error.CorruptSave;
  g.place_dir = try r.get(m.Dir);
  g.player.pos = try r.get(m.V3);
  g.player.facing = try r.get(f32);
  g.player.inv = try r.get(Belly);
  g.weave = try r.get(craft.Crafter);
  g.prog = try r.get(prog.Progression);
  g.cam.target = g.player.pos;

  const plants = try r.get(u32);
  for (0..plants) |_| {
    const p = try r.get(PlantRec);
    if (p.sp >= species.count or p.dir >= m.dirs.len) return error.CorruptSave;
    const sp:species.Id = @enumFromInt(p.sp);
    try ensureFootprint(&g, p.x, p.y, species.get(sp).size);
    _ = try g.plants.placeEx(gpa, &g.world, p.x, p.y, .{
      .x = p.x, .y = p.y, .chunk = undefined, .tile = undefined, .sp = sp,
      .growth = p.growth, .span = p.span, .mana = p.mana, .health = p.health, .seed = p.seed,
      .flow = p.flow, .essence = p.essence, .dir = @intCast(p.dir),
    });
  }
  const structs = try r.get(u32);
  for (0..structs) |_| {
    const s = try r.get(st.Structure);
    try ensureFootprint(&g, s.x, s.y, s.def().size);
    // place allocates and initialises a fresh structure; we then overwrite it
    // with the saved one so its runtime state (inventory, per-kind data) is
    // restored exactly. If place fails the save is corrupt (the world is
    // regenerated from the same seed, so the tile was valid when saved).
    if (!try g.structs.place(gpa, &g.world, s.x, s.y, s.kind(), s.dir, s.seed)) return error.CorruptSave;
    g.structs.list.items[g.structs.list.items.len - 1] = s;
  }
  const nodes = try r.get(u32);
  for (0..nodes) |_| {
    const n = try r.get(NodesRec);
    const c = try g.world.ensure(n.at);
    c.res = n.res;
  }
  g.prog.say(txt.s.msg.remembers, .{});
  return g;
}

fn ensureFootprint(g:*Game, x:i32, y:i32, size:u8) Allocator.Error!void {
  const far = @as(i32, size) - 1;
  for ([_][2]i32{ .{ x, y }, .{ x + far, y }, .{ x, y + far }, .{ x + far, y + far } }) |t| {
    _ = try g.world.ensure(ck.Coord.ofTile(t[0], t[1]));
  }
}

/// a saved garden's file name, without its folder or `EXT`.
pub const Name = struct {
  buf:[MAX_NAME]u8 = undefined,
  len:u8 = 0,

  pub fn of(s:[]const u8) ?Name {
    if (s.len == 0 or s.len > MAX_NAME) return null;
    var n:Name = .{ .len = @intCast(s.len) };
    @memcpy(n.buf[0..s.len], s);
    return n;
  }
  pub fn slice(n:*const Name) []const u8 { return n.buf[0..n.len]; }
  pub fn is(n:*const Name, s:[]const u8) bool { return eql(u8, n.slice(), s); }
};

/// a garden in `home.SAVES`, as listed: its name and how long ago (s) it
/// was saved, when the list was made.
pub const Entry = struct { name:Name, age:i64 };

/// lists the saved gardens into `out`, the most recent first.
pub fn list(gpa:Allocator, io:Io, out:*std.ArrayList(Entry)) Error!void {
  out.clearRetainingCapacity();
  var d = home.dir().openDir(io, home.SAVES, .{ .iterate = true }) catch return error.SaveUnreadable;
  defer d.close(io);
  const now = Io.Clock.real.now(io).nanoseconds;
  var it = d.iterate();
  while (it.next(io) catch return error.SaveUnreadable) |e| {
    if (e.kind != .file or !endsWith(u8, e.name, EXT)) continue;
    const name = Name.of(e.name[0 .. e.name.len - EXT.len]) orelse continue;
    const st_ = d.statFile(io, e.name, .{}) catch continue;
    const age:i64 = @intCast(@divFloor(now - st_.mtime.nanoseconds, ns_per_s));
    try out.append(gpa, .{ .name = name, .age = @max(age, 0) });
  }
  sort(Entry, out.items, {}, struct {
    fn newer(_:void, a:Entry, b:Entry) bool { return a.age < b.age; }
  }.newer);
}

/// a name no garden in `have` uses: `FRESH` and the next number up.
pub fn fresh(have:[]const Entry) Name {
  var top:u32 = 0;
  for (have) |e| if (startsWith(u8, e.name.slice(), FRESH)) {
    top = @max(top, parseInt(u32, e.name.slice()[FRESH.len..], 10) catch continue);
  };
  var buf:[MAX_NAME]u8 = undefined;
  return Name.of(bufPrint(&buf, FRESH ++ "{d}", .{top + 1}) catch unreachable).?;
}

/// `home.SAVES`/`name``EXT`, plus `extra`
fn pathOf(buf:*[MAX_PATH]u8, name:Name, extra:[]const u8) []const u8 {
  return bufPrint(buf, "{s}{s}{s}{s}{s}", .{home.SAVES, sep_str, name.slice(), EXT, extra}) catch unreachable;
}

/// writes the garden as `name` (whole or not at all: into a scratch file
/// first, then over the old one).
pub fn save(g:*Game, gpa:Allocator, io:Io, name:Name) Error!void {
  const bytes = try encode(gpa, g);
  defer gpa.free(bytes);
  var tmp_buf:[MAX_PATH]u8 = undefined;
  var to_buf:[MAX_PATH]u8 = undefined;
  const tmp = pathOf(&tmp_buf, name, TMP);
  home.dir().writeFile(io, .{ .sub_path = tmp, .data = bytes }) catch return error.SaveUnwritable;
  Io.Dir.rename(home.dir(), tmp, home.dir(), pathOf(&to_buf, name, ""), io) catch return error.SaveUnwritable;
}

pub fn load(gpa:Allocator, io:Io, name:Name) Error!Game {
  var buf:[MAX_PATH]u8 = undefined;
  const bytes = home.dir().readFileAlloc(io, pathOf(&buf, name, ""), gpa, .limited(MAX_SAVE)) catch |e| return switch (e) {
    error.FileNotFound => error.NoSave,
    error.OutOfMemory => error.OutOfMemory,
    else => error.SaveUnreadable,
  };
  defer gpa.free(bytes);
  return decode(gpa, bytes);
}

test "a fresh garden's name follows the highest numbered one" {
  var have = [_]Entry{
    .{ .name = Name.of(FRESH ++ "2").?, .age = 0 },
    .{ .name = Name.of(AUTO).?, .age = 0 },
    .{ .name = Name.of(FRESH ++ "x").?, .age = 0 },
  };
  try testing.expectEqualStrings(FRESH ++ "3", fresh(&have).slice());
  try testing.expectEqualStrings(FRESH ++ "1", fresh(have[1..]).slice());
}

test "a garden survives a save round trip" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, play.DEFAULT_SEED);
  defer g.deinit();
  try @import("setups.zig").demo(&g, 3);
  // gather from some node so a depleted chunk is stored too
  const c = g.world.chunkOfTile(m.tileOf(g.player.pos[0]), m.tileOf(g.player.pos[2])).?;
  for (&c.res) |*r| if (r.* > 0) { r.* -= 1; break; };

  const bytes = try encode(gpa, &g);
  defer gpa.free(bytes);
  var back = try decode(gpa, bytes);
  defer back.deinit();

  try testing.expectEqual(g.plants.len(), back.plants.len());
  try testing.expectEqual(g.structs.list.items.len, back.structs.list.items.len);
  try testing.expectEqual(g.player.inv.count(.grit), back.player.inv.count(.grit));
  try testing.expect(back.prog.done.contains(.root_communion));
  try testing.expectEqual(g.player.pos, back.player.pos);
  const c2 = back.world.chunkOfTile(m.tileOf(g.player.pos[0]), m.tileOf(g.player.pos[2])).?;
  try testing.expectEqualSlices(ck.Res, &c.res, &c2.res);
  // a structure's per-kind state comes back intact
  for (g.structs.list.items, 0..) |s, i| try testing.expectEqual(s.kind(), back.structs.list.items[i].kind());
}