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
/// how fast the gardens list follows its scroll (share a second)
const gardenEase=lib.play.gardenEase;
/// how many rows a wheel notch scrolls the gardens list
const gardenNotch=lib.play.gardenNotch;
/// keybinds menu: how many rows a wheel notch scrolls
const bindNotch=lib.play.bindNotch;
/// how fast the right stick, leant all the way, looks round in the free
/// camera (the mouse's pixels a second, as out of the wolf's eyes)
const padLook=lib.play.frame.padLook;
/// every action, one keybinds row each, in order
const actions=lib.std.enums.values(ctl.Action);
/// the HUD under the mouse, the keys and the pad
const pointer=lib.play.pointer;
/// the game, which these act on
const Game=lib.play.game.Game;
/// the saved gardens menu's buttons
const GardenAct=lib.play.GardenAct;
/// the pause menu's rows
const PauseRow=lib.play.PauseRow;
/// the main menu's rows
const TitleRow=lib.play.TitleRow;
/// the pause menu and the panels opened from it, while the world is
/// frozen: a click on a pause row does what it says; on an option it
/// turns it (the other button turns it back); in the saved gardens it
/// chooses a garden, or saves or loads it. The arrows, tab and the pad
/// move between the rows and confirm chooses; keys still work for the
/// pause rows; the name prompt takes the typing; a keybind listening
/// takes the next key; the research tree is moved round and zoomed.
pub fn menu(g:*Game,in:*const Input,dt:f32)void{
  if(g.mode==.keybinds)if(g.rebinding)|a|return listen(g,in,a);
  pointer.point(g,in,in.mouse);
  // the HUD row under the mouse, if any
  const hit=g.rows.at(in.mouse);
  g.pointed=hit;
  if(g.mode==.paused){
    if(ctl.pressed(in,.quit))g.request=.quit;
    if(ctl.pressed(in,.options))g.mode=.options;
    if(ctl.pressed(in,.keybinds))g.openKeybinds();
    if(ctl.pressed(in,.gardens))g.openGardens();
  }
  pointer.steer(g,in);
  pointer.typeInto(g,in);
  pointer.clicks(g,in,hit);
  if(g.mode==.gardens)g.scroll(in,dt);
  if(g.mode==.keybinds)g.keybinds(in,dt);
  if(g.mode==.options)hud.panels.options.tick(g,dt);
  // the research tree: its key closes it again, else it is moved round
  if(g.mode==.research){
    if(ctl.pressed(in,.research)){g.mode=.roam;}else hud.panels.research.tick(g,in,hit,dt);
  }
}
/// does what pause row `row` says: resume, open the options or the saved
/// gardens, toggle fullscreen, or ask main to save and leave.
pub fn choose(g:*Game,row:PauseRow)void{
  g.menuHome=.paused;
  switch(row){
    .@"resume"=>g.mode=.roam,
    .options=>g.mode=.options,
    .keybinds=>g.openKeybinds(),
    .gardens=>g.openGardens(),
    .fullscreen=>g.opts.fullscreen=!g.opts.fullscreen,
    .quit=>g.request=.quit,
  }
}
/// does what main menu row `row` says: wake into the newest garden or the
/// fresh one, open the saved gardens, the options or the keybinds (each
/// going back to the main menu), or leave without saving
pub fn chooseTitle(g:*Game,row:TitleRow)void{
  g.menuHome=.title;
  switch(row){
    .@"continue"=>if(g.gardens.items.len>0){g.request=.{.loadFrom=g.gardens.items[0].name};},
    // (in the garden now: what it opens is play's, not the main menu's)
    .newGarden=>{
      g.mode=.roam;
      g.menuHome=.paused;
    },
    .gardens=>g.openGardens(),
    .options=>g.mode=.options,
    .keybinds=>g.openKeybinds(),
    .leave=>g.request=.leave,
  }
}
/// the saved gardens menu opens on a fresh list, the played garden chosen
pub fn openGardens(g:*Game)void{
  g.mode=.gardens;
  g.request=.list;
  g.garden=0;
  g.overwrite=false;
  g.deleting=false;
  g.gardenList.reset();
  g.keyFocus=null;
}
/// the keybinds menu opens at its top, listening for nothing
pub fn openKeybinds(g:*Game)void{
  g.mode=.keybinds;
  g.rebinding=null;
  g.bindList.reset();
  g.keyFocus=null;
}
/// the action `a` listening: the first key, mouse or pad button pressed
/// binds it (back, which cancels, never reaches here); main writes the
/// bindings out
fn listen(g:*Game,in:*const Input,a:ctl.Action)void{
  g.bindList.keep(@intFromEnum(a));
  const b=in.anyPressed() orelse return;
  ctl.rebind(a,b);
  g.rebinding=null;
  g.request=.bindings;
}
/// the wheel scrolls the keybinds list (its stem, held, drags it: the
/// keybinds panel's `drag`); the row the keys are on is kept in view
pub fn keybinds(g:*Game,in:*const Input,dt:f32)void{
  g.bindList.wheel(in.scroll,bindNotch);
  if(hud.own(.keybinds,g.keyFocus))|p|switch(p){
    .action=>|a|g.bindList.keep(@intFromEnum(a)),
    .reset,.back,.scroll=>{},
  };
  g.bindList.tick(actions.len,dt,gardenEase);
}
/// main has just listed the gardens (`gardens`): the played one is
/// chosen (else the choice is kept in range) and scrolled into view.
pub fn listed(g:*Game)void{
  g.listedAt=g.uiTime;
  g.overwrite=false;
  g.deleting=false;
  if(g.slot)|n|for(g.gardens.items,1..)|e,i|if(e.name.is(n.slice())){g.garden=i;};
  g.garden=@min(g.garden,g.gardens.items.len);
  // scrolled no further than the chosen garden needs to stay in view
  const l=&g.gardenList;
  l.keep(g.garden);
  l.top=@min(l.top,l.most(g.gardens.items.len+1));
}
/// the wheel scrolls the gardens list (its stem, held, drags it: the
/// gardens panel's `drag`); it eases to where it is wanted
pub fn scroll(g:*Game,in:*const Input,dt:f32)void{
  g.gardenList.wheel(in.scroll,gardenNotch);
  // the row the keys are on is kept in view
  if(hud.own(.gardens,g.keyFocus))|p|switch(p){
    .garden=>|i|g.gardenList.keep(i),
    .act,.back,.scroll=>{},
  };
  g.gardenList.tick(g.gardens.items.len+1,dt,gardenEase);
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
  g.typing=hud.row(.naming,.field);
  g.keyFocus=null;
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
  var look:m.Vice(f32,2)=.{0,0};
  if(ctl.pressed(in,.use)and!f.captured){
    in.capture(true);
    f.captured=true;
  }else if(f.captured or ctl.down(in,.use)){
    look=.{-in.mouseDelta[0]*camera.lookSpeed,-in.mouseDelta[1]*camera.lookSpeed};
  }
  // the right stick looks too, gently near its middle (+y up: looks up)
  const rs=in.stick(.right);
  const turn=rs*m.splatOf(f32,2,m.lenOf(f32,2,rs)*padLook*camera.lookSpeed*dt);
  look=.{look[0]-turn[0],look[1]+turn[1]};
  // how far it flies this frame (metres)
  const speed=camera.flySpeed*dt*@as(f32,if(ctl.down(in,.flyFast))flyFastSpeed else 1);
  // the move this frame: right, up, forward
  var move=m.v3(0,0,0);
  if(ctl.down(in,.moveForward))move[2]+=speed;
  if(ctl.down(in,.moveBack))move[2]-=speed;
  if(ctl.down(in,.moveRight))move[0]+=speed;
  if(ctl.down(in,.moveLeft))move[0]-=speed;
  // the left stick flies as far as it leans
  const ls=in.stick(.left);
  move[0]+=ls[0]*speed;
  move[2]+=ls[1]*speed;
  if(ctl.down(in,.rise))move[1]+=if(ctl.down(in,.alt))-speed else speed;
  // how far it rolls this frame (radians)
  var roll:f32=0;
  if(ctl.down(in,.rollLeft))roll-=camera.rollSpeed*dt;
  if(ctl.down(in,.rollRight))roll+=camera.rollSpeed*dt;
  g.cam.fly(look,move,roll,in.scroll*dollyPerNotch);
}
