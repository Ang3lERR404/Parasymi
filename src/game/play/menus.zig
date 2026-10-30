//! the pause menu, the saved gardens, naming a garden, inspecting and flying.
const lib=@import("../../lib.zig");
/// the engine package
const engine=lib.engine;
/// all the maths: clamps, vectors
const m=engine.core.math;
/// the keys and buttons down this frame
const Input=engine.platform.input.Input;
/// the bindings: which action each key is
const ctl=lib.controls;
/// the engine's camera: look, fly and roll speeds
const camera=engine.render.camera;
/// the HUD: clicks, picks and rows
const hud=lib.hud;
/// saving, for a garden's name
const save=lib.save;
/// how far the wheel dollies the free camera a notch
const dollyPerNotch=lib.play.dollyPerNotch;
/// how much faster the free camera flies with Shift held
const flyFastSpeed=lib.play.flyFastSpeed;
/// how many gardens' rows are in view at once
const gardensShown=lib.play.gardensShown;
/// how fast the gardens list follows its scroll (share a second)
const gardenEase=lib.play.gardenEase;
/// how many rows a wheel notch scrolls the gardens list
const gardenNotch=lib.play.gardenNotch;
/// the game, which these act on
const Game=lib.play.game.Game;
/// the saved gardens menu's buttons
const GardenAct=lib.play.GardenAct;
/// the pause menu's rows
const PauseRow=lib.play.PauseRow;
/// the pause menu and the panels opened from it, while the world is
/// frozen: a click on a pause row does what it says; on an option it
/// turns it (the other button turns it back); in the saved gardens it
/// chooses a garden, or saves or loads it. Keys still work for the pause
/// rows.
pub fn menu(g:*Game,in:*const Input,dt:f32)void{
  g.mouse=in.mouse;
  g.pointer=.{.at=in.mouse,.down=ctl.down(in,.use),.went=ctl.pressed(in,.use)};
  // the HUD row under the mouse, if any
  const hit=g.rows.at(in.mouse);
  g.pointed=hit;
  if(g.mode==.paused){
    if(ctl.pressed(in,.quit))g.request=.quit;
    if(ctl.pressed(in,.options))g.mode=.options;
    if(ctl.pressed(in,.gardens))g.openGardens();
  }
  if(g.mode==.naming)g.typeName(in);
  if(hit)|p|{
    if(ctl.pressed(in,.use))hud.click(g,p,.use,in)
    else if(ctl.pressed(in,.remove))hud.click(g,p,.remove,in);
  }
  if(g.mode==.gardens)g.scroll(in,dt);
}
/// does what pause row `row` says: resume, open the options or the saved
/// gardens, toggle fullscreen, or ask main to save and leave.
pub fn choose(g:*Game,row:PauseRow)void{
  switch(row){
    .@"resume"=>g.mode=.roam,
    .options=>g.mode=.options,
    .gardens=>g.openGardens(),
    .fullscreen=>g.opts.fullscreen=!g.opts.fullscreen,
    .quit=>g.request=.quit,
  }
}
/// the saved gardens menu opens on a fresh list, the played garden chosen
pub fn openGardens(g:*Game)void{
  g.mode=.gardens;
  g.request=.list;
  g.garden=0;
  g.overwrite=false;
  g.deleting=false;
  g.gardenTop=0;
  g.gardenAt=0;
}
/// main has just listed the gardens (`gardens`): the played one is
/// chosen (else the choice is kept in range) and scrolled into view.
pub fn listed(g:*Game)void{
  g.listedAt=g.uiTime;
  g.overwrite=false;
  g.deleting=false;
  if(g.slot)|n|for(g.gardens.items,1..)|e,i|if(e.name.is(n.slice())){g.garden=i;};
  g.garden=@min(g.garden,g.gardens.items.len);
  // the topmost the list may scroll to while the chosen garden stays in view
  const first=@max(m.f(g.garden)-m.f(gardensShown-1),0);
  g.gardenTop=@min(m.clamp(g.gardenTop,first,m.f(g.garden)),g.gardenScroll());
}
/// how far the gardens list scrolls (rows above the first in view)
pub fn gardenScroll(g:*const Game)f32{
  return m.f((g.gardens.items.len+1)-|gardensShown);
}
/// the wheel scrolls the gardens list; its groove, held, drags it
/// (a click on it takes hold of it: the gardens panel's `click`)
pub fn scroll(g:*Game,in:*const Input,dt:f32)void{
  // how far the list can scroll at most
  const most=g.gardenScroll();
  g.gardenTop-=in.scroll*gardenNotch;
  if(!ctl.down(in,.use))g.scrolling=false;
  if(g.scrolling)if(g.rows.find(hud.row(.gardens,.scroll)))|r|{
    g.gardenTop=m.clamp(r.local(in.mouse)[1],0,1)*most;
  };
  g.gardenTop=m.clamp(g.gardenTop,0,most);
  g.gardenAt+=(g.gardenTop-g.gardenAt)*@min(1,dt*gardenEase);
}
/// SAVE: a fresh garden asks for its name; over a saved one only when
/// asked twice. LOAD: the chosen saved garden. DELETE: the chosen one,
/// when asked twice. OK and CANCEL: the name prompt's.
pub fn gardenAct(g:*Game,a:GardenAct)void{
  // the chosen saved garden's name, or null for a fresh one
  const chosen:?save.Name=if(g.garden==0)null else g.gardens.items[g.garden-1].name;
  switch(a){
    .save=>if(chosen)|n|{
      if(g.overwrite)g.request=.{.saveAs=n};
      g.overwrite=!g.overwrite;
    }else g.startNaming(),
    .load=>if(chosen)|n|{g.request=.{.loadFrom=n};},
    .delete=>if(chosen)|n|{
      if(g.deleting)g.request=.{.delete=n};
      g.deleting=!g.deleting;
    },
    .ok=>g.nameChosen(),
    .cancel=>g.mode=g.namingFrom,
  }
}
/// ask for the name of the garden about to be saved (over the mode it
/// returns to); the gardens are listed, to know the names taken
pub fn startNaming(g:*Game)void{
  g.namingFrom=if(g.mode==.naming)g.namingFrom else g.mode;
  g.mode=.naming;
  g.typed.clear();
  g.overwrite=false;
  g.request=.list;
}
/// the name prompt: typing adds to the name, erase takes back, confirm
/// is OK
pub fn typeName(g:*Game,in:*const Input)void{
  switch(g.typed.feed(.{.typed=in.typed(),.erase=ctl.pressed(in,.erase),.confirm=ctl.pressed(in,.confirm)})){
    .same=>{},
    .changed=>g.overwrite=false,
    .submitted=>g.nameChosen(),
  }
}
/// the garden typed is taken
pub fn nameTaken(g:*const Game)bool{
  // the name typed, if it can be one
  const n=save.named(&g.typed) orelse return false;
  for(g.gardens.items)|e|if(e.name.same(n))return true;
  return false;
}
/// OK: save as the name typed (over a garden of that name only when
/// asked twice); a name that cannot be one does nothing
pub fn nameChosen(g:*Game)void{
  // the name typed, if it can be one
  const n=save.named(&g.typed) orelse return;
  if(g.nameTaken()and!g.overwrite){
    g.overwrite=true;
    return;
  }
  g.overwrite=false;
  g.mode=g.namingFrom;
  g.request=.{.saveAs=n};
}
/// enter or leave the free camera. Leaving gives the cursor back and eases
/// the view home.
pub fn inspect(g:*Game,in:*const Input,on:bool)void{
  if(on){
    g.mode=.inspect;
    g.cam.startFree();
    return;
  }
  g.mode=.roam;
  if(g.cam.view==.free and g.cam.view.free.captured)in.capture(false);
  g.cam.endFree();
}
/// the free camera: click to hold the cursor and look around, WASD to fly
/// (Shift faster), Q/E to roll, the wheel to dolly. Space and Ctrl+Space
/// rise and sink.
pub fn fly(g:*Game,in:*const Input,dt:f32)void{
  // the free camera's own state; nothing to fly in any other view
  const f=switch(g.cam.view){
    .free=>|*f|f,
    .follow,.returning,.eyes=>return,
  };
  // the look this frame (radians); the frame the cursor is taken its jump is not a look
  var look:[2]f32=.{0,0};
  if(ctl.pressed(in,.use)and!f.captured){
    in.capture(true);
    f.captured=true;
  }else if(f.captured or ctl.down(in,.use)){
    look=.{-in.mouseDelta[0]*camera.lookSpeed,-in.mouseDelta[1]*camera.lookSpeed};
  }
  // how far it flies this frame (metres)
  const speed=camera.flySpeed*dt*@as(f32,if(ctl.down(in,.flyFast))flyFastSpeed else 1);
  // the move this frame: right, up, forward
  var move=m.v3(0,0,0);
  if(ctl.down(in,.moveForward))move[2]+=speed;
  if(ctl.down(in,.moveBack))move[2]-=speed;
  if(ctl.down(in,.moveRight))move[0]+=speed;
  if(ctl.down(in,.moveLeft))move[0]-=speed;
  if(ctl.down(in,.rise))move[1]+=if(ctl.down(in,.alt))-speed else speed;
  // how far it rolls this frame (radians)
  var roll:f32=0;
  if(ctl.down(in,.rollLeft))roll-=camera.rollSpeed*dt;
  if(ctl.down(in,.rollRight))roll+=camera.rollSpeed*dt;
  g.cam.fly(look,move,roll,in.scroll*dollyPerNotch);
}
