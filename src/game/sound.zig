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
//!   (now and then a lighter, smaller one or two among them), all muffled. It settles more often while the wolf stands; a full belly
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
//!   pentatonic line over a soft left hand, phrased as a motif and its
//!   variation over a slow chord progression, a soft low drum on some bars,
//!   all with a dark echo three steps behind; it rises with the morning and
//!   fades out at dusk.
const lib = @import("../lib.zig");
const std = lib.std;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const dsp = engine.core.dsp;
const rng = engine.core.rng;
const Footfall = lib.player.Footfall;
pub const footstep = @import("sound/footstep.zig");
pub const sap = @import("sound/sap.zig");
pub const wind = @import("sound/wind.zig");
pub const twinkle = @import("sound/twinkle.zig");
pub const score = @import("sound/score.zig");
pub const voices = @import("sound/voices.zig");
pub const music = @import("sound/music.zig");
pub const mixer = @import("sound/mixer.zig");
pub const arsthraxia = @import("sound/arsthraxia.zig");
pub const boom = @import("sound/boom.zig");
pub const tests = @import("sound/tests.zig");
pub const Sounds = mixer.Sounds;

/// samples per second the sounds are built for (a device that will not
/// play at it leaves the garden silent)
pub const RATE:u32 = 48000;
/// steps that may sound at once (a sprint overlaps two or three)
pub const VOICES = 64;
/// a step quieter than this has ended and frees its voice
pub const SILENT:f32 = 1e-4;

test {
  _ = footstep;
  _ = sap;
  _ = wind;
  _ = twinkle;
  _ = score;
  _ = voices;
  _ = music;
  _ = mixer;
  _ = arsthraxia;
  _ = boom;
  _ = tests;
}
