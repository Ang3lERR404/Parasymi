//! saving and restoring the garden. The world itself is never stored: it is
//! regenerated from the seed, and only what the gardener changed is kept:
//! the wolf and its belly, research, the weave queue, every plant and
//! structure, and resource nodes that were gathered.
//!
//! Format: a small header (magic, version, layout fingerprint) followed by
//! plain-old-data records. The fingerprint changes whenever a stored type's
//! size changes, so an incompatible save is refused instead of misread.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const asBytes = std.mem.asBytes;
const eql = std.mem.eql;
const testing = std.testing;
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
const item_count = std.meta.fields(items.Item).len;
comptime { std.debug.assert(item_count < NO_ITEM); }

pub const PATH = "parasymi.sav";
const MAGIC = "PRSY".*;
const VERSION:u32 = 11;
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
    if (p.sp >= species.count) return error.CorruptSave;
    const sp:species.Id = @enumFromInt(p.sp);
    try ensureFootprint(&g, p.x, p.y, species.get(sp).size);
    _ = try g.plants.placeEx(gpa, &g.world, p.x, p.y, .{
      .x = p.x, .y = p.y, .chunk = undefined, .tile = undefined, .sp = sp,
      .growth = p.growth, .span = p.span, .mana = p.mana, .health = p.health, .seed = p.seed,
      .flow = p.flow, .essence = p.essence,
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

pub fn save(g:*Game, gpa:Allocator, io:Io) Error!void {
  const bytes = try encode(gpa, g);
  defer gpa.free(bytes);
  Io.Dir.cwd().writeFile(io, .{ .sub_path = PATH, .data = bytes }) catch return error.SaveUnwritable;
}

pub fn load(gpa:Allocator, io:Io) Error!Game {
  const bytes = Io.Dir.cwd().readFileAlloc(io, PATH, gpa, .limited(MAX_SAVE)) catch |e| return switch (e) {
    error.FileNotFound => error.NoSave,
    error.OutOfMemory => error.OutOfMemory,
    else => error.SaveUnreadable,
  };
  defer gpa.free(bytes);
  return decode(gpa, bytes);
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