//! day/night cycle and starfall. At night starlight motes drift down near the
//! player and hover over the ground until dawn burns them away. The
//! unforming shifts the sky for good (`Sky.shift`): it turns the ley's
//! violet, glowing, its sun and moon gone, the glow's own turning the only
//! tell of day and night; the motes shatter, and no star falls again.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the motes grow with
const Allocator=std.mem.Allocator;
/// the test harness
const testing=std.testing;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, angles, easing
const m=engine.core.math;
/// the random stream starfall draws from
const Rng=engine.core.rng.Rng;
/// the world, for which tiles a mote may land on
const World=lib.world.World;
/// every player-facing string, for the time of day's name
const txt=lib.txt;
/// seconds per full day/night cycle
pub const dayLen:f32=300;
/// the game starts mid-morning
const startTod:f32=0.3;
/// daylight rises from sun elevation `dawnAt` over `dawnSpan`
const dawnAt:f32=-0.12;
/// how far above `dawnAt` the sun climbs before daylight is full
const dawnSpan:f32=0.35;
/// the sun keys the light above this elevation, the moon below
const sunAbove:f32=-0.08;
/// dusk glows within this elevation of the horizon
const duskBand:f32=0.25;
/// how strong the dusk glow is at its most
const duskGlow:f32=0.8*0.6;
/// dawn and dusk are named within this elevation of the horizon
const twilightBand:f32=0.15;
/// the key light's direction: the sun swings this far east-west
/// (the moon likewise, by its own constants)
const sunSwing:f32=0.7;
/// the least elevation the sun's light keys from, before `sunLift`
const sunLow:f32=0.1;
/// how much higher than its elevation the sun's light keys from
const sunLift:f32=0.2;
/// how far south the sun's light leans
const sunLean:f32=0.35;
/// how far east-west the moon swings
const moonSwing:f32=0.5;
/// how much higher than its depth the moon's light keys from
const moonLift:f32=0.3;
/// how far north the moon's light leans
const moonLean:f32=-0.3;
/// the sky's colours (linear): night
const nightSky=[3]f32{0.008,0.01,0.028};
/// a plain day
const daySky=[3]f32{0.16,0.22,0.32};
/// a day veiled by the world event: a little violet
const veiledSky=[3]f32{0.2,0.12,0.38};
/// the dusk glow near the horizon
const duskSky=[3]f32{0.32,0.13,0.08};
/// the shifted sky (after the unforming), the ley's glow: by night, a deep
/// blue violet
const leyNight=[3]f32{0.03,0.02,0.09};
/// by day, a rose violet
const leyDay=[3]f32{0.24,0.1,0.4};
/// the shifted sky's key light circles this far off the zenith (its glow
/// overhead, no sun to swing it)
const leyLean:f32=0.3;
/// the fog and the horizon turn to the ley's colour over this stretch of
/// the shift (0..1), as the old sky's shattering sweeps down the dome to
/// the horizon (sky.frag FRONT_FROM, FRONT_SPAN)
const fogFrom:f32=0.15;
/// how much of the shift that takes
const fogSpan:f32=0.35;
/// the sky's clock: the time of day, which lights, colours and names it
pub const Sky=struct{
  /// time of day 0..1 (0 midnight, 0.5 noon)
  tod:f32=startTod,
  /// how far the unforming has shifted it, 0 the old sky .. 1 the ley's for
  /// good (set each tick from the event, not saved)
  shift:f32=0,
  /// moves the clock on by `dt` seconds, wrapping at a full day
  pub fn update(s:*Sky,dt:f32)void{s.tod=@mod(s.tod+dt/dayLen,1);}
  /// sun elevation -1..1
  pub fn elevation(s:*const Sky)f32{return-@cos(s.tod*m.tau);}
  /// how much daylight there is, 0..1 (eased in round dawn)
  pub fn daylight(s:*const Sky)f32{return m.smooth(m.clamp01((s.elevation()-dawnAt)/dawnSpan));}
  /// direction toward the key light: the sun by day, a cool moon by night;
  /// once shifted, the glow overhead, circling slowly with the day
  pub fn lightDir(s:*const Sky)m.V3{
    // the clock as an angle, and the sun's elevation
    const az=s.tod*m.tau;
    const e=s.elevation();
    // the old sky's key light
    const old=if(e>sunAbove)m.norm(m.v3(@cos(az)*sunSwing,@max(e,sunLow)+sunLift,sunLean))
      else m.norm(m.v3(-@cos(az)*moonSwing,-e+moonLift,moonLean));
    if(s.shift<=0)return old;
    // the shifted sky's: its glow overhead
    const glow=m.norm(m.v3(@cos(az)*leyLean,1,@sin(az)*leyLean));
    return m.norm(old+(glow-old)*m.splat3(m.smooth(s.shift)));
  }
  /// linear sky/fog colour, with dusk glow near the horizon.
  /// `veil` blends the day colour toward the celestial palette (0..1);
  /// the shift turns it all to the ley's glow, rose by day, deep by night
  pub fn color(s:*const Sky,veil:f32)[3]f32{
    // daylight, and the sun's elevation
    const d=s.daylight();
    const e=s.elevation();
    // how much the dusk glows, near the horizon
    const dusk=m.clamp01(1-@abs(e)/duskBand)*duskGlow;
    // how far it has shifted, at the horizon
    const sh=m.smooth(m.clamp01((s.shift-fogFrom)/fogSpan));
    // the colour, built channel by channel
    var o:[3]f32=undefined;
    inline for(0..3)|i|o[i]=m.lerp(m.lerp(m.lerp(nightSky[i],m.lerp(daySky[i],veiledSky[i],veil),d),duskSky[i],dusk),m.lerp(leyNight[i],leyDay[i],d),sh);
    return o;
  }
  /// the time of day's name: dawn or dusk near the horizon, else day or night
  pub fn name(s:*const Sky)[]const u8{
    // the sun's elevation
    const e=s.elevation();
    if(@abs(e)<twilightBand)return if(s.tod<0.5)txt.s.sky.dawn else txt.s.sky.dusk;
    return if(e>0)txt.s.sky.day else txt.s.sky.night;
  }
};
/// one starlight mote: where it is, how it falls and how much of it is left
pub const Mote=struct{
  /// where it is
  pos:m.V3,
  /// how fast it falls (m/s; negative is down)
  vy:f32,
  /// how much of it is left, 0..1 (dawn burns it away)
  life:f32=1,
  /// its own phase, 0..1, so motes bob and sway apart
  phase:f32,
  /// still falling (it trails light) rather than resting over the ground
  falling:bool=true,
  /// the ground height it lands on (kept while its tile is not walkable)
  ground:f32=0,
  /// how far its sway has it off the point it fell toward
  sway:f32=0,
  /// being drawn to the wolf's chest (actions.catchStarlight moves it)
  pulled:bool=false,
  /// seconds since it shattered (the unforming), < 0 whole; gone at `shatterTime`
  shatter:f32=-1,
  /// whether it is shattering
  pub fn shattering(mo:Mote)bool{return mo.shatter>=0;}
};
/// seconds a shattered mote's shards take to fly apart and fade
pub const shatterTime:f32=1.4;
/// how many motes fall a second at full night (starfall tuning: tune here,
/// not scattered through update)
const spawnRate:f32=0.9;
/// the nearest a new mote falls to the wolf (m)
const spawnRMin:f32=2;
/// the furthest a new mote falls from the wolf (m)
const spawnRMax:f32=16;
/// how far above the ground motes start falling (m)
const spawnHeight:f32=7;
/// the slowest speed a mote sets off at (m/s)
const fallMin:f32=1.5;
/// the fastest speed a mote sets off at (m/s)
const fallMax:f32=2.5;
/// how hard a mote is pulled down (m/s²)
const gravity:f32=4;
/// how far above the ground motes rest (m)
const restHover:f32=0.35;
/// how far a resting mote bobs up and down (m)
const hoverAmp:f32=0.08;
/// horizontal sway (m) at spawn height, gone by the time it lands
const drift:f32=0.25;
/// how quickly a mote settles onto its rest height (a share a second)
const landEase:f32=3;
/// night deeper than this (0..1), and stars fall
const spawnNight:f32=0.6;
/// above its rest by this much (m), a mote still trails light
const fallingAbove:f32=0.05;
/// how fast a resting mote bobs (its phase's rate)
const hoverRate:f32=40;
/// how fast a falling mote sways (its phase's rate)
const driftRate:f32=20;
/// night shallower than this (0..1), and motes start burning away
const burnBelow:f32=0.4;
/// how much of its life a mote loses a second while burning
const burnRate:f32=0.4;
/// a mote within this (m) of the wolf may twinkle now and then
const twinkleNear:f32=6;
/// seconds between twinkles, least and most (a gap with none near passes silent)
const twinkleGap=[2]f32{2.5,8};
/// a mote near the wolf twinkled, for what hears it (game/sound.zig)
pub const Twinkle=struct{
  /// how near it was: 0 at `twinkleNear` .. 1 touching
  near:f32
};
/// the starlight falling round the wolf: its motes, and what has twinkled
pub const Starfall=struct{
  /// every mote falling or resting
  motes:std.ArrayList(Mote)=.empty,
  /// how many motes are owed to fall, building up a second at a time
  acc:f32=0,
  /// the random stream where and how motes fall
  rng:Rng,
  /// seconds until a near mote may twinkle
  quiet:f32=0,
  /// the twinkle since `twinkled` last took it
  twinkle:?Twinkle=null,
  /// no star falls any more: the unforming shattered them (set each tick
  /// from the event)
  stilled:bool=false,
  /// the most motes that may be about at once
  pub const max=80;
  /// frees the motes
  pub fn deinit(sf:*Starfall,gpa:Allocator)void{sf.motes.deinit(gpa);}
  /// every mote shatters at once, and no star falls again (the unforming)
  pub fn shatterAll(sf:*Starfall)void{
    sf.stilled=true;
    for(sf.motes.items)|*mo|{
      mo.shatter=0;
      mo.pulled=false;
    }
  }
  /// the twinkle since last asked, once
  pub fn twinkled(sf:*Starfall)?Twinkle{
    defer sf.twinkle=null;
    return sf.twinkle;
  }
  /// motes fall round `around` at night, settle over the ground and bob
  /// there, and burn away by day; they land only on walkable tiles
  pub fn update(sf:*Starfall,gpa:Allocator,sky:*const Sky,around:m.V3,ground:*const World,dt:f32)Allocator.Error!void{
    sf.listen(around,dt);
    // how deep the night is, 0..1
    const night=1-sky.daylight();
    if(!sf.stilled and night>spawnNight and sf.motes.items.len<max){
      sf.acc+=dt*spawnRate*night;
      while(sf.acc>=1):(sf.acc-=1){
        // a random bearing and distance round the wolf
        const a=sf.rng.range(0,m.tau);
        const r=sf.rng.range(spawnRMin,spawnRMax);
        // where the mote falls, and the walkable ground it lands on (none: skip)
        const x=around[0]+@cos(a)*r;
        const z=around[2]+@sin(a)*r;
        const h=ground.walkable(m.tileOf(x),m.tileOf(z)) orelse continue;
        try sf.motes.append(gpa,.{.pos=m.v3(x,h+spawnHeight,z),.vy=-sf.rng.range(fallMin,fallMax),.phase=sf.rng.float(),.ground=h});
      }
    }
    // the mote being looked at
    var i:usize=0;
    while(i<sf.motes.items.len){
      // the mote
      const mo=&sf.motes.items[i];
      if(mo.shattering()){
        // its shards flying apart, gone once faded
        mo.shatter+=dt;
        if(mo.shatter>=shatterTime){_=sf.motes.swapRemove(i);continue;}
        i+=1;
        continue;
      }
      if(mo.pulled){i+=1;continue;}
      if(ground.walkable(m.tileOf(mo.pos[0]),m.tileOf(mo.pos[2])))|h|mo.ground=h;
      // its rest height, bobbing
      const rest=mo.ground+restHover+hoverAmp*@sin(mo.phase*hoverRate);
      mo.falling=mo.pos[1]>rest+fallingAbove;
      if(mo.pos[1]>rest){
        mo.vy-=gravity*dt;
        mo.pos[1]=@max(rest,mo.pos[1]+mo.vy*dt);
      }else{
        mo.vy=-fallMin;
        mo.pos[1]+=(rest-mo.pos[1])*@min(1,dt*landEase);
      }
      // the sway is an offset that dies away as it nears the ground, so it
      // lands where it was falling toward
      // its sway now: dying away toward the ground
      const sway=@sin(mo.phase*driftRate+mo.pos[1])*drift*m.clamp01((mo.pos[1]-rest)/spawnHeight);
      mo.pos[0]+=sway-mo.sway;
      mo.sway=sway;
      if(night<burnBelow)mo.life-=dt*burnRate;
      if(mo.life<=0){_=sf.motes.swapRemove(i);continue;}
      i+=1;
    }
  }
  /// after a quiet gap, the nearest mote within reach twinkles
  fn listen(sf:*Starfall,around:m.V3,dt:f32)void{
    sf.quiet-=dt;
    if(sf.quiet>0)return;
    sf.quiet=sf.rng.range(twinkleGap[0],twinkleGap[1]);
    // the nearest mote, counted further off as it burns away
    var nearest:f32=twinkleNear;
    for(sf.motes.items)|mo|if(!mo.shattering()){nearest=@min(nearest,m.len(mo.pos-around)*mo.life+twinkleNear*(1-mo.life));};
    if(nearest<twinkleNear)sf.twinkle=.{.near=1-nearest/twinkleNear};
  }
};
test"the unforming shatters every mote at once, and no star falls again"{
  // a starfall with a fixed seed, its motes, the sky at midnight and a flat world
  var sf:Starfall=.{.rng=Rng.init(3)};
  defer sf.deinit(testing.allocator);
  for(0..5)|k|try sf.motes.append(testing.allocator,.{.pos=m.v3(m.f(k),1,0),.vy=0,.phase=0.1*m.f(k)});
  const sky:Sky=.{.tod=0};
  var w=World.init(testing.allocator,1);
  defer w.deinit();
  sf.shatterAll();
  // a few seconds of the deepest night
  for(0..240)|_|try sf.update(testing.allocator,&sky,m.v3(0,0,0),&w,1.0/60.0);
  try testing.expectEqual(@as(usize,0),sf.motes.items.len);
}
test"the shifted sky is the ley's, with no sun to key it"{
  // noon, the old sky and the shifted one
  const old:Sky=.{.tod=0.5};
  const shifted:Sky=.{.tod=0.5,.shift=1};
  try testing.expect(shifted.color(0)[2]>shifted.color(0)[1]*2);
  try testing.expect(shifted.lightDir()[1]>0.9 and old.color(0)[0]<shifted.color(0)[0]);
}
test"a near mote twinkles now and then, a far one never"{
  // a starfall with a fixed seed, and one mote far off
  var sf:Starfall=.{.rng=Rng.init(7)};
  defer sf.deinit(testing.allocator);
  try sf.motes.append(testing.allocator,.{.pos=m.v3(20,0,0),.vy=0,.phase=0});
  // the wolf, at the origin, and how many twinkles were heard
  const here=m.v3(0,0,0);
  var heard:u32=0;
  // a minute at 60 frames a second
  for(0..3600)|_|{
    sf.listen(here,1.0/60.0);
    if(sf.twinkled()!=null)heard+=1;
  }
  try testing.expectEqual(@as(u32,0),heard);
  sf.motes.items[0].pos=m.v3(2,0,0);
  for(0..3600)|_|{
    sf.listen(here,1.0/60.0);
    if(sf.twinkled())|t|{
      heard+=1;
      try testing.expect(t.near>0.5 and t.near<0.8);
    }
  }
  try testing.expect(heard>=6 and heard<=25);
}
