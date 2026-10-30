//! the source the device pulls from: every sound's voices mixed into one stream.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const dsp=engine.core.dsp;
const rng=engine.core.rng;
const Footfall=lib.player.Footfall;
const Boom=lib.sound.boom.Boom;
const gapFirst=lib.sound.sap.gapFirst;
const gapStill=lib.sound.sap.gapStill;
const gapWalk=lib.sound.sap.gapWalk;
const Music=lib.sound.music.Music;
const Research=lib.sound.arsthraxia.Research;
const sapFade=lib.sound.sap.sapFade;
const silent=lib.sound.silent;
const stillAfter=lib.sound.sap.stillAfter;
const Settle=lib.sound.sap.Settle;
const Step=lib.sound.footstep.Step;
const twinkles=lib.sound.twinkle.twinkles;
const Twinkle=lib.sound.twinkle.Twinkle;
const voiceCount=lib.sound.voiceCount;
const Wind=lib.sound.wind.Wind;
const samples=lib.sound.sap.samples;
/// the source the device pulls from (`platform.audio.Output(Sounds)`)
pub const Sounds=struct{
  /// a paw landed; the view entered or left the wolf's eyes; a mote near
  /// the wolf twinkled; the daylight changed (0 night .. 1 day)
  pub const Cmd=union(enum){
    step:Footfall,
    eyes:bool,
    twinkle:lib.sky.Twinkle,
    daylight:f32,
    arsthraxia:struct{progress:f32,fed:f32,complete:bool}
  };
  rate:f32,
  r:rng.Rng,
  steps:[voiceCount]?Step=@splat(null),
  /// the voice taken when none is free (round the pool: the oldest)
  steal:usize=0,
  eyes:bool=false,
  /// how much of the settling is heard (1 in the eyes)
  fade:dsp.Smooth,
  settle:?Settle=null,
  /// samples until the next settling, and since a paw last landed
  wait:u32=0,
  sinceStep:u32=m.maxInt(u32),
  /// the belly at the last step
  weight:f32=0,
  wind:Wind,
  /// a new twinkle takes the oldest's place when both are sounding
  twinkles:[twinkles]?Twinkle=@splat(null),
  nextTwinkle:usize=0,
  music:Music,
  research:?Research=null,
  boom:?Boom=null,
  resProgress:f32=0,
  resFed:f32=0,
  pub fn init(seed:u64,rate:f32)Sounds{
    var r:rng.Rng=.init(seed);
    const wind:Wind=.init(&r,rate);
    const music:Music=.init(&r,rate);
    return.{.rate=rate,.r=r,.fade=.init(0,sapFade,rate),.wind=wind,.music=music};
  }
  pub fn apply(s:*Sounds,cmd:Cmd)void{
    switch(cmd){
      .step=>|f|{
        s.steps[s.free()]=.init(f,&s.r,s.rate);
        s.sinceStep=0;
        s.weight=f.weight;
      },
      .eyes=>|e|{
        if(e and !s.eyes)s.wait=samples(&s.r,gapFirst,s.rate);
        s.eyes=e;
        s.fade.target=if(e)1 else 0;
      },
      .twinkle=>|t|{
        s.twinkles[s.nextTwinkle]=.init(m.clamp01(t.near),&s.r,s.rate);
        s.nextTwinkle=(s.nextTwinkle+1)%twinkles;
      },
      .daylight=>|d|s.music.daylight(d),
      .arsthraxia=>|a|{
        s.resProgress=a.progress;
        s.resFed=a.fed;
        if(a.complete and s.boom==null)s.boom=.init(&s.r,s.rate);
        if(a.progress>0 and a.progress<1){
          if(s.research==null)s.research=.init(&s.r,s.rate);
        }else if(a.progress==0){
          s.research=null;
        }
      }
    }
  }
  pub fn render(s:*Sounds,out:[]f32)void{
    for(&s.steps)|*v|if(v.*)|*st|{
      if(!st.render(out))v.*=null;
    };
    for(&s.twinkles)|*v|if(v.*)|*t|{
      if(!t.render(out))v.*=null;
    };
    s.sap(out);
    if(s.research)|*rs|rs.render(out,s.resProgress,s.resFed);
    if(s.boom)|*bm|{
      if(!bm.render(out))s.boom=null;
    }
    s.wind.render(out);
    s.music.render(out);
    for(out)|*x|x.*=dsp.softClip(x.*);
  }
  /// the sap settling now and then while in the eyes
  pub fn sap(s:*Sounds,out:[]f32)void{
    const n:u32=@intCast(out.len);
    s.sinceStep+|=n;
    if(s.eyes){
      s.wait-|=n;
      if(s.wait==0 and s.settle==null){
        s.settle=.init(s.weight,&s.r,s.rate);
        const still=m.f(s.sinceStep)>stillAfter*s.rate;
        s.wait=s.settle.?.len+samples(&s.r,if(still)gapStill else gapWalk,s.rate);
      }
    }
    if(s.settle)|*st|{
      if(!st.render(out,&s.fade)or(!s.eyes and s.fade.value<silent))s.settle=null;
    }
  }
  pub fn free(s:*Sounds)usize{
    for(s.steps,0..)|v,i|if(v==null)return i;
    defer s.steal=(s.steal+1)%voiceCount;
    return s.steal;
  }
};
