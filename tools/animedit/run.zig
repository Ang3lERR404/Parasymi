//! the animation editor's window and frame loop on the game's renderer.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the I/O interface: files, the clock
const Io=std.Io;
/// a directory, for reading clips and writing the shot
const Dir=Io.Dir;
/// whether two byte strings are the same
const eql=std.mem.eql;
/// whether an argument begins with a flag's name
const startsWith=std.mem.startsWith;
/// where in a name any of a set of bytes first falls
const indexOfAny=std.mem.indexOfAny;
/// a name turned into its enum tag, or null if none matches
const stringToEnum=std.meta.stringToEnum;
/// the log, for usage, warnings and notes
const log=std.log;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// the window library: the window, its events and the clock
const glfw=engine.glfw;
/// all the maths: vectors, clamps, casts
const m=engine.core.math;
/// keyframed clips: channels, keys, parsing
const clip=engine.anim.clip;
/// the keys and buttons held this frame
const Input=engine.platform.input.Input;
/// the UI's draw batch, which the panel goes into
const Draw=engine.ui.draw.Draw;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the tools' free camera, turning round its target
const Orbit=@import("../orbit.zig").Orbit;
/// play: the running game
const play=ps.play;
/// the running game, here holding only the world, the wolf or a specimen
const Game=play.Game;
/// the wolf's skeleton and its `Pose`
const skel=ps.skeleton;
/// one plant or structure standing alone, and its `Look`
const specimen=ps.specimen;
/// the garden's renderer module: syncing, meshes ready
const renderer=ps.renderer;
/// the renderer itself
const Renderer=renderer.Renderer;
/// the loading screen, shown while the meshes grow
const loading=ps.loading;
/// the key and button bindings (the orbit follows the game's)
const ctl=ps.controls;
/// every f32 of the wolf's `Pose`, each a channel a clip can key
const PoseCh=clip.Channels(skel.Pose);
/// every f32 of a specimen's `Look`, each a channel a clip can key
const LookCh=clip.Channels(specimen.Look);
/// the editor's root, through which its other files are reached
const animedit=@import("../animedit.zig");
/// how far (m) the camera starts from the wolf
const camDist=animedit.settings.camDist;
/// how much farther (m) it starts per tile of a thing's size
const camPer=animedit.settings.camPer;
/// how high over its subject the camera starts (rad)
const camPitch=animedit.settings.camPitch;
/// how far (m) the camera starts from a thing, before its size
const camThing=animedit.settings.camThing;
/// where clips are kept
const dir=animedit.settings.dir;
/// the file ending every kept clip carries
const ext=animedit.settings.ext;
/// the editor's state
const Editor=animedit.editor.Editor;
/// how big (m) a joint is framed as when focused
const jointSize=animedit.settings.jointSize;
/// how long (s) a new clip runs
const length=animedit.settings.length;
/// how high (m) over the wolf's feet the camera looks
const lookUp=animedit.settings.lookUp;
/// the longest a stalled frame counts as (s)
const maxDt=animedit.settings.maxDt;
/// the bytes a clip's name may not hold
const notInName=animedit.settings.notInName;
/// what the gizmo needs of the wolf this frame
const Rig=animedit.rigging.Rig;
/// where `--shot` writes its frame
const shotPath=animedit.settings.shotPath;
/// how many frames `--shot` waits first
const shotFrames=animedit.settings.shotFrames;
/// who the clip moves
const Subject=animedit.rigging.Subject;
/// every look channel's index: a plant shows them all
const allLook=animedit.editor.allLook;
/// every pose channel's index: the wolf shows them all
const allPose=animedit.editor.allPose;
/// the wolf's bones in the world this frame
const bonesOf=animedit.rigging.bonesOf;
/// a structure shows only its growth
const growthOnly=animedit.editor.growthOnly;
/// whether a point is on the timeline
const inTimeline=animedit.editor.inTimeline;
/// whether a point is over the channel list
const overList=animedit.editor.overList;
/// a rigged sculpt the clip may move, and the mesh it is read as
const Sculpt=animedit.sculpt.Sculpt;
const Doc=animedit.sculpt.Doc;
/// the mesh library, whose first slot a sculpt is drawn from
const meshlib=ps.meshlib;
/// the game's mesh builder, which a sculpt is meshed into
const meshgen=ps.meshgen;
/// the most bones a sculpt may have
const maxBones=@import("../meshedit/rig.zig").maxBones;
/// where sculpts are kept, and their file ending
const meshDir=@import("../meshedit.zig").settings.dir;
const meshExt=@import("../meshedit.zig").settings.ext;
/// the library slot a sculpt is drawn from: nothing else is drawn
const sculptSlot:meshlib.Id=meshlib.ids[0];
/// the animation editor's start: reads the subject and clip from the
/// flags, loads or makes the clip, opens the game's window and renderer on
/// a quiet world with the wolf or the one thing alone, then runs frames,
/// keying as the gardener edits, until the window closes (or `--shot` is taken)
pub fn main(init:std.process.Init)!void{
  // the general allocator, the I/O, and the run's arena
  const gpa=init.gpa;
  const io=init.io;
  const arena=init.arena.allocator();
  // the command line, kept in the arena
  const args=try init.minimal.args.toSlice(arena);
  // `--wolf`/`--plant=`/`--structure=`/`--mesh=`: who the clip moves
  var subject:?Subject=null;
  // `--clip=`: the clip's name, else the subject's own
  var name:?[]const u8=null;
  // `--at=`: where the playhead starts (s)
  var start:f32=0;
  // `--channel=`: the channel selected at the start
  var channel:?[]const u8=null;
  // `--shot`: save one frame and close
  var shot=false;
  for(args[1..])|a|{
    if(eql(u8,a,"--wolf"))subject=.wolf;
    if(startsWith(u8,a,"--plant="))subject=.{.thing=.{.plant=stringToEnum(ps.species.Id,a["--plant=".len..]) orelse return error.BadPlant}};
    if(startsWith(u8,a,"--structure="))subject=.{.thing=.{.structure=stringToEnum(ps.structures.Kind,a["--structure=".len..]) orelse return error.BadStructure}};
    if(startsWith(u8,a,"--mesh="))subject=.{.sculpt=a["--mesh=".len..]};
    if(startsWith(u8,a,"--clip="))name=a["--clip=".len..];
    if(startsWith(u8,a,"--at="))start=try std.fmt.parseFloat(f32,a["--at=".len..]);
    if(startsWith(u8,a,"--channel="))channel=a["--channel=".len..];
    if(eql(u8,a,"--shot"))shot=true;
  }
  // who the clip moves, which the flags must say
  const sj=subject orelse {
    log.err("usage: zig build animedit -- --wolf | --plant=<species> | --structure=<kind> | --mesh=<sculpt> [--clip=<name>]",.{});
    return error.NoSubject;
  };
  // the clip's name, checked to be a plain file name
  const named=name orelse sj.name();
  if(named.len==0 or indexOfAny(u8,named,notInName)!=null){
    log.err("--clip={s}: a plain file name, kept as "++dir++"/<name>"++ext,.{named});
    return error.BadName;
  }
  // where it is kept
  const path=try std.fmt.allocPrint(arena,dir++"/{s}"++ext,.{named});
  // the clip: as kept, else a fresh one, written at once so a new name is
  // a file from the start
  var wb:[64]u8=undefined;
  // the subject's word, which a kept clip must carry
  const word=sj.word(&wb);
  // whether the clip is new, and so to be written at once
  var made=false;
  const c=load:{
    // the clip's text, if it is kept
    const text=Dir.cwd().readFileAlloc(io,path,gpa,.limited(1<<22))catch|er|switch(er){
      error.FileNotFound=>{
        // a fresh clip for the subject, as long as a new clip runs
        var fresh=try clip.Clip.init(gpa,word);
        fresh.length=length;
        made=true;
        break:load fresh;
      },
      else=>return er,
    };
    defer gpa.free(text);
    break:load try clip.Clip.parse(gpa,text);
  };
  // the clip's text as it was read, where the history starts
  const first=try animedit.editor.text(gpa,&c);
  defer gpa.free(first);
  // the editor, showing every channel of the wolf or a plant, or a structure's growth
  var e:Editor=.{
    .history=try .init(gpa,first),
    .gpa=gpa,
    .io=io,
    .subject=sj,
    .path=path,
    .clip=c,
    .shown=switch(sj){
      .wolf=>&allPose,
      .thing=>|t|if(t==.plant)&allLook else&growthOnly,
      .sculpt=>&.{},
    },
  };
  defer e.clip.deinit();
  defer e.history.deinit();
  // a sculpt's mesh and bones, read from the mesh editor's file
  var rigged:?Sculpt=switch(sj){
    .sculpt=>|n|load:{
      if(n.len==0 or indexOfAny(u8,n,notInName)!=null)return error.BadMesh;
      // the mesh's path and text
      const mpath=try std.fmt.allocPrint(arena,meshDir++"/{s}"++meshExt,.{n});
      const text=try Dir.cwd().readFileAlloc(io,mpath,gpa,.limited(1<<22));
      defer gpa.free(text);
      // the mesh, its channels made from its bones
      var doc=try Doc.parse(gpa,text);
      errdefer doc.deinit(gpa);
      break:load try Sculpt.init(gpa,doc);
    },
    else=>null,
  };
  defer if(rigged)|*sc|sc.deinit();
  if(rigged)|*sc|{
    e.sculpt=sc;
    e.shown=sc.order;
  }
  e.t=m.clamp(start,0,e.clip.length);
  if(channel)|want|e.sel=for(0..e.shown.len)|i|{
    if(eql(u8,e.chName(i),want))break i;
  }else return error.BadChannel;
  if(!eql(u8,e.clip.subject,word)){
    log.err("{s} animates {s}, not {s}",.{path,e.clip.subject,word});
    return error.WrongSubject;
  }
  if(made){
    e.dirty=true;
    e.save();
    if(e.dirty)return error.SaveFailed;
    e.say("new {s}",.{path});
    log.info("new {s}",.{path});
  }
  // the game's files (controls, strings), as the game reads them
  try ps.home.open(io,init.environ_map);
  defer ps.home.close(io);
  // the gardener's settings: vsync and antialiasing
  const opts=try ps.options.load(gpa,io);
  try ctl.load(gpa,io);
  defer ctl.unload();
  try ps.txt.load(gpa,io);
  defer ps.txt.unload(gpa);
  try glfw.init();
  defer glfw.terminate();
  if(!glfw.isVulkanSupported())return error.VulkanUnsupported;
  glfw.windowHint(.client_api,.no_api);
  // the editor's window, as big as the game's
  const window=try glfw.createWindow(play.windowSize[0],play.windowSize[1],"Parasymi animation editor",null,null);
  defer window.destroy();
  // the input, reading keys and buttons from the window
  var input:Input=.{.win=window};
  input.attach();
  // the one thing alone in a fresh world, or none for the wolf
  var lone:?specimen.Specimen=switch(sj){
    .wolf,.sculpt=>null,
    .thing=>|t|.{.what=t.subject(),.state=.{.look=.{}}},
  };
  // the renderer, building only the meshes the subject needs
  const r=try Renderer.init(gpa,window,opts.vsync,opts.aa,.{.only=if(lone)|*l|try l.only(arena)else if(sj==.sculpt).{.parts=&.{sculptSlot}}else null,.io=io});
  defer r.deinit();
  // every mesh grows, then the world wakes and its ground is meshed,
  // behind the game's loading screen
  var screenL=loading.Loading.init(gpa);
  defer screenL.deinit();
  // the clock at the last frame (s)
  var last=glfw.getTime();
  // how many forms are grown, and the whole loading count: forms, the world, its chunks
  const forms=renderer.meshProgress(r)[1];
  const whole=forms+1+play.streamChunks;
  while(!try renderer.meshesReady(r)){
    if(!try loadFrame(&screenL,r,&input,&last,.forms,.{.done=renderer.meshProgress(r)[0],.total=whole}))return;
  }
  // the quiet world the subject stands in
  var game=try Game.init(gpa,play.defaultSeed);
  defer game.deinit();
  game.world.io=io;
  game.opts=opts;
  if(lone)|l|{
    game.specimen=l;
    try game.specimen.?.sow(&game);
  }
  // a sculpt meshed once, as every level of detail of its slot
  var built:meshgen.Builder=.{.gpa=gpa};
  defer built.deinit();
  if(rigged)|*sc|{
    // every sculpt kept beside it, for its nests
    var parts=try ps.sculptDoc.Folder.load(gpa,io,Dir.cwd(),meshDir);
    defer parts.deinit();
    try sc.doc.mesh(gpa,io,false,&built,parts.lookup());
    // where in the builder each library slot's level of detail lies
    var ranges:[meshlib.slots][2]u32=@splat(.{0,0});
    const run:[2]u32=.{0,@intCast(built.mark())};
    for(0..meshgen.lods)|l|ranges[meshlib.slot(sculptSlot,@intCast(l))]=run;
    try renderer.setParts(r,&built,ranges,0);
  }
  // where the camera looks to start, and from how far
  const home=game.player.pos+m.v3(0,lookUp,0);
  const homeDist:f32=switch(sj){
    .wolf=>camDist,
    .sculpt=>camThing,
    .thing=>|t|camThing+camPer*m.f(switch(t){
      .plant=>|sp|ps.species.get(sp).size,
      .structure=>|k|ps.structures.defs.get(k).size,
    }),
  };
  // the camera, turning round the subject
  var cam=Orbit.init(home,homeDist,camPitch);
  while(game.world.unmeshed()>0){
    if(!try loadFrame(&screenL,r,&input,&last,.ground,.{.done=whole-game.world.unmeshed(),.total=whole}))return;
    try renderer.syncWorld(r,&game.world,m.maxInt(u32),renderer.meshMs*8);
  }
  // the panel's draw batch
  var ui:Draw=.{.gpa=gpa};
  defer ui.deinit();
  // how many frames have run (for `--shot`)
  var frames:u32=0;
  while(!window.shouldClose()){
    glfw.pollEvents();
    input.update();
    frames+=1;
    // the clock now, and the time since the last frame, capped (s)
    const now=glfw.getTime();
    const dt:f32=@floatCast(@min(now-last,maxDt));
    last=now;
    // the swapchain's size this frame (px)
    const screen=r.extent();
    // the joints as last frame's camera saw them
    // the wolf's joints as the camera sees them
    var rg:Rig=.{
      .view=.{.vp=game.cam.viewProj(),.eye=game.cam.viewEye(),.screen=screen},
      .bones=bonesOf(e.pose,game.player.heading()),
      .heading=game.player.heading(),
    };
    try e.handle(&input,screen,dt,&rg);
    e.sample();
    switch(sj){
      .wolf=>game.player.posed=e.pose,
      .sculpt=>{},
      .thing=>game.specimen.?.state=.{.look=e.look},
    }
    // the camera orbits the subject freely and zooms; nothing of play runs
    // but the world's tick (which holds a specimen as it is set)
    game.uiTime+=dt;
    game.time+=dt;
    game.cam.aspect=screen[0]/@max(screen[1],1);
    // whether the mouse is over the panel, where the wheel scrolls the list
    const overUi=overList(screen,input.mouse[0],input.mouse[1]) or inTimeline(screen,input.mouse[0],input.mouse[1]);
    if(ctl.down(&input,.orbit))cam.turn(input.mouseDelta);
    if(input.scroll!=0 and !overUi)cam.zoom(input.scroll);
    if(e.focus){
      if(e.gizmoAt(&rg))|at|cam.focus(at.g.at,jointSize)else cam.send(home,homeDist);
    }
    e.focus=false;
    cam.step(&game.cam,dt);
    game.player.animate(&game.world,dt);
    try game.simulate(dt);
    try renderer.syncWorld(r,&game.world,6,renderer.meshMs);
    // what the renderer draws this frame
    var scene=try ps.view.scene(&game,screen);
    // a sculpt alone where the wolf would stand, its skin bent by its bones
    var sculptBones:[maxBones]m.M4=undefined;
    var sculptInst:[1]ps.vertex.PartInstance=undefined;
    if(rigged)|*sc|{
      for(&scene.parts)|*p|p.*=&.{};
      const k=sc.pose(m.translate(game.player.pos),&sculptBones);
      scene.bones=sculptBones[0..k.count];
      sculptInst[0]=ps.parts.skinned(game.player.pos,0,.{});
      scene.parts[meshlib.slot(sculptSlot,0)]=&sculptInst;
    }
    rg=.{
      .view=.{.vp=game.cam.viewProj(),.eye=game.cam.viewEye(),.screen=screen},
      .bones=bonesOf(e.pose,game.player.heading()),
      .heading=game.player.heading(),
    };
    ui.clear(@floatCast(game.uiTime));
    try e.draw(&ui,screen,&rg);
    scene.ui=ui.v.items;
    // whether the window was resized since the last frame
    const resized=input.resized;
    input.resized=false;
    r.capture=shot and frames==shotFrames;
    try r.draw(&scene,resized);
    if(r.shot())|sh|{
      // the frame encoded as a PNG
      const bytes=try engine.core.png.encode(gpa,sh.w,sh.h,sh.px,if(sh.bgra).bgra else.rgba);
      defer gpa.free(bytes);
      try Dir.cwd().createDirPath(io,"shots");
      try Dir.cwd().writeFile(io,.{.sub_path=shotPath,.data=bytes});
      log.info("shot {s}",.{shotPath});
      window.setShouldClose(true);
    }
  }
  if(e.dirty)log.warn("{s}: unsaved changes dropped",.{path});
}
/// one frame of the loading screen; false once the window is closed
fn loadFrame(l:*loading.Loading,r:*Renderer,input:*Input,last:*f64,stage:loading.Stage,at:loading.Progress)!bool{
  glfw.pollEvents();
  input.update();
  if(r.window.shouldClose())return false;
  // the clock now, and the time since the last frame, capped (s)
  const now=glfw.getTime();
  const dt=@min(now-last.*,maxDt);
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
