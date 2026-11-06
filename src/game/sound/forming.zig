//! a radiant plant gathering, heard: each fragment a glass tink swelling up reversed before it lands, climbing a D Lydian chord with a far echo of the unforming's rising bell; a bowed-glass hum phasing like light through a prism as its threads join; and once whole a soap-bubble shimmer, one breath of far choir and a fizz of crystal grains.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, clamps, easing, conversions
const m=engine.core.math;
/// the engine's sound pieces: sines, noise, filters, smoothing, hearing
const dsp=engine.core.dsp;
/// the seeded random numbers each forming draws from
const rng=engine.core.rng;
/// a tiny glass bell, the grain the unforming's glass is made of
const Glint=lib.sound.unforming.Glint;
/// the note (MIDI) a step of D Lydian up from a note is
const lydianNote=lib.sound.unforming.lydianNote;
/// a value nudged a little either way, so no two formings are alike
const vary=lib.sound.footstep.vary;
/// quieter than this, a sound has ended
const silent=lib.sound.silent;
// decision: kept apart from the arsthraxia (its glass whorls on A4 and E5,
// its bell bloom): here the glass is struck, not rubbed, the hum sits on D
// and A an octave up, and the whole thing is light and brief
// ---- when each fragment lands: plant.vert's gathering, mirrored ----
/// how much of its growth each later fragment lands after the first:
/// plant.vert ARRIVE_PACE
const landPace:f32=0.7;
/// how much growth a fragment takes to come in, so the first lands at it:
/// plant.vert ARRIVE_SPAN
const landFirst:f32=0.3;
/// the chord the fragments climb as they land (MIDI): D5 F#5 A5 C#6 E6
/// G#6 A6, D Lydian stacked in thirds, one note a fragment
// decision: a few fragments heard, spread evenly through the gathering, not
// every mesh fragment (the mesh has dozens; a tink each would be a rattle)
const chord=[_]f32{74,78,81,85,88,92,93};
/// how many fragments are heard landing
pub const fragments=chord.len;
/// the growth at which fragment `i` of `fragments` lands
pub fn landAt(i:usize)f32{return landFirst+landPace*m.f(i)/m.f(fragments-1);}
// ---- the tink: a glass struck, its ring heard first, reversed ----
/// a tink's partials (shares of its pitch, stretched as glass rings)
const tinkPartials=[_]f32{1,2.76,5.4};
/// (their levels)
const tinkPartialLevel=[tinkPartials.len]f32{1,0.35,0.12};
/// (how long each rings once struck, s, ~63%)
const tinkPartialRing=[tinkPartials.len]f32{1.4,0.5,0.2};
/// how long the reversed ring swells before it lands (s): light arriving
/// ahead of the thing
pub const swellS:f32=0.9;
/// how long the reversed ring takes to rise (s, ~63%): slow, then sudden
const swellRise:f32=0.28;
/// how loud the reversed swell is against the strike
const swellLevel:f32=0.55;
/// how gently the swell fades in from nothing at its very start (s)
const swellIn:f32=0.04;
/// a strike's soft attack (s)
const tinkAttack:f32=0.003;
/// how loud a tink is
const tinkLevel:f32=0.022;
/// how far either side of its plant each tink rings (pan), the golden share
/// of the way round from the last so none sits on another
const tinkSide:f32=0.35;
// ---- the echo: the unforming's climbing bell, far and quiet ----
/// the unforming's arrivals climb D Lydian from here (MIDI): D5
/// (unforming.zig arriveFrom)
const echoFrom:f32=74;
/// how long after the strike the echo answers (s)
const echoAfter:f32=0.16;
/// how long it rings (s), and how loud
const echoRing:f32=1.1;
/// (how loud)
const echoLevel:f32=0.005;
// ---- the hum: threads of light, a finger round a wine glass ----
/// the hum's two notes (MIDI): D5 and A5, the key and its fifth
const humNote=m.Vice(f32,2){74,81};
/// how fast each note's two tones beat against each other (Hz)
const humBeat=m.Vice(f32,2){0.23,0.37};
/// its partials, as shares of its pitch
const humPartials=[_]f32{1,2,3};
/// (their levels, before the prism turns them)
const humPartialLevel=[humPartials.len]f32{1,0.3,0.14};
/// how fast the prism turns, the partials swelling one after another (Hz)
const prismHz:f32=0.11;
/// how deep the prism turns them (a share)
const prism:f32=0.7;
/// the finger's friction: noise rung at each note (q), and how much of it
const rubQ:f32=60;
/// (how much of it)
const rub:f32=0.35;
/// the low-pass over the hum, at the first thread and with all joined (Hz)
const humSoftHz=m.Vice(f32,2){1400,3600};
/// how fast the hum follows the threads joining or fading (s, ~63%)
const humGlide:f32=1.2;
/// how loud the hum is with every thread joined
const humLevel:f32=0.012;
/// samples between retunings of the hum's brightness
const humRetune=64;
// ---- the whole: a soap bubble, a breath of far choir, crystal grains ----
/// the bubble's band, swept to and fro round this (Hz), how wide, how fast
const bubbleHz:f32=6200;
/// (how wide either way, a share)
const bubbleSweep:f32=0.45;
/// (how fast, Hz)
const bubbleRate:f32=5.5;
/// (the band's q)
const bubbleQ:f32=9;
/// its swell in and fade (s)
const bubbleIn:f32=0.06;
/// (its fade, s, ~63%)
const bubbleFall:f32=0.55;
/// how loud the bubble is
const bubbleLevel:f32=0.05;
/// the choir's notes (MIDI): D4 F#4 A4 D5, an "ooh" chord
const choirNotes=[_]f32{62,66,69,74};
/// each note sung by two voices this far apart (cents either way)
const choirSpread:f32=7;
/// the vowel "oo": its three formants (Hz), widths (q) and levels
const ooHz=[_]f32{330,800,2400};
/// (their q)
const ooQ=[ooHz.len]f32{5,6,10};
/// (their levels)
const ooLevel=[ooHz.len]f32{1,0.35,0.06};
/// the breath's swell in and its fade (s): one breath, in and out
const choirIn:f32=0.7;
/// (its fade, s, ~63%)
const choirFall:f32=1.3;
/// how far off it sounds: its highs darkened above this (Hz)
const choirFar:f32=1800;
/// how loud the breath is
const choirLevel:f32=0.05;
/// how long after the whole the grains begin to fizz, and stop (s)
const grainSpan=m.Vice(f32,2){0.25,2.4};
/// seconds between grains at first; they thin out as they fade
const grainGap:f32=0.035;
/// the grains' notes: D Lydian steps up from D7 (MIDI), this many steps
const grainFrom:f32=98;
/// (how many steps)
const grainSteps:u32=10;
/// how long a grain rings (s), how loud at first, how far either side (pan)
const grainRing:f32=0.12;
/// (how loud at first)
const grainLevel:f32=0.006;
/// (how far either side, pan)
const grainSide:f32=0.6;
/// grains that may ring at once
const grainCount=24;
/// how long after the whole it has surely rung away (s)
const wholeLen:f32=6;
// ---- the forming as a whole ----
/// how fast the growth's pace is learned from what it is told (a share
/// toward each new reading)
const paceLearn:f32=0.3;
/// frames worked through at a time
const block=256;
/// told this much less gathered than before, it has begun afresh
const restartDrop:f32=0.2;
/// one tink: its ring swelling up reversed for `lead` samples, then struck
/// and ringing out
const Tink=struct{
  /// its partials' sines
  osc:[tinkPartials.len]dsp.Sine,
  /// each partial's level once struck, 1 falling away
  amp:[tinkPartials.len]f32=@splat(1),
  /// how much of its level each partial keeps a sample once struck
  fall:[tinkPartials.len]f32,
  /// samples its swell takes before the strike
  lead:u32,
  /// samples since it began
  at:u32=0,
  /// samples a second
  rate:f32,
  /// where it rings between the speakers
  place:dsp.Frame,
  /// a tink of note `note` (MIDI) at `pan`, struck `lead` seconds from now
  /// (its swell heard until then), its rings nudged by `r`
  fn init(note:f32,lead:f32,pan:f32,r:*rng.Rng,rate:f32)Tink{
    // its pitch, and its partials
    const hz=dsp.noteToHz(note);
    var osc:[tinkPartials.len]dsp.Sine=undefined;
    var fall:[tinkPartials.len]f32=undefined;
    for(tinkPartials,tinkPartialRing,0..)|p,ring,k|{
      osc[k]=.init(hz*p,rate);
      fall[k]=dsp.fall(vary(r,ring),rate);
    }
    return.{.osc=osc,.fall=fall,.lead=m.floorTo(u32,m.clamp(lead,0,swellS)*rate),.rate=rate,.place=dsp.spot(pan)};
  }
  /// mixes it into `out`; false once rung out
  pub fn render(t:*Tink,out:[]dsp.Frame)bool{
    for(out)|*s|{
      // the partials summed, swelling or ringing
      var y:f32=0;
      if(t.at<t.lead){
        // how long until the strike, and how gently it fades in at its start
        const left=m.f(t.lead-t.at)/t.rate;
        const in=m.smooth(m.clamp01(m.f(t.at)/(swellIn*t.rate)));
        for(&t.osc,0..)|*o,k|y+=o.next()*tinkPartialLevel[k]*@exp(-left/(swellRise*(1+m.f(k))));
        y*=swellLevel*in;
      }else{
        // how far into its strike
        const strike=m.clamp01(m.f(t.at-t.lead)/(tinkAttack*t.rate));
        for(&t.osc,&t.amp,t.fall,tinkPartialLevel)|*o,*a,f,l|{
          y+=o.next()*l*a.*;
          a.*=f*a.*;
        }
        y*=strike;
      }
      s.*+=dsp.put(t.place,y*tinkLevel);
      t.at+|=1;
    }
    return t.at<t.lead or t.amp[0]*tinkLevel>silent;
  }
};
/// the threads of light: two glasses rubbed, each two tones beating, their
/// partials swelling in turn as a prism turns, louder and brighter as
/// threads join
const Hum=struct{
  /// each note's two tones, each with its partials: [note][twin][partial]
  osc:[2][2][humPartials.len]dsp.Osc,
  /// the prism turning
  turn:dsp.Osc,
  /// the finger's friction
  noise:dsp.Noise,
  /// the friction rung at each note
  rubs:[2]dsp.Biquad,
  /// the low-pass over it all
  soft:dsp.OnePole,
  /// how many threads are joined (0..1), gliding
  joined:dsp.Smooth,
  /// samples a second
  rate:f32,
  /// samples hummed (wraps), for when to retune its brightness
  at:u32=0,
  /// a silent hum, its tones' phases drawn from `r`
  fn init(r:*rng.Rng,rate:f32)Hum{
    // the hum, its tones filled in below
    var h:Hum=.{
      .osc=undefined,
      .turn=.{.rate=rate,.freq=vary(r,prismHz),.phase=r.float()},
      .noise=.init(r.next()),
      .rubs=undefined,
      .soft=.init(humSoftHz[0],rate),
      .joined=.init(0,humGlide,rate),
      .rate=rate,
    };
    for(0..2)|n|{
      // the note's pitch
      const hz=dsp.noteToHz(humNote[n]);
      for(0..2)|w|{
        // this twin's pitch, a hair apart from the other
        const at=hz+humBeat[n]*(m.f(w)-0.5);
        for(humPartials,0..)|p,k|h.osc[n][w][k]=.{.rate=rate,.freq=at*p,.phase=r.float()};
      }
      h.rubs[n]=.init(.band,hz,rubQ,rate);
    }
    return h;
  }
  /// its next sample (mono)
  fn tick(h:*Hum)f32{
    // how many threads are joined now
    const j=h.joined.next();
    if(j<silent and h.joined.target==0)return 0;
    // where the prism has turned to (0..1), then turned on a sample
    const turn=h.turn.phase;
    _=h.turn.next();
    // the glasses summed, each partial's level turned by the prism
    var y:f32=0;
    for(0..humPartials.len)|k|{
      // this partial's share, a third of a turn after the last
      const lit=1-prism*(0.5+0.5*@sin(m.tau*(turn+m.f(k)/3)));
      for(0..2)|n|{
        for(0..2)|w|y+=h.osc[n][w][k].next()*humPartialLevel[k]*lit;
      }
    }
    // the friction under it
    const fr=h.noise.next();
    for(&h.rubs)|*b|y+=b.tick(fr)*rub;
    // brighter as more threads join (retuned now and then: it glides slowly)
    h.at+%=1;
    if(h.at%humRetune==0)h.soft.a=dsp.OnePole.coeff(m.lerp(humSoftHz[0],humSoftHz[1],j),h.rate);
    return h.soft.low(y)*j*humLevel;
  }
};
/// the gathering whole: a soap-bubble shimmer, one breath of far choir
/// ("ooh"), and crystal grains fizzing and fading
const Whole=struct{
  /// the bubble's noise
  noise:dsp.Noise,
  /// its band, swept
  band:dsp.Biquad,
  /// the sweep's wave
  sweep:dsp.Osc,
  /// the choir's voices: two to a note
  voices:[choirNotes.len*2]dsp.Osc,
  /// the vowel's formants
  oo:[ooHz.len]dsp.Biquad,
  /// how far off it sounds
  far:dsp.OnePole,
  /// the grains ringing
  grains:dsp.Pool(Glint,grainCount)=.{},
  /// samples until the next grain
  wait:u32,
  /// how many grains have rung
  rung:u32=0,
  /// samples since it was whole
  at:u32=0,
  /// samples a second
  rate:f32,
  /// the random numbers its grains draw from
  r:rng.Rng,
  /// the whole begun now, its voices drawn from `r`
  fn init(r:*rng.Rng,rate:f32)Whole{
    // the whole, its voices and formants filled in below
    var w:Whole=.{
      .noise=.init(r.next()),
      .band=.init(.band,bubbleHz,bubbleQ,rate),
      .sweep=.{.rate=rate,.freq=vary(r,bubbleRate),.phase=r.float()},
      .voices=undefined,
      .oo=undefined,
      .far=.init(choirFar,rate),
      .wait=m.floorTo(u32,grainSpan[0]*rate),
      .rate=rate,
      .r=.init(r.next()),
    };
    for(choirNotes,0..)|n,i|{
      for(0..2)|k|w.voices[i*2+k]=.{.rate=rate,.shape=.saw,.freq=dsp.noteToHz(n+choirSpread/100*(m.f(k)*2-1)),.phase=r.float()};
    }
    for(&w.oo,ooHz,ooQ)|*f,hz,q|f.*=.init(.band,hz,q,rate);
    return w;
  }
  /// mixes it into `out`; false once rung away
  fn render(w:*Whole,out:[]dsp.Frame)bool{
    for(out)|*s|{
      // seconds since it was whole
      const t=m.f(w.at)/w.rate;
      // the bubble: noise in a band swept to and fro, swelling in and fading
      const sw=w.sweep.next();
      if(w.at%32==0)w.band.tune(.band,bubbleHz*(1+bubbleSweep*@sin(m.tau*sw)),bubbleQ,w.rate);
      const bubbleEnv=m.smooth(m.clamp01(t/bubbleIn))*@exp(-t/bubbleFall);
      var y=w.band.tick(w.noise.next())*bubbleEnv*bubbleLevel;
      // the breath: the voices shaped into "oo", far off, in and out once
      var v:f32=0;
      for(&w.voices)|*o|v+=o.next();
      var oo:f32=0;
      for(&w.oo,ooLevel)|*f,l|oo+=f.tick(v)*l;
      const breathEnv=m.smooth(m.clamp01(t/choirIn))*@exp(-@max(0,t-choirIn)/choirFall);
      y+=w.far.low(oo)*breathEnv*choirLevel/m.f(w.voices.len);
      s.*+=dsp.mid(y);
      w.at+|=1;
    }
    // the grains: begun after a breath, coming quick then thinning out
    var left:u32=@intCast(out.len);
    while(true){
      // how far into the span they have come (0..1)
      const t=m.f(w.at)/w.rate;
      if(t>grainSpan[1] or w.wait>=left)break;
      left-=w.wait;
      const k=m.unlerp(grainSpan[0],grainSpan[1],t);
      const round=m.f(w.rung)*m.goldenShare;
      w.grains.add(.init(lydianNote(grainFrom,w.r.below(grainSteps)),vary(&w.r,grainRing),grainLevel*(1-k),m.f(out.len-left)/w.rate,((round-@floor(round))*2-1)*grainSide,w.rate));
      w.rung+=1;
      w.wait=m.floorTo(u32,grainGap*(1+4*k)*w.rate*vary(&w.r,1));
    }
    w.wait-|=left;
    w.grains.render(out);
    return m.f(w.at)/w.rate<wholeLen;
  }
};
/// what the game tells of the nearest radiant plant gathering: which it is,
/// how far grown (0..1), where it is heard from and how much of the way to
/// it is hidden
pub const Gathering=struct{
  /// the plant (its index, to tell one plant from the next)
  id:u32,
  /// how far gathered it is, 0 nothing .. 1 whole
  growth:f32,
  /// where it is heard from
  at:m.V3=@splat(0),
  /// how much of the way to it is hidden (0..1)
  muffle:f32=0,
};
/// one radiant plant gathering, heard from where it hangs
pub const Forming=struct{
  /// the plant it is
  id:u32,
  /// how far gathered it was last told
  growth:f32,
  /// how fast it gathers (growth a second), learned as it is told
  pace:f32=0,
  /// samples since it was last told
  since:u32=0,
  /// which fragments have begun (a bit each)
  begun:u32=0,
  /// whether it has been heard whole
  wasWhole:bool=false,
  /// whether the game still tells of it
  told:bool=true,
  /// the tinks: one a fragment, a few still ringing as the next swell
  tinks:dsp.Pool(Tink,fragments)=.{},
  /// the unforming's bell answering each, far and quiet
  echoes:dsp.Pool(Glint,fragments)=.{},
  /// the threads of light humming
  hum:Hum,
  /// the whole ringing away, once it is whole
  whole:?Whole=null,
  /// how it is heard from where it hangs
  sp:dsp.Spatial,
  /// the random numbers its voices draw from
  r:rng.Rng,
  /// samples a second
  rate:f32,
  /// a plant `g` begun gathering, heard as `h`, its voices drawn from `seed`:
  /// the fragments already landed are taken as heard
  pub fn init(g:Gathering,h:dsp.Heard,seed:u64,rate:f32)Forming{
    // its random numbers
    var r:rng.Rng=.init(seed);
    // the forming, its fragments already in place marked below
    var f:Forming=.{.id=g.id,.growth=g.growth,.hum=.init(&r,rate),.sp=.init(h,rate),.r=r,.rate=rate,.wasWhole=g.growth>=1};
    for(0..fragments)|i|{
      if(g.growth>=landAt(i))f.begun|=@as(u32,1)<<@intCast(i);
    }
    return f;
  }
  /// told how far it has gathered now and how it is heard: learns its pace,
  /// begins each fragment's swell as its landing nears, hums as its threads
  /// join, and rings whole once whole
  pub fn tell(f:*Forming,g:Gathering,h:dsp.Heard)void{
    f.sp.follow(h);
    f.told=true;
    // gathered afresh (a plant shown alone, looping its gathering): heard anew
    if(g.growth+restartDrop<f.growth){
      f.begun=0;
      f.wasWhole=false;
      f.pace=0;
      f.since=0;
    }
    // its pace, learned from how far it came since last told
    if(f.since>0 and g.growth>f.growth){
      const now=(g.growth-f.growth)/(m.f(f.since)/f.rate);
      f.pace=if(f.pace==0)now else m.lerp(f.pace,now,paceLearn);
    }
    f.since=0;
    f.growth=g.growth;
    for(0..fragments)|i|{
      // this fragment's bit, and when it lands
      const bit=@as(u32,1)<<@intCast(i);
      const land=landAt(i);
      if(f.begun&bit!=0)continue;
      if(g.growth+f.pace*swellS<land and g.growth<land)continue;
      // how long until it lands (s): its swell heard until then
      const lead=if(f.pace>0)(land-g.growth)/f.pace else 0;
      const round=m.f(i)*m.goldenShare;
      const pan=((round-@floor(round))*2-1)*tinkSide;
      f.tinks.add(.init(chord[i],lead,pan,&f.r,f.rate));
      f.echoes.add(.init(lydianNote(echoFrom,@intCast(i)),echoRing,echoLevel,m.clamp(lead,0,swellS)+echoAfter,-pan,f.rate));
      f.begun|=bit;
    }
    if(g.growth>=1 and !f.wasWhole){
      f.whole=.init(&f.r,f.rate);
      f.wasWhole=true;
    }
    // the threads joined: from the first fragment landing to the last, then
    // fading as it hangs whole
    f.hum.joined.target=if(g.growth>=1)0 else m.clamp01((g.growth-landFirst)/landPace);
  }
  /// the game no longer tells of it (gone, out of hearing, or whole): its
  /// hum fades and what rings rings out
  pub fn leave(f:*Forming)void{
    f.told=false;
    f.hum.joined.target=0;
  }
  /// mixes it into `out`, what reaches the place's echo into `send`; false
  /// once it has left and rung away
  pub fn render(f:*Forming,out:[]dsp.Frame,send:[]f32)bool{
    f.since+|=@intCast(out.len);
    // how far into `out` the blocks have reached
    var off:usize=0;
    while(off<out.len){
      // this block's length, and what sounds in it before it is heard
      const k=@min(block,out.len-off);
      var buf:[block]dsp.Frame=@splat(@splat(0));
      f.tinks.render(buf[0..k]);
      f.echoes.render(buf[0..k]);
      if(f.whole)|*w|{
        if(!w.render(buf[0..k]))f.whole=null;
      }
      for(buf[0..k],out[off..][0..k],send[off..][0..k])|x,*o,*e|{
        // the hum under it, in the middle of the plant
        const h=f.sp.tick(x+dsp.mid(f.hum.tick()));
        o.*+=h.dry;
        e.*+=h.send;
      }
      off+=k;
    }
    return f.told or f.ringing();
  }
  /// whether anything of it still sounds
  fn ringing(f:*const Forming)bool{
    if(f.whole!=null)return true;
    if(f.hum.joined.value*humLevel>silent)return true;
    for(f.tinks.slots)|t|if(t!=null)return true;
    for(f.echoes.slots)|e|if(e!=null)return true;
    return false;
  }
};
/// the test expectations
const testing=lib.std.testing;
/// the sample rate the tests render at (samples a second)
const testRate:f32=48000;
/// frames told between, as a frame of play is (s)
const testTell=480;
test"each fragment swells before it lands, the gathering is heard softly, rings whole and rings away"{
  // a plant gathering over twenty seconds, heard close in front
  const span:f32=20;
  var f:Forming=.init(.{.id=3,.growth=0},.{},7,testRate);
  var buf:[testTell]dsp.Frame=undefined;
  var send:[testTell]f32=undefined;
  // the loudest sample heard, and whether each fragment began before it landed
  var peak:f32=0;
  var early=true;
  var growth:f32=0;
  var wholeHeard=false;
  while(growth<1){
    growth=@min(1,growth+m.f(testTell)/testRate/span);
    f.tell(.{.id=3,.growth=growth},.{});
    for(0..fragments)|i|{
      // once the pace is learned, a fragment begins a swell ahead of landing
      if(growth>=landAt(i) and growth>0.1 and f.begun&(@as(u32,1)<<@intCast(i))==0)early=false;
    }
    if(f.whole!=null)wholeHeard=true;
    @memset(&buf,@splat(0));
    @memset(&send,0);
    _=f.render(&buf,&send);
    for(buf)|x|peak=@max(peak,@max(@abs(x[0]),@abs(x[1])));
  }
  try testing.expect(early);
  try testing.expect(wholeHeard);
  try testing.expectEqual(@as(u32,(1<<fragments)-1),f.begun);
  try testing.expect(peak>0.003 and peak<0.3);
  // told no more: within ten seconds it has rung away
  f.leave();
  var blocks:u32=0;
  while(blocks<1000){
    @memset(&buf,@splat(0));
    @memset(&send,0);
    if(!f.render(&buf,&send))break;
    blocks+=1;
  }
  try testing.expect(blocks<1000);
}
test"a plant heard first half gathered takes its landed fragments as heard, and a fresh gathering is heard anew"{
  // half gathered: only the fragments still to land wait
  var f:Forming=.init(.{.id=1,.growth=0.6},.{},2,testRate);
  for(0..fragments)|i|try testing.expectEqual(landAt(i)<=0.6,f.begun&(@as(u32,1)<<@intCast(i))!=0);
  // gathered afresh: nothing begun, not yet whole
  f.tell(.{.id=1,.growth=1},.{});
  try testing.expect(f.wasWhole);
  f.tell(.{.id=1,.growth=0},.{});
  try testing.expect(!f.wasWhole);
  try testing.expectEqual(@as(u32,0),f.begun);
}
