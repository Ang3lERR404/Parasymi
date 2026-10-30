//! the source the device pulls from: every sound's voices mixed into one stream.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: clamps, conversions, the largest counts
const m=engine.core.math;
/// the engine's sound pieces: smoothing, the soft clip
const dsp=engine.core.dsp;
/// the seeded random numbers every sound draws from
const rng=engine.core.rng;
/// a paw coming down: how heavy, how fast
const Footfall=lib.player.Footfall;
/// the arsthraxia's completing boom
const Boom=lib.sound.boom.Boom;
/// how soon the first settling comes after the view enters the eyes (s)
const gapFirst=lib.sound.sap.gapFirst;
/// seconds between settlings while the wolf stands
const gapStill=lib.sound.sap.gapStill;
/// seconds between settlings while it walks
const gapWalk=lib.sound.sap.gapWalk;
/// the daytime piano
const Music=lib.sound.music.Music;
/// the arsthraxia's working voice: whorl and choir
const Research=lib.sound.arsthraxia.Research;
/// how fast the settling fades in and out with the view (s)
const sapFade=lib.sound.sap.sapFade;
/// quieter than this, a sound has ended
const silent=lib.sound.silent;
/// the wolf stands once no step has landed for this long (s)
const stillAfter=lib.sound.sap.stillAfter;
/// one settling of the sap, heard from inside
const Settle=lib.sound.sap.Settle;
/// one footstep playing out
const Step=lib.sound.footstep.Step;
/// how many twinkles may ring at once
const twinkles=lib.sound.twinkle.twinkles;
/// one twinkle of a mote of starlight
const Twinkle=lib.sound.twinkle.Twinkle;
/// how many footsteps may sound at once
const voiceCount=lib.sound.voiceCount;
/// the wind over the garden
const Wind=lib.sound.wind.Wind;
/// a span of seconds drawn as samples
const samples=lib.sound.sap.samples;
/// the source the device pulls from (`platform.audio.Output(Sounds)`)
pub const Sounds=struct{
  /// a paw landed; the view entered or left the wolf's eyes; a mote near
  /// the wolf twinkled; the daylight changed (0 night .. 1 day)
  pub const Cmd=union(enum){
    /// a paw came down
    step:Footfall,
    /// the view entered (true) or left (false) the wolf's eyes
    eyes:bool,
    /// a mote of starlight near the wolf twinkled
    twinkle:lib.sky.Twinkle,
    /// the daylight changed (0 night .. 1 day)
    daylight:f32,
    /// the arsthraxia's working: how far along (`progress`, 0..1), how well
    /// fed (`fed`, 0..1), and whether it has just completed (`complete`)
    arsthraxia:struct{progress:f32,fed:f32,complete:bool}
  };
  /// samples per second the sounds are made at
  rate:f32,
  /// the random numbers every new sound draws from
  r:rng.Rng,
  /// the footsteps' voices; null is free
  steps:[voiceCount]?Step=@splat(null),
  /// the voice taken when none is free (round the pool: the oldest)
  steal:usize=0,
  /// whether the view is in the wolf's eyes
  eyes:bool=false,
  /// how much of the settling is heard (1 in the eyes)
  fade:dsp.Smooth,
  /// the settling playing now, if any
  settle:?Settle=null,
  /// samples until the next settling, and since a paw last landed
  wait:u32=0,
  /// how many samples since a paw last landed
  sinceStep:u32=m.maxInt(u32),
  /// the belly at the last step
  weight:f32=0,
  /// the wind, always breathing
  wind:Wind,
  /// a new twinkle takes the oldest's place when both are sounding
  twinkles:[twinkles]?Twinkle=@splat(null),
  /// the twinkle slot the next one takes
  nextTwinkle:usize=0,
  /// the daytime piano, always running (silent by night)
  music:Music,
  /// the arsthraxia's working voice, while it works
  research:?Research=null,
  /// the boom, while it rings out
  boom:?Boom=null,
  /// how far along the arsthraxia's work is (0..1)
  resProgress:f32=0,
  /// how well the arsthraxia is fed (0..1)
  resFed:f32=0,
  /// every sound ready to play, seeded from `seed`, at `rate` samples a second
  pub fn init(seed:u64,rate:f32)Sounds{
    // the random numbers, and the wind and music drawn from them
    var r:rng.Rng=.init(seed);
    const wind:Wind=.init(&r,rate);
    const music:Music=.init(&r,rate);
    return.{.rate=rate,.r=r,.fade=.init(0,sapFade,rate),.wind=wind,.music=music};
  }
  /// what happened, heard: a step takes a voice, the eyes fade the
  /// settling in or out, a twinkle takes a slot, daylight sets the music,
  /// and the arsthraxia's work starts, follows or ends its voice and boom
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
  /// the next `out.len` samples: every sounding voice mixed in, those
  /// that have ended freed, and the whole softly clipped
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
  /// the sap settling now and then while in the eyes: counts the samples
  /// since a step, starts the next settling once its wait is up (sooner
  /// while the wolf stands), and mixes it into `out`, faded with the view
  pub fn sap(s:*Sounds,out:[]f32)void{
    // how many samples this block holds
    const n:u32=@intCast(out.len);
    s.sinceStep+|=n;
    if(s.eyes){
      s.wait-|=n;
      if(s.wait==0 and s.settle==null){
        s.settle=.init(s.weight,&s.r,s.rate);
        // whether the wolf has stood still long enough to count as standing
        const still=m.f(s.sinceStep)>stillAfter*s.rate;
        s.wait=s.settle.?.len+samples(&s.r,if(still)gapStill else gapWalk,s.rate);
      }
    }
    if(s.settle)|*st|{
      if(!st.render(out,&s.fade)or(!s.eyes and s.fade.value<silent))s.settle=null;
    }
  }
  /// a footstep voice to play on: the first free one, or else the next in
  /// turn round the pool (the oldest)
  pub fn free(s:*Sounds)usize{
    for(s.steps,0..)|v,i|if(v==null)return i;
    defer s.steal=(s.steal+1)%voiceCount;
    return s.steal;
  }
};
