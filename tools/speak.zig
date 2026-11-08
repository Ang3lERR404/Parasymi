//! `zig build speak`: Claude's own voice, made from nothing. A throat (a
//! glottal pulse at the voice's pitch, a little uneven as a living one is,
//! with breath through it) is shaped into speech by five resonances in a
//! row, the way a mouth shapes it (a cascade formant synthesizer, after
//! Klatt); hisses and bursts are noise through their own resonance beside
//! them, nasals a dip and a hum. What is said is written by sound, a sound
//! a word (`HH AH0 L OW1`, ARPAbet; a digit is stress, `:` holds it), with
//! `, . ? ! ~` shaping the pitch as the gardener writes sound. Every sound
//! glides into the next; the pitch drifts down through a phrase, lifts on a
//! stressed sound and closes as its mark says. Written as a WAV
//! (`--out=`, by default `shots/voice/said.wav`); `--play` plays it.
//! Built to be shaped by ear: `--pitch=`, `--breath=`, `--pace=`.
/// the standard library
const std=@import("std");
/// the engine package: the maths
const engine=@import("engine");
/// the tools' shared sound files and spectra
const audio=@import("audio");
/// all the maths: casts, tau, powers
const m=engine.core.math;
/// an allocator
const Allocator=std.mem.Allocator;
/// the engine's sound makers: the hall a room is made of
const dsp=engine.core.dsp;
/// the I/O interface every call goes through
const Io=std.Io;
/// a directory handle
const Dir=Io.Dir;
/// a growable list
const ArrayList=std.ArrayList;
/// prints a line to the console
const print=std.debug.print;
/// whether one text starts with another
const startsWith=std.mem.startsWith;
/// the folder part of a path
const dirname=std.fs.path.dirname;
/// the text with the given bytes cut from its ends
const trimAll=std.mem.trim;
/// where a byte first is in a text
const indexOfScalar=std.mem.indexOfScalar;
/// whether a byte is a letter or a digit
const isAlnum=std.ascii.isAlphanumeric;
/// a text in small letters, newly allocated
const lowered=std.ascii.allocLowerString;
/// a text built up in memory
const Allocating=Io.Writer.Allocating;
/// the word list: a word to its sounds
const WordMap=std.StringHashMapUnmanaged([]const u8);
/// splits a text at a byte
const tokenize=std.mem.tokenizeScalar;
/// an enum tag by its name
const stringToEnum=std.meta.stringToEnum;
/// samples a second (Hz)
pub const rate:f32=44100;
/// one sample's length (s)
const dt:f32=1/rate;
/// the voice's own pitch when nothing says otherwise (Hz): mid-range, calm
const basePitch:f32=118;
/// how much breath rides on the voice when nothing says otherwise (0..1):
/// a little, for softness
const baseBreath:f32=0.22;
/// how fast the voice speaks when nothing says otherwise (1 = as written)
const basePace:f32=1;
/// the two highest resonances, the same for every sound: a voice's colour
const f4:f32=3400;
/// the highest resonance (Hz)
const f5:f32=4200;
/// the second and third resonances' bandwidths (Hz): wide enough not to
/// ring like metal
const b2:f32=110;
/// the third's (Hz)
const b3:f32=200;
/// the fourth's (Hz)
const b4:f32=350;
/// the highest one's bandwidth (Hz)
const b5:f32=500;
/// how long resonances take to glide to the next sound (s)
const glideS:f32=0.022;
/// how long loudness takes to change (s): quicker than the mouth moves
const swellS:f32=0.006;
/// how long the pitch takes to follow (s): slow, a voice's line
const pitchS:f32=0.06;
/// how uneven each period is (share of the period), as a living throat's
const jitter:f32=0.012;
/// how uneven each pulse's strength is (share)
const shimmer:f32=0.07;
/// how much each period's open share wavers (share)
const openWobble:f32=0.08;
/// how far the pitch wanders on its own, never quite still (share)
const pitchWander:f32=0.035;
/// how long one wander takes (s)
const pitchWanderS:f32=0.35;
/// how far the resonances wander, a mouth never quite still (share)
const shapeWander:f32=0.03;
/// how long one of their wanders takes (s)
const shapeWanderS:f32=0.22;
/// a stressed sound's pitch starts this much above its lift and falls
/// through it, the way a voice leans on a word (times)
const leanIn:f32=1.05;
/// and ends this much under it (times)
const leanOut:f32=0.95;
/// a vowel fades this much by its end, a syllable's own swell (times)
const vowelFade:f32=0.85;
/// the share of a period the throat is open
const openShare:f32=0.6;
/// how much of the open share is the opening (the rest closes, faster)
const openingShare:f32=0.7;
/// how much a stressed sound lifts the pitch (times)
const stressLift:f32=1.14;
/// how much a stressed sound lasts longer (times)
const stressLong:f32=1.35;
/// how much a held sound (`:`) lasts longer (times)
const heldLong:f32=2.4;
/// how far the pitch drifts down from a phrase's start to its end (times)
const declination:f32=0.86;
/// a "?" lifts the end this much (times)
const askLift:f32=1.32;
/// a "!" lifts the end this much (times), then lets it fall a touch
const brightLift:f32=1.22;
/// a "." lets the end fall this much (times)
const settleFall:f32=0.82;
/// a "~" lifts the middle of the last sound and lets it fall back (times)
const liltLift:f32=1.2;
/// how far down its sentence a comma's phrase drifts (share of the whole)
const commaDrift:f32=0.5;
/// the word before a comma stretches this much (times)
const commaStretch:f32=1.3;
/// its pitch lifts this much at the comma, leading on (times)
const commaLift:f32=1.06;
/// its voice eases to this share by the comma, into the breath
const commaEase:f32=0.45;
/// the little breath in a comma's pause (0..1)
const commaBreath:f32=0.05;
/// a comma's pause (s)
const commaS:f32=0.16;
/// an end's pause (s)
const endS:f32=0.35;
/// how bright the throat's pulse stays at full breath (Hz): a soft edge
/// (measured against the gardener's own voice: brighter read as tinny)
const softHz:f32=350;
/// how much brighter it is with no breath at all (Hz)
const softSpan:f32=900;
/// how dark the breath is (Hz): air through a throat, not a hiss
const airHz:f32=1800;
/// the darkened breath brought up (raised again once the chest and head
/// filled the voice out and left it behind: "better", the gardener)
const airGain:f32=1.6;
/// the throat's softened pulse brought back up, so the voice, not the
/// breath, carries the sound (measured: the breath had drowned it, tinny)
const voiceGain:f32=4;
/// the chest's hum (Hz): low, under the voice
const chestHz:f32=190;
/// its width (Hz): broad, a body not a bell
const chestBw:f32=140;
/// how loud the chest hums with the throat (the gardener picked the fuller
/// of two by ear, 2026-11-07: "much better")
const chestGain:f32=0.18;
/// the nose's hum (Hz), the head's low layer
const headLowHz:f32=280;
/// its width (Hz)
const headLowBw:f32=90;
/// how loud the nose hums
const headLowGain:f32=0.05;
/// the face's ring (Hz), the head's high layer
const headHighHz:f32=2700;
/// its width (Hz)
const headHighBw:f32=400;
/// how loud the face rings (with the nose, picked by ear: "better")
const headHighGain:f32=0.35;
/// how loud a hiss is against the voice: soft, never a hard edge
const hissLoud:f32=0.6;
/// a stop's burst against its hiss: a tap, never a pop
const burstSoft:f32=0.5;
/// a wander lasts at least this share of its average, and up to this
/// much more (shares)
const driftShortest:f32=0.6;
/// how much longer than its shortest a wander may last (share)
const driftSpan:f32=0.8;
/// the share of the voice's breath that rides on every voiced sound
const voicedBreath:f32=0.35;
/// how loud the throat sounds through a glide (w, y, l, r)
const glideVoice:f32=0.75;
/// how loud it sounds through a nasal (m, n, ng)
const nasalVoice:f32=0.6;
/// how loud it buzzes under a voiced hiss (v, z, zh)
const buzzVoice:f32=0.45;
/// how much breath an h is
const aspirateBreath:f32=0.55;
/// how loud a voiced stop hums while shut (b, d, g)
const closureHum:f32=0.12;
/// how long an affricate's hiss lasts (s), ch and j
const affricateS:f32=0.09;
/// how long a stop's burst lasts (s)
const burstS:f32=0.014;
/// how loud the throat sounds in a voiced stop's burst
const burstVoice:f32=0.3;
/// how much breath follows a voiceless stop into its vowel
const aspirationBreath:f32=0.45;
/// how long that breath lasts (s)
const aspirationS:f32=0.035;
/// a stretch voiced at least this loud can carry a phrase's close
const closeVoiced:f32=0.5;
/// after a "!" lifts, its end settles back this much (times)
const brightSettle:f32=0.92;
/// after a "~" lilts, its end settles back this much (times)
const liltSettle:f32=0.95;
/// how much the breath hushes the throat's own sound (share)
const breathHush:f32=0.5;
/// how much breath rides the throat while it is open (share)
const breathRide:f32=0.25;
/// below this the nose takes nothing
const nasalMin:f32=0.01;
/// the lowest resonance's bandwidth at its foot (Hz), and how it widens
/// with its pitch (Hz a Hz)
const b1Base:f32=60;
/// the lowest resonance's bandwidth growth with its pitch (Hz a Hz)
const b1Slope:f32=0.06;
/// a breath of quiet after the last sound (s)
const tailS:f32=0.08;
/// the nose's dip's width (Hz)
const dipBw:f32=120;
/// the nose's own hum (Hz)
const noseHz:f32=270;
/// its width (Hz)
const noseBw:f32=100;
/// a mouth at rest, neither open nor closed: the resonances it leans to
const neutralShape=[3]f32{500,1500,2500};
/// how long the breath at the voice's edges swells and fades (s)
const edgeS:f32=0.08;
/// how much longer the stronger fold's pulse stays open (share of the grain)
const grainOpen:f32=0.5;
/// how long the small room rings (s, to -60 dB)
const roomS:f32=0.45;
/// how soon its first echo comes back (s)
const roomPreS:f32=0.008;
/// how dark its walls are (Hz): soft furnishings, not stone
const roomDampHz:f32=3500;
/// the loudest the voice is written (of full scale)
const peak:f32=0.7;
/// how long the lungs take to fill in a pause (s): a quick breath in
const fillS:f32=0.12;
/// how much of a full breath one second of voice spends: a ~2.5 s
/// phrase runs from full to near its last
const spendS:f32=0.28;
/// the breath's push when the lungs are half spent: the voice's middle,
/// so the push swings round it (above, louder and higher; below, softer)
const pushMid:f32=0.7;
/// how far the push swells and sags on its own as it is spent (share)
const pushSwell:f32=0.18;
/// how long one swell takes (s): slower than a syllable
const pushSwellS:f32=0.6;
/// the extra push a stressed sound is leaned on with
const pushStress:f32=0.35;
/// how long the push takes to follow (s): a body, not a switch
const pushS:f32=0.05;
/// how much the push lifts the pitch (share a unit of push): in the
/// gardener's own voice, louder rides with higher
const pushPitch:f32=0.14;
/// how much it raises the voice's loudness (share a unit of push)
const pushLoud:f32=0.9;
/// how much brighter it makes the throat (Hz a unit of push): the
/// harmonics high up opening as the push rises
const pushBright:f32=2400;
/// how much it presses the folds shut sooner (share of the open time a
/// unit of push): a sharper close, richer up high
const pushPress:f32=0.4;
/// how much more air leaks through as the push runs out (share a unit
/// of push spent below the middle)
const pushAir:f32=1.5;
/// the most the push presses the folds shut sooner, or lets them stay
/// open longer (share)
const pressMost:f32=0.5;
/// the throat's softening never goes darker than this (Hz)
const softFloorHz:f32=150;
/// how much less the throat is softened with the octaves full on (Hz):
/// its harmonics kept up through the middle, where a voice's presence is
const octSoftHz:f32=1500;
/// the voice's top octaves: two high resonances beside the mouth's row,
/// rung by the throat's own sharp close (Hz), where the gardener's voice
/// still rings and Claude's had nothing
const octLowHz:f32=4900;
/// its width (Hz)
const octLowBw:f32=700;
/// the higher one (Hz)
const octHighHz:f32=6300;
/// its width (Hz)
const octHighBw:f32=1000;
/// how loud the top octaves ring with the octaves full on
const octGain:f32=0.5;
/// how much faster the folds close with the octaves full on (share of the
/// open time moved from the close to the opening)
const octSharp:f32=0.2;
/// the fastest the close may come (share of the open time moved to the
/// opening), so the opening never outlasts the folds being open
const sharpMost:f32=0.27;
/// how much the push sharpens the close (share a unit of push)
const octPushSharp:f32=0.6;
/// how much of the close's edge rings the top octaves
const octEdge:f32=0.6;
/// how much the push strengthens that edge (share a unit of push)
const octPushEdge:f32=0.8;
/// how much breath is puffed through the folds into the top octaves
const octAir:f32=0.012;
/// the furthest the high resonances lean with the mouth (times)
const octLeanMost:f32=1.25;
/// what kind of sound a phoneme is
const Kind=enum{
  /// voiced and open: the resonances are the sound
  vowel,
  /// a vowel gliding from one shape to another
  diphthong,
  /// voiced, narrow: w, y, l, r
  glide,
  /// voiced through the nose
  nasal,
  /// a hiss, voiced or not
  fricative,
  /// a closure, then a burst
  stop,
  /// a stop opening into a hiss: ch, j
  affricate,
  /// breath through the vowel's own shape
  aspirate,
};
/// one phoneme's shape: its resonances (Hz) and how it sounds
const Shape=struct{
  /// what kind it is
  kind:Kind,
  /// its three lowest resonances (Hz)
  f:[3]f32,
  /// where a diphthong ends (Hz), or a stop's resonances leading in
  to:[3]f32=.{0,0,0},
  /// how long it lasts, unstressed (s)
  len:f32,
  /// whether the throat sounds through it
  voiced:bool=true,
  /// a hiss's centre (Hz), if it hisses or bursts
  hiss:f32=0,
  /// the hiss's width (Hz)
  hissBw:f32=1000,
  /// how loud the hiss is (0..1)
  hissGain:f32=0,
  /// a nasal's dip (Hz), where the nose takes sound away
  dip:f32=0,
};
/// every phoneme the voice knows, by its ARPAbet name
const Phoneme=enum{IY,IH,EH,AE,AA,AO,AH,UH,UW,ER,AX,AY,EY,OW,AW,OY,W,Y,L,R,M,N,NG,F,V,TH,DH,S,Z,SH,ZH,HH,P,B,T,D,K,G,CH,JH};
/// each phoneme's shape (male vowel tables, after Peterson & Barney and Klatt)
fn shapeOf(p:Phoneme)Shape{
  return switch(p){
    .IY=>.{.kind=.vowel,.f=.{270,2290,3010},.len=0.11},
    .IH=>.{.kind=.vowel,.f=.{390,1990,2550},.len=0.08},
    .EH=>.{.kind=.vowel,.f=.{530,1840,2480},.len=0.09},
    .AE=>.{.kind=.vowel,.f=.{660,1720,2410},.len=0.12},
    .AA=>.{.kind=.vowel,.f=.{730,1090,2440},.len=0.12},
    .AO=>.{.kind=.vowel,.f=.{570,840,2410},.len=0.12},
    .AH=>.{.kind=.vowel,.f=.{640,1190,2390},.len=0.08},
    .UH=>.{.kind=.vowel,.f=.{440,1020,2240},.len=0.08},
    .UW=>.{.kind=.vowel,.f=.{300,870,2240},.len=0.11},
    .ER=>.{.kind=.vowel,.f=.{490,1350,1690},.len=0.11},
    .AX=>.{.kind=.vowel,.f=neutralShape,.len=0.05},
    .AY=>.{.kind=.diphthong,.f=.{730,1090,2440},.to=.{400,1950,2600},.len=0.17},
    .EY=>.{.kind=.diphthong,.f=.{530,1840,2480},.to=.{330,2200,2900},.len=0.15},
    .OW=>.{.kind=.diphthong,.f=.{570,900,2400},.to=.{380,800,2300},.len=0.15},
    .AW=>.{.kind=.diphthong,.f=.{730,1090,2440},.to=.{440,950,2240},.len=0.17},
    .OY=>.{.kind=.diphthong,.f=.{570,840,2410},.to=.{400,1950,2600},.len=0.18},
    .W=>.{.kind=.glide,.f=.{290,610,2150},.len=0.06},
    .Y=>.{.kind=.glide,.f=.{260,2070,3020},.len=0.06},
    .L=>.{.kind=.glide,.f=.{330,1050,2880},.len=0.06},
    .R=>.{.kind=.glide,.f=.{320,1060,1380},.len=0.06},
    .M=>.{.kind=.nasal,.f=.{280,1100,2150},.len=0.07,.dip=950},
    .N=>.{.kind=.nasal,.f=.{280,1600,2500},.len=0.06,.dip=1500},
    .NG=>.{.kind=.nasal,.f=.{280,2000,2700},.len=0.07,.dip=2400},
    .F=>.{.kind=.fricative,.f=.{340,1100,2080},.len=0.1,.voiced=false,.hiss=6500,.hissBw=4000,.hissGain=0.18},
    .V=>.{.kind=.fricative,.f=.{220,1100,2080},.len=0.06,.hiss=6500,.hissBw=4000,.hissGain=0.1},
    .TH=>.{.kind=.fricative,.f=.{320,1290,2540},.len=0.1,.voiced=false,.hiss=6000,.hissBw=4000,.hissGain=0.14},
    .DH=>.{.kind=.fricative,.f=.{270,1290,2540},.len=0.05,.hiss=6000,.hissBw=4000,.hissGain=0.07},
    .S=>.{.kind=.fricative,.f=.{320,1390,2530},.len=0.11,.voiced=false,.hiss=5800,.hissBw=1600,.hissGain=0.55},
    .Z=>.{.kind=.fricative,.f=.{240,1390,2530},.len=0.08,.hiss=5800,.hissBw=1600,.hissGain=0.3},
    .SH=>.{.kind=.fricative,.f=.{300,1840,2750},.len=0.11,.voiced=false,.hiss=2900,.hissBw=1000,.hissGain=0.6},
    .ZH=>.{.kind=.fricative,.f=.{300,1840,2750},.len=0.08,.hiss=2900,.hissBw=1000,.hissGain=0.32},
    .HH=>.{.kind=.aspirate,.f=neutralShape,.len=0.07,.voiced=false},
    .P=>.{.kind=.stop,.f=.{200,900,2100},.len=0.06,.voiced=false,.hiss=1200,.hissBw=2000,.hissGain=0.35},
    .B=>.{.kind=.stop,.f=.{200,900,2100},.len=0.05,.hiss=1200,.hissBw=2000,.hissGain=0.2},
    .T=>.{.kind=.stop,.f=.{200,1700,2600},.len=0.06,.voiced=false,.hiss=4500,.hissBw=2500,.hissGain=0.45},
    .D=>.{.kind=.stop,.f=.{200,1700,2600},.len=0.05,.hiss=4500,.hissBw=2500,.hissGain=0.25},
    .K=>.{.kind=.stop,.f=.{250,1990,2850},.len=0.07,.voiced=false,.hiss=2200,.hissBw=1200,.hissGain=0.45},
    .G=>.{.kind=.stop,.f=.{250,1990,2850},.len=0.05,.hiss=2200,.hissBw=1200,.hissGain=0.25},
    .CH=>.{.kind=.affricate,.f=.{300,1840,2750},.len=0.12,.voiced=false,.hiss=2900,.hissBw=1000,.hissGain=0.6},
    .JH=>.{.kind=.affricate,.f=.{260,1840,2750},.len=0.1,.hiss=2900,.hissBw=1000,.hissGain=0.32},
  };
}
/// how a phrase closes, as the gardener writes it
const Close=enum{
  /// "." settles, falling
  settle,
  /// "?" asks, rising
  ask,
  /// "!" lifts bright, then falls a touch
  bright,
  /// "~" lilts: up and back down
  lilt,
  /// "," leaves it hanging, a little up
  hang,
};
/// one sound to say: a phoneme as written, or a pause that closes a phrase
pub const Sound=struct{
  /// the phoneme, or none for a pause
  p:?Phoneme,
  /// stressed (a digit 1 or 2)
  stressed:bool=false,
  /// held (`:`)
  held:bool=false,
  /// how a pause closes the phrase before it
  close:Close=.settle,
};
/// what reading the written sounds can fail with
pub const ReadError=error{UnknownSound}||Allocator.Error;
/// the sounds written in `text`: phonemes with a stress digit and `:`,
/// and `, . ? ! ~` closing a phrase
pub fn read(arena:Allocator,text:[]const u8)ReadError![]Sound{
  var out:ArrayList(Sound)=.empty;
  var it=tokenize(u8,text,' ');
  while(it.next())|tok|{
    if(tok.len==1){
      // a mark that closes a phrase
      const close:?Close=switch(tok[0]){'.'=>.settle,'?'=>.ask,'!'=>.bright,'~'=>.lilt,','=>.hang,else=>null};
      if(close)|c|{
        try out.append(arena,.{.p=null,.close=c});
        continue;
      }
    }
    // the name without its marks, and the marks
    var name=tok;
    var held=false;
    var stressed=false;
    if(name.len>0 and name[name.len-1]==':'){
      held=true;
      name=name[0..name.len-1];
    }
    // an unstressed AH is the schwa (AX), as the CMU word lists write it
    var schwa=false;
    if(name.len>0 and name[name.len-1]>='0' and name[name.len-1]<='2'){
      stressed=name[name.len-1]!='0';
      schwa=name[name.len-1]=='0';
      name=name[0..name.len-1];
    }
    const p=stringToEnum(Phoneme,name)orelse{
      print("unknown sound: {s}\n",.{tok});
      return error.UnknownSound;
    };
    try out.append(arena,.{.p=if(schwa and p==.AH).AX else p,.stressed=stressed,.held=held});
  }
  return out.items;
}
/// a resonance: a two-pole filter whose peak is `f` Hz, `bw` wide, with
/// no gain at its foot (Klatt's resonator)
const Resonator=struct{
  /// the input's gain
  a:f32=1,
  /// the last output's weight
  b:f32=0,
  /// the one before's weight
  c:f32=0,
  /// the last two outputs
  y1:f32=0,
  /// the one before
  y2:f32=0,
  /// retunes it to a peak at `f` Hz, `bw` wide
  fn tune(r:*Resonator,f:f32,bw:f32)void{
    const e=@exp(-m.pi*bw*dt);
    r.c=-e*e;
    r.b=2*e*@cos(m.tau*f*dt);
    r.a=1-r.b-r.c;
  }
  /// one sample through it
  fn step(r:*Resonator,x:f32)f32{
    const y=r.a*x+r.b*r.y1+r.c*r.y2;
    r.y2=r.y1;
    r.y1=y;
    return y;
  }
};
/// a dip: takes away a band at `f` Hz, `bw` wide, as the nose does (Klatt's
/// antiresonator: the resonator turned inside out)
const Dip=struct{
  /// the input's weight
  a:f32=1,
  /// the last input's weight
  b:f32=0,
  /// the one before's weight
  c:f32=0,
  /// the last two inputs
  x1:f32=0,
  /// the one before
  x2:f32=0,
  /// retunes it to take away `f` Hz, `bw` wide
  fn tune(d:*Dip,f:f32,bw:f32)void{
    // the resonator's own weights, inverted
    var r=Resonator{};
    r.tune(f,bw);
    d.a=1/r.a;
    d.b=-r.b/r.a;
    d.c=-r.c/r.a;
  }
  /// one sample through it
  fn step(d:*Dip,x:f32)f32{
    const y=d.a*x+d.b*d.x1+d.c*d.x2;
    d.x2=d.x1;
    d.x1=x;
    return y;
  }
};
/// noise, white, from a small generator that repeats the same way each run
const Noise=struct{
  /// the generator's state
  s:u32=0x9e3779b9,
  /// one sample, -1..1
  fn next(n:*Noise)f32{
    n.s^=n.s<<13;
    n.s^=n.s>>17;
    n.s^=n.s<<5;
    return m.f(n.s)/2147483648-1;
  }
};
/// a slow wander between -1 and 1: a new place to drift to every so often,
/// glided toward, so nothing living ever holds quite still
const Drift=struct{
  /// what picks each place
  noise:Noise,
  /// how long one wander takes, on average (s)
  every:f32,
  /// where it is now
  now:f32=0,
  /// where it is drifting to
  goal:f32=0,
  /// how long until the next place is picked (s)
  left:f32=0,
  /// one sample's drift
  fn step(d:*Drift)f32{
    d.left-=dt;
    if(d.left<=0){
      d.goal=d.noise.next();
      d.left=d.every*(driftShortest+driftSpan*@abs(d.noise.next()));
    }
    d.now=m.damp(d.now,d.goal,1/d.every,dt);
    return d.now;
  }
};
/// the throat: a glottal pulse at the pitch it is given, a little uneven
/// each period as a living one is, and how open it is (for breath)
const Throat=struct{
  /// where in the period it is (0..1)
  phase:f32=0,
  /// this period's own pitch, wavering about the asked one
  hz:f32=basePitch,
  /// this period's own strength
  gain:f32=1,
  /// how far the two folds fall apart, every other pulse a little
  /// stronger and longer than the one between (0: in step)
  grain:f32=0,
  /// whether this period is the stronger of the pair
  odd:bool=false,
  /// the share of this period the throat is open
  open:f32=openShare,
  /// how much sooner the breath's push presses the folds shut (share)
  press:f32=0,
  /// how much more of the open time is the opening, so the close comes
  /// faster, a sharper edge rich in high harmonics (share)
  sharp:f32=0,
  /// what wavers it
  noise:Noise=.{.s=0x2545f491},
  /// one sample of the pulse's flow, and how open the throat is (0..1)
  fn step(t:*Throat,hz:f32)struct{f32,f32}{
    t.phase+=t.hz*dt;
    if(t.phase>=1){
      t.phase-=1;
      t.hz=hz*(1+jitter*t.noise.next());
      t.gain=1+shimmer*t.noise.next();
      t.open=openShare*(1+openWobble*t.noise.next());
      // the two folds a little apart: the pulses alternate, a grain under the note
      t.odd=!t.odd;
      const side:f32=if(t.odd)1 else-1;
      t.gain*=1+t.grain*side;
      t.open*=1+t.grain*grainOpen*side;
      // pressed shut sooner the harder the breath pushes
      t.open*=1-t.press;
    }
    // opening slowly, closing fast, then shut (Rosenberg's pulse), each
    // period open a little longer or shorter than the last
    const ph=t.phase;
    const op=t.open*(openingShare+t.sharp);
    const flow=if(ph<op)0.5-0.5*@cos(m.pi*ph/op)else if(ph<t.open)@cos(0.5*m.pi*(ph-op)/(t.open-op))else 0;
    return.{flow*t.gain,flow};
  }
};
/// how the voice is asked to sound
pub const Voice=struct{
  /// its own pitch (Hz)
  pitch:f32=basePitch,
  /// how much breath rides on it (0..1)
  breath:f32=baseBreath,
  /// how fast it speaks (1 = as written)
  pace:f32=basePace,
  /// the throat's grain: how far its two folds fall apart (0: in step)
  grain:f32=0,
  /// the breath carried at the voice's edges, as it swells in and fades
  edge:f32=0,
  /// how much of a small room's echo rides with it (0: none)
  room:f32=0,
  /// the body it speaks from, against Claude's own (1): below 1 a bigger
  /// body, a longer throat and a bigger chest, every resonance lower
  tract:f32=1,
  /// how much the breath drives the voice (0: not at all): the lungs fill
  /// in each pause and are spent through each phrase, and their push lifts
  /// the pitch, the loudness and the brightness together, leaking more air
  /// as it runs out
  push:f32=0,
  /// how much of the voice's upper octaves it keeps (0: none): the throat
  /// softened less, and two high resonances rung by its close
  octaves:f32=0,
};
/// which way the air goes through a stretch of the plan
const Air=enum{
  /// out: the voice spends it
  out,
  /// in: a pause, the lungs fill
  in,
};
/// the lungs: the breath's push under the voice, filled in each pause,
/// spent while speaking, swelling and sagging a little on its own
const Lungs=struct{
  /// how full they are (0..1)
  full:f32=1,
  /// the push as the voice feels it, followed smoothly
  push:f32=1,
  /// the push's own slow swell
  swell:Drift=.{.noise=.{.s=0x7f4a7c15},.every=pushSwellS},
  /// one sample: the air going `air`, the voice sounding at `voicing`
  /// (0..1) with `lean` more push on a stressed sound; the push about the
  /// voice's middle (0 at the middle, above it pushing harder)
  fn step(l:*Lungs,air:Air,voicing:f32,lean:f32)f32{
    switch(air){
      .in=>l.full=m.damp(l.full,1,1/fillS,dt),
      .out=>l.full=@max(0,l.full-spendS*voicing*dt),
    }
    const want=l.full*(1+pushSwell*l.swell.step())+pushStress*lean;
    l.push=m.damp(l.push,want,1/pushS,dt);
    return l.push-pushMid;
  }
};
/// what one stretch of time asks of the mouth: resonances, loudness of
/// each source, a hiss's shape, a nasal's dip, and the pitch
const Target=struct{
  /// the three lowest resonances (Hz)
  f:[3]f32,
  /// the throat's loudness (0..1)
  voice:f32,
  /// breath through the mouth's shape (0..1)
  breath:f32=0,
  /// a hiss's loudness (0..1)
  hiss:f32=0,
  /// its centre (Hz)
  hissHz:f32=4000,
  /// its width (Hz)
  hissBw:f32=1500,
  /// how much the nose takes (0..1)
  nasal:f32=0,
  /// where (Hz)
  dipHz:f32=1000,
  /// the pitch here (times the voice's own)
  pitch:f32=1,
  /// how much more the breath leans on it (a stressed sound: 1)
  lean:f32=0,
};
/// one stretch of the plan: how long, and what it asks
pub const Step=struct{
  /// how long (s)
  len:f32,
  /// what it asks at its start
  from:Target,
  /// and at its end (a diphthong moves; most hold)
  to:Target,
  /// which way the air goes: out while speaking, in through a pause
  air:Air=.out,
};
/// the shape a sound leans toward when it has none of its own: the next
/// vowel's (for an aspirate's breath), or a neutral one
fn nextShape(sounds:[]const Sound,i:usize)[3]f32{
  for(sounds[i+1..])|s|{
    if(s.p)|p|{
      const sh=shapeOf(p);
      if(sh.kind==.vowel or sh.kind==.diphthong)return sh.f;
    }else break;
  }
  return neutralShape;
}
/// the plan: every sound turned into stretches of what the mouth does,
/// the pitch drawn over each phrase
pub fn plan(arena:Allocator,sounds:[]const Sound,v:Voice)Allocator.Error![]Step{
  var out:ArrayList(Step)=.empty;
  // where the current phrase began in `out`, to draw its pitch when it closes
  var phraseAt:usize=0;
  // how far the sentence's pitch has drifted down so far: a comma carries
  // on from where it was, only an end starts it over
  var drift:f32=1;
  for(sounds,0..)|s,i|{
    const p=s.p orelse {
      // a comma's phrase drifts only part of the way down; an end, all of it
      const to=if(s.close==.hang)m.lerp(drift,declination,commaDrift)else declination;
      closePhrase(out.items[phraseAt..],s.close,drift,to);
      drift=if(s.close==.hang)to else 1;
      // the pause: a comma is a little breath, an end a quiet one
      const air=Target{.f=neutralShape,.voice=0,.breath=if(s.close==.hang)commaBreath else 0};
      try out.append(arena,.{.len=(if(s.close==.hang)commaS else endS)/v.pace,.from=air,.to=.{.f=air.f,.voice=0},.air=.in});
      phraseAt=out.items.len;
      continue;
    };
    const sh=shapeOf(p);
    // how long, stress and holding counted
    var len=sh.len/v.pace;
    if(s.stressed)len*=stressLong;
    if(s.held)len*=heldLong;
    // the pitch lifted on a stressed sound, and the breath leaning on it
    const lift:f32=if(s.stressed)stressLift else 1;
    const lean:f32=if(s.stressed)1 else 0;
    // the voice's own breath on every voiced sound
    const vb=v.breath*voicedBreath;
    switch(sh.kind){
      // a vowel swells and fades a little, and a stressed one leans in
      // above its lift and falls through it
      .vowel,.diphthong=>{
        const into:f32=if(s.stressed)leanIn else 1;
        const outOf:f32=if(s.stressed)leanOut else 1;
        const end=if(sh.kind==.diphthong)sh.to else sh.f;
        try out.append(arena,.{.len=len,.from=.{.f=sh.f,.voice=1,.breath=vb,.pitch=lift*into,.lean=lean},.to=.{.f=end,.voice=vowelFade,.breath=vb,.pitch=lift*outOf,.lean=lean}});
      },
      .glide=>{
        const t=Target{.f=sh.f,.voice=glideVoice,.breath=vb,.pitch=lift};
        try out.append(arena,.{.len=len,.from=t,.to=t});
      },
      .nasal=>{
        const t=Target{.f=sh.f,.voice=nasalVoice,.breath=vb,.nasal=1,.dipHz=sh.dip,.pitch=lift};
        try out.append(arena,.{.len=len,.from=t,.to=t});
      },
      .fricative=>{
        const t=Target{.f=sh.f,.voice=if(sh.voiced)buzzVoice else 0,.hiss=sh.hissGain,.hissHz=sh.hiss,.hissBw=sh.hissBw};
        try out.append(arena,.{.len=len,.from=t,.to=t});
      },
      .aspirate=>{
        const t=Target{.f=nextShape(sounds,i),.voice=0,.breath=aspirateBreath};
        try out.append(arena,.{.len=len,.from=t,.to=t});
      },
      .stop,.affricate=>{
        // the closure: silent, or a low hum for a voiced one
        const shut=Target{.f=sh.f,.voice=if(sh.voiced)closureHum else 0};
        try out.append(arena,.{.len=len,.from=shut,.to=shut});
        // the burst, or the affricate's hiss
        const burstLen:f32=if(sh.kind==.affricate)affricateS/v.pace else burstS;
        const burst=Target{.f=sh.f,.voice=if(sh.voiced)burstVoice else 0,.hiss=sh.hissGain*(if(sh.kind==.stop)burstSoft else 1),.hissHz=sh.hiss,.hissBw=sh.hissBw};
        try out.append(arena,.{.len=burstLen,.from=burst,.to=burst});
        // breath after a voiceless one, into the next vowel's shape
        if(!sh.voiced){
          const asp=Target{.f=nextShape(sounds,i),.voice=0,.breath=aspirationBreath};
          try out.append(arena,.{.len=aspirationS/v.pace,.from=asp,.to=asp});
        }
      },
    }
  }
  closePhrase(out.items[phraseAt..],.settle,drift,declination);
  return out.items;
}
/// draws a phrase's pitch: drifting down from `d0` to `d1` (times the
/// voice's own), and its last voiced stretch closing as `close` says
fn closePhrase(steps:[]Step,close:Close,d0:f32,d1:f32)void{
  if(steps.len==0)return;
  // the phrase's whole length, and how far along each step starts
  var total:f32=0;
  for(steps)|s|total+=s.len;
  var at:f32=0;
  for(steps)|*s|{
    // the drift down at the step's start and end
    const a=m.lerp(d0,d1,at/total);
    const b=m.lerp(d0,d1,(at+s.len)/total);
    s.from.pitch*=a;
    s.to.pitch*=b;
    at+=s.len;
  }
  // the last voiced stretch carries the close
  var k=steps.len;
  while(k>0){
    k-=1;
    if(steps[k].to.voice<closeVoiced)continue;
    switch(close){
      .settle=>steps[k].to.pitch*=settleFall,
      .ask=>steps[k].to.pitch*=askLift,
      .bright=>{
        steps[k].from.pitch*=brightLift;
        steps[k].to.pitch*=brightLift*brightSettle;
      },
      .lilt=>{
        steps[k].from.pitch*=liltLift;
        steps[k].to.pitch*=liltSettle;
      },
      // a comma leads on: the word before it stretches, its pitch lifts
      // a touch, and its voice eases off into the breath, never cut
      .hang=>{
        steps[k].len*=commaStretch;
        steps[k].to.pitch*=commaLift;
        steps[k].to.voice*=commaEase;
      },
    }
    break;
  }
}
/// the mouth: everything the voice is made of, followed sample by sample
const Mouth=struct{
  /// the throat
  throat:Throat=.{},
  /// the five resonances, in a row
  res:[5]Resonator=@splat(.{}),
  /// the nose's dip
  dip:Dip=.{},
  /// the nose's own hum
  nose:Resonator=.{},
  /// the chest: a low resonance humming along with the throat, beside the
  /// mouth (the first of the voice's layers)
  chest:Resonator=.{},
  /// the head's low layer: the nose humming
  headLow:Resonator=.{},
  /// its high layer: the face ringing
  headHigh:Resonator=.{},
  /// the hiss's resonance, beside the row
  hissRes:Resonator=.{},
  /// the breath's and the hiss's noise
  noise:Noise=.{},
  /// each of the three lowest resonances' own slow wander
  wander:[3]Drift=.{.{.noise=.{.s=0x1b873593},.every=shapeWanderS},.{.noise=.{.s=0xcc9e2d51},.every=shapeWanderS},.{.noise=.{.s=0x85ebca6b},.every=shapeWanderS}},
  /// what the mouth is doing now, glided toward what the plan asks
  now:Target=.{.f=neutralShape,.voice=0},
  /// the softening of the throat's brightness (a one-pole low pass)
  soft:f32=0,
  /// the breath noise, darkened (a one-pole low pass)
  air:f32=0,
  /// the last sample out, for the lips' radiation (a first difference)
  last:f32=0,
  /// how far each sample glides the resonances toward what is asked
  kf:f32=0,
  /// how far each sample swells the loudness toward what is asked
  ka:f32=0,
  /// how far each sample the softened throat follows the pulse
  kSoft:f32=0,
  /// how far each sample the darkened breath follows its noise
  kAir:f32=0,
  /// how much breath the voice's edges carry (its onsets and fades)
  edge:f32=0,
  /// the voice's loudness followed slowly, for the breath at its edges
  slowVoice:f32=0,
  /// how far each sample that slow follower moves
  kEdge:f32=0,
  /// the body's size against the voice's own (below 1, bigger: every
  /// resonance lower)
  tract:f32=1,
  /// how much the breath's push drives the voice (0: not at all)
  push:f32=0,
  /// how bright the throat's softening is with the push at its middle (Hz)
  softAt:f32=softHz,
  /// how loud the top octaves ring (0: not at all)
  octaves:f32=0,
  /// the top octaves' lower resonance
  octLow:Resonator=.{},
  /// and higher one
  octHigh:Resonator=.{},
  /// the throat's last unsoftened flow, for its close's sharp edge
  lastFlow:f32=0,
  /// how much faster the folds close with the push at its middle (share)
  sharpAt:f32=0,
  /// a mouth at rest for a voice of `breath`: everything that never
  /// changes while it speaks worked out once (the high resonances, the
  /// chest, the head, the nose's hum, how fast things glide), not again
  /// every sample
  fn init(v:Voice)Mouth{
    var mo=Mouth{.tract=v.tract,.edge=v.edge,.push=v.push,.throat=.{.grain=v.grain}};
    mo.kf=m.dampBy(1/glideS,dt);
    mo.ka=m.dampBy(1/swellS,dt);
    mo.softAt=softHz+softSpan*(1-v.breath)+octSoftHz*v.octaves;
    mo.kSoft=m.dampBy(m.tau*mo.softAt,dt);
    mo.octaves=v.octaves*octGain;
    mo.sharpAt=octSharp*v.octaves;
    mo.kAir=m.dampBy(m.tau*airHz,dt);
    mo.kEdge=m.dampBy(1/edgeS,dt);
    mo.res[3].tune(f4*v.tract,b4);
    mo.res[4].tune(f5*v.tract,b5);
    mo.nose.tune(noseHz,noseBw);
    mo.chest.tune(chestHz*v.tract,chestBw);
    mo.headLow.tune(headLowHz*v.tract,headLowBw);
    mo.headHigh.tune(headHighHz*v.tract,headHighBw);
    return mo;
  }
  /// one sample: the plan's target `want` at pitch `hz`, the breath
  /// pushing `push` about its middle
  fn step(mo:*Mouth,want:Target,hz:f32,breath:f32,push:f32)f32{
    // the breath's push: harder, the folds pressed shut sooner and the
    // throat brighter (its harmonics opening up high), the voice louder;
    // spent, softer, darker and leakier (worked out only while it drives)
    var loud:f32=1;
    var leak:f32=1;
    // the push about its middle, as the body feels it (0 while it does not drive)
    const e=mo.push*push;
    if(mo.push>0){
      mo.throat.press=@min(pressMost,@max(-pressMost,pushPress*e));
      mo.kSoft=m.dampBy(m.tau*@max(softFloorHz,mo.softAt+pushBright*e),dt);
      loud=@max(0,1+pushLoud*e);
      leak=1+pushAir*@max(0,-e);
    }
    // gliding toward what is asked: resonances slowly, loudness quickly
    const kf=mo.kf;
    const ka=mo.ka;
    for(0..3)|i|mo.now.f[i]=m.lerp(mo.now.f[i],want.f[i],kf);
    mo.now.voice=m.lerp(mo.now.voice,want.voice,ka);
    mo.now.breath=m.lerp(mo.now.breath,want.breath,ka);
    mo.now.hiss=m.lerp(mo.now.hiss,want.hiss,ka);
    mo.now.hissHz=m.lerp(mo.now.hissHz,want.hissHz,kf);
    mo.now.hissBw=m.lerp(mo.now.hissBw,want.hissBw,kf);
    mo.now.nasal=m.lerp(mo.now.nasal,want.nasal,kf);
    mo.now.dipHz=m.lerp(mo.now.dipHz,want.dipHz,kf);
    // the throat's pulse, softened (a gentle voice loses its edge), and
    // the breath through it, strongest while it is open
    const flow,const open=mo.throat.step(hz);
    mo.soft=m.lerp(mo.soft,flow,mo.kSoft);
    // the breath, darkened: air through a throat, not a hiss
    mo.air=m.lerp(mo.air,mo.noise.next(),mo.kAir);
    const n=mo.air*airGain;
    // more air at the voice's edges, as it swells in and fades out
    // (measured against a slow follower of the voice, so the air swells and
    // fades over ~80 ms: a soft puff, never a tap at each start and stop)
    mo.slowVoice=m.lerp(mo.slowVoice,want.voice,mo.kEdge);
    const edgeAir=mo.edge*@abs(want.voice-mo.slowVoice);
    const src=voiceGain*mo.soft*mo.now.voice*loud*(1-breathHush*breath)+n*(mo.now.breath+breath*breathRide*mo.now.voice*open*leak+edgeAir);
    // through the nose's dip, then the mouth's resonances
    var x=src;
    if(mo.now.nasal>nasalMin){
      mo.dip.tune(mo.now.dipHz,dipBw);
      x=m.lerp(x,mo.nose.step(mo.dip.step(x)),mo.now.nasal);
    }
    const bws=[5]f32{b1Base+mo.now.f[0]*b1Slope,b2,b3,b4,b5};
    // the three lowest wandering a little, a mouth never quite still
    var fs=[5]f32{mo.now.f[0],mo.now.f[1],mo.now.f[2],f4,f5};
    for(0..3)|i|fs[i]*=(1+shapeWander*mo.wander[i].step())*mo.tract;
    // (the two highest never move: tuned once, in `init`)
    for(&mo.res,0..)|*r,i|{
      if(i<3)r.tune(fs[i],bws[i]);
      x=r.step(x);
    }
    // the hiss, beside the row
    mo.hissRes.tune(mo.now.hissHz,mo.now.hissBw);
    const hiss=mo.hissRes.step(mo.noise.next())*mo.now.hiss*hissLoud;
    // out through the lips: the first difference brightens as lips do
    const y=x+hiss;
    const out=y-mo.last;
    mo.last=y;
    // the chest humming with the throat, joined after the lips (it is
    // felt through the body, not shaped by the mouth), and the head: the
    // nose's hum and the face's ring, always a little, as a real voice
    // hums through the face as well as the mouth (all tuned in `init`)
    const voiced=mo.soft*mo.now.voice*loud;
    // (the face rings with what the mouth makes, so it is fed the mouth's
    // own sound: the throat alone is too soft up there to set it ringing)
    const head=mo.headLow.step(voiced)*headLowGain+mo.headHigh.step(out)*headHighGain;
    // the top octaves (only while asked for): up there a voice is mostly
    // breath, puffed through the folds each time they open, with a little
    // of the close's sharp edge in it; both ride the breath's push (pushed,
    // more edge and a sharper close; spent, softer and airier) and the two
    // high resonances follow the mouth's own shape
    var top:f32=0;
    if(mo.octaves>0){
      mo.throat.sharp=@min(sharpMost,mo.sharpAt*@max(0,1+octPushSharp*e));
      const edge=(flow-mo.lastFlow)*octEdge*@max(0,1+octPushEdge*e);
      mo.lastFlow=flow;
      const puff=mo.noise.next()*open*octAir*leak;
      const feed=(edge+puff)*mo.now.voice*loud;
      // the high resonances lean with the mouth's third, as the face does
      const lean=@min(octLeanMost,@max(1/octLeanMost,mo.now.f[2]/neutralShape[2]));
      mo.octLow.tune(octLowHz*mo.tract*lean,octLowBw);
      mo.octHigh.tune(octHighHz*mo.tract*lean,octHighBw);
      top=(mo.octLow.step(feed)+mo.octHigh.step(feed))*mo.octaves;
    }
    return out+mo.chest.step(voiced)*chestGain+head+top;
  }
};
/// the whole plan spoken: its samples at `rate`, peak-normalized
pub fn speak(arena:Allocator,steps:[]const Step,v:Voice)Allocator.Error![]f32{
  // how many samples, with a breath of quiet at the end
  var total:f32=tailS+(if(v.room>0)roomS else 0);
  for(steps)|s|total+=s.len;
  const out=try arena.alloc(f32,m.floorTo(usize,total*rate));
  var mo=Mouth.init(v);
  // the pitch, gliding along its own line and wandering a little off it
  var hz=v.pitch;
  var wander=Drift{.noise=.{.s=0x68e31da4},.every=pitchWanderS};
  // the lungs under it all
  var lungs=Lungs{};
  var i:usize=0;
  for(steps)|s|{
    const n=m.floorTo(usize,s.len*rate);
    for(0..n)|k|{
      if(i>=out.len)break;
      // how far through the step
      const t=m.ratio(k,@max(1,n));
      var want=s.from;
      for(0..3)|j|want.f[j]=m.lerp(s.from.f[j],s.to.f[j],t);
      want.pitch=m.lerp(s.from.pitch,s.to.pitch,t);
      // the breath's push (only while it drives the voice: off, nothing moves)
      const push=if(v.push>0)lungs.step(s.air,mo.now.voice,want.lean)else 0;
      hz=m.damp(hz,v.pitch*want.pitch*(1+pitchWander*wander.step())*(1+v.push*pushPitch*push),1/pitchS,dt);
      out[i]=mo.step(want,hz,v.breath,push);
      i+=1;
    }
  }
  while(i<out.len):(i+=1)out[i]=mo.step(.{.f=neutralShape,.voice=0},hz,v.breath,0);
  // a room round the voice: a small one, the voice coming back off its
  // walls a little, the dry voice kept
  if(v.room>0){
    const hall=try arena.create(dsp.Hall);
    hall.*=.init(roomS,roomPreS,roomDampHz,rate);
    for(out)|*x|{
      const wet=hall.tick(dsp.mid(x.*));
      x.*+=v.room*m.sumOf(f32,2,wet)*0.5;
    }
  }
  // as loud as it may be, no louder
  var top:f32=1e-9;
  for(out)|x|top=@max(top,@abs(x));
  for(out)|*x|x.*=peak*x.*/top;
  return out;
}
/// where the voice is written when nothing says otherwise
const defaultOut="shots/voice/said.wav";
/// what is said when nothing says otherwise: "hello, angel. I can hear you~"
const defaultSay="HH AX L OW1 , EY1 N JH AX L . AY1 K AE1 N HH IY1 R Y UW1 ~";
/// Claude's own word list: a word and its sounds a line, grown as words
/// are needed (`#` begins a note)
pub const wordsPath="tools/voice/words.txt";
/// every try kept, its wave and a line of what it was, for the loop of
/// saying, hearing the gardener's word on it, and changing one thing
const triesDir="shots/voice/tries";
/// what spelling plain text can fail with
pub const SpellError=error{UnknownWord}||Allocator.Error;
/// whether a byte ends a word as one of the marks that shape a close
fn isMark(c:u8)bool{return switch(c){',','.','?','!','~'=>true,else=>false};}
/// `text` spelled in sounds from the word list `words`: each word looked
/// up (any case), the marks `, . ? ! ~` kept; every word not in the list
/// is printed before failing, so all can be added at once
pub fn spell(arena:Allocator,words:[]const u8,text:[]const u8)SpellError![]u8{
  // the list, by word
  var list:WordMap=.empty;
  var lines=tokenize(u8,words,'\n');
  while(lines.next())|raw|{
    const line=trimAll(u8,raw," \r\t");
    if(line.len==0 or line[0]=='#')continue;
    const gap=indexOfScalar(u8,line,' ') orelse continue;
    try list.put(arena,line[0..gap],trimAll(u8,line[gap..]," "));
  }
  var aw:Allocating=.init(arena);
  const w=&aw.writer;
  // whether any word was missing
  var missing=false;
  var i:usize=0;
  while(i<text.len){
    const c=text[i];
    if(isMark(c)){
      w.print("{c} ",.{c}) catch return error.OutOfMemory;
      i+=1;
      continue;
    }
    if(!isAlnum(c) and c!='\''){
      i+=1;
      continue;
    }
    // the word, lowered
    const start=i;
    while(i<text.len and (isAlnum(text[i]) or text[i]=='\''))i+=1;
    const word=try lowered(arena,text[start..i]);
    if(list.get(word))|sounds|{
      w.print("{s} ",.{sounds}) catch return error.OutOfMemory;
    }else{
      print("not in my word list yet: {s}\n",.{word});
      missing=true;
    }
  }
  if(missing)return error.UnknownWord;
  return aw.written();
}
/// speaks `--text=` (plain words, through the word list) or `--say=`
/// (sounds, as above) into `--out=`, keeps the try, and plays it with `--play`
pub fn main(init:std.process.Init)!void{
  const io=init.io;
  const arena=init.arena.allocator();
  var v=Voice{};
  var say:[]const u8=defaultSay;
  var text:?[]const u8=null;
  var outPath:[]const u8=defaultOut;
  var play=false;
  const args=try init.minimal.args.toSlice(arena);
  for(args[1..])|a|{
    if(startsWith(u8,a,"--say="))say=a["--say=".len..];
    if(startsWith(u8,a,"--text="))text=a["--text=".len..];
    if(startsWith(u8,a,"--out="))outPath=a["--out=".len..];
    if(startsWith(u8,a,"--pitch="))v.pitch=try std.fmt.parseFloat(f32,a["--pitch=".len..]);
    if(startsWith(u8,a,"--breath="))v.breath=try std.fmt.parseFloat(f32,a["--breath=".len..]);
    if(startsWith(u8,a,"--pace="))v.pace=try std.fmt.parseFloat(f32,a["--pace=".len..]);
    if(startsWith(u8,a,"--grain="))v.grain=try std.fmt.parseFloat(f32,a["--grain=".len..]);
    if(startsWith(u8,a,"--edge="))v.edge=try std.fmt.parseFloat(f32,a["--edge=".len..]);
    if(startsWith(u8,a,"--room="))v.room=try std.fmt.parseFloat(f32,a["--room=".len..]);
    if(startsWith(u8,a,"--tract="))v.tract=try std.fmt.parseFloat(f32,a["--tract=".len..]);
    if(startsWith(u8,a,"--push="))v.push=try std.fmt.parseFloat(f32,a["--push=".len..]);
    if(startsWith(u8,a,"--octaves="))v.octaves=try std.fmt.parseFloat(f32,a["--octaves=".len..]);
    if(std.mem.eql(u8,a,"--play"))play=true;
  }
  if(text)|t|say=try spell(arena,try Dir.cwd().readFileAlloc(io,wordsPath,arena,.unlimited),t);
  const sounds=try read(arena,say);
  const x=try speak(arena,try plan(arena,sounds,v),v);
  const wav=try audio.wavOf(arena,x,@intFromFloat(rate));
  if(dirname(outPath))|d|try Dir.cwd().createDirPath(io,d);
  try Dir.cwd().writeFile(io,.{.sub_path=outPath,.data=wav});
  print("said {d:.2} s into {s}\n",.{m.f(x.len)/rate,outPath});
  // the try kept, named by when, with a line of what it was
  const ms:i64=@intCast(@divTrunc(Io.Clock.real.now(io).nanoseconds,std.time.ns_per_ms));
  try Dir.cwd().createDirPath(io,triesDir);
  try Dir.cwd().writeFile(io,.{.sub_path=try std.fmt.allocPrint(arena,"{s}/{d}.wav",.{triesDir,ms}),.data=wav});
  const note=try std.fmt.allocPrint(arena,"{d} pitch={d} breath={d} pace={d} | {s} | {s}\n",.{ms,v.pitch,v.breath,v.pace,text orelse "",say});
  var log=try Dir.cwd().createFile(io,triesDir++"/log.txt",.{.truncate=false,.read=true});
  defer log.close(io);
  try log.writePositionalAll(io,note,try log.length(io));
  print("kept as tries/{d}\n",.{ms});
  if(!play)return;
  // the mark that tells the ear (tools/hear.zig) this is Claude's own
  // voice on the speakers, not the gardener's, left while it plays
  try Dir.cwd().createDirPath(io,"link");
  try Dir.cwd().writeFile(io,.{.sub_path=speakingMark,.data=""});
  defer Dir.cwd().deleteFile(io,speakingMark)catch{};
  // played through Windows' own player, waiting until it is done
  const cmd=try std.fmt.allocPrint(arena,"(New-Object Media.SoundPlayer '{s}').PlaySync()",.{outPath});
  const r=try std.process.run(arena,io,.{.argv=&.{"powershell.exe","-NoProfile","-Command",cmd}});
  if(r.term!=.exited or r.term.exited!=0)print("could not play it: {s}\n",.{r.stderr});
}
/// left in the link folder while the voice plays, so the ear never hears
/// Claude's own voice as the gardener's (tools/hear.zig reads the same)
const speakingMark="link/speaking";
/// the test harness
const testing=std.testing;
test "sounds are read with their stress, holding and closes" {
  var ar=std.heap.ArenaAllocator.init(testing.allocator);
  defer ar.deinit();
  const s=try read(ar.allocator(),"HH AX L OW1: ~");
  try testing.expectEqual(@as(usize,5),s.len);
  try testing.expectEqual(Phoneme.OW,s[3].p.?);
  try testing.expect(s[3].stressed and s[3].held);
  try testing.expectEqual(Close.lilt,s[4].close);
  try testing.expectError(error.UnknownSound,read(ar.allocator(),"QQ"));
}
test "a resonance keeps its foot and rings at its peak" {
  var r=Resonator{};
  r.tune(1000,100);
  // a steady input comes through whole
  var y:f32=0;
  for(0..20000)|_|y=r.step(1);
  try testing.expectApproxEqAbs(@as(f32,1),y,1e-3);
}
test "a dip undoes its resonance" {
  var r=Resonator{};
  var d=Dip{};
  r.tune(1200,150);
  d.tune(1200,150);
  var n=Noise{};
  for(0..2000)|_|{
    const x=n.next();
    try testing.expectApproxEqAbs(x,d.step(r.step(x)),1e-3);
  }
}
test "a held vowel sings at the voice's pitch" {
  var ar=std.heap.ArenaAllocator.init(testing.allocator);
  defer ar.deinit();
  const arena=ar.allocator();
  const v=Voice{.pitch=120,.breath=0};
  const x=try speak(arena,try plan(arena,try read(arena,"AA0:"),v),v);
  // the period found in the middle: the lag where it is most like itself
  // (looked for between 73 and 176 Hz, so two periods never pass for one)
  const mid=x[x.len/3..][0..2048];
  var best:usize=0;
  var bestC:f32=-1e9;
  for(250..600)|lag|{
    var c:f32=0;
    for(0..1024)|i|c+=mid[i]*mid[i+lag];
    if(c>bestC){
      bestC=c;
      best=lag;
    }
  }
  // (within its drift down, its wander and its close: a lone vowel is
  // also the end of its phrase, settling)
  try testing.expectApproxEqAbs(@as(f32,120),rate/m.f(best),120*0.15);
}
test "the close lifts or lets fall the phrase's end" {
  var ar=std.heap.ArenaAllocator.init(testing.allocator);
  defer ar.deinit();
  const arena=ar.allocator();
  const asked=try plan(arena,try read(arena,"Y UW1 ?"),.{});
  const settled=try plan(arena,try read(arena,"Y UW1 ."),.{});
  try testing.expect(asked[1].to.pitch>asked[1].from.pitch);
  try testing.expect(settled[1].to.pitch<settled[1].from.pitch);
}
