//! what moves, read from a burst of shots (`--inspect=<focus> --burst=S
//! --shots=N`, the camera held still): every frame laid side by side in one
//! contact sheet (`shots/<focus>_sheet.png`), and the light of one spot
//! measured in each, printed as a curve, so a light that breathes shows as
//! a wave and a still one as a flat line, and how much the spot changed
//! from frame to frame, so a spark jumping shows where a still glow does
//! not. Seen and measured, never taken on trust.
/// the standard library
const std=@import("std");
/// the engine: its PNG reading and writing, its maths and its flags
const engine=@import("engine");
/// all the maths: casts, clamps
const m=engine.core.math;
/// screenshots read back and written
const png=engine.core.png;
/// the command line's flags, split once at the edge
const flag=engine.core.flag;
/// the allocator everything is made with
const Allocator=std.mem.Allocator;
/// the I/O interface every file call goes through
const Io=std.Io;
/// a directory handle
const Dir=Io.Dir;
/// a text written into a buffer
const bufPrint=std.fmt.bufPrint;
/// a whole number read from text
const parseInt=std.fmt.parseInt;
/// a text cut at a mark
const splitScalar=std.mem.splitScalar;
/// prints a line to the console
const print=std.debug.print;
/// the test harness
const testing=std.testing;
/// where the shots are, under the working directory
const shotsDir="shots";
/// the largest shot read (bytes)
const maxShot=64<<20;
/// the most frames a burst holds
const maxFrames=120;
/// how much each frame is shrunk on the sheet (each side)
const sheetShrink:u32=4;
/// a spot that changes less than this from its quietest to its brightest
/// (a share of its mean) counts as still
const stillSpread:f32=0.04;
/// how wide the printed curve's bars run at their longest (characters)
const barWidth=40;
/// perceptual weights of red, green and blue (Rec. 601)
const luma=m.Vice(f32,3){0.299,0.587,0.114};
/// every flag the tool takes, by its own spelling
const Flag=enum{
  /// `--focus=`: the shots' name, as `--inspect` wrote them (`<focus>_<n>.png`)
  focus,
  /// `--shots=`: how many frames the burst holds
  shots,
  /// `--at=x,y`: the spot measured, in the shot's pixels (unset: its middle)
  at,
  /// `--r=`: the spot's radius, in pixels
  r,
  /// `--cols=`: frames a row on the sheet
  cols,
};
/// the spot measured in every frame: its middle and radius, in pixels
const Spot=struct{
  /// its middle, x then y
  at:?m.Vice(u32,2)=null,
  /// how far round its middle it reaches
  r:u32=24,
  /// the mean brightness (0..1) of `im`'s pixels within it
  fn light(s:Spot,im:png.Image)f32{
    // its middle, the frame's if unset, and the sum and count so far
    const c=s.at orelse m.Vice(u32,2){im.w/2,im.h/2};
    var sum:f32=0;
    var n:f32=0;
    const r2=s.r*s.r;
    for(c[1]-|s.r..@min(c[1]+s.r+1,im.h))|y|for(c[0]-|s.r..@min(c[0]+s.r+1,im.w))|x|{
      // how far from the middle, squared
      const dx=@as(i64,@intCast(x))-c[0];
      const dy=@as(i64,@intCast(y))-c[1];
      if(dx*dx+dy*dy>r2)continue;
      sum+=pixelLight(im,x,y);
      n+=1;
    };
    return if(n>0)sum/n else 0;
  }
  /// the mean change (0..1) of each pixel within it from `a` to `b`
  fn change(s:Spot,a:png.Image,b:png.Image)f32{
    // its middle, and the sum and count so far
    const c=s.at orelse m.Vice(u32,2){a.w/2,a.h/2};
    var sum:f32=0;
    var n:f32=0;
    for(c[1]-|s.r..@min(c[1]+s.r+1,a.h))|y|for(c[0]-|s.r..@min(c[0]+s.r+1,a.w))|x|{
      sum+=@abs(pixelLight(a,x,y)-pixelLight(b,x,y));
      n+=1;
    };
    return if(n>0)sum/n else 0;
  }
};
/// how bright pixel (x, y) of `im` is (0..1)
fn pixelLight(im:png.Image,x:usize,y:usize)f32{
  // the pixel's first byte
  const i=(y*im.w+x)*3;
  return(luma[0]*m.f(im.rgb[i])+luma[1]*m.f(im.rgb[i+1])+luma[2]*m.f(im.rgb[i+2]))/255;
}
/// `x,y` read as a pixel
fn parsePoint(s:[]const u8)!m.Vice(u32,2){
  var it=splitScalar(u8,s,',');
  // the two whole numbers
  const x=try parseInt(u32,it.next() orelse return error.BadPoint,10);
  const y=try parseInt(u32,it.next() orelse return error.BadPoint,10);
  return.{x,y};
}
/// whether a curve of lights (its least and most, round its mean) breathes
fn breathes(lo:f32,hi:f32,mean:f32)bool{
  return mean>0 and (hi-lo)/mean>stillSpread;
}
/// reads `shots/<focus>_<n>.png` for every frame, writes their sheet beside
/// them and prints the spot's light and change through the burst
pub fn main(init:std.process.Init)!void{
  // the allocator, the I/O, and the command line
  const gpa=init.gpa;
  const io=init.io;
  const args=try init.minimal.args.toSlice(init.arena.allocator());
  // what is read and measured, and how the sheet is laid out
  var focus:[]const u8="player";
  var count:usize=0;
  var spot=Spot{};
  var cols:usize=6;
  for(args[1..])|a|{
    const f=flag.parse(Flag,a) orelse continue;
    const v=f.value orelse continue;
    switch(f.name){
      .focus=>focus=v,
      .shots=>count=@min(try parseInt(usize,v,10),maxFrames),
      .at=>spot.at=try parsePoint(v),
      .r=>spot.r=try parseInt(u32,v,10),
      .cols=>cols=@max(try parseInt(usize,v,10),1),
    }
  }
  if(count==0)return error.NoShots;
  // the frames read back
  var frames:[maxFrames]png.Image=undefined;
  var read:usize=0;
  defer for(frames[0..read])|im|im.deinit(gpa);
  var pb:[128]u8=undefined;
  for(0..count)|i|{
    const path=try bufPrint(&pb,shotsDir++"/{s}_{d}.png",.{focus,i});
    const bytes=try Dir.cwd().readFileAlloc(io,path,gpa,.limited(maxShot));
    defer gpa.free(bytes);
    frames[read]=try png.decode(gpa,bytes);
    read+=1;
  }
  try sheet(gpa,io,frames[0..read],cols,focus);
  report(frames[0..read],spot);
}
/// lays `frames` out `cols` a row, each shrunk, into `shots/<focus>_sheet.png`
fn sheet(gpa:Allocator,io:Io,frames:[]const png.Image,cols:usize,focus:[]const u8)!void{
  // one frame's size on the sheet, the sheet's rows and its pixels (RGBA)
  const fw=frames[0].w/sheetShrink;
  const fh=frames[0].h/sheetShrink;
  const rows=(frames.len+cols-1)/cols;
  const sw:u32=@intCast(fw*@min(cols,frames.len));
  const sh:u32=@intCast(fh*rows);
  const px=try gpa.alloc(u8,@as(usize,sw)*sh*4);
  defer gpa.free(px);
  @memset(px,0);
  // a frame widened to four bytes a pixel, reused for each
  const wide=try gpa.alloc(u8,@as(usize,frames[0].w)*frames[0].h*4);
  defer gpa.free(wide);
  for(frames,0..)|im,k|{
    for(0..@as(usize,im.w)*im.h)|i|{
      @memcpy(wide[i*4..][0..3],im.rgb[i*3..][0..3]);
      wide[i*4+3]=255;
    }
    const small=try png.shrink(gpa,wide,im.w,im.h,sheetShrink);
    defer gpa.free(small);
    // where it goes on the sheet
    const ox=(k%cols)*fw;
    const oy=(k/cols)*fh;
    for(0..fh)|y|@memcpy(px[((oy+y)*sw+ox)*4..][0..fw*4],small[y*fw*4..][0..fw*4]);
  }
  const file=try png.encode(gpa,sw,sh,px,.rgba);
  defer gpa.free(file);
  var pb:[128]u8=undefined;
  const path=try bufPrint(&pb,shotsDir++"/{s}_sheet.png",.{focus});
  try Dir.cwd().writeFile(io,.{.sub_path=path,.data=file});
  print("sheet: {s} ({d} frames, {d} a row)\n",.{path,frames.len,cols});
}
/// prints the spot's light in each frame as a bar, how much it changed from
/// the frame before, and whether it breathes and whether it jumps
fn report(frames:[]const png.Image,spot:Spot)void{
  // each frame's light, and the least, most and sum of them
  var lights:[maxFrames]f32=undefined;
  var lo:f32=1;
  var hi:f32=0;
  var sum:f32=0;
  for(frames,0..)|im,i|{
    lights[i]=spot.light(im);
    lo=@min(lo,lights[i]);
    hi=@max(hi,lights[i]);
    sum+=lights[i];
  }
  const mean=sum/m.f(frames.len);
  // the most the spot changed between two frames
  var most:f32=0;
  print("frame  light  change\n",.{});
  for(frames,0..)|im,i|{
    const ch=if(i==0)0 else spot.change(frames[i-1],im);
    most=@max(most,ch);
    // the bar's length, the light's place between the least and most
    const bar=if(hi>lo)m.floorTo(usize,(lights[i]-lo)/(hi-lo)*barWidth+0.5)else 0;
    var bb:[barWidth]u8=undefined;
    @memset(&bb,'#');
    print("{d:>5}  {d:.3}  {d:.3}  |{s}\n",.{i,lights[i],ch,bb[0..bar]});
  }
  print("light {d:.3}..{d:.3} (mean {d:.3}): {s}; most change between frames {d:.3}\n",.{lo,hi,mean,if(breathes(lo,hi,mean))"it breathes" else "it is still",most});
}
test"a spot's light is the mean of the pixels within it, its change between frames"{
  // two 4x4 frames: one black, one white in its middle 2x2
  var dark=[_]u8{0}**48;
  var lit=[_]u8{0}**48;
  for([_]usize{5,6,9,10})|p|@memset(lit[p*3..][0..3],255);
  const a=png.Image{.w=4,.h=4,.rgb=&dark};
  const b=png.Image{.w=4,.h=4,.rgb=&lit};
  const s=Spot{.at=.{1,1},.r=0};
  try testing.expectApproxEqAbs(@as(f32,0),s.light(a),1e-4);
  try testing.expectApproxEqAbs(@as(f32,1),s.light(b),1e-3);
  try testing.expectApproxEqAbs(@as(f32,1),s.change(a,b),1e-3);
}
test"a light that swells round its mean breathes; a flat one is still"{
  try testing.expect(breathes(0.40,0.50,0.45));
  try testing.expect(!breathes(0.449,0.451,0.45));
  try testing.expect(!breathes(0,0,0));
}
test"a point is read as x,y"{
  try testing.expectEqual(m.Vice(u32,2){12,340},try parsePoint("12,340"));
  try testing.expectError(error.BadPoint,parsePoint("12"));
}
