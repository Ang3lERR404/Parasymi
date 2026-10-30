//! the gardener's settings (pause menu, OPTIONS): how the garden is drawn
//! and shown, and how often it saves itself. Kept in `filePath` in `home`: read
//! once at startup (written with the defaults when missing), written
//! whenever one changes. An unreadable file means the defaults.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the file's text is read with
const Allocator=std.mem.Allocator;
/// the I/O interface, for reading and writing the file
const Io=std.Io;
/// a text writer, for writing the options out
const Writer=Io.Writer;
/// are two strings equal?
const eql=std.mem.eql;
/// reads an anti-aliasing mode from its name
const stringToEnum=std.meta.stringToEnum;
/// reads a number, for the autosave minutes
const parseInt=std.fmt.parseInt;
/// the log, for a file that will not parse
const log=std.log;
/// the test harness
const testing=std.testing;
/// a type's fields, for counting the anti-aliasing modes
const fields=std.meta.fields;
/// the runtime cfg reader
const ctext=lib.engine.core.text;
/// every player-facing string, for how each setting is shown
const txt=lib.txt;
/// the renderer's anti-aliasing modes
const Antialias=lib.renderer.Antialias;
/// the gardener's folder, where the file lives
const home=lib.home;
// decision: a file of its own (not the save): settings belong to the
// player, not to one garden, and loading a save keeps them.
/// the settings file's name, inside home
pub const filePath="options.cfg";
/// the file is a few lines; anything this large is not one
const maxFile:usize=1<<12;
/// the gardener's settings, as held while playing
pub const Options=struct{
  /// how edges are smoothed (MSAA samples, FXAA or none)
  aa:Antialias=.msaa4,
  /// whether frames wait for the screen's refresh
  vsync:bool=true,
  /// whether the game fills the screen
  fullscreen:bool=false,
  /// minutes between autosaves (one of `autosaveMinutes`; 0: never)
  autosave:u8=5,
};
/// the autosave intervals offered, in minutes (in `txt.s.hud.autosave` order)
pub const autosaveMinutes=[_]u8{0,1,2,5,10,15,30,60};
/// the options panel's rows, in `txt.s.hud.optionLabels` order
pub const Setting=enum{
  /// how edges are smoothed
  antialias,
  /// waiting for the screen's refresh
  vsync,
  /// filling the screen
  fullscreen,
  /// how often the garden saves itself
  autosave
};
/// where `minutes` is in `autosaveMinutes` (else the next longer one there)
fn autosaveIndex(minutes:u8)usize{
  for(autosaveMinutes,0..)|a,i|if(a>=minutes)return i;
  return autosaveMinutes.len-1;
}
/// turn `set` one way (`dir` +1) or back (-1), wrapping round; anti-aliasing
/// skips MSAA with more than `most` samples (what the GPU can take)
pub fn step(o:*Options,set:Setting,dir:i32,most:u32)void{
  switch(set){
    .antialias=>{
      // how many modes there are, and the one being tried
      const n:i32=@intCast(fields(Antialias).len);
      var i:i32=@intFromEnum(o.aa);
      while(true){
        i=@mod(i+dir,n);
        // the mode being tried
        const a:Antialias=@enumFromInt(i);
        if(a.samples()<=most){o.aa=a;return;}
      }
    },
    .vsync=>o.vsync=!o.vsync,
    .fullscreen=>o.fullscreen=!o.fullscreen,
    .autosave=>{
      // how many intervals are offered
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
  /// the `[options]` section's lines
  options:struct{
    /// `antialias = <mode>`: a mode's name
    antialias:?[]const u8=null,
    /// `vsync = on|off`
    vsync:?[]const u8=null,
    /// `fullscreen = on|off`
    fullscreen:?[]const u8=null,
    /// `autosave = <minutes>`
    autosave:?[]const u8=null,
  }=.{},
};
/// a switch that is on, as written
const on="on";
/// a switch that is off, as written
const off="off";
/// the options in cfg source `text`; what is missing or unknown stays default.
pub fn parse(text:[]const u8)Options{
  // the defaults, overwritten by what the file says
  var o:Options=.{};
  // room for the parser's complaint, and the writer that fills it
  var badBuf:[128]u8=undefined;
  var bad:Writer=.fixed(&badBuf);
  // every setting as written, by name
  var src:Source=.{};
  ctext.parse(Source,&src,text,&bad)catch|e|{
    log.warn("{s}: {t}: {s}",.{filePath,e,bad.buffered()});
    return o;
  };
  // the `[options]` section
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
/// reads `filePath`; the defaults if it cannot be read, written out if there
/// is none.
pub fn load(gpa:Allocator,io:Io)Allocator.Error!Options{
  // the file's text, owned; missing, and the defaults are written out
  const text=home.dir().readFileAlloc(io,filePath,gpa,.limited(maxFile))catch|e|switch(e){
    error.OutOfMemory=>return error.OutOfMemory,
    error.FileNotFound=>{
      // the defaults
      const o:Options=.{};
      save(&o,io)catch|se|log.warn("{s}: {t}",.{filePath,se});
      return o;
    },
    else=>return.{},
  };
  defer gpa.free(text);
  return parse(text);
}
/// the file could not be written
pub const Error=error{OptionsUnwritable};
/// writes `o` to `filePath` in home
pub fn save(o:*const Options,io:Io)Error!void{
  // room for the file, and the writer that fills it
  var buf:[256]u8=undefined;
  var w:Writer=.fixed(&buf);
  format(o,&w) catch return error.OptionsUnwritable;
  home.dir().writeFile(io,.{.sub_path=filePath,.data=w.buffered()}) catch return error.OptionsUnwritable;
}
test"options round-trip through their file; unknown values keep the defaults"{
  // a set of options off the defaults, written out
  const o:Options=.{.aa=.fxaa,.vsync=false,.fullscreen=true,.autosave=15};
  // room for the file, and the writer that fills it
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
  // options with anti-aliasing off
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
