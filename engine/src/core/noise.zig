//! 2D gradient noise + fractal variants. Output of `grad` is roughly -1..1.
/// the standard library
const std=@import("std");
/// the engine's maths: floor, tau, casts
const m=@import("math.zig");
/// the test helpers
const testing=std.testing;
/// the lattice hash each cell's gradient is drawn from
const rng=@import("rng.zig");
/// quintic smoothstep (C2 continuous), 0..1 in and out. Used for Perlin
/// interpolation; m.smooth is cubic (C1) and shows pinch points at cell
/// boundaries.
inline fn fade(t:f32)f32{return t*t*t*(t*(t*6-15)+10);}
/// 16 bits of the hash give 65536 gradient angles — visually indistinguishable
/// from 64 bits at game scale, and keeps the multiply cheap.
const gradBits=16;
/// the mask that keeps those 16 bits of the hash
const gradMask=(1<<gradBits)-1;
/// how far one step of those bits turns the gradient (radians)
const gradScale=m.tau/m.f(1<<gradBits);
/// the dot of a cell corner's gradient with the offset (`fx`, `fy`) from
/// that corner: how much that corner pushes the noise up or down there
inline fn gdot(seed:u64,ix:i32,iy:i32,fx:f32,fy:f32)f32{
  // the corner's hash, which picks its gradient
  const h=rng.hash2(seed,ix,iy);
  // the gradient's angle (radians)
  const a=m.f(h&gradMask)*gradScale;
  return@cos(a)*fx+@sin(a)*fy;
}
/// √2: the max of bilinearly-interpolated 2D dot products is ~1/√2,
/// so multiplying normalises the output to roughly -1..1.
const normScale:f32=1.41421356;
/// octave frequency multiplier. The 0.03 offset breaks the exact 2× lattice
/// so adjacent octaves don't align into visible grid artifacts.
const lacunarity:f32=2.03;
/// gradient noise at (`x`, `y`) for `seed`: smooth hills and hollows a
/// lattice cell wide, roughly -1..1, the same every time it is asked
pub fn grad(seed:u64,x:f32,y:f32)f32{
  // the cell's corner below the point, as floats then as whole numbers
  const x0=@floor(x);
  const y0=@floor(y);
  const ix:i32=@intFromFloat(x0);
  const iy:i32=@intFromFloat(y0);
  // how far into the cell the point lies, 0..1 on each axis
  const fx=x-x0;
  const fy=y-y0;
  // the faded blend weights along each axis
  const u=fade(fx);
  const v=fade(fy);
  // the four corners' pushes: below-left, below-right, above-left,
  // above-right
  const n00=gdot(seed,ix,iy,fx,fy);
  const n10=gdot(seed,ix+1,iy,fx-1,fy);
  const n01=gdot(seed,ix,iy+1,fx,fy-1);
  const n11=gdot(seed,ix+1,iy+1,fx-1,fy-1);
  // the bottom and top edges blended across, then down the middle
  const a=n00+(n10-n00)*u;
  const b=n01+(n11-n01)*u;
  return(a+(b-a)*v)*normScale;
}
/// fractal brownian motion, normalised to about -1..1.
/// NOTE: changing `octaves` changes the output for all lower octaves too,
/// because each octave is re-seeded from the previous. Don't "add an octave
/// later" expecting the existing ones to stay the same.
pub fn fbm(seed:u64,x:f32,y:f32,octaves:u32)f32{
  // the running total, this octave's weight and its frequency
  var sum:f32=0;
  var amp:f32=1;
  var freq:f32=1;
  // the weights summed, to bring the total back to about -1..1
  var norm:f32=0;
  // this octave's seed, re-mixed for each next one
  var s=seed;
  for(0..octaves)|_|{
    sum+=grad(s,x*freq,y*freq)*amp;
    norm+=amp;
    amp*=0.5;
    freq*=lacunarity;
    s=rng.mix64(s);
  }
  return sum/norm;
}
/// ridged noise: thin bright lines (used for ley veins), 0..1, peaking
/// where the fractal noise crosses zero
pub fn ridged(seed:u64,x:f32,y:f32,octaves:u32)f32{
  // one less the noise's distance from zero: 1 on the ridge lines
  const n=1-@abs(fbm(seed,x,y,octaves));
  return n*n;
}
// ---- tests ----
test"grad range + determinism"{
  // the point walked over a grid, row by row
  var x:f32=-50;
  while(x<50):(x+=0.37){
    // the column being sampled
    var y:f32=-50;
    while(y<50):(y+=0.37){
      // the noise there
      const n=grad(42,x,y);
      try testing.expect(n>=-1.5 and n<=1.5);
      try testing.expectEqual(n,grad(42,x,y));
    }
  }
}
test"fbm range + determinism + seed sensitivity"{
  // how many points another seed changed
  var differs:usize=0;
  // the point walked along a slanted line
  var x:f32=-20;
  while(x<20):(x+=0.5){
    // the noise there
    const n=fbm(42,x,x*0.7,4);
    try testing.expect(n>=-1.5 and n<=1.5);
    try testing.expectEqual(n,fbm(42,x,x*0.7,4));
    if(@abs(n-fbm(43,x,x*0.7,4))>1e-6)differs+=1;
  }
  // another seed is another field almost everywhere
  try testing.expect(differs>70);
}
/// the classic sine hash's weights, one per input (the fourth most often a seed)
pub const sineWeights=m.Vice(f32,4){12.9898,78.233,37.719,91.31};
/// how far the sine is stretched before its whole part is dropped
const sineScale:f32=43758.5453;
/// a number 0..1 from the `n` inputs `p`, each weighed by `w`: the classic
/// sine hash, a fast scramble, the same for the same inputs (summed left to
/// right, so it matches the sum written out)
pub fn sineHash(comptime n:usize,p:m.Vice(f32,n),w:m.Vice(f32,n))f32{
  // the inputs weighed and summed in turn
  var s:f32=p[0]*w[0];
  inline for(1..n)|i|s+=p[i]*w[i];
  // the sine stretched, its fraction kept
  const h=@sin(s)*sineScale;
  return h-@floor(h);
}
test"the sine hash is 0..1 and matches it written out"{
  // a few inputs, and the hash written out by hand
  const a:f32=3.25;
  const b:f32=7;
  const c:f32=0.5;
  const h=@sin(a*12.9898+b*78.233+c*37.719)*43758.5453;
  try testing.expectEqual(h-@floor(h),sineHash(3,.{a,b,c},sineWeights[0..3].*));
  // and in range over a sweep
  for(0..200)|i|{
    // the hash of this step
    const v=sineHash(2,.{m.f(i)*0.37,1.5},.{127.1,311.7});
    try testing.expect(v>=0 and v<1);
  }
}
test"ridged is in 0..1"{
  // the point walked along a slanted line
  var x:f32=-10;
  while(x<10):(x+=0.3){
    // the noise there
    const n=ridged(7,x,x*1.3,3);
    try testing.expect(n>=0 and n<=1);
  }
}
test"fbm single octave ≈ grad"{
  // with 1 octave, fbm is just grad normalised by amp=1, so they should match
  const a=fbm(99,3.7,-2.1,1);
  // grad itself, at the same point
  const b=grad(99,3.7,-2.1);
  try testing.expectApproxEqAbs(a,b,1e-5);
}
