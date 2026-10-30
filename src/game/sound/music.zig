//! the day's music playing: phrases of plunks over a slow pulse, fading with the light.
const lib = @import("../../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const dsp = engine.core.dsp;
const rng = engine.core.rng;
const BAR = lib.sound.score.BAR;
const BARS = lib.sound.score.BARS;
const BREATHE = lib.sound.score.BREATHE;
const Chord = lib.sound.score.Chord;
const DRUMS = lib.sound.score.DRUMS;
const DRUM_CHANCE = lib.sound.score.DRUM_CHANCE;
const Drum = lib.sound.voices.Drum;
const ECHO = lib.sound.score.ECHO;
const Echo = lib.sound.voices.Echo;
const FIFTH_CHANCE = lib.sound.score.FIFTH_CHANCE;
const LOW = lib.sound.score.LOW;
const LOW_FOLD = lib.sound.score.LOW_FOLD;
const LOW_VEL = lib.sound.score.LOW_VEL;
const MEL_HI = lib.sound.score.MEL_HI;
const MEL_LO = lib.sound.score.MEL_LO;
const MOTIF = lib.sound.score.MOTIF;
const MUSIC = lib.sound.score.MUSIC;
const MUSIC_FROM = lib.sound.score.MUSIC_FROM;
const MUSIC_GLIDE = lib.sound.score.MUSIC_GLIDE;
const MUTATE = lib.sound.score.MUTATE;
const NEW_CHORDS = lib.sound.score.NEW_CHORDS;
const NEW_MOTIF = lib.sound.score.NEW_MOTIF;
const NOTE_CHANCE = lib.sound.score.NOTE_CHANCE;
const NOTE_VEL = lib.sound.score.NOTE_VEL;
const PHRASE = lib.sound.score.PHRASE;
const PLUNKS = lib.sound.score.PLUNKS;
const PROGRESSIONS = lib.sound.score.PROGRESSIONS;
const Plunk = lib.sound.voices.Plunk;
const SILENT = lib.sound.SILENT;
const STEP_S = lib.sound.score.STEP_S;
const TAP_CHANCE = lib.sound.score.TAP_CHANCE;
const TAP_VEL = lib.sound.score.TAP_VEL;
const chordTone = lib.sound.score.chordTone;
const scaleNote = lib.sound.score.scaleNote;
const vary = lib.sound.footstep.vary;

/// samples the music renders at a time between its steps
const CHUNK = 256;

/// the day's music: light piano plunks over a slow steady pulse, a soft
/// drum now and then, fading in with the morning and out at dusk
pub const Music = struct {
  rate:f32,
  r:rng.Rng,
  plunks:[PLUNKS]?Plunk = @splat(null),
  drums:[DRUMS]?Drum = @splat(null),
  next_plunk:usize = 0,
  next_drum:usize = 0,
  echo:Echo,
  fade:dsp.Smooth,
  /// the step about to play, and samples until it does
  step:u32 = 0,
  left:u32 = 0,
  step_len:u32,
  chords:[BARS]Chord = PROGRESSIONS[0],
  /// scale steps (null rests) of the motif and of its variation
  motif:[MOTIF]?u8 = @splat(null),
  varied:[MOTIF]?u8 = @splat(null),
  fresh:bool = true,
  /// silent through the night: nothing rings, the next day starts a phrase
  resting:bool = true,
  /// notes and drums struck (tests count them)
  struck:u32 = 0,
  drummed:u32 = 0,
  level:f32 = MUSIC,

  pub fn init(r:*rng.Rng, rate:f32) Music {
    return .{
      .rate = rate,
      .r = .init(r.next()),
      .echo = .init(rate),
      .fade = .init(0, MUSIC_GLIDE, rate),
      .step_len = m.floorTo(u32, STEP_S * rate),
    };
  }

  pub fn daylight(mu:*Music, d:f32) void { mu.fade.target = if (d > MUSIC_FROM) m.clamp01(d) else 0; }

  pub fn render(mu:*Music, out:[]f32) void {
    if (mu.fade.target == 0 and mu.fade.value < SILENT) {
      if (!mu.resting) mu.rest();
      return;
    }
    mu.resting = false;
    var off:usize = 0;
    while (off < out.len) {
      const n = @min(CHUNK, out.len - off);
      var buf:[CHUNK]f32 = @splat(0);
      mu.chunk(buf[0..n]);
      for (out[off..][0..n], buf[0..n]) |*o, x| o.* += x;
      off += n;
    }
  }

  pub fn rest(mu:*Music) void {
    mu.plunks = @splat(null);
    mu.drums = @splat(null);
    mu.echo = .init(mu.rate);
    mu.step = 0;
    mu.left = 0;
    mu.resting = true;
  }

  /// plays `buf` (zeroed) out, striking each step as it comes
  pub fn chunk(mu:*Music, buf:[]f32) void {
    var i:usize = 0;
    while (i < buf.len) {
      if (mu.left == 0) {
        mu.strikeStep();
        mu.left = mu.step_len;
      }
      const n:u32 = @intCast(@min(mu.left, buf.len - i));
      const part = buf[i..][0..n];
      for (&mu.plunks) |*v| if (v.*) |*p| {
        if (!p.render(part)) v.* = null;
      };
      for (&mu.drums) |*v| if (v.*) |*d| {
        if (!d.render(part)) v.* = null;
      };
      mu.left -= n;
      i += n;
    }
    for (buf) |*s| s.* = (s.* + ECHO * mu.echo.tick(s.*)) * mu.level * mu.fade.next();
  }

  pub fn strikeStep(mu:*Music) void {
    if (mu.step == 0) mu.phrase();
    const bar = mu.step / BAR;
    const s = mu.step % BAR;
    const c = mu.chords[bar];
    const at:usize = if (s == 0) 0 else if (s % 2 == 0) 1 else 2;
    const line = if (mu.step < MOTIF) mu.motif else mu.varied;
    if (line[mu.step % MOTIF]) |i| {
      const n = scaleNote(i);
      mu.plunk(if (s == 0) chordTone(n, c) else n, vary(&mu.r, NOTE_VEL[at]));
    }
    const low = LOW + c.root - (if (c.root > LOW_FOLD) @as(u8, 12) else 0);
    if (s == 0) mu.plunk(low, vary(&mu.r, LOW_VEL));
    if (s == BAR / 2 and mu.r.float() < FIFTH_CHANCE) mu.plunk(low + 7, vary(&mu.r, LOW_VEL * 0.8));
    if (s == 0 and mu.r.float() < DRUM_CHANCE) mu.drum(1);
    if (s == BAR / 2 and mu.r.float() < TAP_CHANCE) mu.drum(TAP_VEL);
    mu.step = (mu.step + 1) % PHRASE;
  }

  /// a new phrase: maybe new chords, a new motif or a variation of the last
  pub fn phrase(mu:*Music) void {
    if (mu.r.float() < NEW_CHORDS) mu.chords = PROGRESSIONS[mu.r.below(PROGRESSIONS.len)];
    if (mu.fresh or mu.r.float() < NEW_MOTIF) {
      mu.motif = mu.newMotif();
      mu.fresh = false;
    } else mu.motif = mu.alter(mu.varied);
    mu.varied = mu.alter(mu.motif);
    if (mu.r.float() < BREATHE) {
      mu.varied[MOTIF - 2] = null;
      mu.varied[MOTIF - 1] = null;
    }
  }

  /// a wandering line: small steps up and down the scale, mostly on beats
  pub fn newMotif(mu:*Music) [MOTIF]?u8 {
    var out:[MOTIF]?u8 = undefined;
    var i:u8 = @intCast(MEL_LO + 2 + mu.r.below(MEL_HI - MEL_LO - 3));
    for (&out, 0..) |*o, k| {
      const s = k % BAR;
      const at:usize = if (s == 0) 0 else if (s % 2 == 0) 1 else 2;
      if (mu.r.float() >= NOTE_CHANCE[at]) {
        o.* = null;
        continue;
      }
      i = mu.wander(i, 2);
      o.* = i;
    }
    return out;
  }

  /// `line` with some of its steps changed: a note moved a step, dropped,
  /// or a rest filled
  pub fn alter(mu:*Music, line:[MOTIF]?u8) [MOTIF]?u8 {
    var out = line;
    var last:u8 = MEL_LO + (MEL_HI - MEL_LO) / 2;
    for (&out) |*o| {
      if (mu.r.float() < MUTATE) o.* = if (o.*) |i| (if (mu.r.float() < 0.3) null else mu.wander(i, 1)) else mu.wander(last, 1);
      if (o.*) |i| last = i;
    }
    return out;
  }

  /// `i` moved up to `by` steps either way, kept in the melody's range
  pub fn wander(mu:*Music, i:u8, by:u8) u8 {
    const d:i32 = @as(i32, @intCast(mu.r.below(2 * by + 1))) - by;
    return @intCast(m.clamp(@as(i32, i) + d, MEL_LO, MEL_HI));
  }

  pub fn plunk(mu:*Music, note:u8, vel:f32) void {
    mu.plunks[mu.freePlunk()] = .init(note, vel, &mu.r, mu.rate);
    mu.struck += 1;
  }

  pub fn drum(mu:*Music, vel:f32) void {
    mu.drums[mu.next_drum] = .init(vel, &mu.r, mu.rate);
    mu.next_drum = (mu.next_drum + 1) % DRUMS;
    mu.drummed += 1;
  }

  pub fn freePlunk(mu:*Music) usize {
    for (mu.plunks, 0..) |v, i| if (v == null) return i;
    defer mu.next_plunk = (mu.next_plunk + 1) % PLUNKS;
    return mu.next_plunk;
  }
};
