//! the sound path end to end, on this machine's speakers: a `dsp.Voice` played
//! through `platform.audio.Output` and recorded back by WASAPI loopback, then
//! a single-bin DFT (Goertzel) asks whether the energy came back at its
//! pitch, and on the side it was panned to: hard left, then hard right.
//! Exits with an error when it did not.
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
/// how much louder the tone must be than any of them, and on its own side
/// than on the other (~26 dB)
const margin=20;
/// the softest the tone may come back (the voice plays at ~0.14 before the
/// endpoint's own volume)
const minLevel=0.01;
/// seconds to wait for a device to stream, or for one read of the recording
const waitS=5;
/// how long (ms) the tone's release is waited out between the two sides
const releaseMs=500;
/// how much is recorded each side (s), and how much of its start is left
/// unheard: what the loopback still held of the side before
/// (this one: recorded)
const recordS:f32=1.5;
/// (left unheard)
const skipS:f32=0.5;
/// plays a 440 Hz tone panned hard left and then hard right, records each
/// back by loopback and checks it came back loud enough, well above an
/// octave either side and 3 kHz, and well above what the other side heard
/// (on a mono endpoint, only the first two); prints each level and fails
/// with `ToneNotHeard` if not
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
  // a side's interleaved recording, reused for each
  const rec=try gpa.alloc(f32,m.floorTo(usize,recordS*m.f(rate))*ch);
  defer gpa.free(rec);
  std.debug.print("{d} Hz, {d} ch\n",.{rate,ch});
  // whether everything was heard as it should be
  var ok=true;
  for([_]f32{-1,1},0..)|pan,side|{
    try out.send(.{.pan=pan});
    try out.send(.{.play=toneHz});
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
    // the frames heard (past what the loopback still held), the channel
    // the tone should be on and the one it should not
    const skip=@min(m.floorTo(usize,skipS*m.f(rate)),got);
    const r=rec[skip*ch..got*ch];
    const near:u16=if(ch<2)0 else@intCast(side);
    const tone=level(r,ch,near,toneHz,rate);
    std.debug.print("{s}: {d} frames, {d} Hz: {d:.4}\n",.{if(side==0)"left"else"right",got-skip,toneHz,tone});
    if(tone<minLevel)ok=false;
    for(others)|hz|{
      // the level at this pitch that should stay quiet
      const l=level(r,ch,near,hz,rate);
      std.debug.print("  {d} Hz: {d:.4}\n",.{hz,l});
      if(tone<l*margin)ok=false;
    }
    if(ch>=2){
      // what the other side heard of it
      const l=level(r,ch,1-near,toneHz,rate);
      std.debug.print("  other side: {d:.4}\n",.{l});
      if(tone<l*margin)ok=false;
    }
  }
  std.debug.print("{d} underruns\n",.{out.underruns()});
  if(!ok or out.underruns()!=0)return error.ToneNotHeard;
  std.debug.print("ok\n",.{});
}
/// the amplitude of `hz` in channel `c` of interleaved audio of `ch`
/// channels (Goertzel)
fn level(x:[]const f32,ch:u16,c:u16,hz:f32,rate:u32)f32{
  // the Goertzel filter's coefficient for `hz`
  const k:f64=2*@cos(m.tau*hz/m.f(rate));
  // the filter's last two states
  var s1:f64=0;
  var s2:f64=0;
  // how many samples were filtered, and where in the buffer
  var n:u32=0;
  var i:usize=c;
  while(i<x.len):(i+=ch){
    // the filter's newest state
    const s=x[i]+k*s1-s2;
    s2=s1;
    s1=s;
    n+=1;
  }
  if(n==0)return 0;
  // the energy left at `hz` (never below zero)
  const power:f32=@floatCast(@max(0,s1*s1+s2*s2-k*s1*s2));
  return@sqrt(power)/m.f(n)*2;
}
/// a wait of `s` seconds on the awake clock
fn timeout(s:i64)std.Io.Timeout{return.{.duration=.{.raw=.fromSeconds(s),.clock=.awake}};}
