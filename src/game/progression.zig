//! research tree, discoveries and world events.
//!
//! research works like Factorio labs: a technology is chosen, then a research
//! structure in the world consumes its per-unit ingredients from its own
//! inventory, one unit at a time, until enough units are done. Nothing is
//! paid from a pool.
//!
//! Each technology is its own module under `research/` declaring:
//!   def:Research                  cost, prerequisites, branch  (required)
//!   apply(*ecology.Mods)          what it changes in the living world
//!   unlocks:[_]species.Id         species it lets the gardener plant
//!   completed(*Progression)       anything said or done when it is learned
//!   veil:f32                      how far it pulls the world-event veil
//!   reveals:[_]species.Id         species whose yield it makes visible
//!   study(*Study)                 what it teaches the labs (arsthraxias)
//! A new technology is one new file plus one line in `techs`.
const lib=@import("../lib.zig");
const std=lib.std;
const EnumArray=std.enums.EnumArray;
const copyBackwards=std.mem.copyBackwards;
const testing=std.testing;
const engine=lib.engine;
const m=engine.core.math;
const registry=engine.core.registry;
const species=lib.species;
const ecology=lib.ecology;
const items=lib.items;
const txt=lib.txt;
const ctext=engine.core.text;
const techs=struct{
  pub const leySight=@import("research/ley_sight.zig");
  pub const deepRooting=@import("research/deep_rooting.zig");
  pub const driftSpores=@import("research/drift_spores.zig");
  pub const rootCommunion=@import("research/root_communion.zig");
  pub const canopyWeaving=@import("research/canopy_weaving.zig");
  pub const hungeringTendrils=@import("research/hungering_tendrils.zig");
  pub const seedSplicing=@import("research/seed_splicing.zig");
  pub const thinningVeil=@import("research/thinning_veil.zig");
  pub const convergenceTheory=@import("research/convergence_theory.zig");
  pub const celestialDefragmentation=@import("research/celestial_defragmentation.zig");
  pub const arsthraxia=@import("research/arsthraxia.zig");
  pub const sapSatellites=@import("research/sap_satellites.zig");
  pub const condensingWhorl=@import("research/condensing_whorl.zig");
  pub const latticeOfThought=@import("research/lattice_of_thought.zig");
  pub const livingLooms=@import("research/living_looms.zig");
  pub const lithophagy=@import("research/lithophagy.zig");
  pub const braidedRoots=@import("research/braided_roots.zig");
  pub const sporeCasting=@import("research/spore_casting.zig");
  pub const wovenStone=@import("research/woven_stone.zig");
  pub const braidedDrift=@import("research/braided_drift.zig");
  pub const sharedNerves=@import("research/shared_nerves.zig");
  pub const interweaving=@import("research/interweaving.zig");
};
const reg=registry.Registry(techs);
pub const Discovery=enum{
  convergence,diamond,
  /// a pair of lineage structures grown side by side (structures `meets`):
  /// each opens the study of the convergent structure they would make
  loomAndStone,braidAndSpore,crownAndNerve,
  /// the two convergent structures grown side by side
  weftAndDrift,
};
pub const Id=reg.Id;
pub const Research=struct{
  /// ingredients consumed per unit, units needed, seconds per unit.
  perUnit:[]const items.Ingredient,
  units:u32,
  unitTime:f32,
  prereq:[]const Id=&.{},
  needs:?Discovery=null,
  /// a big step (new structures, species, a world event): grows as a branch
  /// of the research sapling; anything else is a leaf (hud/research.zig).
  branch:bool=false,
};
pub const tree=reg.table(Research,"def");
pub const Status=enum{done,open,locked};
/// for each species, the technology that must be known to plant it (null: always).
const plantGate=blk:{
  var gate=EnumArray(species.Id,?Id).initFill(null);
  for(reg.ids)|id|if(reg.has(id,"unlocks"))for(reg.module(id).unlocks)|sp|gate.set(sp,id);
  break:blk gate;
};
/// for each species, the technology that must be known to see its yield (null: always).
const yieldGate=blk:{
  var gate=EnumArray(species.Id,?Id).initFill(null);
  for(reg.ids)|id|if(reg.has(id,"reveals"))for(reg.module(id).reveals)|sp|gate.set(sp,id);
  break:blk gate;
};
/// what research has taught the labs, summed over what is known (`study`
/// hooks).
pub const Study=struct{
  /// how fast a lab condenses a unit by itself, unfed, as a share of the
  /// pace it works one it has eaten the ingredients of
  unfed:f32=unfed,
  /// how fast it works, fed or not
  speed:f32=1,
  /// how many times the labs have grown (each an offshoot, a satellite)
  growth:u32=0,
  /// the labs' thought has quickened (Arsthraxia): vines climb them
  vines:bool=false,
};
/// a lab condenses this share of its fed pace unfed, knowing nothing yet
const unfed:f32=0.2;
/// one growth of the labs (a minor study along Arsthraxia)
const flourishUnfed:f32=0.1;
pub fn flourish(s:*Study)void{
  s.growth+=1;
  s.unfed+=flourishUnfed;
}
/// working state of one research structure: the unit it condenses.
pub const Lab=struct{
  /// how far along the unit is (0..1)
  t:f32=0,
  /// its ingredients have been eaten: it goes at the full pace
  fed:bool=false,
  /// it is condensing (a study is chosen)
  active:bool=false,
  /// share of the current study it adds a second (0..1)
  pub fn pace(lab:*const Lab,g:*const Progression,s:Study)f32{
    const id=g.current orelse return 0;
    const r=tree.get(id);
    return(if(lab.fed)@as(f32,1)else s.unfed)*s.speed/(r.unitTime*m.f(r.units));
  }
};
const logLen=6;
const msgBuf:usize=96;
pub const Message=struct{
  buf:[msgBuf]u8=undefined,
  len:usize=0,
  age:f32=0,
};
/// seconds before a batch of withered plants is reported (avoids log spam)
const witherBatch:f32=2;
/// how quickly the veil eases toward its target (per second)
const veilEase:f32=0.3;
pub const Progression=struct{
  done:std.EnumSet(Id)=.initEmpty(),
  found:std.EnumSet(Discovery)=.initEmpty(),
  /// world event blend 0..1 (sky/glow shift after the veil thins).
  veil:f32=0,
  log:[logLen]Message=@splat(.{}),
  /// the technology every lab works on, and units finished per technology.
  current:?Id=null,
  progress:std.EnumArray(Id,u32)=.initFill(0),
  /// withered plants are reported in batches, not every tick.
  died:u32=0,
  diedT:f32=0,
  /// `tpl` is a runtime template (`core/text.zig`), usually `txt.s.msg.*`.
  pub fn say(g:*Progression,tpl:[]const u8,args:anytype)void{
    copyBackwards(Message,g.log[1..],g.log[0..g.log.len-1]);
    const msg=&g.log[0];
    msg.*=.{};
    // if the message is too long it silently truncates to the buffer size
    msg.len=ctext.bufRender(&msg.buf,tpl,args).len;
  }
  pub fn status(g:*const Progression,id:Id)Status{
    if(g.done.contains(id))return.done;
    const r=tree.get(id);
    for(r.prereq)|p|if(!g.done.contains(p))return.locked;
    if(r.needs)|d|if(!g.found.contains(d))return.locked;
    return.open;
  }
  pub fn select(g:*Progression,id:Id)void{
    const name=txt.research(id).name;
    switch(g.status(id)){
      .open=>{g.current=id;g.say(txt.s.msg.researching,.{name});},
      .done=>g.say(txt.s.msg.alreadyKnown,.{name}),
      .locked=>g.say(txt.s.msg.locked,.{name}),
    }
  }
  /// what the labs have been taught, from everything known.
  pub fn study(g:*const Progression)Study{
    var s:Study=.{};
    inline for(reg.ids)|id|{
      if(comptime reg.has(id,"study"))if(g.done.contains(id))reg.module(id).study(&s);
    }
    return s;
  }
  /// advance one research structure. `inv` is the structure's own
  /// inventory: it eats a unit's ingredients from it when it has them and
  /// works the unit at full pace, else condenses it by itself at
  /// `Study.unfed` of that. Returns whether it finished a unit.
  pub fn labTick(g:*Progression,lab:*Lab,inv:items.Bag,s:Study,dt:f32)bool{
    const id=g.current orelse {
      lab.active=false;
      return false;
    };
    const r=tree.get(id);
    if(!lab.fed)feed:{
      for(r.perUnit)|ing|if(inv.count(ing.item)<ing.n)break:feed;
      for(r.perUnit)|ing|_=inv.take(ing.item,ing.n);
      lab.fed=true;
    }
    const rate=(if(lab.fed)@as(f32,1)else s.unfed)*s.speed;
    lab.active=rate>0;
    lab.t+=dt*rate/r.unitTime;
    if(lab.t<1)return false;
    lab.t=0;
    lab.fed=false;
    // another lab may have finished it while this unit was in progress
    if(g.done.contains(id))return false;
    const p=g.progress.getPtr(id);
    p.*+=1;
    if(p.*>=r.units)g.complete(id);
    return true;
  }
  fn complete(g:*Progression,id:Id)void{
    g.done.insert(id);
    if(g.current==id)g.current=null;
    g.say(txt.s.msg.researched,.{txt.research(id).name});
    switch(id){
      inline else=>|k|if(comptime reg.has(k,"completed"))reg.module(k).completed(g),
    }
  }
  pub fn canPlant(g:*const Progression,sp:species.Id)bool{
    const gate=plantGate.get(sp) orelse return true;
    return g.done.contains(gate);
  }
  /// does the gardener know what this species condenses?
  pub fn yieldKnown(g:*const Progression,sp:species.Id)bool{
    const gate=yieldGate.get(sp) orelse return true;
    return g.done.contains(gate);
  }
  /// something witnessed in the garden, said once.
  pub fn discover(g:*Progression,d:Discovery)void{
    if(g.found.contains(d))return;
    g.found.insert(d);
    switch(d){
      .convergence=>{
        g.say(txt.s.msg.entwine,.{});
        g.say(txt.s.msg.hybridStirs,.{});
      },
      .diamond=>{
        g.say(txt.s.msg.latticeStirs,.{});
      },
      .loomAndStone=>{
        g.say(txt.s.msg.loomMeetsStone,.{});
        g.say(txt.s.msg.researchNamed,.{txt.research(.wovenStone).name});
      },
      .braidAndSpore=>{
        g.say(txt.s.msg.braidMeetsSpore,.{});
        g.say(txt.s.msg.researchNamed,.{txt.research(.braidedDrift).name});
      },
      .crownAndNerve=>{
        g.say(txt.s.msg.crownMeetsNerve,.{});
        g.say(txt.s.msg.researchNamed,.{txt.research(.sharedNerves).name});
      },
      .weftAndDrift=>{
        g.say(txt.s.msg.weftMeetsDrift,.{});
        g.say(txt.s.msg.researchNamed,.{txt.research(.interweaving).name});
      },
    }
  }
  /// the living world as shaped by everything learned so far.
  pub fn mods(g:*const Progression)ecology.Mods{
    var md:ecology.Mods=.{};
    inline for(reg.ids)|id|{
      if(comptime reg.has(id,"apply"))if(g.done.contains(id))reg.module(id).apply(&md);
    }
    return md;
  }
  /// where the world-event veil is heading, from what has been learned.
  fn veilTarget(g:*const Progression)f32{
    var v:f32=0;
    inline for(reg.ids)|id|{
      if(comptime reg.has(id,"veil"))if(g.done.contains(id)){v=@max(v,reg.module(id).veil);};
    }
    return v;
  }
  pub fn absorb(g:*Progression,ev:ecology.Events,dt:f32)void{
    g.died+=ev.died;
    g.diedT+=dt;
    if(g.diedT>witherBatch){
      if(g.died>0)g.say(txt.s.msg.withered,.{g.died});
      g.died=0;
      g.diedT=0;
    }
    g.veil+=(g.veilTarget()-g.veil)*@min(1,dt*veilEase);
    for(&g.log)|*msg|msg.age+=dt;
  }
};
test"labs consume ingredients unit by unit"{
  var g:Progression=.{};
  var lab:Lab=.{};
  var inv:items.Inventory(8)=.{};
  // labs that condense nothing unfed only work what they are fed
  const fedOnly:Study=.{.unfed=0};
  g.select(.seedSplicing);
  try testing.expect(g.current==null); // locked
  g.select(.leySight);
  try testing.expect(g.current==.leySight);
  // no ingredients: nothing happens
  _=g.labTick(&lab,inv.bag(),fedOnly,10);
  try testing.expect(!lab.fed and lab.t==0);
  _=inv.add(.starlight,20);
  var t:f32=0;
  while(t<60):(t+=0.1)_=g.labTick(&lab,inv.bag(),fedOnly,0.1);
  try testing.expect(g.done.contains(.leySight));
  try testing.expectEqual(@as(u32,10),inv.count(.starlight));
  try testing.expect(g.current==null);
  // convergence gates splicing even once prerequisites are done
  g.done.insert(.rootCommunion);
  g.done.insert(.hungeringTendrils);
  try testing.expect(g.status(.seedSplicing)==.locked);
  try testing.expect(g.status(.convergenceTheory)==.locked);
  try testing.expect(!g.yieldKnown(.confluence) and g.yieldKnown(.lumenroot));
  g.discover(.convergence);
  try testing.expect(g.status(.seedSplicing)==.open);
  try testing.expect(g.status(.convergenceTheory)==.open);
  g.done.insert(.convergenceTheory);
  try testing.expect(g.yieldKnown(.confluence));
}
test"an unfed lab condenses research by itself, faster along Arsthraxia"{
  var g:Progression=.{};
  var lab:Lab=.{};
  var inv:items.Inventory(8)=.{};
  g.select(.leySight);
  const r=tree.get(.leySight);
  // a fifth of the fed pace: one unit takes five unit times
  var s=g.study();
  try testing.expectApproxEqAbs(unfed,s.unfed,1e-6);
  var t:f32=0;
  while(t<r.unitTime*5+0.05):(t+=0.1)_=g.labTick(&lab,inv.bag(),s,0.1);
  try testing.expectEqual(@as(u32,1),g.progress.get(.leySight));
  try testing.expect(lab.active and !lab.fed);
  // the line quickens it and grows the labs once per minor study
  for([_]Id{.arsthraxia,.sapSatellites,.condensingWhorl})|id|g.done.insert(id);
  s=g.study();
  try testing.expectEqual(@as(u32,2),s.growth);
  try testing.expect(s.unfed>unfed+0.35 and s.speed>1);
  try testing.expect(lab.pace(&g,s)>lab.pace(&g,.{}));
}
