//! a 32x32 block of tiles, stored as struct-of-arrays so hot loops stay linear.
const std = @import("std");

pub const SIZE = 32;
pub const N = SIZE * SIZE;
pub const NONE:u32 = std.math.maxInt(u32);

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

/// what sits on a tile: a rooted plant or a structure (by index), or NONE.
/// Floating plants occupy no tile.
pub const Occ = struct {
  pub const STRUCT:u32 = 1 << 31;
  pub fn plant(i:u32) u32 { return i; }
  pub fn structure(i:u32) u32 { return i | STRUCT; }
  pub fn isStructure(o:u32) bool { return o != NONE and o & STRUCT != 0; }
  pub fn isPlant(o:u32) bool { return o != NONE and o & STRUCT == 0; }
  pub fn index(o:u32) u32 { return o & ~STRUCT; }
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
  occ:[N]u32,
  /// how many things the player grew here touch this chunk; a pinned chunk
  /// stays loaded so the garden keeps living off-screen.
  pins:u32 = 0,
  /// renderer-owned mesh slot, NONE until meshed.
  gpu_slot:u32 = NONE,
  dirty:bool = true,

  pub fn originX(c:*const Chunk) i32 { return c.at.x * SIZE; }
  pub fn originY(c:*const Chunk) i32 { return c.at.y * SIZE; }
};
