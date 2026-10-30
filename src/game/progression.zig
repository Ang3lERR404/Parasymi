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
/// the standard library, reached through the hub
const std=lib.std;
/// a table with one slot per enum tag, for the per-species gates
const EnumArray=std.enums.EnumArray;
/// shifts the log's lines down a place, oldest falling off the end
const copyBackwards=std.mem.copyBackwards;
/// the test harness
const testing=std.testing;
/// the engine package: maths, registry, text
const engine=lib.engine;
/// all the maths: vectors, easing, the int-to-float cast
const m=engine.core.math;
/// the registry machinery that turns `techs` into ids and hook lookups
const registry=engine.core.registry;
/// the species registry, for what a study lets be planted or seen
const species=lib.species;
/// the living world's tick, whose modifiers research shapes
const ecology=lib.ecology;
/// what can be held: item kinds, ingredients, bags
const items=lib.items;
/// every player-facing string, including each study's name
const txt=lib.txt;
/// the runtime string templates the log's messages are rendered with
const ctext=engine.core.text;
/// every technology, one module each under `research/`, in tree order
const techs=struct{
  /// first light: the ley currents beneath the ground made visible
  pub const leySight=@import("research/ley_sight.zig");
  /// root-diggers, which work the nodes for the wolf
  pub const deepRooting=@import("research/deep_rooting.zig");
  /// the first floaters, driftwisps
  pub const driftSpores=@import("research/drift_spores.zig");
  /// symbiotic links reaching a second ring of neighbours
  pub const rootCommunion=@import("research/root_communion.zig");
  /// hollowhearts, the first plants larger than a tile
  pub const canopyWeaving=@import("research/canopy_weaving.zig");
  /// parasites draining twice as hard
  pub const hungeringTendrils=@import("research/hungering_tendrils.zig");
  /// vesper seeds, spliced from both lineages
  pub const seedSplicing=@import("research/seed_splicing.zig");
  /// the first world event: the veil thins
  pub const thinningVeil=@import("research/thinning_veil.zig");
  /// what the confluence gives, where the lineages meet
  pub const convergenceTheory=@import("research/convergence_theory.zig");
  /// study of the diamond a halo leaves
  pub const celestialDefragmentation=@import("research/celestial_defragmentation.zig");
  /// the bloom that studies: the labs' thought quickens
  pub const arsthraxia=@import("research/arsthraxia.zig");
  /// the first minor study along arsthraxia: the labs grow once
  pub const sapSatellites=@import("research/sap_satellites.zig");
  /// the second minor study along arsthraxia: they grow again
  pub const condensingWhorl=@import("research/condensing_whorl.zig");
  /// the third minor study along arsthraxia, the last
  pub const latticeOfThought=@import("research/lattice_of_thought.zig");
  /// loomferns and gathering crowns
  pub const livingLooms=@import("research/living_looms.zig");
  /// lithophages and ganglia: parasites feeding on stone
  pub const lithophagy=@import("research/lithophagy.zig");
  /// braided conduits, four lanes in one weave
  pub const braidedRoots=@import("research/braided_roots.zig");
  /// sporecasters, sending however far
  pub const sporeCasting=@import("research/spore_casting.zig");
  /// weftstones, born of a loomfern and a lithophage
  pub const wovenStone=@import("research/woven_stone.zig");
  /// driftbraids, born of a braided conduit and a sporecaster
  pub const braidedDrift=@import("research/braided_drift.zig");
  /// the vultrixi, born of a crown and a ganglion
  pub const sharedNerves=@import("research/shared_nerves.zig");
  /// monfris, born of a weftstone and a driftbraid
  pub const interweaving=@import("research/interweaving.zig");
};
/// the registry over `techs`: ids, `has` and `module` for the hooks
const reg=registry.Registry(techs);
/// something witnessed in the garden that opens a study (`needs`)
pub const Discovery=enum{
  /// the lineages seen to converge on one plant
  convergence,
  /// a diamond formed where a halo was
  diamond,
  /// a loomfern grown beside a lithophage (structures `meets`): opens the
  /// study of the weftstone they would make together
  loomAndStone,
  /// a braided conduit grown beside a sporecaster: opens the driftbraid's study
  braidAndSpore,
  /// a gathering crown grown beside a ganglion: opens the vultrixi's study
  crownAndNerve,
  /// the two convergent structures grown side by side: opens the study of monfris
  weftAndDrift,
};
/// a technology's id, one per module in `techs`
pub const Id=reg.Id;
/// what a technology is: its cost, what it waits on, and its place in the tree
pub const Research=struct{
  /// the ingredients one unit eats from a lab's inventory
  perUnit:[]const items.Ingredient,
  /// how many units the whole study takes
  units:u32,
  /// seconds one fed unit takes to condense
  unitTime:f32,
  /// the studies that must be known first (none: open from the start)
  prereq:[]const Id=&.{},
  /// what must have been witnessed in the garden first, if anything
  needs:?Discovery=null,
  /// a big step (new structures, species, a world event): grows as a branch
  /// of the research sapling; anything else is a leaf (hud/research.zig).
  branch:bool=false,
};
/// every technology's `def`, looked up by id
pub const tree=reg.table(Research,"def");
/// where a study stands for the gardener
pub const Status=enum{
  /// known: its teaching is in the world
  done,
  /// can be chosen for the labs now
  open,
  /// waiting on a prerequisite or a discovery
  locked
};
/// for each species, the technology that must be known to plant it (null: always).
const plantGate=blk:{
  // every species ungated, then each `unlocks` list claims its plants
  var gate=EnumArray(species.Id,?Id).initFill(null);
  for(reg.ids)|id|if(reg.has(id,"unlocks"))for(reg.module(id).unlocks)|sp|gate.set(sp,id);
  break:blk gate;
};
/// for each species, the technology that must be known to see its yield (null: always).
const yieldGate=blk:{
  // every species visible, then each `reveals` list hides its own
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
/// one growth of the labs: counts it and lets them condense a tenth more
/// of their fed pace unfed
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
    // the study every lab works on (none: no pace), and its cost
    const id=g.current orelse return 0;
    const r=tree.get(id);
    return(if(lab.fed)@as(f32,1)else s.unfed)*s.speed/(r.unitTime*m.f(r.units));
  }
};
/// how many messages the log keeps; the oldest falls away
const logLen=6;
/// how many bytes one log message may hold
const msgBuf:usize=96;
/// one line of the log the HUD shows
pub const Message=struct{
  /// the rendered text, of which `len` bytes are used
  buf:[msgBuf]u8=undefined,
  /// how many bytes of `buf` the message fills
  len:usize=0,
  /// seconds since it was said, so the HUD can fade it
  age:f32=0,
};
/// seconds before a batch of withered plants is reported (avoids log spam)
const witherBatch:f32=2;
/// how quickly the veil eases toward its target (per second)
const veilEase:f32=0.3;
/// what the gardener has learned and witnessed, the labs' shared choice,
/// and the log of what was said
pub const Progression=struct{
  /// every technology known
  done:std.EnumSet(Id)=.initEmpty(),
  /// every discovery witnessed
  found:std.EnumSet(Discovery)=.initEmpty(),
  /// world event blend 0..1 (sky/glow shift after the veil thins).
  veil:f32=0,
  /// the log, newest first
  log:[logLen]Message=@splat(.{}),
  /// the technology every lab works on (none: the labs rest)
  current:?Id=null,
  /// units finished so far, per technology
  progress:std.EnumArray(Id,u32)=.initFill(0),
  /// plants withered since the last report, gathered into one message
  died:u32=0,
  /// seconds since the last withering report
  diedT:f32=0,
  /// adds a message to the top of the log, pushing the oldest out.
  /// `tpl` is a runtime template (`core/text.zig`), usually `txt.s.msg.*`.
  pub fn say(g:*Progression,tpl:[]const u8,args:anytype)void{
    copyBackwards(Message,g.log[1..],g.log[0..g.log.len-1]);
    // the freshly cleared top line
    const msg=&g.log[0];
    msg.*=.{};
    // if the message is too long it silently truncates to the buffer size
    msg.len=ctext.bufRender(&msg.buf,tpl,args).len;
  }
  /// where a study stands: done once known, locked while a prerequisite or
  /// a needed discovery is missing, else open
  pub fn status(g:*const Progression,id:Id)Status{
    if(g.done.contains(id))return.done;
    // the study's cost and what it waits on
    const r=tree.get(id);
    for(r.prereq)|p|if(!g.done.contains(p))return.locked;
    if(r.needs)|d|if(!g.found.contains(d))return.locked;
    return.open;
  }
  /// makes a study the labs' choice if it is open; either way the log says
  /// what happened (researching, already known, locked)
  pub fn select(g:*Progression,id:Id)void{
    // the study's name, for the log
    const name=txt.research(id).name;
    switch(g.status(id)){
      .open=>{g.current=id;g.say(txt.s.msg.researching,.{name});},
      .done=>g.say(txt.s.msg.alreadyKnown,.{name}),
      .locked=>g.say(txt.s.msg.locked,.{name}),
    }
  }
  /// what the labs have been taught, from everything known.
  pub fn study(g:*const Progression)Study{
    // the teaching so far, starting from nothing known
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
    // the study being worked; none, and the lab rests
    const id=g.current orelse {
      lab.active=false;
      return false;
    };
    // its cost
    const r=tree.get(id);
    if(!lab.fed)feed:{
      for(r.perUnit)|ing|if(inv.count(ing.item)<ing.n)break:feed;
      for(r.perUnit)|ing|_=inv.take(ing.item,ing.n);
      lab.fed=true;
    }
    // how much of a unit a second it works: whole if fed, else the unfed share
    const rate=(if(lab.fed)@as(f32,1)else s.unfed)*s.speed;
    lab.active=rate>0;
    lab.t+=dt*rate/r.unitTime;
    if(lab.t<1)return false;
    lab.t=0;
    lab.fed=false;
    // another lab may have finished it while this unit was in progress
    if(g.done.contains(id))return false;
    // this study's finished units
    const p=g.progress.getPtr(id);
    p.*+=1;
    if(p.*>=r.units)g.complete(id);
    return true;
  }
  /// marks a study known, frees the labs' choice if it was theirs, says so,
  /// and runs its `completed` hook
  fn complete(g:*Progression,id:Id)void{
    g.done.insert(id);
    if(g.current==id)g.current=null;
    g.say(txt.s.msg.researched,.{txt.research(id).name});
    switch(id){
      inline else=>|k|if(comptime reg.has(k,"completed"))reg.module(k).completed(g),
    }
  }
  /// may the gardener plant this species yet? True once its gating study
  /// is known, or if none gates it
  pub fn canPlant(g:*const Progression,sp:species.Id)bool{
    // the study that gates planting it; none, and it is always allowed
    const gate=plantGate.get(sp) orelse return true;
    return g.done.contains(gate);
  }
  /// does the gardener know what this species condenses?
  pub fn yieldKnown(g:*const Progression,sp:species.Id)bool{
    // the study that gates seeing its yield; none, and it is always shown
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
    // the modifiers so far, the world untouched
    var md:ecology.Mods=.{};
    inline for(reg.ids)|id|{
      if(comptime reg.has(id,"apply"))if(g.done.contains(id))reg.module(id).apply(&md);
    }
    return md;
  }
  /// where the world-event veil is heading, from what has been learned.
  fn veilTarget(g:*const Progression)f32{
    // the furthest pull any known study gives, 0..1
    var v:f32=0;
    inline for(reg.ids)|id|{
      if(comptime reg.has(id,"veil"))if(g.done.contains(id)){v=@max(v,reg.module(id).veil);};
    }
    return v;
  }
  /// takes in a tick of the living world: gathers withered plants into one
  /// report every couple of seconds, eases the veil toward its target and
  /// ages the log's messages
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
  // a fresh tree, one lab, and an inventory of eight slots
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
  // seconds ticked so far
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
  // a fresh tree, one lab, and an empty inventory of eight slots
  var g:Progression=.{};
  var lab:Lab=.{};
  var inv:items.Inventory(8)=.{};
  g.select(.leySight);
  // ley sight's cost, to know a unit's time
  const r=tree.get(.leySight);
  // a fifth of the fed pace: one unit takes five unit times
  // what the labs know: nothing yet
  var s=g.study();
  try testing.expectApproxEqAbs(unfed,s.unfed,1e-6);
  // seconds ticked so far
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
