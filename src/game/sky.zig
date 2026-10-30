//! day/night cycle and starfall. At night starlight motes drift down near the
//! player and hover over the ground until dawn burns them away.
const lib=@import("../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const testing=std.testing;
const engine=lib.engine;
const m=engine.core.math;
const Rng=engine.core.rng.Rng;
const World=lib.world.World;
const txt=lib.txt;
/// seconds per full day/night cycle
pub const dayLen:f32=300;
/// the game starts mid-morning
const startTod:f32=0.3;
/// daylight rises from sun elevation `DAWN_AT` over `DAWN_SPAN`
const dawnAt:f32=-0.12;
const dawnSpan:f32=0.35;
/// the sun keys the light above this elevation, the moon below
const sunAbove:f32=-0.08;
/// dusk glows within this elevation of the horizon, at most this strong
const duskBand:f32=0.25;
const duskGlow:f32=0.8*0.6;
/// dawn and dusk are named within this elevation of the horizon
const twilightBand:f32=0.15;
/// the key light's direction: the sun swings this far east-west, rises at
/// least `SUN_LOW` plus `SUN_LIFT` and leans this far south; the moon likewise
const sunSwing:f32=0.7;
const sunLow:f32=0.1;
const sunLift:f32=0.2;
const sunLean:f32=0.35;
const moonSwing:f32=0.5;
const moonLift:f32=0.3;
const moonLean:f32=-0.3;
/// sky colours (linear): night, day plain and veiled, dusk glow
const nightSky=[3]f32{0.008,0.01,0.028};
const daySky=[3]f32{0.16,0.22,0.32};
const veiledSky=[3]f32{0.2,0.12,0.38};
const duskSky=[3]f32{0.32,0.13,0.08};
pub const Sky=struct{
  /// time of day 0..1 (0 midnight, 0.5 noon)
  tod:f32=startTod,
  pub fn update(s:*Sky,dt:f32)void{s.tod=@mod(s.tod+dt/dayLen,1);}
  /// sun elevation -1..1
  pub fn elevation(s:*const Sky)f32{return-@cos(s.tod*m.tau);}
  pub fn daylight(s:*const Sky)f32{return m.smooth(m.clamp01((s.elevation()-dawnAt)/dawnSpan));}
  /// direction toward the key light: the sun by day, a cool moon by night.
  pub fn lightDir(s:*const Sky)m.V3{
    const az=s.tod*m.tau;
    const e=s.elevation();
    if(e>sunAbove)return m.norm(m.v3(@cos(az)*sunSwing,@max(e,sunLow)+sunLift,sunLean));
    return m.norm(m.v3(-@cos(az)*moonSwing,-e+moonLift,moonLean));
  }
  /// linear sky/fog colour, with dusk glow near the horizon.
  /// `veil` blends the day colour toward the celestial palette (0..1).
  pub fn color(s:*const Sky,veil:f32)[3]f32{
    const d=s.daylight();
    const e=s.elevation();
    const dusk=m.clamp01(1-@abs(e)/duskBand)*duskGlow;
    var o:[3]f32=undefined;
    inline for(0..3)|i|o[i]=m.lerp(m.lerp(nightSky[i],m.lerp(daySky[i],veiledSky[i],veil),d),duskSky[i],dusk);
    return o;
  }
  pub fn name(s:*const Sky)[]const u8{
    const e=s.elevation();
    if(@abs(e)<twilightBand)return if(s.tod<0.5)txt.s.sky.dawn else txt.s.sky.dusk;
    return if(e>0)txt.s.sky.day else txt.s.sky.night;
  }
};
pub const Mote=struct{
  pos:m.V3,
  vy:f32,
  life:f32=1,
  phase:f32,
  /// still falling (it trails light) rather than resting over the ground
  falling:bool=true,
  /// ground height it lands on (kept while its tile is not walkable), and
  /// how far its sway has it off the point it fell toward
  ground:f32=0,
  sway:f32=0,
  pulled:bool=false
};
/// starfall tuning (tune here, not scattered through update)
const spawnRate:f32=0.9; // motes per second at full night
const spawnRMin:f32=2;
const spawnRMax:f32=16;
const spawnHeight:f32=7; // how far above ground they start
/// speed it sets off at (m/s) and how hard it is pulled down (m/s²)
const fallMin:f32=1.5;
const fallMax:f32=2.5;
const gravity:f32=4;
const restHover:f32=0.35; // how far above ground they rest
const hoverAmp:f32=0.08; // vertical bob amplitude while resting
/// horizontal sway (m) at spawn height, gone by the time it lands
const drift:f32=0.25;
const landEase:f32=3; // how quickly they settle onto the rest height
const spawnNight:f32=0.6; // night deeper than this, stars fall
const fallingAbove:f32=0.05; // above rest by this much, a mote still trails
/// phase rates of the rest bob and the falling sway
const hoverRate:f32=40;
const driftRate:f32=20;
const burnBelow:f32=0.4; // night below this, motes start burning away
const burnRate:f32=0.4; // life lost per second while burning
/// a mote within this (m) of the wolf twinkles now and then: seconds
/// between twinkles (a gap with none near passes silent)
const twinkleNear:f32=6;
const twinkleGap=[2]f32{2.5,8};
/// a mote near the wolf twinkled, for what hears it (game/sound.zig): how
/// near (0 at `TWINKLE_NEAR` .. 1 touching)
pub const Twinkle=struct{near:f32};
pub const Starfall=struct{
  motes:std.ArrayList(Mote)=.empty,
  acc:f32=0,
  rng:Rng,
  /// seconds until a near mote may twinkle, and one since `twinkled` last took it
  quiet:f32=0,
  twinkle:?Twinkle=null,
  pub const max=80;
  pub fn deinit(sf:*Starfall,gpa:Allocator)void{sf.motes.deinit(gpa);}
  /// the twinkle since last asked, once
  pub fn twinkled(sf:*Starfall)?Twinkle{
    defer sf.twinkle=null;
    return sf.twinkle;
  }
  /// motes land only on walkable tiles.
  pub fn update(sf:*Starfall,gpa:Allocator,sky:*const Sky,around:m.V3,ground:*const World,dt:f32)Allocator.Error!void{
    sf.listen(around,dt);
    const night=1-sky.daylight();
    if(night>spawnNight and sf.motes.items.len<max){
      sf.acc+=dt*spawnRate*night;
      while(sf.acc>=1):(sf.acc-=1){
        const a=sf.rng.range(0,m.tau);
        const r=sf.rng.range(spawnRMin,spawnRMax);
        const x=around[0]+@cos(a)*r;
        const z=around[2]+@sin(a)*r;
        const h=ground.walkable(m.tileOf(x),m.tileOf(z)) orelse continue;
        try sf.motes.append(gpa,.{.pos=m.v3(x,h+spawnHeight,z),.vy=-sf.rng.range(fallMin,fallMax),.phase=sf.rng.float(),.ground=h});
      }
    }
    var i:usize=0;
    while(i<sf.motes.items.len){
      const mo=&sf.motes.items[i];
      if(mo.pulled){i+=1;continue;}
      if(ground.walkable(m.tileOf(mo.pos[0]),m.tileOf(mo.pos[2])))|h|mo.ground=h;
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
    var nearest:f32=twinkleNear;
    for(sf.motes.items)|mo|nearest=@min(nearest,m.len(mo.pos-around)*mo.life+twinkleNear*(1-mo.life));
    if(nearest<twinkleNear)sf.twinkle=.{.near=1-nearest/twinkleNear};
  }
};
test"a near mote twinkles now and then, a far one never"{
  var sf:Starfall=.{.rng=Rng.init(7)};
  defer sf.deinit(testing.allocator);
  try sf.motes.append(testing.allocator,.{.pos=m.v3(20,0,0),.vy=0,.phase=0});
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
