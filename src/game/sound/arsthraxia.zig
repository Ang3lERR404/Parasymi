//! the arsthraxia's working: a spinning whorl under a swelling choir.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, easing, clamps
const m=engine.core.math;
/// the engine's sound pieces: oscillators, filters, smoothing
const dsp=engine.core.dsp;
/// the seeded random numbers each voice draws from
const rng=engine.core.rng;
/// samples between retunings of a swept filter
const retune=lib.sound.sap.retune;
/// a value nudged a little either way, so no two plays are alike
const vary=lib.sound.footstep.vary;
// pub const Choir = struct{
//   const This = @This();
//   singers:comptime_int,
//   spread:f32 = 14,
//   vibratoHZ:[]f32 = &.{4.2,5.8},
//   vibrato:f32 = 12,
//   formants:[]f32
// };
// ---- the arsthraxia: whorl → choir crescendo → boom → shimmer ----
// the whorl: two detuned saws whose beat IS the vortex spin; a fast FM
// (depth increasing with progress) creates the "spinning" sensation; a
// band-pass focuses them and tightens as the energy concentrates
/// the two saws' pitches (Hz); their half-hertz gap is the spin
const whorlBase=[2]f32{55,55.5};
/// how fast the frequency wobble runs, from the start to full progress (Hz)
const whorlFmHz=[2]f32{6,18};
/// how deep that wobble goes, from the start to full progress (a share)
const whorlFmDepth=[2]f32{0.02,0.12};
/// the band-pass's centre, from the start to full progress (Hz)
const whorlFilter=[2]f32{200,800};
/// how tight the band-pass rings, from the start to full progress (q)
const whorlQ=[2]f32{1.5,6};
/// the whorl's level in the mix
const whorl:f32=1.8;
/// the deep sine rumble under it (Hz)
const rumbleHz:f32=35;
/// the rumble's level in the mix
const rumble:f32=0.4;
/// how far along the work the whorl stops tightening and opens out (0..1)
const expandAt:f32=0.72;
/// the low-pass that softens the whole voice (Hz)
const resSoftHz:f32=3500;
/// the whole voice's loudness
const res:f32=0.10;
/// how much louder it grows while fed (a share at full feed)
const resFed:f32=0.3;
// the choir: a vowel sung by a few voices, swelling with progress
/// how many voices sing
const singerCount=4;
/// the choir's pitch at the start, and where it has risen to at full progress (Hz)
const choirBase=[2]f32{165,262};
/// how far apart the singers are detuned (cents between neighbours)
const choirSpread:f32=14;
/// how fast each singer's vibrato wavers, drawn between these (Hz)
const vibratoHz=[2]f32{4.5,6.0};
/// how deep the vibrato wavers
const vibratoCents:f32=15;
/// the low-pass that gives the choir its chest (Hz)
const bodyHz:f32=350;
/// how much of that chest is heard
const body:f32=0.8;
/// the vowel's first formant (Hz)
const f1:f32=500;
/// the vowel's second formant (Hz)
const f2:f32=1200;
/// the vowel's third formant (Hz)
const f3:f32=2800;
/// how tight the first formant rings (q)
const f1Q:f32=6;
/// how tight the second formant rings (q)
const f2Q:f32=8;
/// how tight the third formant rings (q)
const f3Q:f32=10;
/// the first formant's level
const f1L:f32=1.0;
/// the second formant's level
const f2L:f32=0.5;
/// the third formant's level
const f3L:f32=0.2;
/// how far along the work the choir starts to swell (0..1)
const choirFrom:f32=0.3;
/// how far along it is fully in (0..1)
const choirFull:f32=0.85;
/// how long the choir takes to glide to a new level (s)
const choirAttack:f32=1.5;
/// the choir's level in the mix
const choir:f32=0.18;
/// one singer: a detuned saw with its own vibrato
const Singer=struct{
  /// its saw
  osc:dsp.Osc,
  /// its vibrato's slow wave
  vibrato:dsp.Osc,
  /// its own detuned pitch (Hz)
  base:f32,
  /// singer `i` of the choir, detuned from `base` (Hz) by its place in it,
  /// its vibrato rate drawn from `r`
  fn init(i:usize,base:f32,r:*rng.Rng,rate:f32)Singer{
    // how far this singer is detuned (cents), and its pitch
    const cents=m.f(@as(i32,@intCast(i))-(singerCount-1)/2)*choirSpread;
    const hz=base*m.pow(f32,2,cents/1200);
    return.{
      .osc=.{.rate=rate,.shape=.saw,.freq=hz},
      .vibrato=.{.rate=rate,.freq=r.range(vibratoHz[0],vibratoHz[1])},
      .base=hz,
    };
  }
  /// its next sample, `u` (0..1, the work's progress) lifting its pitch
  /// toward the choir's top as it swells
  fn tick(sg:*Singer,u:f32)f32{
    // how far the choir has risen, as a pitch ratio
    const rise=m.lerp(1,choirBase[1]/choirBase[0],m.smooth(u));
    sg.osc.freq=sg.base*rise*(1+vibratoCents/100*0.01*sg.vibrato.next());
    return sg.osc.next();
  }
};
/// the sustained voice: whorl + rumble + choir crescendo, driven by progress
pub const Research=struct{
  /// samples per second
  rate:f32,
  /// its own random numbers
  r:rng.Rng,
  /// the whorl's first saw
  oscA:dsp.Osc,
  /// the whorl's second saw, half a hertz apart
  oscB:dsp.Osc,
  /// the wobble swinging the two saws' pitches apart
  fm:dsp.Osc,
  /// the band-pass that focuses the whorl
  band:dsp.Biquad,
  /// the deep sine rumble
  rumble:dsp.Osc,
  /// the choir's voices
  singers:[singerCount]Singer,
  /// the low-pass that gives the choir its chest
  body:dsp.OnePole,
  /// the first formant's band-pass
  f1:dsp.Biquad,
  /// the second formant's band-pass
  f2:dsp.Biquad,
  /// the third formant's band-pass
  f3:dsp.Biquad,
  /// the choir's level, gliding as it swells
  choirFade:dsp.Smooth,
  /// the low-pass softening the whole voice
  soft:dsp.OnePole,
  /// samples played so far (wraps), for when to retune the band-pass
  at:u32=0,
  /// this voice's loudness, varied a little each time
  gain:f32,
  /// a fresh voice, its singers and loudness drawn from `r`
  pub fn init(r:*rng.Rng,rate:f32)Research{
    // the choir's singers, each detuned in turn
    var singers:[singerCount]Singer=undefined;
    for(&singers,0..)|*sg,i|sg.*=.init(i,choirBase[0],r,rate);
    return.{
      .rate=rate,
      .r=.init(r.next()),
      .oscA=.{.rate=rate,.shape=.saw,.freq=whorlBase[0]},
      .oscB=.{.rate=rate,.shape=.saw,.freq=whorlBase[1]},
      .fm=.{.rate=rate,.shape=.sine,.freq=whorlFmHz[0]},
      .band=.init(.band,whorlFilter[0],whorlQ[0],rate),
      .rumble=.{.rate=rate,.shape=.sine,.freq=rumbleHz},
      .singers=singers,
      .body=.init(bodyHz,rate),
      .f1=.init(.band,f1,f1Q,rate),
      .f2=.init(.band,f2,f2Q,rate),
      .f3=.init(.band,f3,f3Q,rate),
      .choirFade=.init(0,choirAttack,rate),
      .soft=.init(resSoftHz,rate),
      .gain=vary(r,res),
    };
  }
  /// mixes the next `out.len` samples into `out`, the whorl tightening and
  /// the choir swelling with `progress` (0..1), and louder as `fed` (0..1)
  pub fn render(rs:*Research,out:[]f32,progress:f32,fed:f32)void{
    // how far the whorl has tightened, 0..1 by `expandAt`
    const u=m.smooth(m.clamp01(progress/expandAt));
    // the wobble's rate and depth, and the band-pass's centre and ring, for that
    const fmHz=m.lerp(whorlFmHz[0],whorlFmHz[1],u);
    const fmDepth=m.lerp(whorlFmDepth[0],whorlFmDepth[1],u);
    const filtHz=m.lerp(whorlFilter[0],whorlFilter[1],u);
    const q=m.lerp(whorlQ[0],whorlQ[1],u);
    // how far it has opened out past `expandAt`, and the ring loosening with it
    const ex=m.clamp01((progress-expandAt)/(1-expandAt));
    const qOpen=m.lerp(q,1.0,ex);
    // how far the choir has swelled, 0..1
    const choirU=m.clamp01((progress-choirFrom)/(choirFull-choirFrom));
    rs.choirFade.target=m.smooth(choirU);
    for(out)|*s|{
      if(rs.at%retune==0)rs.band.tune(.band,filtHz,qOpen,rs.rate);
      rs.at+%=1;
      rs.fm.freq=fmHz;
      // the wobble this sample, swinging the two saws apart
      const mod=rs.fm.next()*fmDepth;
      rs.oscA.freq=whorlBase[0]*(1+mod);
      rs.oscB.freq=whorlBase[1]*(1-mod);
      // the two saws, focused into the swirl, and the rumble under it
      const raw=rs.oscA.next()+rs.oscB.next();
      const swirl=rs.band.tick(raw);
      const low=rs.rumble.next();
      // the choir summed
      var cr:f32=0;
      for(rs.singers[0..])|*sg|cr+=sg.tick(progress);
      // its chest and its vowel, together at the choir's level
      const bod=rs.body.low(cr)*body;
      const formant=rs.f1.tick(cr)*f1L+rs.f2.tick(cr)*f2L+rs.f3.tick(cr)*f3L;
      const voice=(bod+formant)*rs.choirFade.next();
      // how loud the whole voice is: rising with the whorl, swelling as it opens
      const vol=u*u*(1+0.5*ex);
      // the whorl, rumble and choir mixed
      const y=swirl*whorl+low*rumble+voice*choir;
      s.*+=rs.soft.low(y)*rs.gain*vol*(1+resFed*fed);
    }
  }
};
