//! THE UNFORMING: the garden's first world event, begun the moment the
//! study of that name is learned. Every radiant plant (the celestial
//! bloom, the vesper) glitches, shatters like glass and blinks out of
//! reality, one after another; what they were streams up as shards to one
//! point in the sky over the middle of them all, where it gathers into a
//! seed, which falls to the ground and lies there, never planting itself
//! (a `strangeSeed` the wolf may pick up). The symbiotic and parasitic
//! lineages die with them: their plants wither, their structures unform
//! (grown back down to nothing and gone), all but the arsthraxia, which
//! evolves instead (`Msg.unform`). What is convergent or common stays.
//! The radiant plants' glitching is drawn on the GPU (plant.vert/.frag,
//! `PlantInstance.glitch`).
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the shards' list grows with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, easing, hashes
const m=lib.engine.core.math;
/// the engine's seeded hashes, for each plant's own moment
const rng=lib.engine.core.rng;
/// the species registry: lineages and forms
const species=lib.species;
/// the structures registry: what dies, the arsthraxia's evolving
const st=lib.structures;
/// every player-facing string
const txt=lib.txt;
/// the scene's list of moving parts the shards and seed go into
const Parts=lib.parts.Parts;
/// the whole running game the event befalls
const Game=lib.play.Game;
/// where the event stands
pub const Phase=enum(u8){
  /// not begun: its study is not yet learned
  waiting,
  /// the radiant plants shattering, the lineages dying, the seed gathering
  shattering,
  /// the seed falling out of the sky
  falling,
  /// the seed lies on the ground; it is over
  landed,
};
/// how far over the radiant plants' middle the seed gathers
const skyHeight:f32=14;
/// seconds over which the radiant plants begin to shatter, one after another
const spread:f32=6;
/// seconds one radiant plant takes from its first glitch to gone
const shatterTime:f32=5;
/// how far through its shattering a plant's shards break away (0..1)
const breakAt:f32=0.6;
/// seconds a shard takes to fly up to the seed
const flyTime:f32=2.4;
/// shards each radiant plant sends up
pub const shardsEach=4;
/// seconds over which the lineages begin to die, one after another
const dieSpread:f32=8;
/// seconds a dying plant takes to wither, or a structure to unform
const dieTime:f32=6;
/// seconds the seed takes to fall to the ground
const fallTime:f32=2.2;
/// the whole of the shattering: every plant gone and its shards arrived
const shatterEnd:f32=spread+shatterTime+flyTime;
/// what the event remembers (saved with the garden)
pub const Unforming=struct{
  /// where it stands
  phase:Phase=.waiting,
  /// seconds since it began
  t:f32=0,
  /// where the seed gathers, in the sky (world space)
  at:[3]f32=.{0,0,0},
  /// a radiant plant's shattering, 0 its first glitch .. 1 gone (< 0 not
  /// yet, or no event), its moment drawn from its seed
  pub fn glitchOf(u:*const Unforming,seed:f32)f32{
    if(u.phase==.waiting)return -1;
    // how far it has come
    const k=(u.t-delayOf(seed,spread))/shatterTime;
    return if(k<0)-1 else @min(k,1);
  }
  /// where the seed hangs or falls now (nothing before it gathers or once landed)
  pub fn seedAt(u:*const Unforming,ground:f32)?m.V3{
    // where it gathers
    const sky=m.v3(u.at[0],u.at[1],u.at[2]);
    return switch(u.phase){
      .waiting,.landed=>null,
      .shattering=>sky,
      .falling=>blk:{
        // how far it has fallen, falling faster as it goes
        const k=m.clamp01((u.t-shatterEnd)/fallTime);
        break:blk m.v3(sky[0],m.lerp(sky[1],ground+seedRest,k*k),sky[2]);
      },
    };
  }
  /// how much of the seed has gathered (0..1): as the shards arrive
  pub fn gathered(u:*const Unforming)f32{
    return m.smooth(m.clamp01((u.t-spread*0.5)/(shatterEnd-spread*0.5)));
  }
};
/// how high the seed rests over the ground, lying there
const seedRest:f32=0.05;
/// one radiant plant as it was when the event began: where it stood and
/// its seed, for its shards' flight once it is gone (not saved: a garden
/// loaded mid-event sends none up)
pub const Source=struct{
  /// where it stood (its middle, a little over its foot)
  at:m.V3,
  /// its seed, which sets its moment
  seed:f32,
};
/// the moment of the event at which a radiant plant of seed `seed` is `k`
/// (0..1) through its shattering (a specimen shows it so)
pub fn momentOf(seed:f32,k:f32)f32{return delayOf(seed,spread)+k*shatterTime;}
/// a thing's moment in a spread of `over` seconds, drawn from its seed
fn delayOf(seed:f32,over:f32)f32{
  return over*rng.unit(rng.hash2(0x0F0E,m.floorTo(i32,seed*100003),7));
}
/// whether a species is radiant (the celestial bloom, the vesper): it shatters
pub fn radiant(sp:species.Id)bool{
  return switch(species.get(sp).genome.form){
    .radiant,.star=>true,
    else=>false,
  };
}
/// whether a species is of a lineage the event kills (symbiotic or parasitic, not radiant)
fn dies(sp:species.Id)bool{
  return !radiant(sp) and species.get(sp).lineage!=.convergent;
}
/// one tick of the event: begun once its study is learned, it shatters the
/// radiant plants, withers and unforms the lineages, gathers the seed and
/// lets it fall
pub fn tick(g:*Game,dt:f32)Allocator.Error!void{
  // the event
  const u=&g.unforming;
  switch(u.phase){
    .waiting=>{
      if(!g.prog.done.contains(.unforming))return;
      try begin(g);
    },
    .shattering=>{
      u.t+=dt;
      try shatter(g);
      try unform(g);
      if(u.t>=shatterEnd)u.phase=.falling;
    },
    .falling=>{
      u.t+=dt;
      try shatter(g);
      try unform(g);
      if(u.t>=shatterEnd+fallTime)try land(g);
    },
    .landed=>{
      // the lineages still dying after it lands
      u.t+=dt;
      if(u.t>dieSpread+dieTime+1)return;
      try shatter(g);
      try unform(g);
    },
  }
}
/// it begins: the radiant plants are found and the seed's point set over
/// the middle of them (over the wolf if there are none); the arsthraxias evolve
fn begin(g:*Game)Allocator.Error!void{
  // the event, and the plants' columns
  const u=&g.unforming;
  const s=g.plants.list.slice();
  g.unformSources.clearRetainingCapacity();
  // the sum of where they stand
  var sum=m.v3(0,0,0);
  for(s.items(.sp),s.items(.at),s.items(.seed))|sp,at,seed|{
    if(!radiant(sp))continue;
    try g.unformSources.append(g.gpa,.{.at=at+m.v3(0,species.get(sp).hover+0.4,0),.seed=seed});
    sum+=at;
  }
  // their middle
  const n=g.unformSources.items.len;
  const mid=if(n>0)sum/m.splat3(m.f(n))else g.player.pos;
  u.at=.{mid[0],g.heightAt(m.floorTo(i32,mid[0]),m.floorTo(i32,mid[2]))+skyHeight,mid[2]};
  u.phase=.shattering;
  u.t=0;
  for(0..g.structs.list.items.len)|i|_=g.structs.send(g.structCtx(.{}),.of(i),.unform);
  g.prog.say(txt.s.msg.unformingBegins,.{});
}
/// the radiant plants gone once shattered; the lineages' plants withering, one after another
fn shatter(g:*Game)Allocator.Error!void{
  // the event
  const u=&g.unforming;
  // walking down the list, so removing one never skips another
  var i=g.plants.len();
  while(i>0){
    i-=1;
    // the plant's species and seed
    const sp=g.plants.list.items(.sp)[i];
    const seed=g.plants.list.items(.seed)[i];
    if(radiant(sp)){
      if(u.glitchOf(seed)>=1)g.plants.remove(&g.world,.of(i));
    }else if(dies(sp)){
      // how far it has withered, and its health held under that (gone, once withered)
      const k=m.clamp01((u.t-delayOf(seed,dieSpread))/dieTime);
      if(k>=1){
        g.plants.remove(&g.world,.of(i));
        continue;
      }
      const h=&g.plants.list.items(.health)[i];
      h.*=@min(h.*,1-k);
    }
  }
}
/// the lineages' structures unforming, one after another, gone once
/// grown back down to nothing (what they held is lost)
fn unform(g:*Game)Allocator.Error!void{
  // the event
  const u=&g.unforming;
  // walking down the list, so removing one never skips another
  var i=g.structs.list.items.len;
  while(i>0){
    i-=1;
    // the structure
    const s=&g.structs.list.items[i];
    if(!s.def().unforms)continue;
    s.fade=m.clamp01((u.t-delayOf(s.seed,dieSpread))/dieTime);
    if(s.fade<1)continue;
    // gone
    var gone=g.structs.remove(&g.world,.of(i));
    gone.deinit(g.gpa);
  }
}
/// the seed lands, where it fell or on the nearest free tile, and lies there
fn land(g:*Game)Allocator.Error!void{
  // the event, and the tile under where it fell
  const u=&g.unforming;
  u.phase=.landed;
  const cx=m.floorTo(i32,u.at[0]);
  const cz=m.floorTo(i32,u.at[2]);
  // the rings searched outward from there
  var r:i32=0;
  while(r<landSearch):(r+=1){
    // the walk round that ring
    var it=m.ring(r);
    while(it.next())|o|{
      if(!try g.structs.place(g.gpa,&g.world,cx+o[0],cz+o[1],.strangeSeed,0,0.5))continue;
      g.prog.say(txt.s.msg.seedFalls,.{});
      return;
    }
  }
}
/// tiles round where it fell the seed may land on, if that is taken
const landSearch:i32=6;
/// the shards in flight and the seed, gathering, falling: drawn each frame
pub fn draw(g:*Game,tf:f32)Allocator.Error!void{
  // the event
  const u=&g.unforming;
  if(u.phase==.waiting or u.phase==.landed or g.specimen!=null)return;
  // where the seed gathers
  const sky=m.v3(u.at[0],u.at[1],u.at[2]);
  for(g.unformSources.items)|src|for(0..shardsEach)|j|{
    // how far this shard has flown (0..1; outside, none)
    const k=(u.t-delayOf(src.seed,spread)-shatterTime*breakAt-0.25*m.f(j))/flyTime;
    if(k<0 or k>=1)continue;
    // its own swirl round the way up, and where that puts it
    const a=src.seed*m.tau*7+m.f(j)*2.4+k*5;
    const swirl=m.v3(@cos(a),0,@sin(a))*m.splat3(1.2*@sin(m.pi*k));
    const e=k*k*(3-2*k);
    const at=src.at+(sky-src.at)*m.splat3(e)+swirl+m.v3(0,2.5*@sin(m.pi*k),0);
    try g.parts.emit(.unformShard,m.chain(&.{m.translate(at),m.rotY(tf*3+a),m.rotX(tf*2.3+a),m.scale3(m.splat3(1-0.6*k))}),.{.glow=1.5,.phase=@mod(src.seed*13+m.f(j)*0.37,1),.flutter=k});
  };
  // the seed, gathering in the sky or falling
  const ground=g.heightAt(m.floorTo(i32,u.at[0]),m.floorTo(i32,u.at[2]));
  const at=u.seedAt(ground) orelse return;
  // how much of it has gathered
  const k=u.gathered();
  if(k<=0)return;
  try g.parts.emit(.strangeSeed,m.chain(&.{m.translate(at),m.rotY(tf*0.6),m.scale3(m.splat3(m.lerp(0.2,1,k)))}),.{.glow=1+k,.phase=0.5,.flutter=1-k});
  try g.parts.light(at,m.v3(0.9,0.85,1.0)*m.splat3(1.5*k),8);
}
test"a radiant plant's moment falls within the spread, and its shattering runs 0..1"{
  // the test harness
  const testing=std.testing;
  // an event just begun
  var u:Unforming=.{.phase=.shattering};
  try testing.expect(u.glitchOf(0.3)<0 or u.glitchOf(0.3)==0);
  u.t=spread+shatterTime;
  try testing.expectEqual(@as(f32,1),u.glitchOf(0.3));
  try testing.expect(delayOf(0.77,spread)>=0 and delayOf(0.77,spread)<spread);
  try testing.expect(radiant(.bloom) and radiant(.vesper));
  try testing.expect(!radiant(.lumenroot) and dies(.lumenroot) and dies(.thornleech));
  try testing.expect(!dies(.confluence));
}
test"learned, the unforming shatters the radiant plants, kills the lineages, evolves the arsthraxia and lets a seed fall"{
  // the test harness and its allocator
  const testing=std.testing;
  const gpa=testing.allocator;
  // a fresh game, its world streamed in round the wolf
  var g=try Game.init(gpa,lib.play.defaultSeed);
  defer g.deinit();
  try g.world.stream(g.focus(),2,1000);
  // the wolf's tile, and the ground round it laid flat with soil
  const c=m.tileAt(g.player.pos);
  var dz:i32=-12;
  while(dz<=12):(dz+=1){
    var dx:i32=-12;
    while(dx<=12):(dx+=1){
      // the tile, and the chunk holding it
      const ch=g.world.chunkOfTile(c[0]+dx,c[1]+dz) orelse continue;
      const t=lib.ck.localIndex(c[0]+dx,c[1]+dz);
      ch.kind[t]=.soil;
      ch.height[t]=1;
      ch.res[t]=0;
    }
  }
  // a bloom and a vesper, a lumenroot,
  // a loomfern, an arsthraxia and a polyp
  try testing.expect(try g.plants.placeEx(gpa,&g.world,c[0]+3,c[1],.{.x=c[0]+3,.y=c[1],.chunk=undefined,.tile=undefined,.sp=.bloom,.seed=0.2,.growth=1,.mana=10,.span=1e9}));
  try testing.expect(try g.plants.placeEx(gpa,&g.world,c[0]-3,c[1],.{.x=c[0]-3,.y=c[1],.chunk=undefined,.tile=undefined,.sp=.vesper,.seed=0.6,.growth=1,.mana=10,.span=1e9}));
  try testing.expect(try g.plants.placeEx(gpa,&g.world,c[0],c[1]+3,.{.x=c[0],.y=c[1]+3,.chunk=undefined,.tile=undefined,.sp=.lumenroot,.seed=0.4,.growth=1,.mana=10,.span=1e9}));
  try testing.expect(try g.structs.place(gpa,&g.world,c[0]+5,c[1]+5,.loomfern,0,0.3));
  try testing.expect(try g.structs.place(gpa,&g.world,c[0]-6,c[1]-6,.arsthraxia,0,0.3));
  try testing.expect(try g.structs.place(gpa,&g.world,c[0]-5,c[1]+5,.polyp,0,0.3));
  // learned: it begins
  g.prog.done.insert(.unforming);
  // seconds run
  var t:f32=0;
  while(t<shatterEnd+fallTime+dieSpread+dieTime+1):(t+=lib.play.tickTime)try g.step();
  try testing.expectEqual(Phase.landed,g.unforming.phase);
  // what is left: no radiant plant, no lumenroot
  for(g.plants.list.items(.sp))|sp|try testing.expect(!radiant(sp) and sp!=.lumenroot);
  // the loomfern gone; the arsthraxia evolved, the polyp kept; the seed lying there
  var seeds:u32=0;
  var ars:u32=0;
  for(g.structs.list.items)|*s|switch(s.kind()){
    .loomfern=>return error.LineageKept,
    .arsthraxia=>{
      try testing.expect(s.state.arsthraxia.evolved);
      ars+=1;
    },
    .strangeSeed=>seeds+=1,
    else=>{},
  };
  try testing.expectEqual(@as(u32,1),seeds);
  try testing.expectEqual(@as(u32,1),ars);
}
