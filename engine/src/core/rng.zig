//! deterministic hashing + small PRNG. Everything procedural derives from these,
//! so the same seed always yields the same world.
/// the standard library
const std=@import("std");
/// the engine's maths: float casts
const m=@import("math.zig");
/// the test helpers
const testing=std.testing;
/// the golden ratio's share of 2^64 (Weyl step): the generator's stride and
/// the nudge before every mix, so consecutive seeds land far apart
pub const goldenStep:u64=0x9E3779B97F4A7C15;
/// scrambles a 64-bit value until every bit depends on every other
/// (splitmix64's finaliser): the root of every hash and the generator
pub inline fn mix64(x0:u64)u64{
  // the value, nudged by the golden ratio, then folded and multiplied twice
  var x=x0+%goldenStep;
  x=(x^(x>>30))*%0xBF58476D1CE4E5B9;
  x=(x^(x>>27))*%0x94D049BB133111EB;
  return x^(x>>31);
}
/// hash of an integer lattice point. Takes a middle 32-bit slice of the
/// 64-bit mix (bits 16..47).
pub inline fn hash2(seed:u64,x:i32,y:i32)u32{
  // @bitCast on i32 wraps negatives — intentional: the hash of (-1, 0)
  // must differ from the hash of (0, 0) but be stable across platforms.
  // the two coordinates' bits, wrapped into unsigned halves
  const a:u64=@as(u32,@bitCast(x));
  const b:u64=@as(u32,@bitCast(y));
  return@truncate(mix64(seed^(a<<32|b))>>16);
}
/// top 24 bits of a u32 hash -> 0..1 (exclusive). The >> 8 discards the
/// 8 weakest bits.
pub inline fn unit(h:u32)f32{return m.f(h>>8)*unitStep;}
/// 2^-24: one step of a 24-bit unit value
const unitStep:f32=1.0/16777216.0;
/// a small, fast random generator (splitmix64): the same seed always gives
/// the same sequence
pub const Rng=struct{
  /// where the sequence stands: its state, advanced each draw
  s:u64,
  /// a generator started from `seed`, mixed first so near seeds diverge
  pub fn init(seed:u64)Rng{return.{.s=mix64(seed)};}
  /// the next 64 random bits, stepping the state on
  pub fn next(r:*Rng)u64{r.s+%=goldenStep;return mix64(r.s);}
  /// decision: bits 8..31 of the output, as every grown mesh and the
  /// retired starfall were tuned against; changing them reshapes every plant.
  pub fn float(r:*Rng)f32{return unit(@truncate(r.next()));}
  /// a random float between `lo` and `hi` (`hi` itself never drawn)
  pub fn range(r:*Rng,lo:f32,hi:f32)f32{return lo+(hi-lo)*r.float();}
  /// uniform integer in 0..n (exclusive), no modulo bias.
  pub fn below(r:*Rng,n:u32)u32{
    if(n<=1)return 0;
    // reject the top (2^32 mod n) values so every residue is equally likely
    // 2^32, the span of the drawn values
    const span:u64=@as(u64,1)<<32;
    // the largest multiple of `n` under that span: draws at or above it are
    // thrown back
    const limit:u64=span-span%n;
    while(true){
      // one 32-bit draw
      const h:u64=@as(u32,@truncate(r.next()));
      if(h<limit)return@intCast(h%n);
    }
  }
};
test"hash2 is roughly uniform across buckets"{
  // 10000 samples into 4 buckets; each should be ~2500 ± 10%
  // how many hashes fell in each of four buckets
  var buckets:m.Vice(u32,4)=.{0,0,0,0};
  // the lattice point walked over, row by row, and how many were hashed
  var x:i32=0;
  var y:i32=0;
  var i:u32=0;
  while(i<10000):(i+=1){
    buckets[hash2(42,x,y)&3]+=1;
    x+=1;
    if(x==100){x=0;y+=1;}
  }
  for(buckets)|b|{
    try testing.expect(b>2000 and b<3000);
  }
}
test"Rng sequence is deterministic"{
  // two generators from the same seed
  var a=Rng.init(99);
  var b=Rng.init(99);
  for(0..100)|_|{
    try testing.expectEqual(a.next(),b.next());
  }
}
test"Rng.float distribution"{
  // the generator, and how many draws fell in each tenth of 0..1
  var r=Rng.init(123);
  var buckets:[10]u32=.{0}**10;
  for(0..10000)|_|{
    buckets[@intFromFloat(r.float()*10)]+=1;
  }
  for(buckets)|b|{
    try testing.expect(b>800 and b<1200);
  }
}
test"Rng.below stays in range and covers it"{
  // the generator
  var r=Rng.init(7);
  try testing.expectEqual(@as(u32,0),r.below(1));
  // how often each of 0, 1 and 2 was drawn
  var seen:m.Vice(u32,3)=.{0,0,0};
  for(0..3000)|_|seen[r.below(3)]+=1;
  for(seen)|c|try testing.expect(c>850 and c<1150);
  // a power of two leaves nothing to reject
  for(0..100)|_|try testing.expect(r.below(1<<31)<1<<31);
}
