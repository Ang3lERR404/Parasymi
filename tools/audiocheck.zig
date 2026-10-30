//! the sound path end to end, on this machine's speakers: a `dsp.Voice` played
//! through `platform.audio.Output` and recorded back by WASAPI loopback, then
//! a single-bin DFT (Goertzel) asks whether the energy came back at its
//! pitch. Exits with an error when it did not.
/// the standard library
const std=@import("std");
/// the engine package: the voice, the output and WASAPI
const engine=@import("engine");
/// the Windows audio binding, for recording back by loopback
const wasapi=engine.wasapi;
/// all the maths: tau, casts, clamps
const m=engine.core.math;
/// the sound makers: the voice that plays the tone
const dsp=engine.core.dsp;
/// the audio output, which feeds the device from its own thread
const audio=engine.platform.audio;
/// the note played, Hz
const toneHz:f32=440;
/// the pitches that must stay quiet: an octave either side and well above
const others=[_]f32{toneHz/2,toneHz*2,3000};
/// how much louder the tone must be than any of them (~26 dB)
const margin=20;
/// the softest the tone may come back (the voice plays at ~0.14 before the
/// endpoint's own volume)
const minLevel=0.01;
/// seconds to wait for a device to stream, or for one read of the recording
const waitS=5;
/// how long (ms) the tone's release is waited out before it is measured
const releaseMs=500;
/// plays a 440 Hz tone, records a second of it back by loopback and checks
/// it came back loud enough and well above an octave either side and 3 kHz;
/// prints each level and fails with `ToneNotHeard` if not
pub fn main(init:std.process.Init)!void{
  // the general allocator, and the I/O everything is done through
  const gpa=init.gpa;
  const io=init.io;
  // recording starts first so the tone's start isn't missed
  const cap=try wasapi.Capture.open(gpa,io,.{.name="parasymi audiocheck",.source=.loopback});
  defer cap.close(io);
  if(!try cap.waitStreaming(io,timeout(waitS)))return error.NotStreaming;
  // the recording's sample rate (Hz) and channel count
  const rate=cap.rate();
  const ch=cap.channels();
  // the voice playing on the speakers, at the recording's rate
  const out=try audio.Output(dsp.Voice).open(gpa,io,.init(m.f(rate),.sine),.{.name="parasymi audiocheck",.rate=rate});
  defer out.close(gpa,io);
  try out.send(.{.play=toneHz});
  // one second of interleaved recording
  const rec=try gpa.alloc(f32,@as(usize,rate)*ch);
  defer gpa.free(rec);
  // how many frames have come back so far
  var got:usize=0;
  while(got*ch<rec.len){
    // the frames this read brought back (none: the device has gone quiet)
    const n=try cap.readAll(io,rec[got*ch..],timeout(waitS));
    if(n==0)break;
    got+=n;
  }
  try out.send(.stop);
  try io.sleep(.fromMilliseconds(releaseMs),.awake);
  // the frames recorded, and the tone's level in them
  const r=rec[0..got*ch];
  const tone=level(r,ch,toneHz,rate);
  std.debug.print("{d} Hz, {d} ch, {d} frames, {d} underruns\n{d} Hz: {d:.4}\n",.{rate,ch,got,out.underruns(),toneHz,tone});
  // whether the tone was heard, loud enough and with no underruns
  var ok=tone>=minLevel and out.underruns()==0;
  for(others)|hz|{
    // the level at this pitch that should stay quiet
    const l=level(r,ch,hz,rate);
    std.debug.print("{d} Hz: {d:.4}\n",.{hz,l});
    if(tone<l*margin)ok=false;
  }
  if(!ok)return error.ToneNotHeard;
  std.debug.print("ok\n",.{});
}
/// the amplitude of `hz` in channel 0 of interleaved audio (Goertzel)
fn level(x:[]const f32,ch:u16,hz:f32,rate:u32)f32{
  // the Goertzel filter's coefficient for `hz`
  const c:f64=2*@cos(m.tau*hz/m.f(rate));
  // the filter's last two states
  var s1:f64=0;
  var s2:f64=0;
  // how many samples were filtered, and where in the buffer
  var n:u32=0;
  var i:usize=0;
  while(i<x.len):(i+=ch){
    // the filter's newest state
    const s=x[i]+c*s1-s2;
    s2=s1;
    s1=s;
    n+=1;
  }
  if(n==0)return 0;
  // the energy left at `hz` (never below zero)
  const power:f32=@floatCast(@max(0,s1*s1+s2*s2-c*s1*s2));
  return@sqrt(power)/m.f(n)*2;
}
/// a wait of `s` seconds on the awake clock
fn timeout(s:i64)std.Io.Timeout{return.{.duration=.{.raw=.fromSeconds(s),.clock=.awake}};}
