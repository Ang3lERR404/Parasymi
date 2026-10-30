//! the day's music on paper: pulse, scale, chords and how its voices are tuned.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const rate=lib.sound.rate;
// ---- the day's music ----
/// the pulse: eighth notes at this tempo (beats a minute), eight to a bar,
/// four bars to a phrase
const tempo:f32=84;
pub const stepS:f32=60.0/tempo/2.0;
pub const barSlots=8;
pub const bars=4;
pub const phraseSteps=barSlots*bars;
/// a motif is two bars; the phrase plays it, then a variation of it
pub const motif=2*barSlots;
/// the key (MIDI note of D4) and its pentatonic scale (semitones)
const key:u8=62;
const penta=[_]u8{0,2,4,7,9};
/// the melody's range, in steps of the scale above the key (B4..E6)
pub const melLo:u8=4;
pub const melHi:u8=11;
/// how likely a note is on a bar's first step, on a beat, off the beat
pub const noteChance=[3]f32{0.9,0.6,0.3};
/// how loud a note is there (before it strays by `VARY`)
pub const noteVel=[3]f32{1,0.8,0.62};
/// a new motif instead of a variation of the last, a new progression
/// instead of the last, and each step's chance to change in a variation
pub const newMotifChance:f32=0.4;
pub const newChords:f32=0.4;
pub const mutate:f32=0.25;
/// the phrase breathes out: its last two steps rest this often
pub const breathe:f32=0.7;
/// a chord: its root (semitones above the key) and whether it is minor
pub const Chord=struct{root:u8,minor:bool=false};
/// I vi IV V, IV I ii V, I V vi IV
pub const progressions=[_][bars]Chord{
  .{.{.root=0},.{.root=9,.minor=true},.{.root=5},.{.root=7}},
  .{.{.root=5},.{.root=0},.{.root=2,.minor=true},.{.root=7}},
  .{.{.root=0},.{.root=7},.{.root=9,.minor=true},.{.root=5}},
};
/// the left hand: each bar's root low (D3, roots above this many semitones
/// an octave lower), its fifth on the third beat this often, and how loud
pub const lowLevel:u8=50;
pub const lowFold:u8=4;
pub const fifthChance:f32=0.6;
pub const lowVel:f32=0.55;
/// the plunk: a struck string's partials (harmonics a little stretched,
/// as a piano's are), their levels, and a second string a hair sharp
/// beating against the first
pub const harmonics=5;
pub const stretch:f32=0.0004;
pub const harmonicLevel=[harmonics]f32{1,0.5,0.28,0.14,0.07};
pub const detune:f32=1.0007;
pub const detuneLevel:f32=0.7;
/// how long it rings (s, ~63%) at this pitch (Hz), shorter for higher
/// notes and within these bounds; each higher partial dies this much faster
pub const plunkFall:f32=0.55;
pub const plunkRefHz:f32=400;
pub const plunkFallSpan=[2]f32{0.22,1.3};
pub const plunkDamp:f32=0.9;
/// a softer note is this much duller (its partials fall by this power)
pub const dull:f32=0.7;
/// the felt hammer: a tick of noise this many times the pitch (Hz at most),
/// falling in this (s), at this level; the attack (s)
pub const hammerAt:f32=5;
pub const hammerHz:f32=4500;
pub const hammerFall:f32=0.004;
pub const hammer:f32=0.3;
pub const plunkAttack:f32=0.0015;
/// what softens it (Hz), its loudness, and how many may ring at once
pub const plunkSoftHz:f32=3600;
pub const plunk:f32=0.032;
pub const plunks=10;
/// the drum: a soft low tom on a bar's first step this often, on its third
/// beat this often (lighter); its pitch (Hz) dropping from the first to
/// the second in this (s), its fall (s), the skin's noise (Hz, fall, level)
pub const drumChance:f32=0.5;
pub const tapChance:f32=0.12;
pub const tapVel:f32=0.5;
pub const drumHz=[2]f32{110,62};
pub const drumDrop:f32=0.05;
pub const drumFall:f32=0.22;
pub const skinHz:f32=220;
pub const skinFall:f32=0.03;
pub const skin:f32=0.5;
/// what muffles it (Hz), its loudness, and how many may sound at once
pub const drumSoftHz:f32=700;
pub const drum:f32=0.06;
pub const drums=2;
/// a soft echo three steps behind, kept at a quarter of the rate (it is
/// dark anyway), feeding back this much, darkened (Hz) and at this level
pub const echoSteps:f32=3;
pub const echoDown=4;
pub const echoLen=m.floorTo(usize,echoSteps*stepS*m.f(rate)/echoDown)+4;
pub const echoFeedback:f32=0.3;
pub const echoSoftHz:f32=1800;
pub const echo:f32=0.35;
/// how fast the music follows the daylight (s); it plays only past this
pub const musicGlide:f32=3;
pub const musicFrom:f32=0.05;
/// the music's loudness (tests hush it to hear the rest alone)
pub const music:f32=1;
/// a MIDI note of the scale, `i` steps above the key
pub fn scaleNote(i:u8)u8{return@intCast(key+12*(i/penta.len)+penta[i%penta.len]);}
/// the note nearest `note` (within a whole tone) that is in `c`
pub fn chordTone(note:u8,c:Chord)u8{
  const third:u8=if(c.minor)3 else 4;
  var best=note;
  var dist:u8=3;
  for([_]u8{0,1,2})|d|for([_]u8{note-|d,note+d})|n|{
    const in=(n+12-key%12+12-c.root)%12;
    if((in==0 or in==third or in==7) and d<dist){
      best=n;
      dist=d;
    }
  };
  return best;
}
