//! per-structure hooks the HUD, the renderer and the garden ask through.
const lib=@import("../../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type drawing and gathering may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths and the UI's draw batch
const engine=lib.engine;
/// all the maths: vectors for where a structure stands
const m=engine.core.math;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// every species, for what a plant yields
const species=lib.species;
/// every plant in the garden
const Plants=lib.plants.Plants;
/// a field of celestial energy, as the ecology reads it
const Field=lib.ecology.Field;
/// what the gardener has understood
const prog=lib.progression;
/// the scene's list of moving parts a structure adds to
const Parts=lib.parts.Parts;
/// the UI's draw batch, which hover text goes into
const Draw=engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=engine.ui.draw.Color;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// a placed structure's slot in the list
const Id=lib.structures.Id;
/// which kind of structure
const Kind=lib.structures.Kind;
/// a plant's id
const PlantId=lib.structures.PlantId;
/// one placed structure
const Structure=lib.structures.structure.Structure;
/// the garden's list of structures
const Structures=lib.structures.list.Structures;
/// the structures registry: which kinds have which hooks
const reg=lib.structures.reg;
/// a floating plant a structure draws in toward itself: how far along the
/// way it is (`k`: 0 leaving its tile .. 1 there; the GPU moves it, see
/// common.glsl `haloSpiral`) and how high over the structure's ground it
/// is drawn to (`seat`).
pub const Hold=struct{k:f32,seat:f32};
/// every field of celestial energy a structure holds, into `out`.
pub fn fields(ss:*const Structures,gpa:Allocator,out:*std.ArrayList(Field))Allocator.Error!void{
  out.clearRetainingCapacity();
  for(ss.list.items)|*s|switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"field"))if(reg.module(k).field(s))|f|try out.append(gpa,f),
  };
}
/// the structure drawing the floater at a tile toward itself, if any.
pub fn hold(ss:*const Structures,wx:i32,wy:i32)?struct{s:*const Structure,h:Hold}{
  for(ss.list.items)|*s|switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"hold"))if(reg.module(k).hold(s,wx,wy))|h|return.{.s=s,.h=h},
  };
  return null;
}
/// take back one thing a structure holds outside its slots (a lane's
/// item, a carried one), or null if it holds none there
pub fn release(s:*Structure)?items.Item{
  return switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"release"))reg.module(k).release(s)else null,
  };
}
/// what a click on it hands the wolf straight away, taken out of it (a
/// polyp's drifting flower, pulled from the air); null: a click does what
/// it otherwise does
pub fn handOver(s:*Structure)?items.Item{
  return switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"handOver"))reg.module(k).handOver(s)else null,
  };
}
/// does kind `k` do anything when configured?
pub fn configurable(k:Kind)bool{
  return switch(k){
    inline else=>|t|comptime reg.has(t,"configure"),
  };
}
/// the player's configure key on structure `id`: whatever its kind does
/// (pairing, tethering), or nothing
pub fn configure(ss:*Structures,id:Id,g:*prog.Progression)void{
  switch(ss.get(id).kind()){
    inline else=>|k|if(comptime reg.has(k,"configure"))reg.module(k).configure(ss,id,g),
  }
}
/// what kind `k`'s panel offers to weave, as indices into its recipe
/// table, as far as the gardener's garden has come (`g`; empty: it
/// weaves nothing)
pub fn recipes(k:Kind,g:*const prog.Progression)[]const u8{
  return switch(k){
    inline else=>|t|if(comptime reg.has(t,"recipes"))reg.module(t).recipes(g)else&.{},
  };
}
/// the recipe structure `s` weaves now (an index into its `recipes`), or
/// null if none is chosen
pub fn chosen(s:*const Structure)?u8{
  return switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"chosen"))reg.module(k).chosen(s)else null,
  };
}
/// set the recipe structure `s` weaves to `r` (its own hook decides
/// whether the gardener may yet)
pub fn choose(s:*Structure,g:*prog.Progression,r:u8)void{
  switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"choose"))reg.module(k).choose(s,g,r),
  }
}
/// add structure `s`'s extra moving parts beyond its mesh to `out`, at
/// its centre `ctr` and the time `tf` (seconds)
pub fn emit(s:*const Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"emit"))try reg.module(k).emit(s,out,ctr,tf),
  }
}
/// write structure `s`'s line of hover text into `d` at `x`,`y`
pub fn describe(s:*const Structure,d:*Draw,g:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"describe"))try reg.module(k).describe(s,d,g,x,y),
  }
}
/// draws kind `k`'s bulb in the HUD, its seed tinted `col`.
pub fn icon(k:Kind,ic:iconKit.Icon,col:Color)Allocator.Error!void{
  switch(k){
    inline else=>|t|if(comptime reg.has(t,"icon"))try reg.module(t).icon(ic,col)else try iconKit.plain(ic,col),
  }
}
/// take one ripe unit of a mature plant's yield (plants never set seed).
pub fn harvestOne(plants:*Plants,id:PlantId)?items.Item{
  // the plant's row, and every plant's columns
  const p=id.idx();
  const s=plants.list.slice();
  if(s.items(.growth)[p]<1 or s.items(.essence)[p]<1)return null;
  s.items(.essence)[p]-=1;
  return species.get(s.items(.sp)[p]).yields;
}
