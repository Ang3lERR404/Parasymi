//! the tools' sound files and spectra, shared by the ear (tools/hear.zig),
//! the voice (tools/speak.zig) and Claude's own ear (tools/ownear.zig):
//! a fast Fourier transform, 16-bit WAVs written and read (any WAV
//! Audacity writes, read as mono), and resampling between rates.
/// the standard library
const std=@import("std");
/// the engine package: the maths
const engine=@import("engine");
/// all the maths: casts, tau, lerp
const m=engine.core.math;
/// an allocator
const Allocator=std.mem.Allocator;
/// swaps two values in place
const swap=std.mem.swap;
/// writes a number's bytes, little-endian
const writeInt=std.mem.writeInt;
/// reads a number's bytes, little-endian
const readInt=std.mem.readInt;
/// whether two texts are the same
const eql=std.mem.eql;
/// a plain WAV header's length (bytes)
const headerLen:usize=44;
/// full scale of a 16-bit sample, writing (the largest it may hold)
const fullOut:f32=32767;
/// full scale of a 16-bit sample, reading (so -32768 reads as -1)
const fullIn:f32=32768;
/// full scale of a 24-bit sample, reading
const full24:f32=8388608;
/// an in-place fast Fourier transform of `re`, `im` (a power of two long)
pub fn fft(re:[]f32,im:[]f32)void{
  const n=re.len;
  // the bit-reversed order
  var j:usize=0;
  for(1..n)|i|{
    var bit=n>>1;
    while(j&bit!=0):(bit>>=1)j^=bit;
    j|=bit;
    if(i<j){
      swap(f32,&re[i],&re[j]);
      swap(f32,&im[i],&im[j]);
    }
  }
  // butterflies, doubling in size
  var len:usize=2;
  while(len<=n):(len<<=1){
    const half=len/2;
    var at:usize=0;
    while(at<n):(at+=len){
      for(0..half)|k|{
        // the twiddle, and the pair it joins
        const a=-m.tau*m.f(k)/m.f(len);
        const wr=@cos(a);
        const wi=@sin(a);
        const p=at+k;
        const q=p+half;
        const vr=re[q]*wr-im[q]*wi;
        const vi=re[q]*wi+im[q]*wr;
        re[q]=re[p]-vr;
        im[q]=im[p]-vi;
        re[p]+=vr;
        im[p]+=vi;
      }
    }
  }
}
/// `x` as a 16-bit mono WAV at `rate` (Hz)
pub fn wavOf(arena:Allocator,x:[]const f32,rate:u32)Allocator.Error![]u8{
  // the header, then two bytes a sample
  const out=try arena.alloc(u8,headerLen+x.len*2);
  const dataLen:u32=@intCast(x.len*2);
  @memcpy(out[0..4],"RIFF");
  writeInt(u32,out[4..8],36+dataLen,.little);
  @memcpy(out[8..16],"WAVEfmt ");
  writeInt(u32,out[16..20],16,.little);
  writeInt(u16,out[20..22],1,.little);
  writeInt(u16,out[22..24],1,.little);
  writeInt(u32,out[24..28],rate,.little);
  writeInt(u32,out[28..32],rate*2,.little);
  writeInt(u16,out[32..34],2,.little);
  writeInt(u16,out[34..36],16,.little);
  @memcpy(out[36..40],"data");
  writeInt(u32,out[40..44],dataLen,.little);
  for(x,0..)|v,i|writeInt(i16,out[headerLen+i*2..][0..2],@intFromFloat(@round(@max(-1,@min(1,v))*fullOut)),.little);
  return out;
}
/// a plain 16-bit mono WAV's samples (its header skipped), as floats
pub fn samplesOf(arena:Allocator,wav:[]const u8)Allocator.Error![]f32{
  const body=wav[@min(wav.len,headerLen)..];
  const out=try arena.alloc(f32,body.len/2);
  for(out,0..)|*v,i|v.*=m.f(readInt(i16,body[i*2..][0..2],.little))/fullIn;
  return out;
}
/// `x` at rate `from` resampled to `to` (straight lines between samples)
pub fn resample(arena:Allocator,x:[]const f32,from:f32,to:f32)Allocator.Error![]f32{
  const n=m.floorTo(usize,m.f(x.len)*to/from);
  const out=try arena.alloc(f32,n);
  for(out,0..)|*v,i|{
    const t=m.f(i)*from/to;
    const k=m.floorTo(usize,t);
    const b=@min(k+1,x.len-1);
    v.*=m.lerp(x[@min(k,x.len-1)],x[b],t-m.f(k));
  }
  return out;
}
/// what reading a WAV can fail with
pub const WavError=error{NotWav,UnreadWav}||Allocator.Error;
/// a WAV of any rate and channels, 16-bit, 24-bit or 32-bit float (as
/// Audacity writes), as mono samples at `rate` (Hz)
pub fn readWav(arena:Allocator,bytes:[]const u8,rate:f32)WavError![]f32{
  if(bytes.len<headerLen or !eql(u8,bytes[0..4],"RIFF") or !eql(u8,bytes[8..12],"WAVE"))return error.NotWav;
  // the format, and where the samples are, found chunk by chunk
  var fmtKind:u16=0;
  var ch:u16=1;
  var sr:u32=@intFromFloat(rate);
  var bits:u16=16;
  var data:?[]const u8=null;
  var at:usize=12;
  while(at+8<=bytes.len){
    const id=bytes[at..][0..4];
    const len=readInt(u32,bytes[at+4..][0..4],.little);
    const body=bytes[at+8..@min(bytes.len,at+8+len)];
    if(eql(u8,id,"fmt ") and body.len>=16){
      fmtKind=readInt(u16,body[0..2],.little);
      ch=readInt(u16,body[2..4],.little);
      sr=readInt(u32,body[4..8],.little);
      bits=readInt(u16,body[14..16],.little);
      // the extensible format names its kind further in
      if(fmtKind==0xfffe and body.len>=26)fmtKind=readInt(u16,body[24..26],.little);
    }
    if(eql(u8,id,"data"))data=body;
    at+=8+len+(len&1);
  }
  const d=data orelse return error.UnreadWav;
  const width:usize=bits/8;
  if(ch==0 or width==0)return error.UnreadWav;
  const n=d.len/(width*ch);
  const mono=try arena.alloc(f32,n);
  for(0..n)|i|{
    // the channels averaged
    var s:f32=0;
    for(0..ch)|c|{
      const p=d[(i*ch+c)*width..];
      s+=switch(fmtKind){
        1=>if(bits==16)m.f(readInt(i16,p[0..2],.little))/fullIn else if(bits==24)m.f(readInt(i24,p[0..3],.little))/full24 else return error.UnreadWav,
        3=>if(bits==32)@as(f32,@bitCast(readInt(u32,p[0..4],.little)))else return error.UnreadWav,
        else=>return error.UnreadWav,
      };
    }
    mono[i]=s/m.f(ch);
  }
  return if(m.f(sr)==rate)mono else try resample(arena,mono,m.f(sr),rate);
}
/// the test harness
const testing=std.testing;
test "a WAV written reads back the same" {
  var ar=std.heap.ArenaAllocator.init(testing.allocator);
  defer ar.deinit();
  const a=ar.allocator();
  const w=try wavOf(a,&.{0,0.5,-0.5},16000);
  const x=try readWav(a,w,16000);
  try testing.expectEqual(@as(usize,3),x.len);
  try testing.expectApproxEqAbs(@as(f32,0.5),x[1],1e-4);
  try testing.expectError(error.NotWav,readWav(a,"nope",16000));
}
test "the transform finds a tone in its bin" {
  const n=256;
  var re:[n]f32=undefined;
  var im:[n]f32=@splat(0);
  for(&re,0..)|*v,i|v.*=@cos(m.tau*9*m.f(i)/m.f(n));
  fft(&re,&im);
  var best:usize=0;
  for(0..n/2)|i|{
    if(re[i]*re[i]+im[i]*im[i]>re[best]*re[best]+im[best]*im[best])best=i;
  }
  try testing.expectEqual(@as(usize,9),best);
}
