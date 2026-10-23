//! a 32x32 block of tiles, stored as struct-of-arrays so hot loops stay linear.
const m = @import("../core/math.zig");

pub const SIZE = 32;
pub const N = SIZE * SIZE;
const NONE:u32 = m.maxInt(u32);

pub const Kind = enum(u8) {
  water, soil, moss, stone, ley,

  /// tiles a seed can take root in.
  pub fn fertile(k:Kind) bool { return k == .soil or k == .moss or k == .ley; }
};

pub const Coord = struct {
  x:i32, y:i32,
  pub fn ofTile(wx:i32, wy:i32) Coord {
    return .{.x = @divFloor(wx, SIZE), .y = @divFloor(wy, SIZE)};
  }
};

/// a plant's slot in `sim/plants.zig`. Distinct from `StructId` so the two
/// can never be mixed up; `none` marks an empty link.
pub const PlantId = enum(u32) {
  none = NONE,
  _,
  pub fn of(i:usize) PlantId { return @enumFromInt(i); }
  pub fn idx(p:PlantId) usize { return @intFromEnum(p); }
};

/// a structure's slot in `game/structures.zig`.
pub const StructId = enum(u32) {
  _,
  pub fn of(i:usize) StructId { return @enumFromInt(i); }
  pub fn idx(s:StructId) usize { return @intFromEnum(s); }
};

/// a renderer-owned mesh slot (the world only keeps it for the renderer).
pub const MeshSlot = enum(u32) { _ };

/// what sits on a tile: a rooted plant, a structure, or nothing, packed into
/// one word (the top bit tells structures apart). Floating plants occupy no tile.
pub const Occ = enum(u32) {
  none = NONE,
  _,
  const STRUCT:u32 = 1 << 31;

  pub const Occupant = union(enum) { empty, plant:PlantId, structure:StructId };

  pub fn plant(p:PlantId) Occ { return @enumFromInt(@intFromEnum(p)); }
  pub fn structure(s:StructId) Occ { return @enumFromInt(@intFromEnum(s) | STRUCT); }

  pub fn get(o:Occ) Occupant {
    if (o == .none) return .empty;
    const v = @intFromEnum(o);
    return if (v & STRUCT != 0) .{.structure = @enumFromInt(v & ~STRUCT)} else .{.plant = @enumFromInt(v)};
  }
  pub fn asPlant(o:Occ) ?PlantId {
    return switch (o.get()) { .plant => |p| p, .empty, .structure => null };
  }
  pub fn asStructure(o:Occ) ?StructId {
    return switch (o.get()) { .structure => |s| s, .empty, .plant => null };
  }
};

pub inline fn localIndex(wx:i32, wy:i32) usize {
  const lx:usize = @intCast(@mod(wx, SIZE));
  const ly:usize = @intCast(@mod(wy, SIZE));
  return ly * SIZE + lx;
}

pub fn blank(at:Coord) Chunk {
  return .{.at = at, .height = undefined, .kind = undefined, .ley = undefined, .ley_cap = undefined,
    .res = undefined, .occ = undefined};
}

pub const Chunk = struct {
  at:Coord,
  height:[N]f32,
  kind:[N]Kind,
  /// ambient ley mana currently in the tile, and how much it refills to.
  ley:[N]f32,
  ley_cap:[N]f32,
  /// gatherable resource left on the tile (0 = no node). The item is decided by `kind`.
  res:[N]u8,
  /// occupant of each tile (see `Occ`).
  occ:[N]Occ,
  /// how many things the player grew here touch this chunk; a pinned chunk
  /// stays loaded so the garden keeps living off-screen.
  pins:u32 = 0,
  /// renderer-owned mesh slot, null until meshed.
  gpu_slot:?MeshSlot = null,
  dirty:bool = true,

  pub fn originX(c:*const Chunk) i32 { return c.at.x * SIZE; }
  pub fn originY(c:*const Chunk) i32 { return c.at.y * SIZE; }
  /// world tile (x, y) of local tile index `t` (inverse of `localIndex`).
  pub fn tileOf(c:*const Chunk, t:usize) [2]i32 {
    return .{c.originX() + @as(i32, @intCast(t % SIZE)), c.originY() + @as(i32, @intCast(t / SIZE))};
  }
};
