//! Parasymi: a garden of magically infused plants, parasitic and symbiotic,
//! growing toward something beyond comprehension. This is the game's start:
//! it reads the command line, opens the window, renderer and sound, grows
//! the meshes behind the loading screen, then runs the frame loop and
//! answers the garden's save, load and fullscreen requests.
//!
//! layers (each only imports the ones above it):
//!   engine (core, platform, anim, gfx, world, render, ui) -> gfx -> world
//!   -> sim -> game -> render -> main, all reached through lib.zig
/// the import hub every game module is reached through
const lib=@import("lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type, passed to whatever keeps memory
const Allocator=std.mem.Allocator;
/// the I/O interface: files, the clock, randomness, the thread pool
const Io=std.Io;
/// reads a decimal number from an argument (`--tod=0.5`)
const parseFloat=std.fmt.parseFloat;
/// reads a whole number from an argument (`--seed=0x1234`)
const parseInt=std.fmt.parseInt;
/// whether two byte strings are the same
const eql=std.mem.eql;
/// whether two values are the same field by field (the settings)
const eqlDeep=std.meta.eql;
/// the command line's flags, split once at the edge (engine core)
const flag=lib.engine.core.flag;
/// every flag the game takes, by its own spelling (`--name` or
/// `--name=value`): read once by `flag.parse` and switched on, so a flag
/// the switch forgets won't build
const Flag=enum{
  /// `--full=`: the wolf's belly held this full
  full,
  /// `--inspect[=focus]`: orbit and take shots, then quit
  inspect,
  /// `--record[=S]`: a playback trail of shots and notes
  record,
  /// `--link`: talk with Claude while playing
  link,
  /// `--shots=`: how many inspect shots
  shots,
  /// `--orbit=`: seconds an inspect orbit takes
  orbit,
  /// `--dist=`: how far the inspect eye stands
  dist,
  /// `--pitch=`: degrees the inspect eye looks down
  pitch,
  /// `--novsync`: frames as fast as they come
  novsync,
  /// `--rt=on|off`: ray-traced shadows or not
  rt,
  /// `--demo`: the test garden, fast-forwarded
  demo,
  /// `--stress`: a 120×120 plant field
  stress,
  /// `--load`: the newest saved garden
  load,
  /// `--unforming`: the world event begins at once
  unforming,
  /// `--act2`: the star hyena's act
  act2,
  /// `--tod=`: the time of day
  tod,
  /// `--speed=`: how much faster the world runs
  speed,
  /// `--seed=`: the world's seed
  seed,
  /// `--plant=`: one species alone
  plant,
  /// `--structure=`: one structure alone
  structure,
  /// `--sculpt=`: one sculpt alone, looping its clip
  sculpt,
  /// `--samples=`: library meshes side by side
  samples,
  /// `--state=`: how the lone thing is held or looped
  state,
  /// `--period=`: seconds a loop takes
  period,
  /// `--lit=`: the share of light a lone structure is held in
  lit,
  /// `--crown=`: the crown a lone structure wears
  crown,
  /// `--panel=`: a HUD panel held open
  panel,
  /// `--pad`: the pad held as last used (its buttons in every hint), for shots
  pad,
};
/// a value seen as its raw bytes (a fresh seed is filled through it)
const asBytes=std.mem.asBytes;
/// what the process is handed at start: allocators, I/O, args, environment
const Init=std.process.Init;
/// the log, for warnings and the world's seed
const log=std.log;
/// the engine package
const engine=lib.engine;
/// the window library: the window, its events and the clock
const glfw=engine.glfw;
/// the keys and buttons held this frame
const Input=engine.platform.input.Input;
/// windowed or fullscreen, and the switch between them
const Display=engine.platform.display.Display;
/// the garden's renderer module: syncing, meshes ready, screenshots
const renderer=lib.renderer;
/// the renderer itself: the GPU and every pass
const Renderer=renderer.Renderer;
/// play: the running game and its modes
const play=lib.play;
/// the running game: world, player, sky, HUD, everything played
const Game=play.Game;
/// turns the game into a scene for the renderer to draw
const view=lib.view;
/// the test gardens: `--demo` and `--stress`
const setups=lib.setups;
/// saving, loading, listing and deleting gardens
const save=lib.save;
/// every player-facing string
const txt=lib.txt;
/// the key and button bindings, read from controls.cfg
const controls=lib.controls;
/// the gardener's settings module: load and save
const options=lib.options;
/// the gardener's folder (%LOCALAPPDATA%\Parasymi), where every file lives
const home=lib.home;
/// the `--inspect` camera turn: what it circles and how
const orbit=lib.orbit;
/// the loading screen module: its stages and progress
const loading=lib.loading;
/// one thing standing alone (`--plant=` / `--structure=`)
const specimen=lib.specimen;
/// the plant species, named by `--plant=`
const species=lib.species;
/// the structures registry, named by `--structure=`
const st=lib.structures;
/// a name turned into its enum tag, or null if none matches
const stringToEnum=std.meta.stringToEnum;
/// the loading screen itself
const Loading=loading.Loading;
/// the streamed world of chunks
const World=lib.world.World;
/// writes a captured frame as a PNG
const png=lib.engine.core.png;
/// formats text into a fixed buffer (a shot's path)
const bufPrint=std.fmt.bufPrint;
/// a directory, for writing the shots
const Dir=Io.Dir;
/// the path separator, as a string
const sepStr=std.fs.path.sep_str;
/// the gardener's settings: vsync, antialiasing, fullscreen and the rest
const Options=options.Options;
/// all the maths: vectors, matrices, easing
const m=lib.engine.core.math;
/// the garden's sound: footsteps, twinkles, music, hums
const sound=lib.sound;
/// the audio device, fed the garden's sound commands from the frame loop
const Sounds=engine.platform.audio.Output(sound.Sounds);
/// a stalled frame (window drag, hitch) counts as at most this long (s)
const maxFrameDt:f64=0.1;
/// the sound hears of the daylight once it has changed this much
const dayTold:f32=0.01;
/// `--demo` fast-forwards its garden this many seconds
/// field this many tiles on a side
const demoForward=25;
/// how long act 2's demo garden runs on before play (s): the heart through
/// its story to a builder
const demoAct2=200;
/// `--stress` sows a field this many tiles on a side
const stressSide=120;
/// most streamed chunks meshed in one frame (`renderer.meshMs` also caps it)
const meshBudget=6;
/// behind the loading screen a frame meshes the ground for this long (ms)
const loadMeshMs:f64=25;
/// `--inspect` writes its screenshots here, under the working directory
/// (kept out of git)
const shots="shots";
/// the game's start: reads the flags, opens the window, renderer and sound,
/// grows the world (fresh, loaded, a test garden or one thing alone), then
/// runs frames until the window closes, answering the garden's requests
pub fn main(init:Init)!void{
  // the general allocator, and the I/O everything is done through
  const gpa=init.gpa;
  const io=init.io;
  // the command line, kept in the start's arena
  const args=try init.minimal.args.toSlice(init.arena.allocator());
  // every file of the gardener's lives in their folder, made on first start
  // (with the settings, strings and controls in it); files kept beside the
  // game before move in once
  try home.open(io,init.environ_map);
  defer home.close(io);
  home.adopt(io,options.filePath,options.filePath);
  home.adopt(io,save.legacy,home.saves++sepStr++save.legacy);
  // the gardener's sculpts and their clips, read once (sculpts.zig)
  try lib.sculpts.load(gpa,io);
  defer lib.sculpts.unload();
  // the gardener's settings; `--novsync` and `--rt=on|off` override theirs
  // for this run
  var opts=try options.load(gpa,io);
  // `--demo`, `--stress` and `--load`: which garden to start in
  var demo=false;
  var stress=false;
  var load=false;
  // `--tod=`: the time of day to start at (0..1), else the sky's own
  var tod:?f32=null;
  // `--speed=`: how many times faster the world runs (for slow things watched unattended)
  var speed:f64=1;
  // the world's seed: `--seed=`, else one of its own (see below)
  var seed:?u64=null;
  // `--inspect[=player|<species>|<structure>|x,z]` turns the camera round
  // it, saving screenshots, then closes; `--shots=`, `--orbit=` (seconds a
  // turn), `--dist=`, `--pitch=` (degrees) shape it
  var inspect:?orbit.Focus=null;
  var turn:orbit.Orbit=.{};
  // `--record[=S]`: a shot and a note every S seconds of ordinary play,
  // into `shots/trail_<time>/` (not with `--inspect`, whose shots win)
  var trail:?lib.trail.Trail=null;
  // the trail's folder, once made
  var trailBuf:[64]u8=undefined;
  var trailDir:[]const u8="";
  // `--link`: talk with Claude while playing, through the link folder the
  // bridge (tools/bridge.zig) shares; the chat opens with its key
  var linkOn=false;
  // `--plant=<species>` / `--structure=<kind>` stands it alone (its
  // meshes alone built), `--state=` held or looped (grow, mature, 0.4,
  // 0.2..0.8; plants wither, flow, drain, dark, live; structures idle,
  // active; default grow), `--period=` seconds a loop; `--sculpt=<name>` one sculpt looping its clip; `--samples=<mesh>,...`
  // lays library meshes side by side along the x axis to compare
  var lone:?specimen.Specimen=null;
  var state:specimen.State=.grow;
  var period:?f32=null;
  // a structure alone: `--lit=` the share of light it is held in (its crown
  // gathers, its leaves turn ley-blue), `--crown=<diadem|circlet|orrery|lotus>`
  // the crown it is given
  var lit:?f32=null;
  var crown:?lib.lightCrown.Design=null;
  // `--panel=<belly|research|paused|options|gardens|naming|chat>` holds that panel open
  // (and keeps the HUD in `--inspect` shots); `--panel=overview` holds alt
  // mode on while roaming
  var panel:?play.Mode=null;
  // decision: alt mode is a flag beside the mode, not a mode, so
  // `--panel=overview` roams with it held on
  var overview=false;
  // `--unforming`: the world event begins at once (its study learned), to
  // watch it unattended
  // decision: a test flag beside `--demo`, not a garden of its own
  var unforming=false;
  // `--act2`: the garden begins in the star hyena's act, after the unforming
  // has run its course, the seed it let fall in his keeping
  // decision: a test flag until the wolf's rooting begins act 2 in play
  var act2=false;
  // `--full=`: the wolf's belly held this full (0..1), for shots of it at one size
  var full:?f32=null;
  // `--pad`: the pad held as last used, so shots show its buttons
  var padHeld=false;
  for(args[1..])|a|{
    // the argument as one of the flags (none: it is passed over, as ever),
    // and its value, for the flags that need one
    const f=flag.parse(Flag,a) orelse continue;
    const bare=f.value==null;
    switch(f.name){
      .inspect=>inspect=if(f.value)|v|try orbit.Focus.parse(v)else .player,
      .record=>trail=if(f.value)|v|.{.every=try parseFloat(f32,v)}else .{},
      .link=>if(bare){linkOn=true;},
      .novsync=>if(bare){opts.vsync=false;},
      .demo=>if(bare){demo=true;},
      .stress=>if(bare){stress=true;},
      .load=>if(bare){load=true;},
      .unforming=>if(bare){unforming=true;},
      .act2=>if(bare){act2=true;},
      .pad=>if(bare){padHeld=true;},
      .rt=>if(f.value)|v|{
        if(eql(u8,v,"on"))opts.rayTracing=true;
        if(eql(u8,v,"off"))opts.rayTracing=false;
      },
      .full=>if(f.value)|v|{full=m.clamp01(try parseFloat(f32,v));},
      .shots=>if(f.value)|v|{turn.shots=try parseInt(u32,v,0);},
      .orbit=>if(f.value)|v|{turn.period=try parseFloat(f32,v);},
      .dist=>if(f.value)|v|{turn.dist=try parseFloat(f32,v);},
      .pitch=>if(f.value)|v|{turn.pitch=m.rad(try parseFloat(f32,v));},
      .tod=>if(f.value)|v|{tod=try parseFloat(f32,v);},
      .speed=>if(f.value)|v|{speed=try parseFloat(f64,v);},
      .seed=>if(f.value)|v|{seed=try parseInt(u64,v,0);},
      .plant=>if(f.value)|v|{lone=.{.what=.{.plant=stringToEnum(species.Id,v) orelse return error.BadPlant}};},
      .structure=>if(f.value)|v|{lone=.{.what=.{.structure=stringToEnum(st.Kind,v) orelse return error.BadStructure}};},
      .sculpt=>if(f.value)|v|{
        // the sculpt named, which must be on the shelf
        const i=lib.sculpts.find(v) orelse {
          log.err("{s}: no such sculpt in "++lib.sculptDoc.dir,.{a});
          return error.BadSculpt;
        };
        if(i>=lib.sculpts.slots){
          log.err("{s}: only the first {d} sculpts by name are drawn",.{a,lib.sculpts.slots});
          return error.BadSculpt;
        }
        lone=.{.what=.{.sculpt=@intCast(i)}};
      },
      .samples=>if(f.value)|v|{lone=.{.what=.{.samples=try specimen.Samples.parse(v)}};},
      .state=>if(f.value)|v|{state=try specimen.State.parse(v);},
      .period=>if(f.value)|v|{period=try parseFloat(f32,v);},
      .lit=>if(f.value)|v|{lit=m.clamp01(try parseFloat(f32,v));},
      .crown=>if(f.value)|v|{crown=stringToEnum(lib.lightCrown.Design,v) orelse return error.BadCrown;},
      .panel=>if(f.value)|v|{
        if(eql(u8,v,"overview")){
          panel=.roam;
          overview=true;
        }else panel=switch(stringToEnum(play.Mode,v) orelse return error.BadPanel){
          inline.belly,.research,.paused,.options,.keybinds,.gardens,.naming,.title,.chat=>|p|p,
          else=>return error.BadPanel,
        };
      },
    }
  }
  if(lone)|*l|{
    if(!state.suits(l.what))return error.BadState;
    l.state=state;
    if(period)|t|l.period=@max(t,0.1);
    l.lit=lit;
    l.crown=crown;
  }
  // the only read of the controls file: no key or button is named in code.
  // First, so the strings can show what each action is bound to.
  try controls.load(gpa,io);
  defer controls.unload();
  // the only read of the strings file: everything shown comes from it
  try txt.load(gpa,io);
  defer txt.unload(gpa);
  try glfw.init();
  defer glfw.terminate();
  if(!glfw.isVulkanSupported())return error.VulkanUnsupported;
  glfw.windowHint(.client_api,.no_api);
  // the window, sized as play asks and titled from the strings
  const window=try glfw.createWindow(play.windowSize[0],play.windowSize[1],try init.arena.allocator().dupeZ(u8,txt.s.window.title),null,null);
  defer window.destroy();
  // the input, reading keys and buttons from the window
  var input:Input=.{.win=window};
  input.attach();
  // the display mode, windowed at first
  var display:Display=.{.win=window};
  // the renderer, built for the settings (and, for one thing alone, only its meshes)
  const r=try Renderer.init(gpa,window,opts.vsync,opts.aa,.{.only=if(lone)|*l|try l.only(init.arena.allocator())else null,.io=io});
  defer r.deinit();
  opts.aa=r.antialiasing();
  try r.pointShadows(opts.lightShadows.lights(),opts.lightShadows.res());
  r.setRays(opts.rayTracing);
  // the loading screen shows while every mesh grows (on a thread of its
  // own), the world wakes and its ground is meshed. Until the world is
  // woken its chunks are counted as many as stream in round the gardener.
  var loadScreen=Loading.init(gpa);
  defer loadScreen.deinit();
  // the clock at the last frame (s)
  var last=glfw.getTime();
  // how many forms are grown, and the whole loading count: forms, the world, its chunks
  const forms=renderer.meshProgress(r)[1];
  const whole=forms+1+play.streamChunks;
  while(!try renderer.meshesReady(r)){
    if(!try loadFrame(&loadScreen,r,&input,&last,.forms,.{.done=renderer.meshProgress(r)[0],.total=whole}))return;
  }
  if(!try loadFrame(&loadScreen,r,&input,&last,.world,.{.done=forms,.total=whole}))return;
  // decision: every start grows a world of its own, unless `--seed=` names
  // one; the test gardens (`--demo`, `--stress`, one thing alone) keep the
  // stock world, so they and their screenshots stay alike run to run. A
  // loaded garden brings its own seed.
  // the world's seed: named, the stock one, or fresh from the I/O's randomness
  const world=seed orelse if(demo or stress or lone!=null)play.defaultSeed else fresh:{
    // the fresh seed being filled
    var s:u64=undefined;
    io.random(asBytes(&s));
    break:fresh s;
  };
  log.info("world seed 0x{x}",.{world});
  // the running game, grown from that seed, its heavy work (chunks
  // generated and meshed, plants relinked) split over the pool
  var game=try Game.init(gpa,io,world);
  defer game.deinit();
  game.opts=opts;
  game.gpu=.{.samples=r.maxSamples(),.rays=r.ctx.rayTracing};
  // the garden's sound; without a device it plays on in silence
  const sounds:?*Sounds=Sounds.open(gpa,io,.init(world,sound.rate),.{.name=txt.s.window.title,.rate=sound.rate})catch|e|none:{
    log.warn("no sound: {t}",.{e});
    break:none null;
  };
  defer if(sounds)|o|o.close(gpa,io);
  // what is in effect; the window opens windowed, so a fullscreen setting
  // is applied on the first frame
  var applied=opts;
  applied.fullscreen=false;
  if(lone)|l|{
    // alone in a fresh world: no garden loaded, sown or saved
    game.specimen=l;
    // (shown in act 2: put down in the hyena's act, no world event run)
    if(act2)game.act=.hyena;
    try game.specimen.?.sow(&game);
  }else{
    if(load){
      relist(gpa,io,&game);
      if(game.gardens.items.len>0)_=try restore(gpa,io,&game,r,game.gardens.items[0].name);
    }
    if(demo and !act2)try setups.demo(&game,demoForward);
    if(stress)try setups.stress(&game,stressSide);
  }
  if(tod)|t|game.sky.tod=t;
  game.speed=speed;
  game.player.fullHeld=full;
  if(unforming)game.prog.done.insert(.unforming);
  if(act2 and lone==null)try lib.act.begin(&game);
  if(act2 and demo)try setups.act2(&game,demoAct2);
  // decision: a plain start opens on the main menu (the wolf asleep, the
  // fresh garden grown behind it); a start that names what to show (a
  // test garden, a lone thing, a load, an act, the world event, shots)
  // goes straight in, as before
  if(lone==null and !demo and !stress and !load and !act2 and !unforming and inspect==null){
    game.mode=.title;
    relist(gpa,io,&game);
  }
  if(inspect)|f|{
    turn.focus=f;
    Dir.cwd().createDirPath(io,shots)catch|e|log.err("{s}: {t}",.{shots,e});
  }else if(trail!=null){
    // the time it began (s since 1970), naming the folder
    const began=@divFloor(Io.Clock.real.now(io).nanoseconds,std.time.ns_per_s);
    trailDir=bufPrint(&trailBuf,shots++sepStr++lib.trail.prefix++"{d}",.{began}) catch unreachable;
    Dir.cwd().createDirPath(io,trailDir)catch|e|{
      log.err("{s}: {t}",.{trailDir,e});
      trail=null;
    };
    if(trail!=null)log.info("recording a trail into {s}",.{trailDir});
  }
  // the working directory's path, told in the link's log lines
  var hereBuf:[lib.link.maxWhere]u8=undefined;
  const here=lib.link.here(io,&hereBuf);
  // the link's folder in the working directory, opened (none without
  // `--link`, or if it cannot be)
  var lk:?lib.link.Link=if(linkOn)lib.link.Link.open(io,Dir.cwd(),here)catch|e|blk:{
    log.err("link: {t}",.{e});
    break:blk null;
  }else null;
  defer if(lk)|*l|l.close(io);
  if(lk!=null)log.info("linked: the chat to Claude opens with its key, files in {s}\\{s}",.{here,lib.link.folder});
  // what was pressed since the link's state was last written, and its clock
  var linkState:lib.trail.Trail=.{.every=lib.link.stateEvery};
  // the shots still being written apart from the frames, each waited for
  // before the game closes
  var writing:std.ArrayList(Io.Future(void))=.empty;
  defer{
    for(writing.items)|*w|w.await(io);
    writing.deinit(gpa);
  }
  if(!try ground(&loadScreen,r,&input,&last,&game.world,forms+1))return;
  // play's clock runs on from the screen's, so it fades off without a jump
  game.uiTime=loadScreen.time;
  // what the sound was last told of the view
  var inEyes=false;
  // and of the daylight (none yet, so the first frame tells it)
  var toldDay:f32=-1;
  // and whether the arsthraxia was last heard humming, so its silence is told once
  var arsHumming=false;
  // and the radiant plant gathering it was last told of, if any
  var formingWas:?u32=null;
  // and whether it was told of one, so its leaving is told once
  var formingTold=false;
  // and how loud each part was last set (none yet, so the first frame tells it)
  var toldVolume:?lib.sound.mixer.Volume=null;
  // and the unforming's moment when last heard (< 0 never)
  var unformHeard:f32=-1;
  // quitting: closed once the garden's picture is taken
  var closing=false;
  while(!window.shouldClose()){
    glfw.pollEvents();
    input.update();
    if(padHeld)input.padLast=true;
    // every hint names the pad's buttons while the pad was used last
    txt.showPad(input.padLast);
    // the clock this frame (s)
    const now=glfw.getTime();
    // a stalled frame must not fling animation or movement
    const dt=@min(now-last,maxFrameDt);
    last=now;
    // the swapchain's size this frame (px)
    const screen=r.extent();
    try game.update(&input,@floatCast(dt),screen);
    if(lk)|*l|tendLink(gpa,io,l,&game,&linkState,&input,@floatCast(dt));
    // the sounds are heard from the view, told first so this frame's are placed from it
    if(sounds)|o|{
      o.send(.{.ear=game.ear()})catch|e|log.warn("ear: {t}",.{e});
      o.send(.{.space=game.space()})catch|e|log.warn("space: {t}",.{e});
    }
    for(game.player.footfalls())|ff|if(ff)|f|if(sounds)|o|if(lib.act.steps(game.act)){
      o.send(.{.step=.{.fall=f,.muffle=game.muffle(f.at)}})catch|e|log.warn("footstep: {t}",.{e});
    };
    if(game.starlight.twinkled())|t|if(sounds)|o|{
      o.send(.{.twinkle=.{.spark=t,.muffle=game.muffle(t.at)}})catch|e|log.warn("twinkle: {t}",.{e});
    };
    // the day's music follows the daylight
    if(@abs(game.sky.daylight()-toldDay)>dayTold)if(sounds)|o|{
      o.send(.{.daylight=game.sky.daylight()})catch|e|log.warn("daylight: {t}",.{e});
      toldDay=game.sky.daylight();
    };
    // the asthraxia's research hums and chimes
    if(sounds)|o|{
      if(game.arsthraxiaState())|cmd|{
        o.send(cmd)catch|e|log.warn("arsthraxia:{t}",.{e});
        arsHumming=true;
      }else if(arsHumming){
        // its research done or gone: hushed, once
        o.send(.{.arsthraxia=.{.progress=0,.fed=0,.complete=false}})catch|e|log.warn("arsthraxia:{t}",.{e});
        arsHumming=false;
      }
    }
    // the gardener's volumes, told as they change
    if(sounds)|o|{
      // how loud each part is set now
      const v:lib.sound.mixer.Volume=.{.all=options.gain(game.opts.volume),.music=options.gain(game.opts.music),.sounds=options.gain(game.opts.sounds)};
      if(toldVolume==null or !eqlDeep(toldVolume.?,v)){
        o.send(.{.volume=v})catch|e|log.warn("volume: {t}",.{e});
        toldVolume=v;
      }
    }
    // a radiant plant gathering near the wolf, each fragment heard landing
    if(sounds)|o|{
      if(game.formingState(formingWas))|fg|{
        o.send(.{.forming=fg})catch|e|log.warn("forming: {t}",.{e});
        // once whole it is told no more, so the next one is heard
        formingWas=if(fg.growth>=1)null else fg.id;
        formingTold=true;
      }else if(formingTold){
        o.send(.{.forming=null})catch|e|log.warn("forming: {t}",.{e});
        formingWas=null;
        formingTold=false;
      }
    }
    // the unforming heard while it runs: its clock, what broke, what withers
    if(lib.unforming.running(&game.unforming) and game.specimen==null)if(sounds)|o|{
      o.send(.{.unforming=lib.unforming.heard(&game,unformHeard)})catch|e|log.warn("unforming: {t}",.{e});
      unformHeard=game.unforming.t;
    };
    // out of the wolf's eyes its sap is heard settling
    if(game.cam.inEyes()!=inEyes)if(sounds)|o|{
      o.send(.{.eyes=!inEyes})catch|e|log.warn("eyes: {t}",.{e});
      inEyes=!inEyes;
    };
    if(game.request)|rq|{
      game.request=null;
      // a lone thing's world is never saved, and no garden replaces it
      if(game.specimen!=null and rq!=.bindings){
        if(rq==.quit or rq==.leave)window.setShouldClose(true);
        continue;
      }
      switch(rq){
        .save=>if(game.slot)|n|keep(gpa,io,&game,n),
        .saveAs=>|n|keep(gpa,io,&game,n),
        .autosave=>keep(gpa,io,&game,save.Name.of(save.auto).?),
        .delete=>|n|letGo(gpa,io,&game,n),
        .load=>{
          // the garden being played as last saved, else the newest
          const n=game.slot orelse newest:{
            relist(gpa,io,&game);
            if(game.gardens.items.len==0){
              game.prog.say(txt.s.msg.noSave,.{error.NoSave});
              break:newest null;
            }
            break:newest game.gardens.items[0].name;
          };
          if(n)|nn|if(try restore(gpa,io,&game,r,nn)){
            if(!try reground(&loadScreen,r,&input,&last,&game))break;
          };
        },
        .loadFrom=>|n|if(try restore(gpa,io,&game,r,n)){
          if(!try reground(&loadScreen,r,&input,&last,&game))break;
        },
        .list=>relist(gpa,io,&game),
        .bindings=>try rebound(gpa,io,&game),
        .quit=>{
          // a garden never named is kept as the autosave
          keep(gpa,io,&game,game.slot orelse save.Name.of(save.auto).?);
          // (closed once its picture is taken, the next frame)
          if(game.pictureFor==null)window.setShouldClose(true)else closing=true;
        },
        // (from the main menu: no garden was entered, none is kept)
        .leave=>window.setShouldClose(true),
      }
    }
    if(!eqlDeep(game.opts,applied))try apply(io,&game,r,&display,&applied);
    // inspecting, the camera turns round the focus and the HUD is hidden
    // else a trail asks for one now and then, the HUD kept in it
    const shoot=if(inspect!=null)turn.step(&game,@floatCast(dt))else if(trail)|*t|t.step(&input,@floatCast(dt))else false;
    // the clock before the simulation, to time it
    const t0=glfw.getTime();
    try game.simulate(dt);
    game.simMs+=(@as(f32,@floatCast((glfw.getTime()-t0)*m.msPerS))-game.simMs)*play.timingEase;
    try renderer.syncWorld(r,&game.world,meshBudget,renderer.meshMs);
    game.renderStats=r.stats;
    if(panel)|p|game.mode=p;
    if(overview)game.overview=true;
    lookPicture(gpa,io,&game);
    game.weather.tick(game.moved);
    // what the renderer draws this frame
    var scene=try view.scene(&game,screen);
    // a garden just saved has its picture taken: the world copied out
    // before the HUD is drawn over it (the screen still shows the HUD)
    const picturing=game.pictureFor!=null and inspect==null;
    if(inspect!=null and panel==null){
      scene.ui=&.{};
    }else if(loadScreen.fading()){
      // the loading screen fades off the first frames of play, over the HUD
      loadScreen.fadeStep(@floatCast(dt));
      loadScreen.time=game.uiTime;
      try loadScreen.draw(&game.ui,screen[0],screen[1]);
      scene.ui=game.ui.v.items;
    }
    // whether the window was resized since the last frame
    const resized=input.resized;
    input.resized=false;
    // the link asked for a frame (and nothing is shooting the HUD away)
    const linkShot=if(lk)|l|l.frameWanted and inspect==null else false;
    r.capture=shoot or linkShot or picturing;
    r.bare=picturing;
    try r.draw(&scene,resized);
    game.air=if(r.probed)|p|.{p[0],p[1],p[2]}else null;
    if(game.weather.soak(&game.world,r.field,r.fieldReads))game.prog.discover(.firstRain);
    if(r.shot())|sh|{
      // the shot's path
      var pb:[96]u8=undefined;
      if(inspect!=null){
        // the focus's name, in `shots/<focus>_<n>.png`
        var nb:[32]u8=undefined;
        try snap(gpa,io,sh,.{.path=bufPrint(&pb,shots++sepStr++"{s}_{d}.png",.{turn.focus.name(&nb),turn.taken}) catch unreachable},&writing);
        turn.took();
      }else{
        // the last shots' tasks are long done by now: let them go, so a
        // long play keeps no list of them
        for(writing.items)|*w|w.await(io);
        writing.clearRetainingCapacity();
        if(shoot)if(trail)|*t|{
          try snap(gpa,io,sh,.{.path=bufPrint(&pb,"{s}"++sepStr++"{d}.png",.{trailDir,t.taken}) catch unreachable},&writing);
          noteTrail(io,t,&game,trailDir);
        };
        if(picturing)if(game.pictureFor)|n|{
          // beside its save, small; read back fresh by the menu
          var sb:[save.maxPath]u8=undefined;
          // decision: written in the frame (a small picture, once a save),
          // so the menu reads it whole the moment it looks
          try snapNow(gpa,io,sh,.{.path=save.picturePath(&sb,n),.dir=lib.home.dir(),.fit=pictureW});
          game.pictureFor=null;
          game.pictured=null;
          if(closing)window.setShouldClose(true);
        };
        if(linkShot)if(lk)|*l|{
          // half size, written whole before it takes the frame's name
          try snap(gpa,io,sh,.{.path=lib.link.frameTmp,.dir=l.dir,.half=true,.final=lib.link.frameFile},&writing);
          l.frameTaken(io);
        };
      }
      // (what time taking it still costs is not the world's, so the next
      // frame does not jump: springs would spike, timings slip)
      last=glfw.getTime();
      if(inspect!=null and turn.done())window.setShouldClose(true);
    }
  }
}
/// where a captured frame goes, and how
const ShotTo=struct{
  /// its path, in `dir`
  path:[]const u8,
  /// the folder it is written in (null: the working directory)
  dir:?Dir=null,
  /// whether it is written at half its size (each side), 2x2 pixels averaged
  half:bool=false,
  /// a name it takes once written whole (renamed in `dir`), if any
  final:?[]const u8=null,
  /// shrunk, each side by one whole step, till it is at most this wide
  /// (0: as taken); a saved garden's picture
  fit:u32=0,
};
/// how wide a saved garden's picture is at most (pixels)
const pictureW:u32=128;
/// a captured frame on its way to `shots/<focus>_<n>.png`: its own copy
/// of the pixels and of the path, freed once written
const ShotFile=struct{
  /// the frame's width, in pixels
  w:u32,
  /// its height, in pixels
  h:u32,
  /// its pixels, copied out of the renderer's
  px:[]u8,
  /// whether each pixel comes blue first
  bgra:bool,
  /// where it is written (its own copy of the path, in `to`)
  path:[]u8,
  /// where and how it goes
  to:ShotTo,
  /// encode it as a PNG and write it (failures are logged), then free it
  fn write(f:ShotFile,gpa:Allocator,io:Io)void{
    defer gpa.free(f.px);
    defer gpa.free(f.path);
    // the pixels written, and their size: shrunk if asked (halved, or by
    // the whole step that fits them in `fit`)
    const k:u32=if(f.to.half)2 else if(f.to.fit>0)@max(1,(f.w+f.to.fit-1)/f.to.fit)else 1;
    const px=if(k>1)png.shrink(gpa,f.px,f.w,f.h,k)catch|e|return log.err("{s}: {t}",.{f.path,e})else f.px;
    defer if(k>1)gpa.free(px);
    const w=f.w/k;
    const h=f.h/k;
    // the frame encoded as a PNG, and the folder it goes in
    const bytes=png.encode(gpa,w,h,px,if(f.bgra).bgra else.rgba)catch|e|return log.err("{s}: {t}",.{f.path,e});
    defer gpa.free(bytes);
    const d=f.to.dir orelse Dir.cwd();
    d.writeFile(io,.{.sub_path=f.path,.data=bytes})catch|e|return log.err("{s}: {t}",.{f.path,e});
    if(f.to.final)|fin|{
      Dir.rename(d,f.path,d,fin,io)catch|e|return log.err("{s}: {t}",.{fin,e});
      return;
    }
    log.info("shot {s}",.{f.path});
  }
};
/// one frame's chores for the link: a message sent handed to Claude, the
/// state written each second (with what was pressed), Claude's answers
/// and a frame asked for looked for; failures only warn
fn tendLink(gpa:Allocator,io:Io,l:*lib.link.Link,game:*Game,clock:*lib.trail.Trail,input:*const Input,dt:f32)void{
  // (a garden loaded in play is a fresh `Game`: told again each frame)
  game.linked=true;
  if(game.chatSent){
    game.chatSent=false;
    l.say(io,&game.chat,game.chat.typed.slice(),game.uiTime)catch|e|log.warn("link: {t}",.{e});
    game.chat.typed.clear();
  }
  if(clock.step(input,dt)){
    // the state's text
    var buf:[1024]u8=undefined;
    var w:Io.Writer=.fixed(&buf);
    lib.trail.describe(game,clock.pressed,&w)catch{};
    clock.pressed=.initEmpty();
    l.writeState(io,w.buffered())catch|e|log.warn("link: {t}",.{e});
  }
  if(l.step(dt))l.poll(gpa,io,&game.chat,game.uiTime)catch|e|log.warn("link: {t}",.{e});
}
/// writes the trail's note beside its shot, `<dir>/<n>.txt`, and counts
/// the shot taken (a failure only costs the note)
// decision: a few hundred bytes, written in the frame rather than on a task
fn noteTrail(io:Io,t:*lib.trail.Trail,game:*const Game,dir:[]const u8)void{
  // the note's text, and its path
  var buf:[1024]u8=undefined;
  var w:Io.Writer=.fixed(&buf);
  var pb:[96]u8=undefined;
  const path=bufPrint(&pb,"{s}"++sepStr++"{d}.txt",.{dir,t.taken}) catch unreachable;
  t.note(game,&w)catch{};
  Dir.cwd().writeFile(io,.{.sub_path=path,.data=w.buffered()})catch|e|log.warn("{s}: {t}",.{path,e});
}
/// send a captured frame off to be written as `path` (a PNG): copied, then
/// encoded and written on a task of its own beside the frames (the I/O's,
/// never a thread of ours), so the frame loop never waits on it; written
/// here if no task can be had
fn snap(gpa:Allocator,io:Io,sh:renderer.Shot,to:ShotTo,writing:*std.ArrayList(Io.Future(void)))Allocator.Error!void{
  // room to keep its task, and the frame with its own copies of the pixels and the path
  try writing.ensureUnusedCapacity(gpa,1);
  const px=try gpa.dupe(u8,sh.px);
  errdefer gpa.free(px);
  const f=ShotFile{.w=sh.w,.h=sh.h,.px=px,.bgra=sh.bgra,.path=try gpa.dupe(u8,to.path),.to=to};
  const future=io.concurrent(ShotFile.write,.{f,gpa,io})catch|e|{
    log.warn("shot written without a task of its own: {t}",.{e});
    return f.write(gpa,io);
  };
  writing.appendAssumeCapacity(future);
}
/// a captured frame written as `to` says, here and now (`snap` sends it
/// off to be written beside the frames instead)
fn snapNow(gpa:Allocator,io:Io,sh:renderer.Shot,to:ShotTo)Allocator.Error!void{
  // the frame with its own copies of the pixels and the path
  const px=try gpa.dupe(u8,sh.px);
  errdefer gpa.free(px);
  (ShotFile{.w=sh.w,.h=sh.h,.px=px,.bgra=sh.bgra,.path=try gpa.dupe(u8,to.path),.to=to}).write(gpa,io);
}
/// the saved gardens menu's picture: the chosen garden's read back when the
/// choice changes (or its picture was just taken), let go when none is
/// chosen; one that will not read shows none
fn lookPicture(gpa:Allocator,io:Io,game:*Game)void{
  // the garden whose picture is wanted, if any
  const want:?save.Name=if(game.mode==.gardens and game.garden>0 and game.garden<=game.gardens.items.len)game.gardens.items[game.garden-1].name else null;
  // whether the one read is that one already
  const same=if(want)|w|(if(game.pictured)|p|p.same(w)else false)else game.pictured==null and game.gardenPicture==null;
  if(same)return;
  if(game.gardenPicture)|p|p.deinit(gpa);
  game.gardenPicture=null;
  game.pictured=want;
  if(want)|w|game.gardenPicture=save.picture(gpa,io,w);
}
/// put the gardener's changed settings into effect (as far as the GPU and
/// monitor allow, which the settings then show) and keep them.
fn apply(io:Io,game:*Game,r:*Renderer,display:*Display,applied:*Options)!void{
  // the settings asked for
  const o=&game.opts;
  try r.antialias(o.aa);
  o.aa=r.antialiasing();
  try r.pointShadows(o.lightShadows.lights(),o.lightShadows.res());
  r.setRays(o.rayTracing);
  try r.setVsync(o.vsync);
  // whether the window is fullscreen now
  const full=display.mode==.fullscreen;
  if(o.fullscreen!=full)display.toggle()catch|e|{
    game.prog.say(txt.s.msg.noFullscreen,.{e});
    o.fullscreen=full;
  };
  options.save(o,io)catch|e|game.prog.say(txt.s.msg.optionsUnsaved,.{e});
  applied.*=o.*;
}
/// save the garden as `name`; saved by hand (not the autosave) it becomes
/// the garden being played. A failure is said.
fn keep(gpa:Allocator,io:Io,game:*Game,name:save.Name)void{
  game.sinceSave=0;
  save.save(game,gpa,io,name)catch|e|return game.prog.say(txt.s.msg.saveFailed,.{e});
  // its picture, taken next frame
  game.pictureFor=name;
  if(name.is(save.auto)){
    game.prog.say(txt.s.msg.autosaved,.{});
  }else{
    game.slot=name;
    game.prog.say(txt.s.msg.saved,.{name.slice()});
  }
  if(game.mode==.gardens)relist(gpa,io,game);
}
/// let the saved garden `name` go; played on, the garden has no name
/// again. A failure is said.
fn letGo(gpa:Allocator,io:Io,game:*Game,name:save.Name)void{
  save.remove(io,name)catch|e|return game.prog.say(txt.s.msg.deleteFailed,.{e});
  if(game.slot)|sl|if(sl.same(name)){
    game.slot=null;
  };
  game.prog.say(txt.s.msg.deleted,.{name.slice()});
  relist(gpa,io,game);
}
/// the keybinds menu changed the bindings: they are written to the
/// controls file, and the strings read again so every `{@action}` shows
/// the key now bound
// decision: the strings are read afresh rather than patched; nothing keeps
// a string past the frame it is shown in (messages are copied).
fn rebound(gpa:Allocator,io:Io,game:*Game)!void{
  // why the file could not be written, if it could not
  const failed:?controls.WriteError=if(controls.write(io))|_|null else|e|e;
  txt.unload(gpa);
  try txt.load(gpa,io);
  if(failed)|e|game.prog.say(txt.s.msg.controlsUnsaved,.{e});
}
/// the saved gardens menu's list, made afresh
fn relist(gpa:Allocator,io:Io,game:*Game)void{
  save.list(gpa,io,&game.gardens)catch|e|game.prog.say(txt.s.msg.noGardens,.{e});
  game.listed();
}
/// replace the running game with the saved garden `name` (keeping it on
/// failure); whether it was.
fn restore(gpa:Allocator,io:Io,game:*Game,r:*Renderer,name:save.Name)!bool{
  // the garden read from disk
  var loaded=save.load(gpa,io,name)catch|e|{
    game.prog.say(txt.s.msg.noSave,.{e});
    return false;
  };
  // played on as itself, unless it is the autosave (saved by hand, it
  // becomes a garden of its own)
  loaded.slot=if(name.is(save.auto))null else name;
  // the old world's meshes belong to chunks that are about to disappear
  try renderer.dropWorld(r);
  // the settings belong to the gardener, not the garden
  loaded.opts=game.opts;
  loaded.gpu=game.gpu;
  loaded.world.io=io;
  game.deinit();
  game.*=loaded;
  loaded=undefined;
  return true;
}
/// one frame of the loading screen, `at` of the way through `stage`;
/// false once the window is closed
fn loadFrame(l:*Loading,r:*Renderer,input:*Input,last:*f64,stage:loading.Stage,at:loading.Progress)!bool{
  glfw.pollEvents();
  input.update();
  if(r.window.shouldClose())return false;
  // the clock now, and the time since the last frame, capped as play's is
  const now=glfw.getTime();
  const dt=@min(now-last.*,maxFrameDt);
  last.*=now;
  l.step(stage,at,@floatCast(dt));
  // what the loading screen draws
  var scene=try l.scene(r.extent());
  // whether the window was resized since the last frame
  const resized=input.resized;
  input.resized=false;
  try r.draw(&scene,resized);
  return true;
}
/// mesh the world's ground behind the loading screen, `before` units of the
/// whole already made; false once the window is closed
fn ground(l:*Loading,r:*Renderer,input:*Input,last:*f64,w:*World,before:u32)!bool{
  // how many chunks are still to be meshed, and the whole count with what came before
  const chunks=w.unmeshed();
  const total=before+chunks;
  while(true){
    // the chunks still unmeshed this time round
    const left=w.unmeshed();
    if(!try loadFrame(l,r,input,last,.ground,.{.done=total-left,.total=total}))return false;
    if(left==0)return true;
    try renderer.syncWorld(r,w,m.maxInt(u32),loadMeshMs);
  }
}
/// a garden just loaded in play: its ground meshed behind the loading
/// screen, which fades off again; false once the window is closed
fn reground(l:*Loading,r:*Renderer,input:*Input,last:*f64,game:*Game)!bool{
  l.again();
  l.time=game.uiTime;
  last.*=glfw.getTime();
  if(!try ground(l,r,input,last,&game.world,1))return false;
  game.uiTime=l.time;
  return true;
}
