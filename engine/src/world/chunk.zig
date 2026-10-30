//! the grid every world is cut into: square chunks of tiles, addressed by
//! chunk coordinate, each tile by its index inside its chunk. What a tile
//! holds is the game's (its `Chunk`, see world/world.zig).
/// a chunk's side, in tiles
pub const sizeTiles=32;
/// how many tiles one chunk holds
pub const tileCount=sizeTiles*sizeTiles;
/// a chunk's coordinate: which chunk along x and along y (world z)
pub const Coord=struct{
  /// the chunk's place along x
  x:i32,
  /// the chunk's place along y (world z)
  y:i32,
  /// the chunk holding world tile (wx, wy)
  pub fn ofTile(wx:i32,wy:i32)Coord{
    return.{.x=@divFloor(wx,sizeTiles),.y=@divFloor(wy,sizeTiles)};
  }
};
/// a renderer-owned mesh slot (the world only keeps it for the renderer).
pub const MeshSlot=enum(u32){_};
/// a tile's index inside its chunk, row by row, from its world tile (wx, wy)
pub inline fn localIndex(wx:i32,wy:i32)usize{
  // the tile's place inside its chunk, along x and along y
  const lx:usize=@intCast(@mod(wx,sizeTiles));
  const ly:usize=@intCast(@mod(wy,sizeTiles));
  return ly*sizeTiles+lx;
}
/// world tile (x, y) of local tile index `t` in the chunk at `at` (inverse
/// of `localIndex`).
pub fn tileOf(at:Coord,t:usize)[2]i32{
  return.{at.x*sizeTiles+@as(i32,@intCast(t%sizeTiles)),at.y*sizeTiles+@as(i32,@intCast(t/sizeTiles))};
}
