//! the garden's chunk: a 32x32 block of tiles (engine world/chunk.zig),
//! stored as struct-of-arrays so hot loops stay linear.
const lib=@import("../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const grid=engine.world.chunk;
pub const sizeTiles=grid.sizeTiles;
pub const tileCount=grid.tileCount;
pub const Coord=grid.Coord;
pub const MeshSlot=grid.MeshSlot;
pub const localIndex=grid.localIndex;
/// how much a resource node holds (thousands, so a node lasts)
pub const Res=u16;
const noneId:u32=m.maxInt(u32);
pub const Kind=enum(u8){
  soil,moss,stone,ley,
  /// tiles a seed can take root in.
  pub fn fertile(k:Kind)bool{return k==.soil or k==.moss or k==.ley;}
};
/// a plant's slot in `sim/plants.zig`. Distinct from `StructId` so the two
/// can never be mixed up; `none` marks an empty link.
pub const PlantId=enum(u32){
  none=noneId,
  _,
  pub fn of(i:usize)PlantId{return@enumFromInt(i);}
  pub fn idx(p:PlantId)usize{return@intFromEnum(p);}
};
/// a structure's slot in `game/structures.zig`.
pub const StructId=enum(u32){
  _,
  pub fn of(i:usize)StructId{return@enumFromInt(i);}
  pub fn idx(s:StructId)usize{return@intFromEnum(s);}
};
/// what sits on a tile: a rooted plant, a structure, or nothing, packed into
/// one word (the top bit tells structures apart). Floating plants occupy no tile.
pub const Occ=enum(u32){
  none=noneId,
  _,
  const structBit:u32=1<<31;
  pub const Occupant=union(enum){empty,plant:PlantId,structure:StructId};
  pub fn plant(p:PlantId)Occ{return@enumFromInt(@intFromEnum(p));}
  pub fn structure(s:StructId)Occ{return@enumFromInt(@intFromEnum(s)|structBit);}
  pub fn get(o:Occ)Occupant{
    if(o==.none)return.empty;
    const v=@intFromEnum(o);
    return if(v&structBit!=0).{.structure=@enumFromInt(v&~structBit)}else.{.plant=@enumFromInt(v)};
  }
  pub fn asPlant(o:Occ)?PlantId{
    return switch(o.get()){.plant=>|p|p,.empty,.structure=>null};
  }
  pub fn asStructure(o:Occ)?StructId{
    return switch(o.get()){.structure=>|s|s,.empty,.plant=>null};
  }
};
pub fn blank(at:Coord)Chunk{
  return.{.at=at,.height=undefined,.kind=undefined,.ley=undefined,.leyCap=undefined,
    .res=undefined,.occ=undefined};
}
pub const Chunk=struct{
  at:Coord,
  height:[tileCount]f32,
  kind:[tileCount]Kind,
  /// ambient ley mana currently in the tile, and how much it refills to.
  ley:[tileCount]f32,
  leyCap:[tileCount]f32,
  /// gatherable resource left on the tile (0 = no node). The item is decided by `kind`.
  res:[tileCount]Res,
  /// occupant of each tile (see `Occ`).
  occ:[tileCount]Occ,
  /// how many things the player grew here touch this chunk; a pinned chunk
  /// stays loaded so the garden keeps living off-screen.
  pins:u32=0,
  /// renderer-owned mesh slot, null until meshed.
  gpuSlot:?MeshSlot=null,
  dirty:bool=true,
  pub fn originX(c:*const Chunk)i32{return c.at.x*sizeTiles;}
  pub fn originY(c:*const Chunk)i32{return c.at.y*sizeTiles;}
  /// world tile (x, y) of local tile index `t` (inverse of `localIndex`).
  pub fn tileOf(c:*const Chunk,t:usize)[2]i32{return grid.tileOf(c.at,t);}
};
