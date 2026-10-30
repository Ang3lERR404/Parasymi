//! the garden's sounds rendered offline and measured.
const lib = @import("../../lib.zig");
const std = lib.std;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const rng = engine.core.rng;
const Footfall = lib.player.Footfall;
const VOICES = lib.sound.VOICES;
const BAR = lib.sound.score.BAR;
const DEEP = lib.sound.sap.DEEP;
const MEL_HI = lib.sound.score.MEL_HI;
const MEL_LO = lib.sound.score.MEL_LO;
const MOTIF = lib.sound.score.MOTIF;
const Music = lib.sound.music.Music;
const PINGS = lib.sound.twinkle.PINGS;
const STEP_S = lib.sound.score.STEP_S;
const Settle = lib.sound.sap.Settle;
const Sounds = lib.sound.mixer.Sounds;
const WHISTLE_FROM = lib.sound.wind.WHISTLE_FROM;
const chordTone = lib.sound.score.chordTone;

const TEST_RATE:f32 = 48000;

/// one step rendered alone: its peak, its loudness (rms) and how long it
/// sounds (s)
fn hear(f:Footfall, seed:u64) struct { peak:f32, rms:f32, len:f32 } {
  var s:Sounds = .init(seed, TEST_RATE);
  s.wind.level = 0;
  s.apply(.{.step = f});
  var buf:[480]f32 = undefined;
  var peak:f32 = 0;
  var sum:f32 = 0;
  var n:u32 = 0;
  while (s.steps[0] != null and n < 48000) {
    @memset(&buf, 0);
    s.render(&buf);
    for (buf) |x| {
      peak = @max(peak, @abs(x));
      sum += x * x;
    }
    n += buf.len;
  }
  return .{.peak = peak, .rms = @sqrt(sum / m.f(n)), .len = m.f(n) / TEST_RATE};
}

test "a footstep is short, soft and never clips; a sprint is louder" {
  const soft = hear(.{.weight = 0, .pace = 0.3}, 1);
  const fast = hear(.{.weight = 0, .pace = 1}, 1);
  const full = hear(.{.weight = 1, .pace = 0.3}, 1);
  for ([_]@TypeOf(soft){soft, fast, full}) |h| {
    try testing.expect(h.peak > 0.02 and h.peak < 0.8);
    try testing.expect(h.len > 0.1 and h.len < 0.8);
  }
  try testing.expect(fast.rms > soft.rms);
  try testing.expect(fast.len < soft.len);
}

test "steps vary, a busy pool steals the oldest, and it ends silent" {
  var s:Sounds = .init(9, TEST_RATE);
  s.wind.level = 0;
  for (0..VOICES + 2) |_| s.apply(.{.step = .{.weight = 0.5, .pace = 0.5}});
  for (s.steps) |v| try testing.expect(v != null);
  try testing.expect(s.steps[0].?.gain != s.steps[1].?.gain);
  var buf:[480]f32 = undefined;
  for (0..200) |_| {
    @memset(&buf, 0);
    s.render(&buf);
  }
  for (s.steps) |v| try testing.expect(v == null);
  for (buf) |x| try testing.expectEqual(@as(f32, 0), x);
}

test "the sap settles only in the eyes, softly, and fades out with the view" {
  var s:Sounds = .init(3, TEST_RATE);
  s.wind.level = 0;
  var buf:[480]f32 = undefined;
  // a minute out of the eyes: nothing
  for (0..6000) |_| {
    @memset(&buf, 0);
    s.render(&buf);
    for (buf) |x| try testing.expectEqual(@as(f32, 0), x);
  }
  s.apply(.{.eyes = true});
  var peak:f32 = 0;
  var settles:u32 = 0;
  var was = false;
  for (0..3000) |_| {
    @memset(&buf, 0);
    s.render(&buf);
    for (buf) |x| peak = @max(peak, @abs(x));
    if (s.settle != null and !was) settles += 1;
    was = s.settle != null;
  }
  // half a minute standing in the eyes settles a few times, softly
  try testing.expect(settles >= 2 and settles <= 6);
  try testing.expect(peak > 0.01 and peak < 0.3);
  s.apply(.{.eyes = false});
  for (0..400) |_| {
    @memset(&buf, 0);
    s.render(&buf);
  }
  try testing.expect(s.settle == null);
  for (buf) |x| try testing.expectEqual(@as(f32, 0), x);
}

test "now and then a settling has lighter gloops" {
  var r:rng.Rng = .init(21);
  var light:u32 = 0;
  for (0..200) |_| {
    const st:Settle = .init(0.5, &r, TEST_RATE);
    if (st.gloops[DEEP.n[1]].start != m.maxInt(u32)) light += 1;
  }
  try testing.expect(light > 20 and light < 90);
}

