//! the unforming heard: a low D swelling under it all, glass raining as the sky shatters, a seam humming shut, ash crumbling, a crack as each radiant plant breaks, a rising ping as each shard reaches the star, a whistle as the seed falls and a deep bell blooming where it lands.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, clamps, powers
const m=engine.core.math;
/// the engine's sound pieces: sines, noise, filters, pools
const dsp=engine.core.dsp;
/// the seeded random numbers the event's sounds draw from
const rng=engine.core.rng;
/// the event: its moments, and what it sends each frame
const ev=lib.unforming;
/// what the event sends each frame
const Heard=ev.Heard;
/// quieter than this, a sound has ended
const silent=lib.sound.silent;
/// samples between retunings of a swept filter
const retune=lib.sound.sap.retune;
// decision: it all keeps to the music's D Lydian and stays soft (the
// arsthraxia's bloom, the starlight's twinkle): the end of a world heard as
// glass and a held breath, never a crash
/// D Lydian's steps up from D (semitones): D E F# G# A B C#
const lydian=[_]f32{0,2,4,6,7,9,11};
/// the note (MIDI) a step of D Lydian `k` up from `from` is
fn lydianNote(from:f32,k:u32)f32{return from+12*m.f(k/lydian.len)+lydian[k%lydian.len];}
// ---- a glint: a tiny glass bell, the grain all the glass is made of ----
/// a glint's partials (shares of its pitch, stretched as glass rings) and levels
const glintPartials=[_]f32{1,2.76};
/// (their levels)
const glintPartialLevel=[glintPartials.len]f32{1,0.3};
/// a glint's soft strike (s)
const glintAttack:f32=0.004;
/// a glint this far rung out is gone
const glintSilent:f32=2e-3;
/// one glint: two partials ringing out from a soft strike
const Glint=struct{
  /// its partials' sines
  osc:[glintPartials.len]dsp.Sine,
  /// each partial's level now, 1 falling away
  amp:[glintPartials.len]f32=@splat(1),
  /// how much of its level each partial keeps a sample
  fall:[glintPartials.len]f32,
  /// samples until it rings in
  wait:u32,
  /// samples since it rang in
  at:u32=0,
  /// samples a second
  rate:f32,
  /// its loudness
  level:f32,
  /// a glint of note `note` (MIDI) ringing `ring` seconds (~63%) at
  /// `level`, `delay` seconds from now
  fn init(note:f32,ring:f32,level:f32,delay:f32,rate:f32)Glint{
    // its pitch, and its partials
    const hz=dsp.noteToHz(note);
    var osc:[glintPartials.len]dsp.Sine=undefined;
    var fall:[glintPartials.len]f32=undefined;
    for(glintPartials,0..)|p,k|{
      osc[k]=.init(hz*p,rate);
      fall[k]=dsp.fall(ring/(1+2*m.f(k)),rate);
    }
    return.{.osc=osc,.fall=fall,.wait=m.floorTo(u32,delay*rate),.rate=rate,.level=level};
  }
  /// mixes it into `out`; false once rung out
  pub fn render(g:*Glint,out:[]f32)bool{
    for(out)|*s|{
      if(g.wait>0){
        g.wait-=1;
        continue;
      }
      // how far into its strike
      const strike=m.clamp01(m.f(g.at)/(glintAttack*g.rate));
      var y:f32=0;
      for(&g.osc,&g.amp,g.fall,glintPartialLevel)|*o,*a,f,l|{
        y+=o.next()*l*a.*;
        a.*=f*a.*;
      }
      s.*+=y*strike*g.level;
      g.at+|=1;
      if(g.amp[0]<glintSilent)return false;
    }
    return true;
  }
};
/// glints that may ring at once
const glintCount=64;
// ---- a crack: what breaking glass is made of besides its glints ----
/// a crack's snap: noise high-passed this high (Hz), falling this fast (s)
const crackHz:f32=2800;
/// (how fast it falls)
const crackFall:f32=0.05;
/// how many glints a crack scatters (fewest, most), over how long (s)
const crackGlints=m.Vice(u32,2){4,7};
/// (over how long)
const crackSpread:f32=0.09;
/// its glints' notes: D Lydian steps up from this note (MIDI), this many
const crackFrom:f32=86;
/// (this many steps)
const crackSteps:u32=10;
/// how loud its snap and its glints are
const crackSnap:f32=0.01;
/// (its glints)
const crackGlint:f32=0.009;
/// one crack's snap: a short hiss of breaking
const Crack=struct{
  /// the noise it is drawn from
  noise:dsp.Noise,
  /// the high-pass thinning it to a snap
  thin:dsp.OnePole,
  /// how loud it still is, 1 falling away
  amp:f32=1,
  /// how much it keeps a sample
  keep:f32,
  /// mixes it into `out`; false once gone
  pub fn render(c:*Crack,out:[]f32)bool{
    for(out)|*s|{
      s.*+=c.thin.high(c.noise.next())*c.amp*crackSnap;
      c.amp*=c.keep;
    }
    return c.amp>silent;
  }
};
// ---- the drone: a low D held under it all ----
/// its notes (MIDI): D2, A2, D3 and the Lydian G#3 faint over them
const droneNote=[_]f32{38,45,50,56};
/// (their levels)
const droneLevel=[droneNote.len]f32{1,0.6,0.35,0.12};
/// how far a twin of each drifts off it (Hz), beating slowly against it
const droneBeat:f32=0.35;
/// how long it takes to swell in (s), how long after landing it fades (s)
const droneRise:f32=3;
/// (how long it fades)
const droneFade:f32=9;
/// what darkens it (Hz)
const droneDark:f32=700;
/// how loud
const drone:f32=0.016;
// ---- the glass rain: the sky shattering pane by pane ----
/// glints a second at the shift's height
const rainMost:f32=22;
/// its glints' notes: D Lydian steps up from this note (MIDI), this many
const rainFrom:f32=81;
/// (this many)
const rainSteps:u32=14;
/// how long each rings (s, fewest and most)
const rainRing=m.Vice(f32,2){0.25,0.8};
/// how loud each (fewest and most)
const rainLevel=m.Vice(f32,2){0.002,0.008};
// ---- the seam: the ley lines humming shut ----
/// its glide (MIDI), from and to: D3 sinking to D2
const sealNotes=m.Vice(f32,2){50,38};
/// its twin's drift off it (Hz)
const sealBeat:f32=1.3;
/// how loud
const sealLoud:f32=0.012;
// ---- the crumble: dry ash falling away ----
/// grains a second at a garden's worth withering, their fade (s), the band they ring in (Hz) and its q
const crumbleMost:f32=120;
/// (their fade)
const crumbleGrain:f32=0.004;
/// (the band)
const crumbleHz:f32=3200;
/// (its q)
const crumbleQ:f32=0.9;
/// how loud
const crumble:f32=0.02;
// ---- the arrivals: each shard rising a step in the star ----
/// the first arrival's note (MIDI): D5, each next a Lydian step up, wrapping after this many
const arriveFrom:f32=74;
/// (wrapping after)
const arriveSteps:u32=15;
/// how long each rings (s), and how loud
const arriveRing:f32=1.1;
/// (how loud)
const arriveLevel:f32=0.01;
// ---- the fall: the seed whistling down ----
/// its whistle's band sweep (Hz) and q
const fallSweep=m.Vice(f32,2){3200,280};
/// (its q)
const fallQ:f32=6;
/// its tone's glide (MIDI)
const fallNotes=m.Vice(f32,2){86,62};
/// how loud its air and its tone
const fallAir:f32=0.03;
/// (its tone)
const fallTone:f32=0.006;
// ---- the landing: a deep bell blooming, glass ringing up over it ----
/// its bell's partials (shares of D2), levels and rings (s)
const landPartials=[_]f32{1,2,3,4.2,5.4};
/// (their levels)
const landPartialLevel=[landPartials.len]f32{1,0.6,0.45,0.25,0.15};
/// (their rings)
const landPartialRing=[landPartials.len]f32{4,3,2.4,1.4,0.9};
/// its bell's note (MIDI): D2
const landNote:f32=38;
/// its thump: a low sine sinking (Hz) and falling away (s)
const thumpSweep=m.Vice(f32,2){70,32};
/// (falling away)
const thumpFall:f32=0.22;
/// the glass chord ringing up over it (MIDI): D5 F#5 A5 C#6 G#6, each this long after the last (s)
const landChord=[_]f32{74,78,81,85,92};
/// (each this long after the last)
const landStagger:f32=0.11;
/// how long the chord rings (s), and how loud
const landChordRing:f32=2.8;
/// (how loud)
const landChordLevel:f32=0.012;
/// how loud the bell and the thump
const landBell:f32=0.03;
/// (the thump)
const landThump:f32=0.08;
/// the landing's low half: the bell and the thump (its glass is glints)
const Land=struct{
  /// the bell's partials
  osc:[landPartials.len]dsp.Sine,
  /// each partial's level now
  amp:[landPartials.len]f32=@splat(1),
  /// how much each keeps a sample
  fall:[landPartials.len]f32,
  /// the thump's sine (gliding)
  thump:dsp.Osc,
  /// the thump's level, falling
  thumpAmp:f32=1,
  /// how much it keeps a sample
  thumpKeep:f32,
  /// samples since it struck
  at:u32=0,
  /// samples a second
  rate:f32,
  /// the bell and thump struck now
  fn init(rate:f32)Land{
    // the bell's partials
    var osc:[landPartials.len]dsp.Sine=undefined;
    var fall:[landPartials.len]f32=undefined;
    for(landPartials,landPartialRing,0..)|p,r,k|{
      osc[k]=.init(dsp.noteToHz(landNote)*p,rate);
      fall[k]=dsp.fall(r,rate);
    }
    return.{.osc=osc,.fall=fall,.thump=.{.rate=rate,.freq=thumpSweep[0]},.thumpKeep=dsp.fall(thumpFall,rate),.rate=rate};
  }
  /// mixes it into `out`; false once rung out
  fn render(l:*Land,out:[]f32)bool{
    for(out)|*s|{
      // a soft swell in, so it blooms rather than strikes
      const t=m.f(l.at)/l.rate;
      const swell=m.smooth(m.clamp01(t/0.08));
      var y:f32=0;
      for(&l.osc,&l.amp,l.fall,landPartialLevel)|*o,*a,f,v|{
        y+=o.next()*v*a.*;
        a.*=f*a.*;
      }
      l.thump.freq=m.lerp(thumpSweep[1],thumpSweep[0],l.thumpAmp);
      s.*+=y*swell*landBell+l.thump.next()*l.thumpAmp*landThump;
      l.thumpAmp*=l.thumpKeep;
      l.at+|=1;
    }
    return l.amp[0]>silent;
  }
};
/// the unforming heard, from its first moment until it has all rung away
pub const Unformed=struct{
  /// samples a second
  rate:f32,
  /// its own random numbers
  r:rng.Rng,
  /// the event's clock as heard (s), run on between what it is told
  clock:f32=0,
  /// how much is withering, gliding
  wither:dsp.Smooth,
  /// how many shards have reached the star (each rings a step higher)
  arrived:u32=0,
  /// whether the seed has landed in its hearing
  landed:bool=false,
  /// the drone's sines and their beating twins
  drone:[droneNote.len]dsp.Sine,
  /// (their twins)
  droneTwin:[droneNote.len]dsp.Sine,
  /// what darkens the drone
  droneSoft:dsp.OnePole,
  /// samples until the next glint of the rain
  rainWait:u32=0,
  /// the seam's tone and its twin, gliding down
  seal:dsp.Osc,
  /// (its twin)
  sealTwin:dsp.Osc,
  /// the ash's grains, and the band they ring in
  crumble:dsp.Crackle,
  /// (the band)
  crumbleBand:dsp.Biquad,
  /// the fall's air, its swept band, and its tone
  air:dsp.Noise,
  /// (the swept band)
  fallBand:dsp.Biquad,
  /// (its tone)
  fallTone:dsp.Osc,
  /// every glint ringing
  glints:dsp.Pool(Glint,glintCount)=.{},
  /// every crack's snap
  cracks:dsp.Pool(Crack,6)=.{},
  /// the landing's bell and thump, once struck
  land:?Land=null,
  /// the event heard from its moment `t`, its sounds drawn from `seed`
  pub fn init(t:f32,seed:u64,rate:f32)Unformed{
    // the drone's sines and their twins
    var d:[droneNote.len]dsp.Sine=undefined;
    var tw:[droneNote.len]dsp.Sine=undefined;
    for(droneNote,0..)|n,k|{
      d[k]=.init(dsp.noteToHz(n),rate);
      tw[k]=.init(dsp.noteToHz(n)+droneBeat*(1+m.f(k)),rate);
    }
    return.{
      .rate=rate,
      .r=.init(seed),
      .clock=t,
      .wither=.init(0,0.6,rate),
      .drone=d,
      .droneTwin=tw,
      .droneSoft=.init(droneDark,rate),
      .seal=.{.rate=rate,.freq=dsp.noteToHz(sealNotes[0])},
      .sealTwin=.{.rate=rate,.freq=dsp.noteToHz(sealNotes[0])+sealBeat},
      .crumble=.init(seed^0xA54,crumbleGrain,rate),
      .crumbleBand=.init(.band,crumbleHz,crumbleQ,rate),
      .air=.init(seed^0xF411),
      .fallBand=.init(.band,fallSweep[0],fallQ,rate),
      .fallTone=.{.rate=rate,.freq=dsp.noteToHz(fallNotes[0])},
    };
  }
  /// what the event sent this frame: its clock kept to it (only a slip is
  /// mended, so it runs on smoothly between frames), each crack and arrival
  /// struck, the withering followed
  pub fn apply(u:*Unformed,h:Heard)void{
    if(@abs(h.t-u.clock)>0.25)u.clock=h.t;
    u.wither.target=h.wither;
    for(0..h.cracks)|_|u.crack();
    for(0..h.arrivals)|_|{
      u.glints.cycle(.init(lydianNote(arriveFrom,u.arrived%arriveSteps),arriveRing,arriveLevel,0,u.rate));
      u.arrived+=1;
    }
  }
  /// glass breaking: a snap and a scatter of glints, high in D Lydian
  fn crack(u:*Unformed)void{
    u.cracks.cycle(.{.noise=.init(u.r.next()),.thin=.init(crackHz,u.rate),.keep=dsp.fall(crackFall,u.rate)});
    // how many glints it scatters
    const n=crackGlints[0]+u.r.below(crackGlints[1]-crackGlints[0]+1);
    for(0..n)|_|u.glints.cycle(.init(lydianNote(crackFrom,u.r.below(crackSteps)),u.r.range(0.15,0.5),crackGlint*u.r.range(0.5,1),u.r.range(0,crackSpread),u.rate));
  }
  /// mixes the next `out.len` samples into `out`, its clock running on;
  /// false once all of it has rung away
  pub fn render(u:*Unformed,out:[]f32)bool{
    for(out,0..)|*s,i|{
      // the clock, and how much the drone is heard (swelling in, fading after the landing)
      const t=u.clock;
      const dr=m.smooth(m.clamp01(t/droneRise))*(1-m.smooth(m.clamp01((t-ev.landAt)/droneFade)));
      var y:f32=0;
      if(dr>0){
        var d:f32=0;
        for(&u.drone,&u.droneTwin,droneLevel)|*a,*b,l|d+=(a.next()+b.next())*0.5*l;
        y+=u.droneSoft.low(d)*dr*drone;
      }
      // the seam humming shut as the ley lines seal, sinking
      const sk=(t-ev.sealStart)/(ev.sealEnd-ev.sealStart);
      if(sk>0 and sk<1){
        const note=m.lerp(sealNotes[0],sealNotes[1],sk);
        u.seal.freq=dsp.noteToHz(note);
        u.sealTwin.freq=u.seal.freq+sealBeat;
        y+=(u.seal.next()+u.sealTwin.next())*0.5*m.pow(f32,@sin(m.pi*sk),0.7)*sealLoud;
      }
      // ash crumbling, as much as is withering
      u.crumble.density=u.wither.next()*crumbleMost;
      y+=u.crumbleBand.tick(u.crumble.next())*crumble;
      // the seed whistling down, louder as it nears
      const fk=(t-ev.shatterEnd)/ev.fallTime;
      if(fk>0 and fk<1){
        if(i%retune==0)u.fallBand.tune(.band,fallSweep[0]*m.pow(f32,fallSweep[1]/fallSweep[0],fk),fallQ,u.rate);
        u.fallTone.freq=dsp.noteToHz(m.lerp(fallNotes[0],fallNotes[1],fk*fk));
        const env=m.pow(f32,fk,1.5)*m.smooth(m.clamp01((1-fk)*20));
        y+=(u.fallBand.tick(u.air.next())*fallAir+u.fallTone.next()*fallTone)*env;
      }
      s.*+=y;
      u.clock+=1/u.rate;
    }
    // the sky shattering: glints raining as thick as the front sweeping down
    const k=(u.clock-ev.shiftFrom)/ev.shiftTime;
    if(k>0 and k<1){
      // how many samples this block holds
      const n:u32=@intCast(out.len);
      if(u.rainWait<=n){
        u.glints.addFree(.init(lydianNote(rainFrom,u.r.below(rainSteps)),u.r.range(rainRing[0],rainRing[1]),u.r.range(rainLevel[0],rainLevel[1]),0,u.rate));
        // the next one's wait, as thick as the shattering is now
        const per=rainMost*@sin(m.pi*k)+1;
        u.rainWait=m.floorTo(u32,-@log(@max(u.r.float(),1e-4))/per*u.rate);
      }else u.rainWait-=n;
    }
    // the seed lands: the bell and thump struck, the glass chord ringing up over them
    if(!u.landed and u.clock>=ev.landAt){
      u.landed=true;
      u.land=.init(u.rate);
      for(landChord,0..)|note,j|u.glints.cycle(.init(note,landChordRing,landChordLevel,m.f(j)*landStagger,u.rate));
    }
    if(u.land)|*l|{
      if(!l.render(out))u.land=null;
    }
    u.glints.render(out);
    u.cracks.render(out);
    // all of it rung away once the event has settled and nothing rings
    return u.clock<ev.settled or u.land!=null or u.ringing() or u.wither.value>silent;
  }
  /// whether any glint still rings
  fn ringing(u:*const Unformed)bool{
    for(u.glints.slots)|g|if(g!=null)return true;
    return false;
  }
  /// how much the music gives way to it (0 none .. 1 all): from its first
  /// moment until its drone fades
  pub fn hush(u:*const Unformed)f32{
    return m.smooth(m.clamp01(u.clock/droneRise))*(1-m.smooth(m.clamp01((u.clock-ev.landAt)/droneFade)));
  }
};
/// the sample rate the tests render at (samples a second)
const testRate:f32=48000;
test"the unforming sounds in every stretch, softly, swells to its landing and rings away"{
  // the test harness
  const testing=lib.std.testing;
  // the event heard from its first moment, told a frame at a time
  var u:Unformed=.init(0,7,testRate);
  // a frame's samples, and the loudness (rms) and peak of each second
  var buf:[800]f32=undefined;
  var rms:[64]f32=@splat(0);
  var peak:[64]f32=@splat(0);
  // the frame, and whether it still sounds
  var frame:u32=0;
  var alive=true;
  while(alive and frame<60*64):(frame+=1){
    // the moment, and what broke: a crack each second of the shattering,
    // the shards arriving a few at a time as they gather
    const t=m.f(frame)/60;
    const second:usize=@intCast(frame/60);
    const tick=frame%60==0;
    u.apply(.{.t=t,.wither=if(t>1 and t<14)0.8 else 0,.cracks=if(tick and t<10)1 else 0,.arrivals=if(tick and t>8 and t<ev.shatterEnd)3 else 0});
    @memset(&buf,0);
    alive=u.render(&buf);
    for(buf)|x|{
      rms[second]+=x*x;
      peak[second]=@max(peak[second],@abs(x));
    }
  }
  for(&rms)|*r|r.*=@sqrt(r.*/testRate);
  // it ends once settled and rung away
  try testing.expect(!alive);
  try testing.expect(m.f(frame)/60>ev.settled);
  // soft throughout, never near clipping
  for(peak)|p|try testing.expect(p<0.25);
  // it sounds in every stretch: the shattering, the sealing, the fall
  for([_]f32{1.5,5,9,ev.shatterEnd+1})|at|try testing.expect(rms[@intFromFloat(at)]>1e-3);
  // the landing is its loudest moment, the fall louder than just before it
  const land:usize=@intFromFloat(ev.landAt);
  for(peak,0..)|p,i|if(i!=land and i!=land+1)try testing.expect(p<=@max(peak[land],peak[land+1]));
  // the drone has faded long before the end
  try testing.expect(rms[@intFromFloat(ev.settled-1)]<rms[5]*0.2);
}
