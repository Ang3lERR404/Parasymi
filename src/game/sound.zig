//! what the garden sounds like: the source the audio device plays (main.zig
//! opens it on `platform.audio.Output`). The game sends it what happened
//! (`Cmd`) and each sound plays out on a free voice of its pool, nothing
//! allocated while it plays.
//! - all of it is heard in stereo, from the view (told each frame as an
//!   `ear`: the wolf it follows, turned as the view turns, or the eyes it
//!   looks out of): a step under the paw that fell, a twinkle where its mote
//!   is and the arsthraxia where it stands (following as the view turns),
//!   each left or right as it lies, quieter and darker the farther off,
//!   shaded behind, notched higher the higher it is, muffled when a hill
//!   hides it, and ringing in the echo of the place the ear is in (short and
//!   faint in an open meadow, long and full in a hollow, fuller among
//!   structures; told each frame as a `space`); the sap's gloops rise here and there inside
//!   the wolf round its groan; the wind's hush is two streams of air, its
//!   whistle drifting from side to side gust by gust; the piano spreads low
//!   to high from left to right, the drums stand on a stage (taiko by the
//!   middle, timpani left, the cymbal's metal wide on the right), the
//!   strings sit high to the left and low to the right, each player in its
//!   own seat, the choir stands sopranos to basses left to right, each
//!   section in two halves; the hall's tail spreads wide round both; the
//!   unforming's glass breaks and rains from all round, its drone and seam
//!   beating between the speakers, its seed falling and landing in the middle.
//! - a footstep is a soft crunchy rustle: leaf litter shuffled under a paw
//!   (band-passed noise fluttering like leaves), dry bits crushed in it (a
//!   crackle, thick at the footfall and thinning as it fades) and a muffled
//!   pad landing under both. The heavier the wolf the lower and fuller, the
//!   faster the louder and shorter; no two steps are alike.
//! - out of the wolf's eyes (first person) its sap is heard settling now and
//!   then, from inside: a soft slow groan, a low reedy hum through a closing
//!   throat sagging as it sinks, with a few thick gloops rising through it
//!   (now and then a lighter, smaller one or two among them), all muffled.
//!   It settles more often while the wolf stands; a full belly
//!   groans lower.
//! - all the while a gentle wind breathes over the garden: a soft low hush
//!   swelling and easing in slow gusts, and in the stronger ones a warm,
//!   breathy whistle (low, soft-edged banded air with a rounder octave
//!   under it) leaning up a little with the gust.
//! - a mote of starlight near the wolf twinkles now and then: a few tiny
//!   glassy pings in quick succession (high bell partials, a little
//!   out of tune with each other), dying away in a soft shimmer; the
//!   nearer the mote, the louder.
//! - by day, music: a full piano (felt-hammered strings, a little
//!   stretched and beating, low and long-ringing) on a steady eighth-note
//!   pulse driven by great taiko, timpani rolled up into each phrase and a
//!   cymbal swelling to crash on its first step; a wandering
//!   Lydian line (its raised fourth the sound of wonder) over a soft left
//!   hand, phrased as a motif and its variation over open chords (major
//!   sevenths, the Lydian II, ninths left ringing); it rises with the
//!   morning and fades out at dusk.
//! - by night, music: a choir of sopranos, altos, tenors and basses, eight
//!   voices each, singing "ahh" through slow open chords, each section
//!   gliding to its nearest note of the next and swelling through each
//!   phrase, strings bowing the chords under it; it rises with the dusk and
//!   fades out at dawn.
//! - both musics ring in a great stone hall.
//! - while the arsthraxia works, its flower thinks aloud: its two whorls
//!   sing like wet fingers round glass rims, each two tones a hair apart
//!   swelling against each other as the whorls turn; a low thrum rises
//!   through each pulse of thought climbing its nerves; airy wisps are
//!   breathed in to its core, and a soft low hum swells as the unit
//!   condenses. Fed, it is brighter, quicker and a little louder. When a
//!   unit is done a soft bell chord in the music's key blooms upward over a
//!   warm low note, and a breath rushes up its stems with the surge of light.
//! - the unforming (the first world event), all in D Lydian and soft: a low
//!   D swells under it, beating slowly, and the music gives way to it;
//!   glass rains as the sky shatters, as thick as the front sweeping down;
//!   each radiant plant breaks with a snap and a scatter of glints, the
//!   stars and the ley nodes likewise; the ley lines hum shut, a seam
//!   sinking an octave; dry ash crumbles as the old lineages wither; each
//!   shard reaching the star rings a step higher; the seed whistles down
//!   and lands with a deep soft bell, a thump under it and a glass chord
//!   ringing up over it, the drone fading after.
/// the hub every game module is reached through
const lib=@import("../lib.zig");
/// the footstep: a soft crunchy rustle under a paw
pub const footstep=@import("sound/footstep.zig");
/// the sap settling, heard from inside the wolf
pub const sap=@import("sound/sap.zig");
/// the gentle wind over the garden
pub const wind=@import("sound/wind.zig");
/// a mote of starlight's glassy twinkle
pub const twinkle=@import("sound/twinkle.zig");
/// the daytime music's score: its chords, motif and phrasing
pub const score=@import("sound/score.zig");
/// the piano's voices: felt-hammered strings and the soft drum
pub const voices=@import("sound/voices.zig");
/// the daytime music played out, rising and fading with the light
pub const music=@import("sound/music.zig");
/// the night's strings: a soft ensemble bowing each note
pub const nightVoices=@import("sound/night_voices.zig");
/// the night's choir: four sections singing "ahh"
pub const choir=@import("sound/choir.zig");
/// the day's drums: taiko, timpani, cymbal
pub const drums=@import("sound/drums.zig");
/// the night's music played out, rising with the dusk
pub const night=@import("sound/night.zig");
/// every sound's voices mixed into one stream for the device
pub const mixer=@import("sound/mixer.zig");
/// the arsthraxia's working: glass whorls, thrum, wisps and core
pub const arsthraxia=@import("sound/arsthraxia.zig");
/// the arsthraxia's unit done: a bell chord blooming and a breath rushing up
pub const bloom=@import("sound/bloom.zig");
/// the unforming heard: drone, glass, seam, ash, whistle and landing bell
pub const unforming=@import("sound/unforming.zig");
/// the sounds' headless tests
pub const tests=@import("sound/tests.zig");
/// the source the audio device pulls from
pub const Sounds=mixer.Sounds;
/// samples per second the sounds are built for (a device that will not
/// play at it leaves the garden silent)
pub const rate:u32=48000;
/// footsteps that may sound at once (a sprint overlaps two or three)
pub const voiceCount=64;
/// a sound quieter than this has ended and frees its voice
pub const silent:f32=1e-4;
test{
  _=footstep;
  _=sap;
  _=wind;
  _=twinkle;
  _=score;
  _=voices;
  _=music;
  _=nightVoices;
  _=choir;
  _=drums;
  _=night;
  _=mixer;
  _=arsthraxia;
  _=bloom;
  _=unforming;
  _=tests;
}
