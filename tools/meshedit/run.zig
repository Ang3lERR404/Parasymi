//! the mesh editor's window and frame loop on the game's renderer.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the I/O interface: files, the clock
const Io=std.Io;
/// a directory, for reading meshes and writing the shot
const Dir=Io.Dir;
/// whether two byte strings are the same
const eql=std.mem.eql;
/// the command line's flags, split once at the edge (engine core)
const flag=ps.engine.core.flag;
/// every flag the mesh editor takes, by its own spelling (`flag.parse`)
const Flag=enum{
  /// `--mesh=`: the sculpt's name
  mesh,
  /// `--gizmo=`: what the gizmo does to start
  gizmo,
  /// `--shot`: one frame saved, then closed
  shot,
  /// `--rig`: start in rig mode
  rig,
  /// `--try=<pitch>,<yaw>,<roll>`: the last bone test-turned so
  @"try",
  /// `--rename=`: the sculpt renamed so at once
  rename,
  /// `--link`: talk with Claude, who can read and edit the sculpt (tools/editlink.zig)
  link,
};
/// the editors' link with Claude
const EditLink=@import("../editlink.zig").EditLink;
/// splits text at each comma (`--try=`)
const splitScalar=std.mem.splitScalar;
/// reads a decimal number (`--try=`)
const parseFloat=std.fmt.parseFloat;
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
/// all the maths: vectors, matrices, casts
const m=engine.core.math;
/// the keys and buttons held this frame
const Input=engine.platform.input.Input;
/// the UI's draw batch, which the panel goes into
const Draw=engine.ui.draw.Draw;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the move, turn and size handles on the selected form
const gizmo=@import("../gizmo.zig");
/// the tools' free camera, turning round its target
const Orbit=@import("../orbit.zig").Orbit;
/// play: the running game
const play=ps.play;
/// the running game, here holding only the world and its clocks
const Game=play.Game;
/// the garden's renderer module: syncing, parts, meshes ready
const renderer=ps.renderer;
/// the renderer itself
const Renderer=renderer.Renderer;
/// the loading screen, shown while the ground is meshed
const loading=ps.loading;
/// the game's mesh builder, which the sculpt is meshed into
const meshgen=ps.meshgen;
/// the mesh library: its slots and levels of detail
const meshlib=ps.meshlib;
/// the key and button bindings (the orbit follows the game's)
const ctl=ps.controls;
/// makes a vector from its three parts
const v3=m.v3;
/// the editor's root, through which its other files are reached
const meshedit=@import("../meshedit.zig");
/// how far (m) the camera starts from the sculpt
const camDist=meshedit.settings.camDist;
/// how high over the sculpt the camera starts (rad)
const camPitch=meshedit.settings.camPitch;
/// where meshes are kept
const dir=meshedit.settings.dir;
/// the mesh as kept: its cells and its forms
const Doc=meshedit.doc.Doc;
/// the file ending every kept mesh carries
const ext=meshedit.settings.ext;
/// the editor's state
const Editor=meshedit.editor.Editor;
/// the sculpt's bones
const rig=meshedit.rig;
/// the rig mode: the bones posed, and their joints on screen
const rigging=meshedit.rigging;
/// how big a joint is framed when `.` eases the camera onto it (m)
const jointFocus=meshedit.settings.jointFocus;
/// how high (m) over the ground the camera looks
const lookUp=meshedit.settings.lookUp;
/// the longest a stalled frame counts as (s)
const maxDt=meshedit.settings.maxDt;
/// the bytes a mesh's name may not hold
const notInName=meshedit.settings.notInName;
/// where the wolf's paws are said to be, far off any tile
const noFeet=meshedit.settings.noFeet;
/// how often (s) the surface is meshed again while dragging
const remesh=meshedit.settings.remesh;
/// where `--shot` writes its frame
const shotPath=meshedit.settings.shotPath;
/// how many frames `--shot` waits first
const shotFrames=meshedit.settings.shotFrames;
/// the library slot the sculpt is drawn from
const slotId=meshedit.settings.slotId;
/// how many form rows show
const listRows=meshedit.settings.listRows;
/// whether a point is over the panel
const overUi=meshedit.settings.overUi;
/// the mesh editor's start: reads the mesh's name and gizmo from the flags,
/// loads or makes the mesh, opens the game's window and renderer on a quiet
/// world, then runs frames, meshing the sculpt again as it is edited,
/// until the window closes (or `--shot` is taken)
pub fn main(init:std.process.Init)!void{
  // the general allocator, the I/O, and the run's arena
  const gpa=init.gpa;
  const io=init.io;
  const arena=init.arena.allocator();
  // the command line, kept in the arena
  const args=try init.minimal.args.toSlice(arena);
  // `--mesh=`: the mesh's name
  var name:[]const u8="sculpt";
  // `--shot`: save one frame and close
  var shot=false;
  // `--gizmo=`: what the gizmo does to start
  var mode:gizmo.Mode=.move;
  // `--rig`: start in rig mode; `--try=<pitch>,<yaw>,<roll>`: the last bone test-turned so (degrees)
  var startRig=false;
  var tryTurn:m.V3=.{0,0,0};
  // `--rename=<name>`: the sculpt renamed so at once, as a click on its path would
  var renameAs:?[]const u8=null;
  // `--link`: talk with Claude through the link folder
  var linkOn=false;
  for(args[1..])|a|{
    // the argument as one of its flags (none: passed over)
    const f=flag.parse(Flag,a) orelse continue;
    switch(f.name){
      .mesh=>if(f.value)|v|{name=v;},
      .gizmo=>if(f.value)|v|{mode=stringToEnum(gizmo.Mode,v) orelse return error.BadGizmo;},
      .shot=>if(f.value==null){shot=true;},
      .rig=>if(f.value==null){startRig=true;},
      .@"try"=>if(f.value)|v|{tryTurn=try turnsOf(v);},
      .rename=>if(f.value)|v|{renameAs=v;},
      .link=>if(f.value==null){linkOn=true;},
    }
  }
  if(name.len==0 or indexOfAny(u8,name,notInName)!=null){
    log.err("--mesh={s}: a plain file name, kept as "++dir++"/<name>"++ext,.{name});
    return error.BadName;
  }
  // where the mesh is kept
  const path=try std.fmt.allocPrint(arena,dir++"/{s}"++ext,.{name});
  // the mesh: as kept, else one form to start from, written at once so a
  // new name is a file from the start
  // whether the mesh is new, and so to be written at once
  var made=false;
  // the mesh: read from its text, else a fresh one with a single form
  const doc=load:{
    // the mesh's text, if it is kept
    const text=Dir.cwd().readFileAlloc(io,path,gpa,.limited(1<<22))catch|er|switch(er){
      error.FileNotFound=>{
        // a fresh mesh, one form at rest
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
  // the editor, sculpting that mesh
  // the mesh's text as it was read, where the history starts
  const first=try meshedit.editor.text(gpa,&doc);
  defer gpa.free(first);
  var e:Editor=.{.gpa=gpa,.io=io,.path=path,.doc=doc,.mode=mode,.history=try .init(gpa,first),.disk=.{.gpa=gpa,.canon=meshedit.editor.canon}};
  defer e.doc.deinit(gpa);
  defer e.history.deinit();
  defer e.disk.deinit();
  // the file as it is on disk now, so a later change to it is seen
  _=try e.disk.look(io,path);
  // the link with Claude, if asked for
  var el:?EditLink=null;
  if(linkOn){
    el=undefined;
    try el.?.init(io);
  }
  defer if(el)|*l|l.deinit(io);
  defer if(e.parts)|*f|f.deinit();
  defer if(e.ownedPath)|p|gpa.free(p);
  try e.reloadParts();
  e.rigMode=startRig;
  if(e.doc.bones.items.len>0){
    e.bsel=e.doc.bones.items.len-1;
    e.turns[e.bsel]=tryTurn;
  }
  if(made){
    e.dirty=true;
    e.save();
    if(e.dirty)return error.SaveFailed;
    e.say("new {s}",.{path});
    log.info("new {s}",.{path});
  }
  if(renameAs)|n|{
    try e.renameTo(n);
    log.info("{s}",.{e.note[0..e.noteLen]});
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
  const window=try glfw.createWindow(play.windowSize[0],play.windowSize[1],"Parasymi mesh editor",null,null);
  defer window.destroy();
  // the input, reading keys and buttons from the window
  var input:Input=.{.win=window};
  input.attach();
  // the renderer grows next to nothing (the editor puts its own meshes in)
  const r=try Renderer.init(gpa,window,opts.vsync,opts.aa,.{.only=.{.parts=&.{slotId}},.io=io});
  defer r.deinit();
  // the meshes grow, then the world wakes and its ground is meshed,
  // behind the game's loading screen
  var screenL=loading.Loading.init(gpa);
  defer screenL.deinit();
  // the clock at the last frame (s)
  var last=glfw.getTime();
  // the whole loading count: the forms, the sculpt, the world's chunks
  const whole=2+play.streamChunks;
  while(!try renderer.meshesReady(r)){
    if(!try loadFrame(&screenL,r,&input,&last,.forms,.{.done=0,.total=whole}))return;
  }
  // the sculpt alone, meshed again as it changes
  var b:meshgen.Builder=.{.gpa=gpa};
  defer b.deinit();
  // where in the builder each library slot's level of detail lies
  var ranges:[meshlib.slots]m.Vice(u32,2)=@splat(.{0,0});
  _=try loadFrame(&screenL,r,&input,&last,.forms,.{.done=1,.total=whole});
  // the quiet world the sculpt stands on
  var game=try Game.init(gpa,null,play.defaultSeed);
  defer game.deinit();
  game.world.io=io;
  game.opts=opts;
  while(game.world.unmeshed()>0){
    if(!try loadFrame(&screenL,r,&input,&last,.ground,.{.done=whole-game.world.unmeshed(),.total=whole}))return;
    try renderer.syncWorld(r,&game.world,m.maxInt(u32),renderer.meshMs*8);
  }
  // the sculpt stands where the wolf would have woken (dry ground)
  const origin=game.player.pos;
  // the camera, turning round the sculpt
  var cam=Orbit.init(origin+v3(0,lookUp,0),camDist,camPitch);
  // the panel's draw batch
  var ui:Draw=.{.gpa=gpa};
  defer ui.deinit();
  // each form's handle on screen, or null behind the eye
  var handles:std.ArrayList(?m.Vec(f32,2))=.empty;
  defer handles.deinit(gpa);
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
    // handles and the gizmo as last frame's camera saw them
    const seen:gizmo.View=.{.vp=game.cam.viewProj(),.eye=game.cam.viewEye(),.screen=screen};
    handles.clearRetainingCapacity();
    if(e.rigMode)try rigging.handles(&e,seen,origin,&handles,gpa)else for(e.pieces())|p|try handles.append(gpa,seen.project(origin+p.v.pos));
    // (while the gardener types to Claude, the editor's own keys wait)
    const chatting=if(el)|*l|l.keys(io,&input,game.uiTime,if(e.naming!=null or e.renaming!=null).typing else.free)else false;
    if(!chatting)try e.handle(&input,handles.items,seen,origin);
    try e.watch(dt);
    if(el)|*l|try tendLink(l,&e,gpa,io,dt,game.uiTime,path);
    e.sel=@min(e.sel,e.pieces().len-|1);
    e.bsel=@min(e.bsel,e.doc.bones.items.len-|1);
    // the surface meshed again once it changed (while dragging, not every frame)
    e.since+=dt;
    // (coarser while dragging, at full detail once let go)
    if(e.drag==.none and e.coarse)e.stale=true;
    if(e.stale and (e.drag==.none or e.since>=remesh)){
      // whether this meshing is coarse, for a drag still going on
      const coarse=e.drag!=.none;
      b.v.clearRetainingCapacity();
      b.skin.clearRetainingCapacity();
      b.grow.clearRetainingCapacity();
      if(!coarse)try e.reloadParts();
      try e.doc.mesh(gpa,io,coarse,&b,e.lookup());
      // the whole surface, as every level of detail of the slot
      const run:m.Vice(u32,2)=.{0,@intCast(b.mark())};
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
    // whether the mouse is over the panel, where the wheel doesn't zoom
    const pointerOverUi=e.bar.over(input.mouse) or overUi(listRows(e.pieces().len),input.mouse[0],input.mouse[1]);
    if(ctl.down(&input,.orbit))cam.turn(input.mouseDelta);
    if(input.scroll!=0 and !pointerOverUi)cam.zoom(input.scroll);
    if(e.focus and e.rigMode and e.doc.bones.items.len>0){
      cam.focus(origin+e.doc.bones.items[e.bsel].at,jointFocus);
    }else if(e.focus and e.pieces().len>0){
      // the selected form's values
      const v=e.pieces()[e.sel].v;
      cam.focus(origin+v.pos,@reduce(.Max,v.size));
    }
    e.focus=false;
    // Claude's ask of the view, through the link: a form framed, or the
    // first view, then turned, placed and zoomed as asked
    if(el)|*l|if(l.takeView(io))|ask|{
      if(ask.home)cam.send(origin+v3(0,lookUp,0),camDist);
      if(ask.focus)|n|if(n>=1 and n<=e.pieces().len){
        // the form's values
        const v=e.pieces()[n-1].v;
        cam.focus(origin+v.pos,@reduce(.Max,v.size));
      };
      cam.take(ask,origin);
    };
    cam.step(&game.cam,dt);
    try renderer.syncWorld(r,&game.world,6,renderer.meshMs);
    // the scene as the game sees it, but only the ground and the sculpt
    var scene=try ps.view.scene(&game,screen);
    for(&scene.parts)|*p|p.*=&.{};
    for(&scene.instances)|*p|p.*=&.{};
    scene.lights=&.{};
    for(&scene.push.feet)|*f|f.*=.{noFeet,noFeet,noFeet,0};
    // the sculpt, drawn once where it stands, its skin carried by its
    // bones as they are test-turned
    var bones:[rig.maxBones]m.M4=undefined;
    const k=rigging.posed(&e,origin,&bones);
    scene.bones=bones[0..k.count];
    const inst=[1]ps.vertex.PartInstance{ps.parts.skinned(origin,0,.{})};
    scene.parts[meshlib.slot(slotId,0)]=&inst;
    // handles drawn where the forms (or joints) are now (one may have gone or come)
    const view:gizmo.View=.{.vp=game.cam.viewProj(),.eye=game.cam.viewEye(),.screen=screen};
    handles.clearRetainingCapacity();
    if(e.rigMode)try rigging.handles(&e,view,origin,&handles,gpa)else for(e.pieces())|p|try handles.append(gpa,view.project(origin+p.v.pos));
    ui.clear(@floatCast(game.uiTime));
    try e.draw(&ui,screen,handles.items,view,origin);
    if(el)|*l|try l.draw(&ui,screen);
    scene.ui=ui.v.items;
    // whether the window was resized since the last frame
    const resized=input.resized;
    input.resized=false;
    // the frame kept: for `--shot`, or a frame Claude asked for
    const shooting=shot and frames==shotFrames;
    r.capture=shooting or (if(el)|*l|l.wantsFrame()else false);
    try r.draw(&scene,resized);
    if(r.shot())|sh|{
      if(el)|*l|if(l.wantsFrame())l.sendFrame(gpa,io,sh);
      if(!shooting)continue;
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
/// one frame of the link: an edit Claude left taken as one step of the
/// history (and answered), and the state and the sculpt rewritten when due
fn tendLink(l:*EditLink,e:*Editor,gpa:std.mem.Allocator,io:Io,dt:f32,at:f64,path:[]const u8)!void{
  if(l.takeEdit(gpa,io))|t|{
    defer gpa.free(t);
    // room for the answer
    var rb:[160]u8=undefined;
    l.answer(io,try e.adopt(t,&rb));
  }
  if(!l.tick(gpa,io,dt,at))return;
  // the sculpt's text, and what the editor shows
  const doc=try meshedit.editor.text(gpa,&e.doc);
  defer gpa.free(doc);
  var sb:[640]u8=undefined;
  // what the gardener's hands are on (an edit waits while it is not free)
  const hands=if(e.drag!=.none)"dragging (edits wait)"else if(e.naming!=null)"naming a form (Enter or Esc ends it; edits wait)"else if(e.renaming!=null)"renaming the sculpt (Enter or Esc ends it; edits wait)"else"free";
  const state=std.fmt.bufPrint(&sb,"editor: meshedit\nsculpt: {s}\nforms: {d}, selected {d}\nbones: {d}\nrig mode: {}\nunsaved changes: {}\nthe file changed on disk too (the gardener picks: ctrl+s keeps the editor's, f5 the file's): {}\ngardener's hands: {s}\n(editor_document gives the sculpt's text; editor_edit takes a whole edited one; editor_view turns the camera)\n",.{path,e.pieces().len,e.sel,e.doc.bones.items.len,e.rigMode,e.dirty,e.disk.clash,hands})catch"editor: meshedit\n";
  l.publish(io,state,doc);
}
/// `--try=`'s turns: pitch, yaw and roll (degrees), commas between, the ones left out none
fn turnsOf(text:[]const u8)error{BadTry}!m.V3{
  // the turns read so far, and the text's numbers one by one
  var t:m.Vice(f32,3)=.{0,0,0};
  var it=splitScalar(u8,text,',');
  for(&t)|*x|x.*=parseFloat(f32,it.next() orelse break) catch return error.BadTry;
  return t;
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
