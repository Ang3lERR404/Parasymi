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
/// all the maths: clamping a step
const m=lib.engine.core.math;
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
/// the most the written file takes (bytes)
const fileMost=512;
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
  /// how far the garden is drawn: rings of chunks streamed in and drawn
  /// round the gardener (one of `renderRings`)
  renderDistance:u8=4,
  /// how many points of light near the camera cast shadows into the air,
  /// and how finely (the full look by default)
  lightShadows:LightShadows=.full,
  /// whether shadows are traced as rays where the GPU can (else, or where
  /// it cannot, drawn into shadow maps): on by default
  rayTracing:bool=true,
  /// how many rings of chunks are streamed in and drawn round the gardener
  pub fn rings(o:*const Options)i32{return renderRings[ringsIndex(o.renderDistance)];}
};
/// how many points of light near the camera cast shadows (their glow
/// fanning out in rays between what stands in it), and how finely, in
/// `txt.s.hud.lightShadows` order
pub const LightShadows=enum{
  /// none: every glow a soft ball
  off,
  /// the two most telling lights, in coarse cubes
  few,
  /// the four most telling lights, in coarse cubes
  more,
  /// the four most telling lights, in fine cubes
  full,
  /// how many lights cast shadows at this level
  pub fn lights(l:LightShadows)usize{
    return switch(l){.off=>0,.few=>2,.more,.full=>4};
  }
  /// texels along each side of a shadow cube's face at this level (the
  /// cubes keep their size while none is cast)
  pub fn res(l:LightShadows)u32{
    return switch(l){.off=>0,.few,.more=>256,.full=>512};
  }
};
/// the autosave intervals offered, in minutes (in `txt.s.hud.autosave` order)
pub const autosaveMinutes=[_]u8{0,1,2,5,10,15,30,60};
/// the render distances offered, in rings of chunks (in
/// `txt.s.hud.renderDistance` order: each a chunk of 32 tiles further)
pub const renderRings=[_]u8{2,3,4,5,6,8};
/// the options panel's rows, in `txt.s.hud.optionLabels` order
pub const Setting=enum{
  /// how edges are smoothed
  antialias,
  /// waiting for the screen's refresh
  vsync,
  /// filling the screen
  fullscreen,
  /// how often the garden saves itself
  autosave,
  /// how far the garden is drawn
  renderDistance,
  /// how many points of light cast shadows, and how finely
  lightShadows,
  /// whether shadows are traced as rays
  rayTracing,
};
/// what the GPU can take, which some settings are held to (main asks the
/// renderer)
pub const Gpu=struct{
  /// the most MSAA samples
  samples:u32=8,
  /// whether it can trace rays (else RAY TRACING shows it cannot)
  rays:bool=true,
};
/// how many settings there are
pub const settingCount=fields(Setting).len;
/// how a setting is set in the options panel
pub const Kind=enum{
  /// on or off: a bud that opens when on
  toggle,
  /// one of a few modes, turned either way between two leaves
  picker,
  /// one of a run of stops along a stem
  slider,
};
/// how `set` is set
pub fn kind(set:Setting)Kind{
  return switch(set){
    .antialias,.lightShadows=>.picker,
    .vsync,.fullscreen,.rayTracing=>.toggle,
    .autosave,.renderDistance=>.slider,
  };
}
/// whether the toggle `set` is on on `gpu` (false for any other kind; ray
/// tracing off where the GPU cannot)
pub fn isOn(o:*const Options,set:Setting,gpu:Gpu)bool{
  return switch(set){
    .vsync=>o.vsync,
    .fullscreen=>o.fullscreen,
    .rayTracing=>o.rayTracing and gpu.rays,
    .antialias,.autosave,.renderDistance,.lightShadows=>false,
  };
}
/// how many stops the slider `set` has (1 for any other kind)
pub fn stops(set:Setting)usize{
  return switch(set){
    .autosave=>autosaveMinutes.len,
    .renderDistance=>renderRings.len,
    .antialias,.vsync,.fullscreen,.lightShadows,.rayTracing=>1,
  };
}
/// which stop the slider `set` is at (0 for any other kind)
pub fn stopOf(o:*const Options,set:Setting)usize{
  return switch(set){
    .autosave=>autosaveIndex(o.autosave),
    .renderDistance=>ringsIndex(o.renderDistance),
    .antialias,.vsync,.fullscreen,.lightShadows,.rayTracing=>0,
  };
}
/// the slider `set` moved to stop `i` (kept to its stops; any other kind
/// is left as it is)
pub fn setStop(o:*Options,set:Setting,i:usize)void{
  switch(set){
    .autosave=>o.autosave=autosaveMinutes[@min(i,autosaveMinutes.len-1)],
    .renderDistance=>o.renderDistance=renderRings[@min(i,renderRings.len-1)],
    .antialias,.vsync,.fullscreen,.lightShadows,.rayTracing=>{},
  }
}
/// where `want` rings are in `renderRings` (else the next further one there)
fn ringsIndex(want:u8)usize{
  for(renderRings,0..)|r,i|if(r>=want)return i;
  return renderRings.len-1;
}
/// where `minutes` is in `autosaveMinutes` (else the next longer one there)
fn autosaveIndex(minutes:u8)usize{
  for(autosaveMinutes,0..)|a,i|if(a>=minutes)return i;
  return autosaveMinutes.len-1;
}
/// turn `set` one way (`dir` +1) or back (-1), wrapping round; anti-aliasing
/// skips MSAA with more samples than `gpu` takes, and ray tracing stays as
/// it is where the GPU cannot trace rays
pub fn step(o:*Options,set:Setting,dir:i32,gpu:Gpu)void{
  // the most samples the GPU takes
  const most=gpu.samples;
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
    .renderDistance=>{
      // how many distances are offered (no wrapping: nearest and furthest stay)
      const n:i32=renderRings.len;
      o.renderDistance=renderRings[@intCast(m.clamp(@as(i32,@intCast(ringsIndex(o.renderDistance)))+dir,0,n-1))];
    },
    .lightShadows=>{
      // how many levels there are
      const n:i32=@intCast(fields(LightShadows).len);
      o.lightShadows=@enumFromInt(@mod(@as(i32,@intFromEnum(o.lightShadows))+dir,n));
    },
    .rayTracing=>if(gpu.rays){o.rayTracing=!o.rayTracing;},
  }
}
/// what `set` is now on `gpu`, as shown (ray tracing says so where the GPU
/// cannot)
pub fn shown(o:*const Options,set:Setting,gpu:Gpu)[]const u8{
  return switch(set){
    .rayTracing=>if(gpu.rays)txt.nth(txt.s.hud.toggle,@intFromBool(o.rayTracing))else txt.s.hud.noRays,
    .antialias=>txt.nth(txt.s.hud.antialias,@intFromEnum(o.aa)),
    .vsync=>txt.nth(txt.s.hud.toggle,@intFromBool(o.vsync)),
    .fullscreen=>txt.nth(txt.s.hud.toggle,@intFromBool(o.fullscreen)),
    .autosave=>txt.nth(txt.s.hud.autosave,autosaveIndex(o.autosave)),
    .renderDistance=>txt.nth(txt.s.hud.renderDistance,ringsIndex(o.renderDistance)),
    .lightShadows=>txt.nth(txt.s.hud.lightShadows,@intFromEnum(o.lightShadows)),
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
    /// `renderDistance = <rings>`
    renderDistance:?[]const u8=null,
    /// `lightShadows = off|few|more|full`
    lightShadows:?[]const u8=null,
    /// `rayTracing = on|off`
    rayTracing:?[]const u8=null,
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
  if(f.renderDistance)|v|if(parseInt(u8,v,10))|n|{o.renderDistance=renderRings[ringsIndex(n)];}else|_|{};
  if(f.lightShadows)|v|o.lightShadows=stringToEnum(LightShadows,v) orelse o.lightShadows;
  if(f.rayTracing)|v|o.rayTracing=!eql(u8,v,off);
  return o;
}
/// writes `o` as cfg source.
pub fn format(o:*const Options,w:*Writer)Writer.Error!void{
  try w.print("# Parasymi options: written by the game (pause menu, OPTIONS)\n" ++
    "# autosave: minutes between autosaves (0: never)\n" ++
    "# renderDistance: rings of 32-tile chunks drawn round you\n" ++
    "[options]\nantialias = {t}\nvsync = {s}\nfullscreen = {s}\nautosave = {d}\nrenderDistance = {d}\n",.{
    o.aa,if(o.vsync)on else off,if(o.fullscreen)on else off,o.autosave,o.renderDistance,
  });
  try w.print("lightShadows = {t}\nrayTracing = {s}\n",.{o.lightShadows,if(o.rayTracing)on else off});
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
  var buf:[fileMost]u8=undefined;
  var w:Writer=.fixed(&buf);
  format(o,&w) catch return error.OptionsUnwritable;
  home.dir().writeFile(io,.{.sub_path=filePath,.data=w.buffered()}) catch return error.OptionsUnwritable;
}
test"options round-trip through their file; unknown values keep the defaults"{
  // a set of options off the defaults, written out
  const o:Options=.{.aa=.fxaa,.vsync=false,.fullscreen=true,.autosave=15,.renderDistance=6,.lightShadows=.few,.rayTracing=false};
  // room for the file, and the writer that fills it
  var buf:[fileMost]u8=undefined;
  var w:Writer=.fixed(&buf);
  try format(&o,&w);
  try testing.expectEqual(o,parse(w.buffered()));
  try testing.expectEqual(Options{},parse("[options]\nantialias = sparkle\n"));
  try testing.expectEqual(Options{},parse(""));
  // an interval not offered snaps to the next longer one
  try testing.expectEqual(@as(u8,10),parse("[options]\nautosave = 7\n").autosave);
  // a render distance not offered snaps to the next further one
  try testing.expectEqual(@as(u8,8),parse("[options]\nrenderDistance = 7\n").renderDistance);
}
test"the render distance steps between its stops without wrapping"{
  // the defaults: four rings
  var o:Options=.{};
  try testing.expectEqual(@as(i32,4),o.rings());
  step(&o,.renderDistance,1,.{.samples=4});
  try testing.expectEqual(@as(i32,5),o.rings());
  setStop(&o,.renderDistance,99);
  step(&o,.renderDistance,1,.{.samples=4});
  try testing.expectEqual(@as(i32,8),o.rings());
  setStop(&o,.renderDistance,0);
  step(&o,.renderDistance,-1,.{.samples=4});
  try testing.expectEqual(@as(i32,2),o.rings());
}
test"anti-aliasing turns both ways and skips what the GPU cannot take"{
  // options with anti-aliasing off
  var o:Options=.{.aa=.off};
  step(&o,.antialias,1,.{.samples=4});
  try testing.expectEqual(Antialias.fxaa,o.aa);
  step(&o,.antialias,-1,.{.samples=4});
  step(&o,.antialias,-1,.{.samples=4});
  // msaa8 is beyond 4 samples: wraps back to msaa4
  try testing.expectEqual(Antialias.msaa4,o.aa);
  step(&o,.antialias,1,.{.samples=4});
  try testing.expectEqual(Antialias.off,o.aa);
  step(&o,.vsync,1,.{.samples=4});
  try testing.expect(!o.vsync);
  // autosave: 5 minutes by default, wrapping round to never
  try testing.expectEqual(@as(u8,5),o.autosave);
  step(&o,.autosave,-1,.{.samples=4});
  try testing.expectEqual(@as(u8,2),o.autosave);
  o.autosave=60;
  step(&o,.autosave,1,.{.samples=4});
  try testing.expectEqual(@as(u8,0),o.autosave);
  // the points of light's shadows: the full look by default, wrapping round to none
  try testing.expectEqual(LightShadows.full,o.lightShadows);
  step(&o,.lightShadows,1,.{.samples=4});
  try testing.expectEqual(LightShadows.off,o.lightShadows);
  try testing.expectEqual(@as(usize,0),o.lightShadows.lights());
  step(&o,.lightShadows,-1,.{.samples=4});
  try testing.expectEqual(@as(usize,4),o.lightShadows.lights());
}
test"each setting is a toggle, a picker or a slider; a slider is set by its stops"{
  // the defaults
  var o:Options=.{};
  try testing.expectEqual(Kind.toggle,kind(.vsync));
  try testing.expectEqual(Kind.picker,kind(.antialias));
  try testing.expectEqual(Kind.slider,kind(.autosave));
  try testing.expect(isOn(&o,.vsync,.{})and!isOn(&o,.fullscreen,.{}));
  try testing.expectEqual(autosaveMinutes.len,stops(.autosave));
  try testing.expectEqual(@as(usize,3),stopOf(&o,.autosave));
  setStop(&o,.autosave,1);
  try testing.expectEqual(@as(u8,1),o.autosave);
  setStop(&o,.autosave,99);
  try testing.expectEqual(@as(u8,60),o.autosave);
}
test"ray tracing is on by default where the GPU can, and stays off where it cannot"{
  // the defaults, on a GPU that traces rays and on one that cannot
  var o:Options=.{};
  const can:Gpu=.{};
  const cannot:Gpu=.{.rays=false};
  try testing.expectEqual(Kind.toggle,kind(.rayTracing));
  try testing.expect(isOn(&o,.rayTracing,can));
  try testing.expect(!isOn(&o,.rayTracing,cannot));
  // where it cannot, turning it does nothing
  step(&o,.rayTracing,1,cannot);
  try testing.expect(o.rayTracing);
  step(&o,.rayTracing,1,can);
  try testing.expect(!o.rayTracing and !isOn(&o,.rayTracing,can));
  try testing.expect(!parse("[options]\nrayTracing = off\n").rayTracing);
  try testing.expect(parse("[options]\n").rayTracing);
}
