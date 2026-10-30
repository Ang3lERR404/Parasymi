//! the animation editor's window and frame loop on the game's renderer.
const std=ps.std;
const Io=std.Io;
const Dir=Io.Dir;
const eql=std.mem.eql;
const startsWith=std.mem.startsWith;
const indexOfAny=std.mem.indexOfAny;
const stringToEnum=std.meta.stringToEnum;
const log=std.log;
const engine=ps.engine;
const glfw=engine.glfw;
const m=engine.core.math;
const clip=engine.anim.clip;
const Input=engine.platform.input.Input;
const Draw=engine.ui.draw.Draw;
const ps=@import("parasymi");
const Orbit=@import("../orbit.zig").Orbit;
const play=ps.play;
const Game=play.Game;
const skel=ps.skeleton;
const specimen=ps.specimen;
const renderer=ps.renderer;
const Renderer=renderer.Renderer;
const loading=ps.loading;
const ctl=ps.controls;
const PoseCh=clip.Channels(skel.Pose);
const LookCh=clip.Channels(specimen.Look);
const animedit=@import("../animedit.zig");
const camDist=animedit.settings.camDist;
const camPer=animedit.settings.camPer;
const camPitch=animedit.settings.camPitch;
const camThing=animedit.settings.camThing;
const dir=animedit.settings.dir;
const ext=animedit.settings.ext;
const Editor=animedit.editor.Editor;
const jointSize=animedit.settings.jointSize;
const length=animedit.settings.length;
const lookUp=animedit.settings.lookUp;
const maxDt=animedit.settings.maxDt;
const notInName=animedit.settings.notInName;
const Rig=animedit.rigging.Rig;
const shotPath=animedit.settings.shotPath;
const shotFrames=animedit.settings.shotFrames;
const Subject=animedit.rigging.Subject;
const allLook=animedit.editor.allLook;
const allPose=animedit.editor.allPose;
const bonesOf=animedit.rigging.bonesOf;
const growthOnly=animedit.editor.growthOnly;
const inTimeline=animedit.editor.inTimeline;
const overList=animedit.editor.overList;
pub fn main(init:std.process.Init)!void{
  const gpa=init.gpa;
  const io=init.io;
  const arena=init.arena.allocator();
  const args=try init.minimal.args.toSlice(arena);
  var subject:?Subject=null;
  var name:?[]const u8=null;
  var start:f32=0;
  var channel:?[]const u8=null;
  var shot=false;
  for(args[1..])|a|{
    if(eql(u8,a,"--wolf"))subject=.wolf;
    if(startsWith(u8,a,"--plant="))subject=.{.thing=.{.plant=stringToEnum(ps.species.Id,a["--plant=".len..]) orelse return error.BadPlant}};
    if(startsWith(u8,a,"--structure="))subject=.{.thing=.{.structure=stringToEnum(ps.structures.Kind,a["--structure=".len..]) orelse return error.BadStructure}};
    if(startsWith(u8,a,"--clip="))name=a["--clip=".len..];
    if(startsWith(u8,a,"--at="))start=try std.fmt.parseFloat(f32,a["--at=".len..]);
    if(startsWith(u8,a,"--channel="))channel=a["--channel=".len..];
    if(eql(u8,a,"--shot"))shot=true;
  }
  const sj=subject orelse {
    log.err("usage: zig build animedit -- --wolf | --plant=<species> | --structure=<kind> [--clip=<name>]",.{});
    return error.NoSubject;
  };
  const named=name orelse sj.name();
  if(named.len==0 or indexOfAny(u8,named,notInName)!=null){
    log.err("--clip={s}: a plain file name, kept as "++dir++"/<name>"++ext,.{named});
    return error.BadName;
  }
  const path=try std.fmt.allocPrint(arena,dir++"/{s}"++ext,.{named});
  // the clip: as kept, else a fresh one, written at once so a new name is
  // a file from the start
  var wb:[64]u8=undefined;
  const word=sj.word(&wb);
  var made=false;
  const c=load:{
    const text=Dir.cwd().readFileAlloc(io,path,gpa,.limited(1<<22))catch|er|switch(er){
      error.FileNotFound=>{
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
  var e:Editor=.{
    .gpa=gpa,
    .io=io,
    .subject=sj,
    .path=path,
    .clip=c,
    .shown=switch(sj){
      .wolf=>&allPose,
      .thing=>|t|if(t==.plant)&allLook else&growthOnly,
    },
  };
  defer e.clip.deinit();
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
  const opts=try ps.options.load(gpa,io);
  try ctl.load(gpa,io);
  defer ctl.unload();
  try ps.txt.load(gpa,io);
  defer ps.txt.unload(gpa);
  try glfw.init();
  defer glfw.terminate();
  if(!glfw.isVulkanSupported())return error.VulkanUnsupported;
  glfw.windowHint(.client_api,.no_api);
  const window=try glfw.createWindow(play.windowSize[0],play.windowSize[1],"Parasymi animation editor",null,null);
  defer window.destroy();
  var input:Input=.{.win=window};
  input.attach();
  var lone:?specimen.Specimen=switch(sj){
    .wolf=>null,
    .thing=>|t|.{.what=t,.state=.{.look=.{}}},
  };
  const r=try Renderer.init(gpa,window,opts.vsync,opts.aa,.{.only=if(lone)|*l|try l.only(arena)else null});
  defer r.deinit();
  // every mesh grows, then the world wakes and its ground is meshed,
  // behind the game's loading screen
  var screenL=loading.Loading.init(gpa);
  defer screenL.deinit();
  var last=glfw.getTime();
  const forms=renderer.meshProgress(r)[1];
  const whole=forms+1+play.streamChunks;
  while(!try renderer.meshesReady(r)){
    if(!try loadFrame(&screenL,r,&input,&last,.forms,.{.done=renderer.meshProgress(r)[0],.total=whole}))return;
  }
  var game=try Game.init(gpa,play.defaultSeed);
  defer game.deinit();
  game.world.io=io;
  game.opts=opts;
  if(lone)|l|{
    game.specimen=l;
    try game.specimen.?.sow(&game);
  }
  const home=game.player.pos+m.v3(0,lookUp,0);
  const homeDist:f32=switch(sj){
    .wolf=>camDist,
    .thing=>|t|camThing+camPer*m.f(switch(t){
      .plant=>|sp|ps.species.get(sp).size,
      .structure=>|k|ps.structures.defs.get(k).size,
    }),
  };
  var cam=Orbit.init(home,homeDist,camPitch);
  while(game.world.unmeshed()>0){
    if(!try loadFrame(&screenL,r,&input,&last,.ground,.{.done=whole-game.world.unmeshed(),.total=whole}))return;
    try renderer.syncWorld(r,&game.world,m.maxInt(u32),renderer.meshMs*8);
  }
  var ui:Draw=.{.gpa=gpa};
  defer ui.deinit();
  var frames:u32=0;
  while(!window.shouldClose()){
    glfw.pollEvents();
    input.update();
    frames+=1;
    const now=glfw.getTime();
    const dt:f32=@floatCast(@min(now-last,maxDt));
    last=now;
    const screen=r.extent();
    // the joints as last frame's camera saw them
    var rg:Rig=.{
      .view=.{.vp=game.cam.viewProj(),.eye=game.cam.viewEye(),.screen=screen},
      .bones=bonesOf(e.pose,game.player.heading()),
      .heading=game.player.heading(),
    };
    try e.handle(&input,screen,dt,&rg);
    e.sample();
    switch(sj){
      .wolf=>game.player.posed=e.pose,
      .thing=>game.specimen.?.state=.{.look=e.look},
    }
    // the camera orbits the subject freely and zooms; nothing of play runs
    // but the world's tick (which holds a specimen as it is set)
    game.uiTime+=dt;
    game.time+=dt;
    game.cam.aspect=screen[0]/@max(screen[1],1);
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
    var scene=try ps.view.scene(&game,screen);
    rg=.{
      .view=.{.vp=game.cam.viewProj(),.eye=game.cam.viewEye(),.screen=screen},
      .bones=bonesOf(e.pose,game.player.heading()),
      .heading=game.player.heading(),
    };
    ui.clear(@floatCast(game.uiTime));
    try e.draw(&ui,screen,&rg);
    scene.ui=ui.v.items;
    const resized=input.resized;
    input.resized=false;
    r.capture=shot and frames==shotFrames;
    try r.draw(&scene,resized);
    if(r.shot())|sh|{
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
  const now=glfw.getTime();
  const dt=@min(now-last.*,maxDt);
  last.*=now;
  l.step(stage,at,@floatCast(dt));
  var scene=try l.scene(r.extent());
  const resized=input.resized;
  input.resized=false;
  try r.draw(&scene,resized);
  return true;
}