test "a twinkle is a few soft high pings, louder the nearer, and ends" {
  var peaks:[2]f32 = undefined;
  for ([_]f32{0.1, 1}, &peaks) |near, *peak| {
    var s:Sounds = .init(11, TEST_RATE);
    s.wind.level = 0;
    s.apply(.{.twinkle = .{.near = near}});
    try testing.expect(s.twinkles[0].?.n >= PINGS[0] and s.twinkles[0].?.n <= PINGS[1]);
    var buf:[480]f32 = undefined;
    peak.* = 0;
    var n:u32 = 0;
    while (s.twinkles[0] != null and n < 4 * 48000) : (n += buf.len) {
      @memset(&buf, 0);
      s.render(&buf);
      for (buf) |x| peak.* = @max(peak.*, @abs(x));
    }
    try testing.expect(s.twinkles[0] == null);
    const len = m.f(n) / TEST_RATE;
    try testing.expect(len > 0.5 and len < 3.5);
  }
  try testing.expect(peaks[0] > 0.002 and peaks[1] < 0.1 and peaks[1] > 2 * peaks[0]);
}

test "the wind is gentle, swells in gusts and whistles only in some" {
  var s:Sounds = .init(5, TEST_RATE);
  var buf:[4800]f32 = undefined;
  var peak:f32 = 0;
  var lo:f32 = 1;
  var hi:f32 = 0;
  var whistled:u32 = 0;
  // a minute, a tenth of a second at a time
  for (0..600) |_| {
    @memset(&buf, 0);
    s.render(&buf);
    var sum:f32 = 0;
    for (buf) |x| {
      peak = @max(peak, @abs(x));
      sum += x * x;
    }
    const rms = @sqrt(sum / m.f(buf.len));
    lo = @min(lo, rms);
    hi = @max(hi, rms);
    if (s.wind.gust.value > WHISTLE_FROM + 0.2) whistled += 1;
  }
  try testing.expect(peak > 0.005 and peak < 0.15);
  try testing.expect(lo > 0.0005 and hi > 2 * lo);
  try testing.expect(whistled > 10 and whistled < 400);
}

test "the music is silent at night and plays softly by day, on a steady pulse" {
  var s:Sounds = .init(17, TEST_RATE);
  s.wind.level = 0;
  var buf:[480]f32 = undefined;
  // ten seconds of night: nothing
  for (0..1000) |_| {
    @memset(&buf, 0);
    s.render(&buf);
    for (buf) |x| try testing.expectEqual(@as(f32, 0), x);
  }
  try testing.expectEqual(@as(u32, 0), s.music.struck);
  s.apply(.{.daylight = 1});
  var peak:f32 = 0;
  // two minutes of day
  const secs = 120;
  for (0..secs * 100) |_| {
    @memset(&buf, 0);
    s.render(&buf);
    for (buf) |x| peak = @max(peak, @abs(x));
  }
  try testing.expect(peak > 0.02 and peak < 0.35);
  // steps of the pulse that passed: notes on many of them, a drum on some bars
  const steps = m.f(secs) / STEP_S;
  try testing.expect(m.f(s.music.struck) > 0.5 * steps and m.f(s.music.struck) < 1.5 * steps);
  const bars = steps / BAR;
  try testing.expect(m.f(s.music.drummed) > 0.25 * bars and m.f(s.music.drummed) < 0.8 * bars);
  // dusk: it fades out and rests
  s.apply(.{.daylight = 0});
  for (0..3000) |_| {
    @memset(&buf, 0);
    s.render(&buf);
  }
  try testing.expect(s.music.resting);
  for (buf) |x| try testing.expectEqual(@as(f32, 0), x);
}

test "a phrase's second half varies its first, and melody stays in range" {
  var r:rng.Rng = .init(4);
  var mu:Music = .init(&r, TEST_RATE);
  for (0..50) |_| {
    mu.phrase();
    var same:u32 = 0;
    for (mu.motif, mu.varied) |a, b| {
      if (a) |i| try testing.expect(i >= MEL_LO and i <= MEL_HI);
      if (std.meta.eql(a, b)) same += 1;
    }
    try testing.expect(same >= MOTIF / 2);
  }
  // a bar's first note sits in its chord
  try testing.expectEqual(@as(u8, 62), chordTone(63, .{.root = 0}));
  try testing.expectEqual(@as(u8, 71), chordTone(72, .{.root = 9, .minor = true}));
}
