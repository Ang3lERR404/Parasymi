//! the mesh editor's window and frame loop on the game's renderer.
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
const Input=engine.platform.input.Input;
const Draw=engine.ui.draw.Draw;
const ps=@import("parasymi");
const gizmo=@import("../gizmo.zig");
const Orbit=@import("../orbit.zig").Orbit;
const play=ps.play;
const Game=play.Game;
const renderer=ps.renderer;
const Renderer=renderer.Renderer;
const loading=ps.loading;
const meshgen=ps.meshgen;
const meshlib=ps.meshlib;
const ctl=ps.controls;
const v3=m.v3;
const meshedit=@import("../meshedit.zig");
const camDist=meshedit.settings.camDist;
const camPitch=meshedit.settings.camPitch;
const dir=meshedit.settings.dir;
const Doc=meshedit.doc.Doc;
const ext=meshedit.settings.ext;
const Editor=meshedit.editor.Editor;
const lookUp=meshedit.settings.lookUp;
const maxDt=meshedit.settings.maxDt;
const notInName=meshedit.settings.notInName;
const noFeet=meshedit.settings.noFeet;
const remesh=meshedit.settings.remesh;
const shotPath=meshedit.settings.shotPath;
const shotFrames=meshedit.settings.shotFrames;
const slotId=meshedit.settings.slotId;
const listRows=meshedit.settings.listRows;
const overUi=meshedit.settings.overUi;
pub fn main(init:std.process.Init)!void{
  const gpa=init.gpa;
  const io=init.io;
  const arena=init.arena.allocator();
  const args=try init.minimal.args.toSlice(arena);
  var name:[]const u8="sculpt";
  var shot=false;
  var mode:gizmo.Mode=.move;
  for(args[1..])|a|{
    if(startsWith(u8,a,"--mesh="))name=a["--mesh=".len..];
    if(startsWith(u8,a,"--gizmo="))mode=stringToEnum(gizmo.Mode,a["--gizmo=".len..]) orelse return error.BadGizmo;
    if(eql(u8,a,"--shot"))shot=true;
  }
  if(name.len==0 or indexOfAny(u8,name,notInName)!=null){
    log.err("--mesh={s}: a plain file name, kept as "++dir++"/<name>"++ext,.{name});
    return error.BadName;
  }
  const path=try std.fmt.allocPrint(arena,dir++"/{s}"++ext,.{name});
  // the mesh: as kept, else one form to start from, written at once so a
  // new name is a file from the start
  var made=false;
  const doc=load:{
    const text=Dir.cwd().readFileAlloc(io,path,gpa,.limited(1<<22))catch|er|switch(er){
      error.FileNotFound=>{
        var fresh:Doc=.{};
        try fresh.pieces.append(gpa,.{});
        made=true;
        break:load fresh;
      },
      else=>return er,
    };
    defer gpa.free(text);
    break:load try Doc.parse(gpa,text);
  };
  var e:Editor=.{.gpa=gpa,.io=io,.path=path,.doc=doc,.mode=mode};
  defer e.doc.deinit(gpa);
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
  const window=try glfw.createWindow(play.windowSize[0],play.windowSize[1],"Parasymi mesh editor",null,null);
  defer window.destroy();
  var input:Input=.{.win=window};
  input.attach();
  // the renderer grows next to nothing (the editor puts its own meshes in)
  const r=try Renderer.init(gpa,window,opts.vsync,opts.aa,.{.only=.{.parts=&.{slotId}}});
  defer r.deinit();
  // the meshes grow, then the world wakes and its ground is meshed,
  // behind the game's loading screen
  var screenL=loading.Loading.init(gpa);
  defer screenL.deinit();
  var last=glfw.getTime();
  const whole=2+play.streamChunks;
  while(!try renderer.meshesReady(r)){
    if(!try loadFrame(&screenL,r,&input,&last,.forms,.{.done=0,.total=whole}))return;
  }
  // the sculpt alone, meshed again as it changes
  var b:meshgen.Builder=.{.gpa=gpa};
  defer b.deinit();
  var ranges:[meshlib.slots][2]u32=@splat(.{0,0});
  _=try loadFrame(&screenL,r,&input,&last,.forms,.{.done=1,.total=whole});
  var game=try Game.init(gpa,play.defaultSeed);
  defer game.deinit();
  game.world.io=io;
  game.opts=opts;
  while(game.world.unmeshed()>0){
    if(!try loadFrame(&screenL,r,&input,&last,.ground,.{.done=whole-game.world.unmeshed(),.total=whole}))return;
    try renderer.syncWorld(r,&game.world,m.maxInt(u32),renderer.meshMs*8);
  }
  // the sculpt stands where the wolf would have woken (dry ground)
  const origin=game.player.pos;
  var cam=Orbit.init(origin+v3(0,lookUp,0),camDist,camPitch);
  var ui:Draw=.{.gpa=gpa};
  defer ui.deinit();
  var handles:std.ArrayList(?[2]f32)=.empty;
  defer handles.deinit(gpa);
  var frames:u32=0;
  while(!window.shouldClose()){
    glfw.pollEvents();
    input.update();
    frames+=1;
    const now=glfw.getTime();
    const dt:f32=@floatCast(@min(now-last,maxDt));
    last=now;
    const screen=r.extent();
    // handles and the gizmo as last frame's camera saw them
    const seen:gizmo.View=.{.vp=game.cam.viewProj(),.eye=game.cam.viewEye(),.screen=screen};
    handles.clearRetainingCapacity();
    for(e.pieces())|p|try handles.append(gpa,seen.project(origin+p.v.pos));
    try e.handle(&input,handles.items,seen,origin);
    e.sel=@min(e.sel,e.pieces().len-|1);
    // the surface meshed again once it changed (while dragging, not every frame)
    e.since+=dt;
    // (coarser while dragging, at full detail once let go)
    if(e.drag==.none and e.coarse)e.stale=true;
    if(e.stale and (e.drag==.none or e.since>=remesh)){
      const coarse=e.drag!=.none;
      b.v.clearRetainingCapacity();
      b.skin.clearRetainingCapacity();
      b.grow.clearRetainingCapacity();
      try e.doc.mesh(gpa,io,coarse,&b);
      const run:[2]u32=.{0,@intCast(b.mark())};
      for(0..meshgen.lods)|l|ranges[meshlib.slot(slotId,@intCast(l))]=run;
      try renderer.setParts(r,&b,ranges,0);
      e.stale=false;
      e.coarse=coarse;
      e.since=0;
    }
    // the camera orbits the sculpt freely and zooms; nothing of play runs
    // (no plants grow), only the clocks for the sky and the grass
    game.uiTime+=dt;
    game.time+=dt;
    game.cam.aspect=screen[0]/@max(screen[1],1);
    const pointerOverUi=overUi(listRows(e.pieces().len),input.mouse[0],input.mouse[1]);
    if(ctl.down(&input,.orbit))cam.turn(input.mouseDelta);
    if(input.scroll!=0 and !pointerOverUi)cam.zoom(input.scroll);
    if(e.focus and e.pieces().len>0){
      const v=e.pieces()[e.sel].v;
      cam.focus(origin+v.pos,@reduce(.Max,v.size));
    }
    e.focus=false;
    cam.step(&game.cam,dt);
    try renderer.syncWorld(r,&game.world,6,renderer.meshMs);
    // the scene as the game sees it, but only the ground and the sculpt
    var scene=try ps.view.scene(&game,screen);
    for(&scene.parts)|*p|p.*=&.{};
    for(&scene.instances)|*p|p.*=&.{};
    scene.lights=&.{};
    for(&scene.push.feet)|*f|f.*=.{noFeet,noFeet,noFeet,0};
    const inst=[1]ps.vertex.PartInstance{ps.parts.instance(m.translate(origin),.{})};
    scene.parts[meshlib.slot(slotId,0)]=&inst;
    // handles drawn where the forms are now (one may have gone or come)
    const view:gizmo.View=.{.vp=game.cam.viewProj(),.eye=game.cam.viewEye(),.screen=screen};
    handles.clearRetainingCapacity();
    for(e.pieces())|p|try handles.append(gpa,view.project(origin+p.v.pos));
    ui.clear(@floatCast(game.uiTime));
    try e.draw(&ui,screen,handles.items,view,origin);
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
