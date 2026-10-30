//! the gardener's settings (pause menu, OPTIONS): how the garden is drawn
//! and shown, and how often it saves itself. Kept in `PATH` in `home`: read
//! once at startup (written with the defaults when missing), written
//! whenever one changes. An unreadable file means the defaults.
const lib=@import("../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const Io=std.Io;
const Writer=Io.Writer;
const eql=std.mem.eql;
const stringToEnum=std.meta.stringToEnum;
const parseInt=std.fmt.parseInt;
const log=std.log;
const testing=std.testing;
const fields=std.meta.fields;
const ctext=lib.engine.core.text;
const txt=lib.txt;
const Antialias=lib.renderer.Antialias;
const home=lib.home;
// decision: a file of its own (not the save): settings belong to the
// player, not to one garden, and loading a save keeps them.
pub const filePath="options.cfg";
const maxFile:usize=1<<12;
pub const Options=struct{
  aa:Antialias=.msaa4,
  vsync:bool=true,
  fullscreen:bool=false,
  /// minutes between autosaves (one of `AUTOSAVE`; 0: never)
  autosave:u8=5,
};
/// the autosave intervals offered, in minutes (in `txt.s.hud.autosave` order)
pub const autosaveMinutes=[_]u8{0,1,2,5,10,15,30,60};
/// the options panel's rows, in `txt.s.hud.option_labels` order
pub const Setting=enum{antialias,vsync,fullscreen,autosave};
/// where `minutes` is in `AUTOSAVE` (else the next longer one there)
fn autosaveIndex(minutes:u8)usize{
  for(autosaveMinutes,0..)|a,i|if(a>=minutes)return i;
  return autosaveMinutes.len-1;
}
/// turn `set` one way (`dir` +1) or back (-1), wrapping round; anti-aliasing
/// skips MSAA with more than `most` samples (what the GPU can take)
pub fn step(o:*Options,set:Setting,dir:i32,most:u32)void{
  switch(set){
    .antialias=>{
      const n:i32=@intCast(fields(Antialias).len);
      var i:i32=@intFromEnum(o.aa);
      while(true){
        i=@mod(i+dir,n);
        const a:Antialias=@enumFromInt(i);
        if(a.samples()<=most){o.aa=a;return;}
      }
    },
    .vsync=>o.vsync=!o.vsync,
    .fullscreen=>o.fullscreen=!o.fullscreen,
    .autosave=>{
      const n:i32=autosaveMinutes.len;
      o.autosave=autosaveMinutes[@intCast(@mod(@as(i32,@intCast(autosaveIndex(o.autosave)))+dir,n))];
    },
  }
}
/// what `set` is now, as shown
pub fn shown(o:*const Options,set:Setting)[]const u8{
  return switch(set){
    .antialias=>txt.nth(txt.s.hud.antialias,@intFromEnum(o.aa)),
    .vsync=>txt.nth(txt.s.hud.toggle,@intFromBool(o.vsync)),
    .fullscreen=>txt.nth(txt.s.hud.toggle,@intFromBool(o.fullscreen)),
    .autosave=>txt.nth(txt.s.hud.autosave,autosaveIndex(o.autosave)),
  };
}
/// the file as written: each setting by name (any may be missing)
const Source=struct{
  options:struct{
    antialias:?[]const u8=null,vsync:?[]const u8=null,fullscreen:?[]const u8=null,
    autosave:?[]const u8=null,
  }=.{},
};
const on="on";
const off="off";
/// the options in cfg source `text`; what is missing or unknown stays default.
pub fn parse(text:[]const u8)Options{
  var o:Options=.{};
  var badBuf:[128]u8=undefined;
  var bad:Writer=.fixed(&badBuf);
  var src:Source=.{};
  ctext.parse(Source,&src,text,&bad)catch|e|{
    log.warn("{s}: {t}: {s}",.{filePath,e,bad.buffered()});
    return o;
  };
  const f=src.options;
  if(f.antialias)|v|o.aa=stringToEnum(Antialias,v) orelse o.aa;
  if(f.vsync)|v|o.vsync=!eql(u8,v,off);
  if(f.fullscreen)|v|o.fullscreen=eql(u8,v,on);
  if(f.autosave)|v|if(parseInt(u8,v,10))|n|{o.autosave=autosaveMinutes[autosaveIndex(n)];}else|_|{};
  return o;
}
/// writes `o` as cfg source.
pub fn format(o:*const Options,w:*Writer)Writer.Error!void{
  try w.print("# Parasymi options: written by the game (pause menu, OPTIONS)\n" ++
    "# autosave: minutes between autosaves (0: never)\n" ++
    "[options]\nantialias = {t}\nvsync = {s}\nfullscreen = {s}\nautosave = {d}\n",.{
    o.aa,if(o.vsync)on else off,if(o.fullscreen)on else off,o.autosave,
  });
}
/// reads `PATH`; the defaults if it cannot be read, written out if there
/// is none.
pub fn load(gpa:Allocator,io:Io)Allocator.Error!Options{
  const text=home.dir().readFileAlloc(io,filePath,gpa,.limited(maxFile))catch|e|switch(e){
    error.OutOfMemory=>return error.OutOfMemory,
    error.FileNotFound=>{
      const o:Options=.{};
      save(&o,io)catch|se|log.warn("{s}: {t}",.{filePath,se});
      return o;
    },
    else=>return.{},
  };
  defer gpa.free(text);
  return parse(text);
}
pub const Error=error{OptionsUnwritable};
pub fn save(o:*const Options,io:Io)Error!void{
  var buf:[256]u8=undefined;
  var w:Writer=.fixed(&buf);
  format(o,&w) catch return error.OptionsUnwritable;
  home.dir().writeFile(io,.{.sub_path=filePath,.data=w.buffered()}) catch return error.OptionsUnwritable;
}
test"options round-trip through their file; unknown values keep the defaults"{
  const o:Options=.{.aa=.fxaa,.vsync=false,.fullscreen=true,.autosave=15};
  var buf:[256]u8=undefined;
  var w:Writer=.fixed(&buf);
  try format(&o,&w);
  try testing.expectEqual(o,parse(w.buffered()));
  try testing.expectEqual(Options{},parse("[options]\nantialias = sparkle\n"));
  try testing.expectEqual(Options{},parse(""));
  // an interval not offered snaps to the next longer one
  try testing.expectEqual(@as(u8,10),parse("[options]\nautosave = 7\n").autosave);
}
test"anti-aliasing turns both ways and skips what the GPU cannot take"{
  var o:Options=.{.aa=.off};
  step(&o,.antialias,1,4);
  try testing.expectEqual(Antialias.fxaa,o.aa);
  step(&o,.antialias,-1,4);
  step(&o,.antialias,-1,4);
  // msaa8 is beyond 4 samples: wraps back to msaa4
  try testing.expectEqual(Antialias.msaa4,o.aa);
  step(&o,.antialias,1,4);
  try testing.expectEqual(Antialias.off,o.aa);
  step(&o,.vsync,1,4);
  try testing.expect(!o.vsync);
  // autosave: 5 minutes by default, wrapping round to never
  try testing.expectEqual(@as(u8,5),o.autosave);
  step(&o,.autosave,-1,4);
  try testing.expectEqual(@as(u8,2),o.autosave);
  o.autosave=60;
  step(&o,.autosave,1,4);
  try testing.expectEqual(@as(u8,0),o.autosave);
}
