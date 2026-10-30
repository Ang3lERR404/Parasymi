//! what the garden sounds like: the source the audio device plays (main.zig
//! opens it on `platform.audio.Output`). The game sends it what happened
//! (`Cmd`) and each sound plays out on a free voice of its pool, nothing
//! allocated while it plays.
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
//! - by day, music: light piano plunks (felt-hammered strings, a little
//!   stretched and beating) on a steady eighth-note pulse, a wandering
//!   Lydian line (its raised fourth the sound of wonder) over a soft left
//!   hand, phrased as a motif and its variation over open chords (major
//!   sevenths, the Lydian II, ninths left ringing), a soft low drum on some bars,
//!   all with a dark echo three steps behind; it rises with the morning and
//!   fades out at dusk.
//! - by night, music: open chords swelling slowly on soft bowed strings,
//!   glass chimes glistening two and three octaves over them (now and then
//!   a glint of them run quickly down), a far choir singing "oo", scooping
//!   up into a chord tone held two bars; it rises with the dusk and fades
//!   out at dawn.
//! - while the arsthraxia works, a spinning whorl hums under a choir that
//!   swells with its progress; when it completes, a pop drops into a deep
//!   thud and a fracturing shimmer rings out.
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
/// the night's instruments: glass chimes, bowed strings, a far choir
pub const nightVoices=@import("sound/night_voices.zig");
/// the night's music played out, rising with the dusk
pub const night=@import("sound/night.zig");
/// every sound's voices mixed into one stream for the device
pub const mixer=@import("sound/mixer.zig");
/// the arsthraxia's working: whorl and swelling choir
pub const arsthraxia=@import("sound/arsthraxia.zig");
/// the arsthraxia's completion: pop, thud and shimmer
pub const boom=@import("sound/boom.zig");
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
  _=night;
  _=mixer;
  _=arsthraxia;
  _=boom;
  _=tests;
}
