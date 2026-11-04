//! the source the device pulls from: every sound's voices mixed into one
//! stereo stream, each heard from where it is (the ear the game tells it).
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
/// the arsthraxia's bloom as a unit is done
const Bloom=lib.sound.bloom.Bloom;
/// how soon the first settling comes after the view enters the eyes (s)
const gapFirst=lib.sound.sap.gapFirst;
/// seconds between settlings while the wolf stands
const gapStill=lib.sound.sap.gapStill;
/// seconds between settlings while it walks
const gapWalk=lib.sound.sap.gapWalk;
/// the daytime piano
const Music=lib.sound.music.Music;
/// the night's strings, chimes and choir
const Night=lib.sound.night.Night;
/// the arsthraxia's working voice: glass, thrum, wisps and core
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
/// one twinkle of a starlit patch's spark
const Twinkle=lib.sound.twinkle.Twinkle;
/// how many footsteps may sound at once
const voiceCount=lib.sound.voiceCount;
/// the wind over the garden
const Wind=lib.sound.wind.Wind;
/// the unforming heard
const Unformed=lib.sound.unforming.Unformed;
/// how much of the garden's music is left while the unforming sounds: none,
/// its own theme plays instead
const hushed:f32=0;
/// how much of the world's far-off screaming is heard straight, not through
/// the hall
const farDry:f32=0.35;
/// how long the hall rings (s, to -60 dB)
const hallRt60:f32=4.2;
/// how long before it answers (s): a large space
const hallPre:f32=0.035;
/// what darkens its tail (Hz): stone, not glass
const hallDamp:f32=4500;
/// how much of the hall is heard against the music itself
const hallWet:f32=0.6;
/// samples the music is rendered at a time before the hall
const hallBlock=256;
/// frames rendered at a time, each block's echo sent as it plays
const airBlock=512;
/// how soon the place's echo answers (s): near things answer near
const airPre:f32=0.012;
/// how long the echo takes to become a new place's (s, ~63%)
const airGlide:f32=0.8;
/// how far (a share) the echo glides before it is retuned
const airRetune:f32=0.02;
/// a span of seconds drawn as samples
const samples=lib.sound.sap.samples;
/// the source the device pulls from (`platform.audio.Output(Sounds)`)
pub const Sounds=struct{
  /// a paw landed; the view entered or left the wolf's eyes; a mote near
  /// the wolf twinkled; the daylight changed (0 night .. 1 day); the ear moved
  pub const Cmd=union(enum){
    /// a paw came down, `muffle` (0..1) of the way to it hidden
    step:struct{fall:Footfall,muffle:f32=0},
    /// the view entered (true) or left (false) the wolf's eyes
    eyes:bool,
    /// a starlit patch's spark near the wolf twinkled, `muffle` (0..1) of the way to it hidden
    twinkle:struct{spark:lib.starlight.Twinkle,muffle:f32=0},
    /// the daylight changed (0 night .. 1 day)
    daylight:f32,
    /// the arsthraxia's working: how far along (`progress`, 0..1), how well
    /// fed (`fed`, 0..1), whether it has just completed (`complete`) and
    /// where it stands (`at`, heard from there, `muffle` of the way to it hidden)
    arsthraxia:struct{progress:f32,fed:f32,complete:bool,at:m.V3=@splat(0),muffle:f32=0},
    /// the unforming, this frame: its clock, what broke and what withers
    unforming:lib.unforming.Heard,
    /// where the sounds are heard from now (the view), and which way is right
    ear:dsp.Ear,
    /// the echo of the place they are heard in now
    space:dsp.Space,
  };
  /// samples per second the sounds are made at
  rate:f32,
  /// the random numbers every new sound draws from
  r:rng.Rng,
  /// the footsteps' voices: a free one, else the oldest
  steps:dsp.Pool(Step,voiceCount)=.{},
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
  /// the twinkles: a new one takes the oldest's place
  twinkles:dsp.Pool(Twinkle,twinkles)=.{},
  /// the daytime piano, always running (silent by night)
  music:Music,
  /// the night's music, always running (silent by day)
  night:Night,
  /// the great hall both musics ring in
  hall:dsp.Hall,
  /// the arsthraxia's working voice, while it works or fades away
  research:?Research=null,
  /// the blooms ringing out: a unit may be done before the last has rung away
  blooms:dsp.Pool(Bloom,2)=.{},
  /// how far along the arsthraxia's work is (0..1)
  resProgress:f32=0,
  /// how well the arsthraxia is fed (0..1)
  resFed:f32=0,
  /// whether its last word was a unit done, so one unit blooms once
  resDone:bool=false,
  /// the unforming heard, from its first moment until it has rung away
  unformed:?Unformed=null,
  /// where the sounds are heard from: what places each between the speakers
  ear:dsp.Ear=.{},
  /// where the arsthraxia stands
  resAt:m.V3=@splat(0),
  /// how much of the way to it is hidden
  resMuffle:f32=0,
  /// the place's echo all that is heard in the world rings in
  air:dsp.Hall,
  /// the echo the place has now, gliding to the one it is told
  /// (this one: how long it rings, s)
  airRing:dsp.Smooth,
  /// (how much of it is heard)
  airWet:dsp.Smooth,
  /// (what darkens it, Hz)
  airDamp:dsp.Smooth,
  /// the ringing and darkening the echo was last tuned to
  airTuned:m.Vice(f32,2),
  /// every sound ready to play, seeded from `seed`, at `rate` samples a second
  pub fn init(seed:u64,rate:f32)Sounds{
    // the random numbers, and the wind and music drawn from them
    var r:rng.Rng=.init(seed);
    const wind:Wind=.init(&r,rate);
    const music:Music=.init(&r,rate);
    const night:Night=.init(&r,rate);
    // the place's echo to start with
    const sp:dsp.Space=.{};
    return.{.rate=rate,.r=r,.fade=.init(0,sapFade,rate),.wind=wind,.music=music,.night=night,.hall=.init(hallRt60,hallPre,hallDamp,rate),
      .air=.init(sp.rt60,airPre,sp.dampHz,rate),
      .airRing=.init(sp.rt60,airGlide,rate),
      .airWet=.init(sp.wet,airGlide,rate),
      .airDamp=.init(sp.dampHz,airGlide,rate),
      .airTuned=.{sp.rt60,sp.dampHz},
    };
  }
  /// what happened, heard: a step takes a voice, the eyes fade the
  /// settling in or out, a twinkle takes a slot, daylight sets the day's
  /// and the night's music,
  /// and the arsthraxia's work starts, follows or fades its voice and rings its bloom
  pub fn apply(s:*Sounds,cmd:Cmd)void{
    switch(cmd){
      .step=>|st|{
        // the paw that fell
        const f=st.fall;
        s.steps.add(.init(f,s.ear.hear(f.at,st.muffle),&s.r,s.rate));
        s.sinceStep=0;
        s.weight=f.weight;
      },
      .eyes=>|e|{
        if(e and !s.eyes)s.wait=samples(&s.r,gapFirst,s.rate);
        s.eyes=e;
        s.fade.target=if(e)1 else 0;
      },
      .twinkle=>|tw|{
        // the mote that twinkled
        const t=tw.spark;
        s.twinkles.cycle(.init(m.clamp01(t.near),s.ear.hear(t.at,tw.muffle),&s.r,s.rate));
      },
      .daylight=>|d|{
        s.music.daylight(d);
        s.night.daylight(d);
      },
      .arsthraxia=>|a|{
        s.resProgress=a.progress;
        s.resFed=a.fed;
        s.resAt=a.at;
        s.resMuffle=a.muffle;
        if(a.complete and !s.resDone)s.blooms.cycle(.init(s.ear.hear(a.at,a.muffle),&s.r,s.rate));
        s.resDone=a.complete;
        if(a.progress>0 and a.progress<1){
          if(s.research)|*rs|rs.go()else s.research=.init(s.ear.hear(a.at,a.muffle),&s.r,s.rate);
        }else if(a.progress==0 and !a.complete){
          if(s.research)|*rs|rs.stop();
        }
      },
      .unforming=>|h|{
        if(s.unformed==null)s.unformed=.init(h.t,s.r.next(),s.rate);
        s.unformed.?.apply(h);
      },
      .ear=>|e|s.ear=e,
      .space=>|sp|{
        s.airRing.target=sp.rt60;
        s.airWet.target=sp.wet;
        s.airDamp.target=sp.dampHz;
      },
    }
  }
  /// the next `out.len` frames: every sounding voice mixed in, those
  /// that have ended freed, and the whole softly clipped, each side
  pub fn render(s:*Sounds,out:[]dsp.Frame)void{
    // how far into `out` the blocks have reached
    var off:usize=0;
    while(off<out.len){
      // this block's length
      const k=@min(airBlock,out.len-off);
      s.block(out[off..][0..k]);
      off+=k;
    }
  }
  /// one block of `render` (at most `airBlock` frames): what is heard in
  /// the world sends to the place's echo as it plays
  fn block(s:*Sounds,out:[]dsp.Frame)void{
    // what reaches the place's echo this block
    var sendBuf:[airBlock]f32=@splat(0);
    const send=sendBuf[0..out.len];
    s.steps.renderSent(out,send);
    s.twinkles.renderSent(out,send);
    s.sap(out);
    if(s.research)|*rs|{
      if(!rs.render(out,send,s.resProgress,s.resFed,s.ear.hear(s.resAt,s.resMuffle)))s.research=null;
    }
    s.blooms.renderSent(out,send);
    s.echo(out,send);
    if(s.unformed)|*u|{
      if(!u.render(out))s.unformed=null;
    }
    s.wind.render(out);
    s.musics(out);
    for(out)|*x|x.*=.{dsp.softClip(x[0]),dsp.softClip(x[1])};
  }
  /// the place's echo of what `send` holds, mixed into `out`, gliding to the
  /// echo the place has now
  pub fn echo(s:*Sounds,out:[]dsp.Frame,send:[]const f32)void{
    for(out,send)|*o,x|{
      _=s.airRing.next();
      _=s.airDamp.next();
      o.*+=s.air.tick(dsp.mid(x))*dsp.mid(s.airWet.next());
    }
    // retuned once it has glided far enough from the last
    const now=m.Vice(f32,2){s.airRing.value,s.airDamp.value};
    if(@abs(now[0]-s.airTuned[0])>airRetune*now[0] or @abs(now[1]-s.airTuned[1])>airRetune*now[1]){
      s.air.ring(now[0],now[1],s.rate);
      s.airTuned=now;
    }
  }
  /// the sap settling now and then while in the eyes: counts the samples
  /// since a step, starts the next settling once its wait is up (sooner
  /// while the wolf stands), and mixes it into `out`, faded with the view
  pub fn sap(s:*Sounds,out:[]dsp.Frame)void{
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
  /// the day's and the night's music, mixed into `out` with the hall they
  /// ring in (its tail spread wide round them), a block at a time; while
  /// the unforming sounds, its theme in their place, the world's screams
  /// heard mostly through the hall
  pub fn musics(s:*Sounds,out:[]dsp.Frame)void{
    // how far into `out` the blocks have reached
    var off:usize=0;
    while(off<out.len){
      // this block's length, the music alone in it, and the far-off voices
      const k=@min(hallBlock,out.len-off);
      var buf:[hallBlock]dsp.Frame=@splat(@splat(0));
      var far:[hallBlock]dsp.Frame=@splat(@splat(0));
      s.music.render(buf[0..k]);
      s.night.render(buf[0..k]);
      // how much of the hall's tail is let through
      var tail:f32=1;
      if(s.unformed)|*u|{
        // how much of the garden's music the unforming leaves, its theme over it
        const left=m.lerp(1,hushed,u.hush());
        for(buf[0..k])|*x|x.*=dsp.mid(left)*x.*;
        u.theme.render(buf[0..k],far[0..k]);
        tail=u.theme.tailLeft();
      }
      // how much of the far-off voices is heard straight, and of the hall
      const straight=dsp.mid(farDry);
      const wet=dsp.mid(hallWet*tail);
      for(out[off..][0..k],buf[0..k],far[0..k])|*o,x,f|o.*+=x+f*straight+s.hall.tick(x+f)*wet;
      off+=k;
    }
  }
};
