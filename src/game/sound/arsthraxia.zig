//! the arsthraxia's working: a spinning whorl under a swelling choir.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const dsp=engine.core.dsp;
const rng=engine.core.rng;
const retune=lib.sound.sap.retune;
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
const whorlBase=[2]f32{55,55.5};
const whorlFmHz=[2]f32{6,18};
const whorlFmDepth=[2]f32{0.02,0.12};
const whorlFilter=[2]f32{200,800};
const whorlQ=[2]f32{1.5,6};
const whorl:f32=1.8;
const rumbleHz:f32=35;
const rumble:f32=0.4;
const expandAt:f32=0.72;
const resSoftHz:f32=3500;
const res:f32=0.10;
const resFed:f32=0.3;
// the choir: a vowel sung by a few voices, swelling with progress
const singerCount=4;
const choirBase=[2]f32{165,262};
const choirSpread:f32=14;
const vibratoHz=[2]f32{4.5,6.0};
const vibratoCents:f32=15;
const bodyHz:f32=350;
const body:f32=0.8;
const f1:f32=500;
const f2:f32=1200;
const f3:f32=2800;
const f1Q:f32=6;
const f2Q:f32=8;
const f3Q:f32=10;
const f1L:f32=1.0;
const f2L:f32=0.5;
const f3L:f32=0.2;
const choirFrom:f32=0.3;
const choirFull:f32=0.85;
const choirAttack:f32=1.5;
const choir:f32=0.18;
/// one singer: a detuned saw with its own vibrato
const Singer=struct{
  osc:dsp.Osc,
  vibrato:dsp.Osc,
  base:f32,
  fn init(i:usize,base:f32,r:*rng.Rng,rate:f32)Singer{
    const cents=m.f(@as(i32,@intCast(i))-(singerCount-1)/2)*choirSpread;
    const hz=base*m.pow(f32,2,cents/1200);
    return.{
      .osc=.{.rate=rate,.shape=.saw,.freq=hz},
      .vibrato=.{.rate=rate,.freq=r.range(vibratoHz[0],vibratoHz[1])},
      .base=hz,
    };
  }
  fn tick(sg:*Singer,u:f32)f32{
    const rise=m.lerp(1,choirBase[1]/choirBase[0],m.smooth(u));
    sg.osc.freq=sg.base*rise*(1+vibratoCents/100*0.01*sg.vibrato.next());
    return sg.osc.next();
  }
};
/// the sustained voice: whorl + rumble + choir crescendo, driven by progress
pub const Research=struct{
  rate:f32,
  r:rng.Rng,
  oscA:dsp.Osc,
  oscB:dsp.Osc,
  fm:dsp.Osc,
  band:dsp.Biquad,
  rumble:dsp.Osc,
  singers:[singerCount]Singer,
  body:dsp.OnePole,
  f1:dsp.Biquad,
  f2:dsp.Biquad,
  f3:dsp.Biquad,
  choirFade:dsp.Smooth,
  soft:dsp.OnePole,
  at:u32=0,
  gain:f32,
  pub fn init(r:*rng.Rng,rate:f32)Research{
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
  pub fn render(rs:*Research,out:[]f32,progress:f32,fed:f32)void{
    const u=m.smooth(m.clamp01(progress/expandAt));
    const fmHz=m.lerp(whorlFmHz[0],whorlFmHz[1],u);
    const fmDepth=m.lerp(whorlFmDepth[0],whorlFmDepth[1],u);
    const filtHz=m.lerp(whorlFilter[0],whorlFilter[1],u);
    const q=m.lerp(whorlQ[0],whorlQ[1],u);
    const ex=m.clamp01((progress-expandAt)/(1-expandAt));
    const qOpen=m.lerp(q,1.0,ex);
    const choirU=m.clamp01((progress-choirFrom)/(choirFull-choirFrom));
    rs.choirFade.target=m.smooth(choirU);
    for(out)|*s|{
      if(rs.at%retune==0)rs.band.tune(.band,filtHz,qOpen,rs.rate);
      rs.at+%=1;
      rs.fm.freq=fmHz;
      const mod=rs.fm.next()*fmDepth;
      rs.oscA.freq=whorlBase[0]*(1+mod);
      rs.oscB.freq=whorlBase[1]*(1-mod);
      const raw=rs.oscA.next()+rs.oscB.next();
      const swirl=rs.band.tick(raw);
      const low=rs.rumble.next();
      var cr:f32=0;
      for(rs.singers[0..])|*sg|cr+=sg.tick(progress);
      const bod=rs.body.low(cr)*body;
      const formant=rs.f1.tick(cr)*f1L+rs.f2.tick(cr)*f2L+rs.f3.tick(cr)*f3L;
      const voice=(bod+formant)*rs.choirFade.next();
      const vol=u*u*(1+0.5*ex);
      const y=swirl*whorl+low*rumble+voice*choir;
      s.*+=rs.soft.low(y)*rs.gain*vol*(1+resFed*fed);
    }
  }
};
