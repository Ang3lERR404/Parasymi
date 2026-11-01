//! the garden's chunk: a 32x32 block of tiles (engine world/chunk.zig),
//! stored as struct-of-arrays so hot loops stay linear.
const lib=@import("../lib.zig");
/// the engine package, reached through the hub
const engine=lib.engine;
/// all the maths: the largest number a word holds
const m=engine.core.math;
/// the engine's chunk grid: sizes, coordinates and indexing
const grid=engine.world.chunk;
/// how many tiles a chunk is across (and down)
pub const sizeTiles=grid.sizeTiles;
/// how many tiles a chunk holds
pub const tileCount=grid.tileCount;
/// a chunk's place on the grid, in chunks
pub const Coord=grid.Coord;
/// which of the renderer's ground buffers a chunk is meshed into
pub const MeshSlot=grid.MeshSlot;
/// the index within its chunk of a world tile
pub const localIndex=grid.localIndex;
/// how much a resource node holds (thousands, so a node lasts)
pub const Res=u16;
/// the word that marks an empty link: every bit set
const noneId:u32=m.maxInt(u32);
/// what a tile's ground is
pub const Kind=enum(u8){
  /// plain brown earth
  soil,
  /// soft green moss
  moss,
  /// bare grey stone, where nothing roots
  stone,
  /// violet ground over a ley line, rich in mana
  ley,
  /// tiles a seed can take root in.
  pub fn fertile(k:Kind)bool{return k==.soil or k==.moss or k==.ley;}
};
/// a plant's slot in `sim/plants.zig`. Distinct from `StructId` so the two
/// can never be mixed up; `none` marks an empty link.
pub const PlantId=enum(u32){
  /// no plant: an empty link
  none=noneId,
  _,
  /// the id of the plant in slot `i`
  pub fn of(i:usize)PlantId{return@enumFromInt(i);}
  /// the slot this plant sits in
  pub fn idx(p:PlantId)usize{return@intFromEnum(p);}
};
/// a structure's slot in `game/structures.zig`.
pub const StructId=enum(u32){
  _,
  /// the id of the structure in slot `i`
  pub fn of(i:usize)StructId{return@enumFromInt(i);}
  /// the slot this structure sits in
  pub fn idx(s:StructId)usize{return@intFromEnum(s);}
};
/// what sits on a tile: a rooted plant, a structure, or nothing, packed into
/// one word (the top bit tells structures apart). Floating plants occupy no tile.
pub const Occ=enum(u32){
  /// nothing on the tile
  none=noneId,
  _,
  /// the top bit, set for a structure
  const structBit:u32=1<<31;
  /// a tile's occupant unpacked: nothing, a plant, or a structure
  pub const Occupant=union(enum){
    /// nothing stands there
    empty,
    /// a rooted plant stands there
    plant:PlantId,
    /// a structure stands there
    structure:StructId,
  };
  /// the word for plant `p` on a tile
  pub fn plant(p:PlantId)Occ{return@enumFromInt(@intFromEnum(p));}
  /// the word for structure `s` on a tile
  pub fn structure(s:StructId)Occ{return@enumFromInt(@intFromEnum(s)|structBit);}
  /// unpacks the word into what it names
  pub fn get(o:Occ)Occupant{
    if(o==.none)return.empty;
    // the word itself
    const v=@intFromEnum(o);
    return if(v&structBit!=0).{.structure=@enumFromInt(v&~structBit)}else.{.plant=@enumFromInt(v)};
  }
  /// the plant on the tile, or null
  pub fn asPlant(o:Occ)?PlantId{
    return switch(o.get()){.plant=>|p|p,.empty,.structure=>null};
  }
  /// the structure on the tile, or null
  pub fn asStructure(o:Occ)?StructId{
    return switch(o.get()){.structure=>|s|s,.empty,.plant=>null};
  }
};
/// a chunk at `at` with its tiles not yet filled (the generator fills them)
pub fn blank(at:Coord)Chunk{
  return.{.at=at,.height=undefined,.kind=undefined,.ley=undefined,.leyCap=undefined,
    .water=undefined,.waterCap=undefined,.res=undefined,.occ=undefined};
}
/// one 32x32 block of the world: each tile's ground, mana, resource and occupant
pub const Chunk=struct{
  /// its place on the grid, in chunks
  at:Coord,
  /// each tile's ground height
  height:[tileCount]f32,
  /// each tile's ground kind
  kind:[tileCount]Kind,
  /// ambient ley mana currently in the tile, and how much it refills to.
  ley:[tileCount]f32,
  /// the most ley mana each tile refills to
  leyCap:[tileCount]f32,
  /// the water in the ground under each tile now (0..1 of a tile soaked
  /// through), which roots drink and which slowly comes back
  water:[tileCount]f32,
  /// the water each tile's ground holds when it has been left alone: wet
  /// where moss grows, dry on stone and high ground
  waterCap:[tileCount]f32,
  /// how wet the rain has left each tile's ground (0 dry .. 1 wet
  /// through), read back from the air once a second (game/weather.zig;
  /// not saved: dry until it rains)
  wet:[tileCount]f32=@splat(0),
  /// how deep the rain stands pooled over each tile (m), read back with
  /// `wet` (not saved)
  pool:[tileCount]f32=@splat(0),
  /// gatherable resource left on the tile (0 = no node). The item is decided by `kind`.
  res:[tileCount]Res,
  /// occupant of each tile (see `Occ`).
  occ:[tileCount]Occ,
  /// how many things the player grew here touch this chunk; a pinned chunk
  /// stays loaded so the garden keeps living off-screen.
  pins:u32=0,
  /// renderer-owned mesh slot, null until meshed.
  gpuSlot:?MeshSlot=null,
  /// whether its ground must be meshed again
  dirty:bool=true,
  /// whether its ley lines have sealed (the unforming: gen.sealOf); its
  /// ground is meshed so, and so are its neighbours from the generator
  sealed:bool=false,
  /// its first tile's world x
  pub fn originX(c:*const Chunk)i32{return c.at.x*sizeTiles;}
  /// its first tile's world y (z in the world)
  pub fn originY(c:*const Chunk)i32{return c.at.y*sizeTiles;}
  /// world tile (x, y) of local tile index `t` (inverse of `localIndex`).
  pub fn tileOf(c:*const Chunk,t:usize)m.Vice(i32,2){return grid.tileOf(c.at,t);}
};
