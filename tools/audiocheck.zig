//! the sound path end to end, on this machine's speakers: a `dsp.Voice` played
//! through `platform.audio.Output` and recorded back by WASAPI loopback, then
//! a single-bin DFT (Goertzel) asks whether the energy came back at its
//! pitch. Exits with an error when it did not.
const std = @import("std");
const engine = @import("engine");
const wasapi = engine.wasapi;
const m = engine.core.math;
const dsp = engine.core.dsp;
const audio = engine.platform.audio;

/// the note played, Hz
const TONE:f32 = 440;
/// the pitches that must stay quiet: an octave either side and well above
const OTHERS = [_]f32{TONE / 2, TONE * 2, 3000};
/// how much louder the tone must be than any of them (~26 dB)
const MARGIN = 20;
/// the softest the tone may come back (the voice plays at ~0.14 before the
/// endpoint's own volume)
const MIN_LEVEL = 0.01;
/// seconds to wait for a device, and to wait out the release
const WAIT_S = 5;
const RELEASE_MS = 500;

pub fn main(init:std.process.Init) !void {
  const gpa = init.gpa;
  const io = init.io;
  // recording starts first so the tone's start isn't missed
  const cap = try wasapi.Capture.open(gpa, io, .{.name = "parasymi audiocheck", .source = .loopback});
  defer cap.close(io);
  if (!try cap.waitStreaming(io, timeout(WAIT_S))) return error.NotStreaming;
  const rate = cap.rate();
  const ch = cap.channels();

  const out = try audio.Output(dsp.Voice).open(gpa, io, .init(m.f(rate), .sine), .{.name = "parasymi audiocheck", .rate = rate});
  defer out.close(gpa, io);
  try out.send(.{.play = TONE});

  // one second
  const rec = try gpa.alloc(f32, @as(usize, rate) * ch);
  defer gpa.free(rec);
  var got:usize = 0;
  while (got * ch < rec.len) {
    const n = try cap.readAll(io, rec[got * ch ..], timeout(WAIT_S));
    if (n == 0) break;
    got += n;
  }
  try out.send(.stop);
  try io.sleep(.fromMilliseconds(RELEASE_MS), .awake);

  const r = rec[0 .. got * ch];
  const tone = level(r, ch, TONE, rate);
  std.debug.print("{d} Hz, {d} ch, {d} frames, {d} underruns\n{d} Hz: {d:.4}\n", .{rate, ch, got, out.underruns(), TONE, tone});
  var ok = tone >= MIN_LEVEL and out.underruns() == 0;
  for (OTHERS) |hz| {
    const l = level(r, ch, hz, rate);
    std.debug.print("{d} Hz: {d:.4}\n", .{hz, l});
    if (tone < l * MARGIN) ok = false;
  }
  if (!ok) return error.ToneNotHeard;
  std.debug.print("ok\n", .{});
}

/// the amplitude of `hz` in channel 0 of interleaved audio (Goertzel)
fn level(x:[]const f32, ch:u16, hz:f32, rate:u32) f32 {
  const c:f64 = 2 * @cos(m.tau * hz / m.f(rate));
  var s1:f64 = 0;
  var s2:f64 = 0;
  var n:u32 = 0;
  var i:usize = 0;
  while (i < x.len) : (i += ch) {
    const s = x[i] + c * s1 - s2;
    s2 = s1;
    s1 = s;
    n += 1;
  }
  if (n == 0) return 0;
  const power:f32 = @floatCast(@max(0, s1 * s1 + s2 * s2 - c * s1 * s2));
  return @sqrt(power) / m.f(n) * 2;
}

fn timeout(s:i64) std.Io.Timeout { return .{.duration = .{.raw = .fromSeconds(s), .clock = .awake}}; }
