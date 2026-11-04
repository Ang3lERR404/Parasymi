//! the unforming heard: its own theme playing under it all (unforming_theme.zig), glass raining as the sky shatters, a seam humming shut, ash crumbling, a crack as each radiant plant breaks, a rising ping as each shard reaches the star, a whistle as the seed falls and a deep bell blooming where it lands.
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
// decision: the event is all round the wolf, so its glass is heard from
// everywhere (each break, pane and glint a place of its own) while what
// is one thing (the drone, the seed's fall and landing) holds the middle
/// how far to either side a break is heard (pan), and its glints round it
const crackSide:f32=0.7;
/// (its glints, round it)
const crackAround:f32=0.15;
/// how far to either side the sky's panes rain (pan)
const rainSide:f32=0.85;
/// how wide the arrivals ring round the star (pan), each the golden share
/// of the way round from the last so none sits on another
const arriveSide:f32=0.6;
/// how wide the landing's glass chord opens (pan, lowest to highest)
const landSpread:f32=1;
/// how far apart the seam's tone and its twin sit (pan)
const sealApart:f32=0.3;
/// where the ash's two streams of grains crumble (pan)
const crumbleSide:f32=0.5;
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
  /// where it rings between the speakers
  place:dsp.Frame,
  /// a glint of note `note` (MIDI) ringing `ring` seconds (~63%) at
  /// `level`, `delay` seconds from now, at `pan`
  fn init(note:f32,ring:f32,level:f32,delay:f32,pan:f32,rate:f32)Glint{
    // its pitch, and its partials
    const hz=dsp.noteToHz(note);
    var osc:[glintPartials.len]dsp.Sine=undefined;
    var fall:[glintPartials.len]f32=undefined;
    for(glintPartials,0..)|p,k|{
      osc[k]=.init(hz*p,rate);
      fall[k]=dsp.fall(ring/(1+2*m.f(k)),rate);
    }
    return.{.osc=osc,.fall=fall,.wait=m.floorTo(u32,delay*rate),.rate=rate,.level=level,.place=dsp.spot(pan)};
  }
  /// mixes it into `out`; false once rung out
  pub fn render(g:*Glint,out:[]dsp.Frame)bool{
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
      s.*+=dsp.put(g.place,y*strike*g.level);
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
  /// where it breaks between the speakers
  place:dsp.Frame,
  /// mixes it into `out`; false once gone
  pub fn render(c:*Crack,out:[]dsp.Frame)bool{
    for(out)|*s|{
      s.*+=dsp.put(c.place,c.thin.high(c.noise.next())*c.amp*crackSnap);
      c.amp*=c.keep;
    }
    return c.amp>silent;
  }
};
/// the theme played under it all
const Theme=lib.sound.unformingTheme.Theme;
/// how far the event's clock may drift from the sounds' before it is mended (s)
const slip=lib.sound.unformingTheme.slip;
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
// ---- the landing: a great bell tolling, a boom under it, glass over it ----
// decision: the landing read as comical (the gardener's word) with a glass
// chord rung up note by note (a wand's sparkle) and a thump sinking fast (a
// cartoon's bwomp): the bell is now a great church bell's (its hum an
// octave under, its minor tierce), the boom holds its depth and rings long,
// and the glass sounds all at once, soft, a shimmer over the bell
/// its bell's partials (shares of D2: hum, prime, tierce, quint, nominal and
/// two over), levels and rings (s)
const landPartials=[_]f32{0.5,1,1.19,1.5,2,2.5,3};
/// (their levels)
const landPartialLevel=[landPartials.len]f32{0.7,1,0.5,0.35,0.55,0.22,0.12};
/// (their rings)
const landPartialRing=[landPartials.len]f32{7,5,3.4,2.8,2.4,1.5,1};
/// its bell's note (MIDI): D2
const landNote:f32=38;
/// its boom: a low sine hardly sinking (Hz) and ringing away (s)
const thumpSweep=m.Vice(f32,2){36,31};
/// (ringing away)
const thumpFall:f32=1.1;
/// the glass over it (MIDI): D5 F#5 A5 C#6 G#6, struck together
const landChord=[_]f32{74,78,81,85,92};
/// how far apart its notes are struck (s): together
const landStagger:f32=0;
/// how long the glass rings (s), and how loud
const landChordRing:f32=4;
/// (how loud)
const landChordLevel:f32=0.004;
/// how loud the bell and the boom
const landBell:f32=0.05;
/// (the boom)
const landThump:f32=0.16;
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
  /// mixes it into `out`, in the middle; false once rung out
  fn render(l:*Land,out:[]dsp.Frame)bool{
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
      s.*+=dsp.mid(y*swell*landBell+l.thump.next()*l.thumpAmp*landThump);
      l.thumpAmp*=l.thumpKeep;
      l.at+|=1;
    }
    // (its hum, the longest ringing, heard as loud as it is)
    return l.amp[0]*landBell>silent;
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
  /// its theme, played by the music's mixer in the hall (`theme.render`)
  theme:Theme,
  /// samples until the next glint of the rain
  rainWait:u32=0,
  /// the seam's tone and its twin, gliding down
  seal:dsp.Osc,
  /// (its twin)
  sealTwin:dsp.Osc,
  /// where the seam's tone and its twin sit, left and right of the middle
  sealSides:[2]dsp.Frame,
  /// the ash's grains in two streams, left and right, and the band they ring in
  crumble:[2]dsp.Crackle,
  /// (the band, each stream)
  crumbleBand:dsp.StereoBiquad,
  /// where the two streams crumble
  crumbleSides:[2]dsp.Frame,
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
    return.{
      .rate=rate,
      .r=.init(seed),
      .clock=t,
      .wither=.init(0,0.6,rate),
      .theme=.init(t,seed^0x7E3E,rate),
      .seal=.{.rate=rate,.freq=dsp.noteToHz(sealNotes[0])},
      .sealTwin=.{.rate=rate,.freq=dsp.noteToHz(sealNotes[0])+sealBeat},
      .sealSides=.{dsp.spot(-sealApart),dsp.spot(sealApart)},
      .crumble=.{.init(seed^0xA54,crumbleGrain,rate),.init(seed^0xA55,crumbleGrain,rate)},
      .crumbleBand=.init(.band,crumbleHz,crumbleQ,rate),
      .crumbleSides=.{dsp.spot(-crumbleSide),dsp.spot(crumbleSide)},
      .air=.init(seed^0xF411),
      .fallBand=.init(.band,fallSweep[0],fallQ,rate),
      .fallTone=.{.rate=rate,.freq=dsp.noteToHz(fallNotes[0])},
    };
  }
  /// what the event sent this frame: its clock kept to it (only a slip is
  /// mended, so it runs on smoothly between frames), each crack and arrival
  /// struck, the withering followed
  pub fn apply(u:*Unformed,h:Heard)void{
    if(@abs(h.t-u.clock)>slip)u.clock=h.t;
    u.theme.keep(h.t);
    u.wither.target=h.wither;
    for(0..h.cracks)|_|u.crack();
    for(0..h.arrivals)|_|{
      // where round the star it rings
      const round=m.f(u.arrived)*m.goldenShare;
      u.glints.cycle(.init(lydianNote(arriveFrom,u.arrived%arriveSteps),arriveRing,arriveLevel,0,((round-@floor(round))*2-1)*arriveSide,u.rate));
      u.arrived+=1;
    }
  }
  /// glass breaking somewhere round the wolf: a snap and a scatter of
  /// glints round it, high in D Lydian
  fn crack(u:*Unformed)void{
    // where it breaks
    const at=u.r.range(-crackSide,crackSide);
    u.cracks.cycle(.{.noise=.init(u.r.next()),.thin=.init(crackHz,u.rate),.keep=dsp.fall(crackFall,u.rate),.place=dsp.spot(at)});
    // how many glints it scatters
    const n=crackGlints[0]+u.r.below(crackGlints[1]-crackGlints[0]+1);
    for(0..n)|_|u.glints.cycle(.init(lydianNote(crackFrom,u.r.below(crackSteps)),u.r.range(0.15,0.5),crackGlint*u.r.range(0.5,1),u.r.range(0,crackSpread),at+u.r.range(-crackAround,crackAround),u.rate));
  }
  /// mixes the next `out.len` samples into `out`, its clock running on;
  /// false once all of it has rung away
  pub fn render(u:*Unformed,out:[]dsp.Frame)bool{
    for(out,0..)|*s,i|{
      // the clock
      const t=u.clock;
      var y:dsp.Frame=@splat(0);
      // the seam humming shut as the ley lines seal, sinking
      const sk=(t-ev.sealStart)/(ev.sealEnd-ev.sealStart);
      if(sk>0 and sk<1){
        const note=m.lerp(sealNotes[0],sealNotes[1],sk);
        u.seal.freq=dsp.noteToHz(note);
        u.sealTwin.freq=u.seal.freq+sealBeat;
        y+=(dsp.put(u.sealSides[0],u.seal.next())+dsp.put(u.sealSides[1],u.sealTwin.next()))*dsp.mid(0.5*m.pow(f32,@sin(m.pi*sk),0.7)*sealLoud);
      }
      // ash crumbling, as much as is withering
      // (half of it each stream)
      const wd=u.wither.next()*crumbleMost*0.5;
      u.crumble[0].density=wd;
      u.crumble[1].density=wd;
      const ash=u.crumbleBand.tick(.{u.crumble[0].next(),u.crumble[1].next()});
      y+=(dsp.put(u.crumbleSides[0],ash[0])+dsp.put(u.crumbleSides[1],ash[1]))*dsp.mid(crumble);
      // the seed whistling down, louder as it nears
      const fk=(t-ev.shatterEnd)/ev.fallTime;
      if(fk>0 and fk<1){
        if(i%retune==0)u.fallBand.tune(.band,fallSweep[0]*m.pow(f32,fallSweep[1]/fallSweep[0],fk),fallQ,u.rate);
        u.fallTone.freq=dsp.noteToHz(m.lerp(fallNotes[0],fallNotes[1],fk*fk));
        const env=m.pow(f32,fk,1.5)*m.smooth(m.clamp01((1-fk)*20));
        y+=dsp.mid((u.fallBand.tick(u.air.next())*fallAir+u.fallTone.next()*fallTone)*env);
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
        u.glints.addFree(.init(lydianNote(rainFrom,u.r.below(rainSteps)),u.r.range(rainRing[0],rainRing[1]),u.r.range(rainLevel[0],rainLevel[1]),0,u.r.range(-rainSide,rainSide),u.rate));
        // the next one's wait, as thick as the shattering is now
        const per=rainMost*@sin(m.pi*k)+1;
        u.rainWait=m.floorTo(u32,-@log(@max(u.r.float(),1e-4))/per*u.rate);
      }else u.rainWait-=n;
    }
    // the seed lands: the bell and thump struck, the glass chord ringing up over them
    if(!u.landed and u.clock>=ev.landAt){
      u.landed=true;
      u.land=.init(u.rate);
      for(landChord,0..)|note,j|u.glints.cycle(.init(note,landChordRing,landChordLevel,m.f(j)*landStagger,(m.f(j)/m.f(landChord.len-1)-0.5)*landSpread,u.rate));
    }
    if(u.land)|*l|{
      if(!l.render(out))u.land=null;
    }
    u.glints.render(out);
    u.cracks.render(out);
    // all of it rung away once the event has settled, nothing rings and the
    // theme has given the garden's music back
    return u.clock<ev.settled or u.land!=null or u.ringing() or u.wither.value>silent or !u.theme.done();
  }
  /// whether any glint still rings
  fn ringing(u:*const Unformed)bool{
    for(u.glints.slots)|g|if(g!=null)return true;
    return false;
  }
  /// how much the garden's music gives way to it (0 none .. 1 all): cut as
  /// it begins, given back after the landing (its theme's)
  pub fn hush(u:*const Unformed)f32{return u.theme.hush();}
};
/// the sample rate the tests render at (samples a second)
const testRate:f32=48000;
test"the unforming sounds in every stretch, swells to its landing and rings away"{
  // the test harness
  const testing=lib.std.testing;
  // the event heard from its first moment, told a frame at a time
  var u:Unformed=.init(0,7,testRate);
  // a frame's samples, and the loudness (rms) and peak of each second
  var buf:[800]dsp.Frame=undefined;
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
    @memset(&buf,@splat(0));
    alive=u.render(&buf);
    for(buf)|x|{
      rms[second]+=m.sumOf(f32,2,x*x)*0.5;
      peak[second]=@max(peak[second],@abs(x[0]),@abs(x[1]));
    }
  }
  for(&rms)|*r|r.*=@sqrt(r.*/testRate);
  // it ends once settled and rung away
  try testing.expect(!alive);
  try testing.expect(m.f(frame)/60>ev.settled);
  // it never clips
  for(peak)|p|try testing.expect(p<1);
  // it sounds in every stretch: the shattering, the sealing, the fall
  for([_]f32{1.5,5,9,ev.shatterEnd+1})|at|try testing.expect(rms[@intFromFloat(at)]>1e-3);
  // the landing is its loudest moment, the fall louder than just before it
  const land:usize=@intFromFloat(ev.landAt);
  for(peak,0..)|p,i|if(i!=land and i!=land+1)try testing.expect(p<=@max(peak[land],peak[land+1]));
  // it has quieted long before the end
  try testing.expect(rms[@intFromFloat(ev.settled-1)]<rms[5]*0.2);
}
