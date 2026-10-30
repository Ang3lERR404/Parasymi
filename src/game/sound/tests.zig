//! the garden's sounds rendered offline and measured.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the test expectations
const testing=std.testing;
/// the generic engine package
const engine=lib.engine;
/// all the maths: conversions, the largest counts
const m=engine.core.math;
/// the seeded random numbers the tests draw from
const rng=engine.core.rng;
/// a paw coming down: how heavy, how fast
const Footfall=lib.player.Footfall;
/// how many footsteps may sound at once
const voiceCount=lib.sound.voiceCount;
/// steps to a bar
const barSlots=lib.sound.score.barSlots;
/// the deep gloops every settling has
const deep=lib.sound.sap.deep;
/// the melody's highest scale step
const melHi=lib.sound.score.melHi;
/// the melody's lowest scale step
const melLo=lib.sound.score.melLo;
/// steps in a motif
const motif=lib.sound.score.motif;
/// the daytime piano
const Music=lib.sound.music.Music;
/// how many pings a twinkle has (fewest, most)
const pingRange=lib.sound.twinkle.pingRange;
/// how long one step of the music lasts (s)
const stepS=lib.sound.score.stepS;
/// one settling of the sap
const Settle=lib.sound.sap.Settle;
/// the source the device pulls from, under test
const Sounds=lib.sound.mixer.Sounds;
/// the gust strength past which the wind whistles
const whistleFrom=lib.sound.wind.whistleFrom;
/// the note nearest a given one that is in a chord
const chordTone=lib.sound.score.chordTone;
/// the sample rate the tests render at (samples a second)
const testRate:f32=48000;
/// one step rendered alone: its peak, its loudness (rms) and how long it
/// sounds (s)
fn hear(f:Footfall,seed:u64)struct{peak:f32,rms:f32,len:f32}{
  // the sounds, with the wind hushed so the step is heard alone
  var s:Sounds=.init(seed,testRate);
  s.wind.level=0;
  s.apply(.{.step=f});
  // a block of samples, the step's peak, its sum of squares, and samples heard
  var buf:[480]f32=undefined;
  var peak:f32=0;
  var sum:f32=0;
  var n:u32=0;
  while(s.steps[0]!=null and n<48000){
    @memset(&buf,0);
    s.render(&buf);
    for(buf)|x|{
      peak=@max(peak,@abs(x));
      sum+=x*x;
    }
    n+=buf.len;
  }
  return.{.peak=peak,.rms=@sqrt(sum/m.f(n)),.len=m.f(n)/testRate};
}
test"a footstep is short, soft and never clips; a sprint is louder"{
  // a soft walk, a sprint, and a full belly walking
  const soft=hear(.{.weight=0,.pace=0.3},1);
  const fast=hear(.{.weight=0,.pace=1},1);
  const full=hear(.{.weight=1,.pace=0.3},1);
  for([_]@TypeOf(soft){soft,fast,full})|h|{
    try testing.expect(h.peak>0.02 and h.peak<0.8);
    try testing.expect(h.len>0.1 and h.len<0.8);
  }
  try testing.expect(fast.rms>soft.rms);
  try testing.expect(fast.len<soft.len);
}
test"steps vary, a busy pool steals the oldest, and it ends silent"{
  // the sounds, with the wind hushed
  var s:Sounds=.init(9,testRate);
  s.wind.level=0;
  for(0..voiceCount+2)|_|s.apply(.{.step=.{.weight=0.5,.pace=0.5}});
  for(s.steps)|v|try testing.expect(v!=null);
  try testing.expect(s.steps[0].?.gain!=s.steps[1].?.gain);
  // a block of samples
  var buf:[480]f32=undefined;
  for(0..200)|_|{
    @memset(&buf,0);
    s.render(&buf);
  }
  for(s.steps)|v|try testing.expect(v==null);
  for(buf)|x|try testing.expectEqual(@as(f32,0),x);
}
test"the sap settles only in the eyes, softly, and fades out with the view"{
  // the sounds, with the wind hushed
  var s:Sounds=.init(3,testRate);
  s.wind.level=0;
  // a block of samples
  var buf:[480]f32=undefined;
  // a minute out of the eyes: nothing
  for(0..6000)|_|{
    @memset(&buf,0);
    s.render(&buf);
    for(buf)|x|try testing.expectEqual(@as(f32,0),x);
  }
  s.apply(.{.eyes=true});
  // the loudest sample heard, settlings started, and whether one was sounding
  var peak:f32=0;
  var settles:u32=0;
  var was=false;
  for(0..3000)|_|{
    @memset(&buf,0);
    s.render(&buf);
    for(buf)|x|peak=@max(peak,@abs(x));
    if(s.settle!=null and !was)settles+=1;
    was=s.settle!=null;
  }
  // half a minute standing in the eyes settles a few times, softly
  try testing.expect(settles>=2 and settles<=6);
  try testing.expect(peak>0.01 and peak<0.3);
  s.apply(.{.eyes=false});
  for(0..400)|_|{
    @memset(&buf,0);
    s.render(&buf);
  }
  try testing.expect(s.settle==null);
  for(buf)|x|try testing.expectEqual(@as(f32,0),x);
}
test"now and then a settling has lighter gloops"{
  // the random numbers, and how many settlings brought light gloops
  var r:rng.Rng=.init(21);
  var light:u32=0;
  for(0..200)|_|{
    // a fresh settling for a half-full belly
    const st:Settle=.init(0.5,&r,testRate);
    if(st.gloops[deep.n[1]].start!=m.maxInt(u32))light+=1;
  }
  try testing.expect(light>20 and light<90);
}
test"a twinkle is a few soft high pings, louder the nearer, and ends"{
  // each twinkle's peak, near and far
  var peaks:[2]f32=undefined;
  for([_]f32{0.1,1},&peaks)|near,*peak|{
    // the sounds, with the wind hushed
    var s:Sounds=.init(11,testRate);
    s.wind.level=0;
    s.apply(.{.twinkle=.{.near=near}});
    try testing.expect(s.twinkles[0].?.n>=pingRange[0] and s.twinkles[0].?.n<=pingRange[1]);
    // a block of samples
    var buf:[480]f32=undefined;
    peak.*=0;
    // samples heard
    var n:u32=0;
    while(s.twinkles[0]!=null and n<4*48000):(n+=buf.len){
      @memset(&buf,0);
      s.render(&buf);
      for(buf)|x|peak.*=@max(peak.*,@abs(x));
    }
    try testing.expect(s.twinkles[0]==null);
    // how long it sounded (s)
    const len=m.f(n)/testRate;
    try testing.expect(len>0.5 and len<3.5);
  }
  try testing.expect(peaks[0]>0.002 and peaks[1]<0.1 and peaks[1]>2*peaks[0]);
}
test"the wind is gentle, swells in gusts and whistles only in some"{
  // the sounds, wind and all
  var s:Sounds=.init(5,testRate);
  // a block of a tenth of a second
  var buf:[4800]f32=undefined;
  // the loudest sample, the quietest and loudest blocks, and blocks that whistled
  var peak:f32=0;
  var lo:f32=1;
  var hi:f32=0;
  var whistled:u32=0;
  // a minute, a tenth of a second at a time
  for(0..600)|_|{
    @memset(&buf,0);
    s.render(&buf);
    // this block's sum of squares
    var sum:f32=0;
    for(buf)|x|{
      peak=@max(peak,@abs(x));
      sum+=x*x;
    }
    // this block's loudness (rms)
    const rms=@sqrt(sum/m.f(buf.len));
    lo=@min(lo,rms);
    hi=@max(hi,rms);
    if(s.wind.gust.value>whistleFrom+0.2)whistled+=1;
  }
  try testing.expect(peak>0.005 and peak<0.15);
  try testing.expect(lo>0.0005 and hi>2*lo);
  try testing.expect(whistled>10 and whistled<400);
}
test"the music is silent at night and plays softly by day, on a steady pulse"{
  // the sounds, with the wind hushed
  var s:Sounds=.init(17,testRate);
  s.wind.level=0;
  // a block of samples
  var buf:[480]f32=undefined;
  // ten seconds of night: nothing
  for(0..1000)|_|{
    @memset(&buf,0);
    s.render(&buf);
    for(buf)|x|try testing.expectEqual(@as(f32,0),x);
  }
  try testing.expectEqual(@as(u32,0),s.music.struck);
  s.apply(.{.daylight=1});
  // the loudest sample heard by day
  var peak:f32=0;
  // two minutes of day
  // how many seconds of day to hear
  const secs=120;
  for(0..secs*100)|_|{
    @memset(&buf,0);
    s.render(&buf);
    for(buf)|x|peak=@max(peak,@abs(x));
  }
  try testing.expect(peak>0.02 and peak<0.35);
  // steps of the pulse that passed: notes on many of them, a drum on some bars
  // how many steps of the pulse passed
  const steps=m.f(secs)/stepS;
  try testing.expect(m.f(s.music.struck)>0.5*steps and m.f(s.music.struck)<1.5*steps);
  // how many bars passed
  const bars=steps/barSlots;
  try testing.expect(m.f(s.music.drummed)>0.25*bars and m.f(s.music.drummed)<0.8*bars);
  // dusk: it fades out and rests
  s.apply(.{.daylight=0});
  for(0..3000)|_|{
    @memset(&buf,0);
    s.render(&buf);
  }
  try testing.expect(s.music.resting);
  for(buf)|x|try testing.expectEqual(@as(f32,0),x);
}
test"a phrase's second half varies its first, and melody stays in range"{
  // the random numbers, and the music under test
  var r:rng.Rng=.init(4);
  var mu:Music=.init(&r,testRate);
  for(0..50)|_|{
    mu.phrase();
    // how many of the variation's steps match the motif's
    var same:u32=0;
    for(mu.motif,mu.varied)|a,b|{
      if(a)|i|try testing.expect(i>=melLo and i<=melHi);
      if(std.meta.eql(a,b))same+=1;
    }
    try testing.expect(same>=motif/2);
  }
  // a bar's first note sits in its chord
  try testing.expectEqual(@as(u8,62),chordTone(63,.{.root=0}));
  try testing.expectEqual(@as(u8,71),chordTone(72,.{.root=9,.minor=true}));
}
