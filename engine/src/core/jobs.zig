//! parallel-for over the game's thread pool (the `Io` main is given): [0, n)
//! split into ranges run on its worker threads and waited for together.
//! Each index's work must stand alone (it reads what is shared and writes
//! only its own outputs), so the result never depends on the split. With no
//! `Io` (headless tests) or too few items it runs in place.
//!
//!   const Double = struct {
//!     src:[]const f32,
//!     dst:[]f32,
//!     fn run(d:Double, lo:usize, hi:usize) void {
//!       for (d.src[lo..hi], d.dst[lo..hi]) |s, *o| o.* = s * 2;
//!     }
//!   };
//!   jobs.each(w.io, src.len, 4096, Double, .{.src = src, .dst = dst}, Double.run);
const std=@import("std");
/// the async runtime whose thread pool the ranges run on
const Io=std.Io;
/// threads, for counting the machine's cores
const Thread=std.Thread;
/// the test helpers
const testing=std.testing;
/// most ranges one call splits into
const maxParts=16;
/// the machine's cores, counted once (only main calls `each`)
var cores:usize=0;
/// how many ranges a call may split into: the cores, at most `maxParts`
fn parts()usize{
  if(cores==0)cores=Thread.getCpuCount() catch 1;
  return@min(cores,maxParts);
}
/// `run(ctx, lo, hi)` over [0, n) in ranges of at least `min` items: the
/// first range here, the rest on the pool (or here too when it is busy).
/// Returns once every range is done; with no `io` or too few items it all
/// runs here, in one call.
pub fn each(io:?Io,n:usize,min:usize,comptime Ctx:type,ctx:Ctx,comptime run:fn(Ctx,usize,usize)void)void{
  // how many ranges: as many as cores allow, none smaller than `min`
  const k=@min(parts(),n/@max(min,1));
  // the pool to run on, or none: then it all runs here
  const pool=io orelse return run(ctx,0,n);
  if(k<=1)return run(ctx,0,n);
  // how many items each range holds (the last may hold fewer)
  const step=(n+k-1)/k;
  // the ranges sent to the pool, waited for together
  var g:Io.Group=.init;
  // where the next pooled range starts
  var lo=step;
  while(lo<n):(lo+=step)g.async(pool,run,.{ctx,lo,@min(n,lo+step)});
  run(ctx,0,step);
  g.await(pool)catch{};
}
test"each covers every index once, split or not"{
  // each index counts how often it was run
  const Hits=struct{
    /// how many times each index was visited
    v:[]u32,
    /// counts each index in [lo, hi) once more
    fn run(h:@This(),lo:usize,hi:usize)void{for(h.v[lo..hi])|*x|x.*+=1;}
  };
  // every index visited none so far
  var v:[1000]u32=@splat(0);
  each(testing.io,v.len,10,Hits,.{.v=&v},Hits.run);
  for(v)|x|try testing.expectEqual(@as(u32,1),x);
  each(null,v.len,10,Hits,.{.v=&v},Hits.run);
  each(testing.io,3,10,Hits,.{.v=&v},Hits.run);
  for(v[0..3])|x|try testing.expectEqual(@as(u32,3),x);
  for(v[3..])|x|try testing.expectEqual(@as(u32,2),x);
}
