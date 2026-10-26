//! the grid every world is cut into: square chunks of tiles, addressed by
//! chunk coordinate, each tile by its index inside its chunk. What a tile
//! holds is the game's (its `Chunk`, see world/world.zig).

pub const SIZE = 32;
pub const N = SIZE * SIZE;

pub const Coord = struct {
  x:i32, y:i32,
  pub fn ofTile(wx:i32, wy:i32) Coord {
    return .{.x = @divFloor(wx, SIZE), .y = @divFloor(wy, SIZE)};
  }
};

/// a renderer-owned mesh slot (the world only keeps it for the renderer).
pub const MeshSlot = enum(u32) { _ };

pub inline fn localIndex(wx:i32, wy:i32) usize {
  const lx:usize = @intCast(@mod(wx, SIZE));
  const ly:usize = @intCast(@mod(wy, SIZE));
  return ly * SIZE + lx;
}

/// world tile (x, y) of local tile index `t` in the chunk at `at` (inverse
/// of `localIndex`).
pub fn tileOf(at:Coord, t:usize) [2]i32 {
  return .{at.x * SIZE + @as(i32, @intCast(t % SIZE)), at.y * SIZE + @as(i32, @intCast(t / SIZE))};
}
