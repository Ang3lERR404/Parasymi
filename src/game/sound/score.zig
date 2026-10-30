//! the day's music on paper: pulse, a Lydian scale, open chords and how its voices are tuned.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: rounding, conversions
const m=engine.core.math;
/// samples per second the sounds are made at
const rate=lib.sound.rate;
// ---- the day's music ----
/// the pulse: eighth notes at this tempo (beats a minute), eight to a bar,
/// four bars to a phrase
/// (this one: the tempo, beats a minute)
const tempo:f32=84;
/// how long one step (an eighth note) lasts (s)
pub const stepS:f32=60.0/tempo/2.0;
/// steps to a bar
pub const barSlots=8;
/// bars to a phrase
pub const bars=4;
/// steps to a phrase
pub const phraseSteps=barSlots*bars;
/// a motif is two bars; the phrase plays it, then a variation of it
pub const motif=2*barSlots;
/// the key (MIDI note of D4) and its Lydian scale (semitones)
/// (this one: the key, MIDI D4)
const key:u8=62;
// decision: Lydian, not the major pentatonic: its raised fourth (G sharp
// over D) is the sound of wonder, where the pentatonic read as plain and
// cheerful
/// the Lydian scale's notes, semitones above the key: a major scale with
/// its fourth raised
const scale=[_]u8{0,2,4,6,7,9,11};
/// the melody's range, in steps of the scale above the key (B4..E6)
/// (this one: its lowest step)
pub const melLo:u8=5;
/// its highest step
pub const melHi:u8=15;
/// how likely a note is on a bar's first step, on a beat, off the beat
pub const noteChance=[3]f32{0.9,0.6,0.3};
/// how loud a note is there (before it strays by `vary`)
pub const noteVel=[3]f32{1,0.8,0.62};
/// a new motif instead of a variation of the last, a new progression
/// instead of the last, and each step's chance to change in a variation
/// (this one: the chance of a new motif)
pub const newMotifChance:f32=0.4;
/// the chance of a new progression
pub const newChords:f32=0.4;
/// each step's chance to change in a variation
pub const mutate:f32=0.25;
/// the phrase breathes out: its last two steps rest this often
pub const breathe:f32=0.7;
/// a chord: its root (semitones above the key), whether it is minor, and
/// its seventh (semitones above its root; 0 for none)
/// (fields: `root`, `minor`, `seventh`)
pub const Chord=struct{root:u8,minor:bool=false,seventh:u8=0};
/// the open chords of D Lydian, rising and never quite resolving: Imaj7 II
/// (the raised fourth's own chord), iii7, vi7, V
/// (this one: Imaj7)
const one:Chord=.{.root=0,.seventh=11};
/// II, major: the chord that makes Lydian Lydian
const two:Chord=.{.root=2};
/// iii7
const three:Chord=.{.root=4,.minor=true,.seventh=10};
/// vi7
const six:Chord=.{.root=9,.minor=true,.seventh=10};
/// V
const five:Chord=.{.root=7};
/// Imaj7 II Imaj7 II, vi7 II Imaj7 Imaj7, iii7 II Imaj7 V, Imaj7 vi7 II II
pub const progressions=[_][bars]Chord{
  .{one,two,one,two},
  .{six,two,one,one},
  .{three,two,one,five},
  .{one,six,two,two},
};
/// the left hand: each bar's root low (D3, roots above this many semitones
/// an octave lower), its fifth on the third beat this often, and how loud
/// (this one: the low root's MIDI note, D3)
pub const lowLevel:u8=50;
/// roots above this many semitones drop an octave
pub const lowFold:u8=4;
/// how often the fifth sounds on the third beat
pub const fifthChance:f32=0.6;
/// how often the ninth rings over it instead, left open
pub const ninthChance:f32=0.35;
/// how loud the left hand plays
pub const lowVel:f32=0.55;
/// the plunk: a struck string's partials (harmonics a little stretched,
/// as a piano's are), their levels, and a second string a hair sharp
/// beating against the first
/// (this one: how many partials)
pub const harmonics=5;
/// how much each partial is stretched sharp (grows with its number squared)
pub const stretch:f32=0.0004;
/// each partial's level
pub const harmonicLevel=[harmonics]f32{1,0.5,0.28,0.14,0.07};
/// the second string's pitch, a hair sharp (a ratio)
pub const detune:f32=1.0007;
/// the second string's level
pub const detuneLevel:f32=0.7;
/// how long it rings (s, ~63%) at this pitch (Hz), shorter for higher
/// notes and within these bounds; each higher partial dies this much faster
/// (this one: how long it rings at the reference pitch, s)
pub const plunkFall:f32=0.55;
/// the reference pitch (Hz)
pub const plunkRefHz:f32=400;
/// the shortest and longest it may ring (s)
pub const plunkFallSpan=[2]f32{0.22,1.3};
/// how much faster each higher partial dies
pub const plunkDamp:f32=0.9;
/// a softer note is this much duller (its partials fall by this power)
pub const dull:f32=0.7;
/// the felt hammer: a tick of noise this many times the pitch (Hz at most),
/// falling in this (s), at this level; the attack (s)
/// (this one: the tick's pitch, in multiples of the note's)
pub const hammerAt:f32=5;
/// the highest the tick may go (Hz)
pub const hammerHz:f32=4500;
/// how fast the tick falls (s)
pub const hammerFall:f32=0.004;
/// the tick's level
pub const hammer:f32=0.3;
/// the plunk's attack (s)
pub const plunkAttack:f32=0.0015;
/// what softens it (Hz), its loudness, and how many may ring at once
/// (this one: the low-pass that softens it, Hz)
pub const plunkSoftHz:f32=3600;
/// a plunk's loudness
pub const plunk:f32=0.032;
/// how many plunks may ring at once
pub const plunks=10;
/// the drum: a soft low tom on a bar's first step this often, on its third
/// beat this often (lighter); its pitch (Hz) dropping from the first to
/// the second in this (s), its fall (s), the skin's noise (Hz, fall, level)
/// (this one: how often it falls on a bar's first step)
pub const drumChance:f32=0.5;
/// how often it taps on the third beat
pub const tapChance:f32=0.12;
/// how loud that tap is
pub const tapVel:f32=0.5;
/// its pitch, from the strike to where it drops (Hz)
pub const drumHz=[2]f32{110,62};
/// how long the pitch drop takes (s)
pub const drumDrop:f32=0.05;
/// how long the drum rings (s)
pub const drumFall:f32=0.22;
/// the skin's noise band (Hz)
pub const skinHz:f32=220;
/// how fast the skin's noise falls (s)
pub const skinFall:f32=0.03;
/// the skin's noise level
pub const skin:f32=0.5;
/// what muffles it (Hz), its loudness, and how many may sound at once
/// (this one: the low-pass that muffles it, Hz)
pub const drumSoftHz:f32=700;
/// a drum's loudness
pub const drum:f32=0.06;
/// how many drums may sound at once
pub const drums=2;
/// a soft echo three steps behind, kept at a quarter of the rate (it is
/// dark anyway), feeding back this much, darkened (Hz) and at this level
/// (this one: how many steps behind)
pub const echoSteps:f32=3;
/// the share of the rate the echo is kept at (every fourth sample)
pub const echoDown=4;
/// how many samples the echo's line holds
pub const echoLen=m.floorTo(usize,echoSteps*stepS*m.f(rate)/echoDown)+4;
/// how much of the echo feeds back into itself
pub const echoFeedback:f32=0.3;
/// the low-pass that darkens it (Hz)
pub const echoSoftHz:f32=1800;
/// the echo's level
pub const echo:f32=0.35;
/// how fast the music follows the daylight (s); it plays only past this
/// (this one: the glide, s)
pub const musicGlide:f32=3;
/// the daylight the music plays above (0..1)
pub const musicFrom:f32=0.05;
/// the music's loudness (tests hush it to hear the rest alone)
pub const music:f32=1;
/// a MIDI note of the scale, `i` steps above the key
pub fn scaleNote(i:u8)u8{return@intCast(key+12*(i/scale.len)+scale[i%scale.len]);}
/// the note nearest `note` (within a whole tone) that is in `c`
pub fn chordTone(note:u8,c:Chord)u8{
  // the chord's third: minor or major
  const third:u8=if(c.minor)3 else 4;
  // the best note found, and how far from `note` it is
  var best=note;
  var dist:u8=3;
  for([_]u8{0,1,2})|d|for([_]u8{note-|d,note+d})|n|{
    // where `n` lies in the chord's scale, semitones above its root
    const in=(n+12-key%12+12-c.root)%12;
    if((in==0 or in==third or in==7 or (c.seventh!=0 and in==c.seventh)) and d<dist){
      best=n;
      dist=d;
    }
  };
  return best;
}
