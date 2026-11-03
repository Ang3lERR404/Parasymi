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
/// the light grid: a structure's relay, and one that draws light
const light=lib.light;
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
/// the structures' part in the light grid this tick: every relay one
/// holds (its `relay` hook) into `relays`, and every one that takes light
/// (its `Use` not `.none`) into `users`, its slot into `ids` beside it
pub fn lightGrid(ss:*const Structures,gpa:Allocator,relays:*std.ArrayList(light.Relay),users:*std.ArrayList(light.User),ids:*std.ArrayList(Id))Allocator.Error!void{
  relays.clearRetainingCapacity();
  users.clearRetainingCapacity();
  ids.clearRetainingCapacity();
  for(ss.list.items,0..)|*s,i|{
    switch(s.kind()){
      inline else=>|k|if(comptime reg.has(k,"relay"))if(reg.module(k).relay(s))|r|try relays.append(gpa,r),
    }
    if(lightUse(s)==.none or s.grown<1 or s.fade>0)continue;
    try users.append(gpa,.{.at=s.at,.draw=draws(s)});
    try ids.append(gpa,.of(i));
  }
}
/// how structure `s` takes light now (its `lightUse` hook, else its kind's
/// `Def.light`: the arsthraxia needs it only until it evolves)
pub fn lightUse(s:*const Structure)lib.structures.Use{
  return switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"lightUse"))reg.module(k).lightUse(s)else s.def().light,
  };
}
/// how much light structure `s` draws at full work (its `draws` hook, else
/// its kind's `Def.draws`: a lithophage draws more the further it reaches)
pub fn draws(s:*const Structure)f32{
  return switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"draws"))reg.module(k).draws(s)else s.def().draws,
  };
}
/// how many seconds of work structure `s` does in `dt` by its light: a
/// boost works up to `light.boost` faster, what needs light works as fast
/// as its light allows and not at all short of `light.needAt`
pub fn workTime(s:*const Structure,dt:f32)f32{
  return switch(lightUse(s)){
    .none,.looks=>dt,
    .boost=>dt*(1+boost*s.lit),
    .needs=>if(s.lit<light.needAt)0 else dt*s.lit,
  };
}
/// how much faster a boosted structure works in whole light (0.5: 1.5x)
pub const boost:f32=0.5;
/// the structure drawing the floater at a tile toward itself, if any.
pub fn hold(ss:*const Structures,wx:i32,wy:i32)?struct{s:*const Structure,h:Hold}{
  for(ss.list.items)|*s|switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"hold"))if(reg.module(k).hold(s,wx,wy))|h|return.{.s=s,.h=h},
  };
  return null;
}
/// the gardener has just put structure `s` down by hand, in act `a`
/// (`sown`: the strange seed is planted only in the hyena's)
pub fn sown(s:*Structure,a:lib.act.Act)void{
  switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"sown"))reg.module(k).sown(s,a),
  }
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
/// how much moisture a structure breathes into the air: within `reach`
/// (units) of its centre (moved by `off`, world x and z), `low` a second
/// into the mist on the ground and `high` into the cloud over it
pub const Breath=struct{reach:f32,low:f32,high:f32,off:m.Vice(f32,2)=.{0,0},water:f32=0};
/// what structure `s` breathes into the air, if anything (its `breath` hook)
pub fn breath(s:*const Structure)?Breath{
  return switch(s.kind()){
    inline else=>|k|if(comptime reg.has(k,"breath"))reg.module(k).breath(s)else null,
  };
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
/// take one ripe unit of a mature plant's yield (plants never set seed): a
/// rare one first, while it holds any (`Plants.takeYield`)
pub fn harvestOne(plants:*Plants,id:PlantId)?items.Item{
  if(plants.list.items(.growth)[id.idx()]<1)return null;
  // what one unit taken gives, if it holds one
  const got=plants.takeYield(id,1);
  if(got.rare>0)return species.get(plants.list.items(.sp)[id.idx()]).rareYield();
  return if(got.plain>0)species.get(plants.list.items(.sp)[id.idx()]).yields else null;
}
