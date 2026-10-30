//! one frame of play: input read into actions, the camera, the HUD's picks.
const lib=@import("../../lib.zig");
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, clamps, tiles
const m=engine.core.math;
/// the chunk layer: tile indices
const ck=lib.ck;
/// every player-facing string
const txt=lib.txt;
/// the keys and buttons down this frame
const Input=engine.platform.input.Input;
/// the bindings: which action each key is
const ctl=lib.controls;
/// the player module, for how near the wolf grips a node
const playerMod=lib.player;
/// the structures registry, for configuring one
const st=lib.structures;
/// the gardener's actions: put, harvest, gather, remove, turn
const actions=lib.actions;
/// the HUD: clicks and rows
const hud=lib.hud;
/// how eagerly the wolf walks up to a node it gathers from
const approach=lib.play.approach;
/// what a frame may fail with: running out of memory
const Error=lib.play.Error;
/// how far above the wolf's feet the camera follows
const followHeight=lib.play.followHeight;
/// how quickly the camera follows (share a second)
const followLerp=lib.play.followLerp;
/// the game, which a frame runs
const Game=lib.play.game.Game;
/// how many chunks stream in each frame
const streamFrame=lib.play.streamFrame;
/// how many rings of chunks are streamed round the gardener
const streamRadius=lib.play.streamRadius;
/// how quickly the shown timings follow the measured ones
const timingEase=lib.play.timingEase;
/// one frame of play, `dt` seconds on a screen `screen` pixels across:
/// system keys, the menus while frozen, then (live) the sky, camera and
/// looking, panels and hotbar keys, HUD clicks, movement, what the cursor
/// does to the tile it is on, weaving, the wolf's move and pose, the
/// starfall, and streaming the world round the wolf.
pub fn update(g:*Game,in:*const Input,dt:f32,screen:[2]f32)Error!void{
  g.uiTime+=dt;
  g.frameMs+=(dt*m.msPerS-g.frameMs)*timingEase;
  g.cam.aspect=screen[0]/@max(screen[1],1);
  // system keys work everywhere; Esc closes a panel first, then pauses
  // (not while a name is typed, nor for a garden that has none yet: a
  // name is asked for first)
  if(g.mode!=.naming){
    if(ctl.pressed(in,.save))if(g.slot!=null){g.request=.save;}else g.startNaming();
    if(ctl.pressed(in,.load))g.request=.load;
  }
  if(ctl.pressed(in,.fullscreen))g.opts.fullscreen=!g.opts.fullscreen;
  if(ctl.pressed(in,.back))switch(g.mode){
    .roam=>g.mode=.paused,
    .belly,.structure,.research,.paused=>g.mode=.roam,
    .options,.gardens=>g.mode=.paused,
    .naming=>g.mode=g.namingFrom,
    .inspect=>g.inspect(in,false),
  }else if(!g.mode.live())g.menu(in,dt);
  if(!g.mode.live()){
    // (the frozen world's menus give back a cursor held for looking)
    if(g.looking)in.capture(false);
    g.looking=false;
    return;
  }
  g.time+=dt;
  // the garden saves itself every so often (only time played counts)
  g.sinceSave+=dt;
  if(g.opts.autosave>0 and g.sinceSave>=m.f(g.opts.autosave)*m.sPerMin and g.request==null){
    g.request=.autosave;
    g.sinceSave=0;
  }
  g.sky.update(dt);
  // decision: alt + freeCam (Ctrl+F) toggles the free inspection camera
  // (harvest alone, F, harvests)
  // alt held, for the free camera and to keep harvest off
  const alt=ctl.down(in,.alt);
  if(alt and ctl.pressed(in,.freeCam))g.inspect(in,g.mode!=.inspect);
  // whether the free camera is out
  const inspecting=g.mode==.inspect;
  g.cam.tick(dt);
  // out of the wolf's eyes, the mouse looks round while nothing else wants
  // the cursor; what is used is what the middle of the screen is on
  // whether this frame looks out of the wolf's eyes
  const looking=g.cam.inEyes() and g.mode==.roam;
  if(looking!=g.looking){
    in.capture(looking);
    g.looking=looking;
  }else if(looking)g.cam.look(in.mouseDelta);
  // where the cursor is: the screen's middle while looking, else the mouse
  const cursor=if(looking)[2]f32{screen[0]/2,screen[1]/2}else in.mouse;
  // panels and selection
  if(!inspecting){
    if(ctl.pressed(in,.belly))g.mode=if(g.mode==.belly).roam else.belly;
    if(ctl.pressed(in,.research))g.mode=if(g.mode==.research).roam else.research;
  }
  if(ctl.pressed(in,.debug))g.debug=!g.debug;
  // slot keys pick the hotbar slot, whichever panel is open
  if(!inspecting)for(ctl.slots,0..)|a,i|{
    if(ctl.pressed(in,a))g.hot=i;
  };
  // a click lands on the HUD panel under the mouse before the world: rows
  // choose research, weave a recipe, lift or put down an item; a panel's
  // backdrop just absorbs it
  g.mouse=cursor;
  // a structure's panel closes once it is gone or out of reach
  if(g.mode==.structure and g.opened()==null)g.mode=.roam;
  if(!g.mode.sorting())g.held=null;
  if(g.held)|h|switch(h){
    .slot=>|i|if(g.player.inv.slot[i]==null){g.held=null;},
    .bar=>|i|if(g.bar[i]==null){g.held=null;},
    .store=>|i|if(g.storeSlot(i)==null){g.held=null;},
  };
  // the HUD row under the cursor (none while flying or looking)
  const uiHit=if(inspecting or looking)null else g.rows.at(cursor);
  g.pointed=uiHit;
  if(!ctl.down(in,.use))g.useSpent=false;
  if(ctl.pressed(in,.use)){
    if(uiHit)|hit|hud.click(g,hit,.use,in)else if(g.held!=null){
      g.drop();
      g.useSpent=true;
    }
  }
  if(ctl.pressed(in,.remove))if(uiHit)|hit|hud.click(g,hit,.remove,in);
  // discard throws away the belly stack carried, else the one under the cursor
  if(ctl.pressed(in,.discard) and g.mode.sorting()){
    if(g.held)|h|switch(h){
      .slot=>|i|g.discard(i),
      .bar,.store=>{},
    }else if(uiHit)|hit|hud.click(g,hit,.discard,in);
  }
  // movement relative to the camera: the keys' wish, right and forward
  var mx:f32=0;
  var mz:f32=0;
  if(inspecting){
    g.fly(in,dt);
  }else{
    if(ctl.down(in,.moveLeft))mx-=1;
    if(ctl.down(in,.moveRight))mx+=1;
    if(ctl.down(in,.moveForward))mz+=1;
    if(ctl.down(in,.moveBack))mz-=1;
  }
  // the camera's turn, the wish turned by it, and its length (kept at most 1)
  const yaw=g.cam.yaw;
  var wish=[2]f32{@cos(yaw)*mx-@sin(yaw)*mz,-@sin(yaw)*mx-@cos(yaw)*mz};
  const wl=@sqrt(wish[0]*wish[0]+wish[1]*wish[1]);
  if(wl>1)wish=.{wish[0]/wl,wish[1]/wl};
  // the camera orbits round the wolf while dragged; the wheel zooms, all
  // the way in into its eyes
  if(!inspecting){
    if(ctl.down(in,.orbit)and!g.cam.inEyes())g.cam.orbit(in.mouseDelta);
    if(in.scroll!=0)g.cam.zoom(in.scroll,g.player.eyes());
  }
  // interaction with the hovered tile (none while inspecting)
  g.hover=if(inspecting)null else g.pick(cursor,screen);
  // whether the wolf is working or gathering, and where its hands work
  var working=false;
  var gathering=false;
  var work:?m.V3=null;
  g.plantCd-=dt;
  g.removeCd-=dt;
  g.linger-=dt;
  // whether remove is held over the garden (not the HUD)
  const removing=ctl.down(in,.remove) and uiHit==null;
  if(!removing){
    g.gatherT=0;
    g.fullWarned=false;
    g.removed=null;
  }
  // whether the hovered tile is within reach
  const near=if(g.hover)|h|g.player.inReach(h[0],h[1])else false;
  // R turns what is under the cursor (within reach), else the next thing
  // put down; held with counter, the other way
  if(ctl.pressed(in,.rotate)and!inspecting){
    // whether counter is held, turning the other way, and whether something turned
    const back=ctl.down(in,.counter);
    const turned=if(g.hover)|h|near and actions.turnAt(g,h,back)else false;
    if(!turned)g.placeDir+%=@as(m.Dir,if(back)3 else 1);
  }
  if(g.hover)|h|if(near)if(g.world.chunkOfTile(h[0],h[1]))|c|{
    // the tile's index within its chunk
    const t=ck.localIndex(h[0],h[1]);
    // what floats over a tile is reached first (it is drawn over what is under it)
    const onStruct=g.structs.at(&g.world,h[0],h[1]);
    const onPlant=if(onStruct==null)g.plants.at(&g.world,h[0],h[1])else null;
    // whether a click here acts on the garden: not on the HUD, not spent
    const using=uiHit==null and !g.useSpent;
    // held, use puts what is in hand down wherever it fits as the cursor
    // sweeps; where it does not, a click interacts with a structure or
    // harvests a plant (so does interact, always)
    if(using and ctl.down(in,.use) and actions.canPut(g,h)){
      if(g.plantCd<=0)try actions.put(g,h);
    }else if((using and ctl.pressed(in,.use)) or ctl.pressed(in,.interact)){
      if(onStruct)|j|{
        actions.interact(g,h,j);
        g.useSpent=ctl.down(in,.use);
      }else if(onPlant!=null)actions.harvest(g,h);
    }
    if(ctl.pressed(in,.pick))_=actions.pick(g,h);
    if(ctl.pressed(in,.harvest)and!alt){
      if(onStruct)|j|{
        if(ctl.down(in,.take))actions.takeFrom(g,j)else actions.feed(g,j);
      }else actions.harvest(g,h);
    }
    if(ctl.pressed(in,.configure))if(onStruct)|j|st.configure(&g.structs,j,&g.prog);
    // remove, pressed or held: what stands goes (one tile at a time as
    // the cursor sweeps), a resource node is gathered from
    if(removing){
      if(onStruct!=null or onPlant!=null){
        // whether the cursor has moved onto a new tile since the last removal
        const fresh=if(g.removed)|r|r[0]!=h[0] or r[1]!=h[1]else true;
        if(ctl.pressed(in,.remove)or(fresh and g.removeCd<=0)){
          if(onStruct)|j|actions.unbuild(g,j)else actions.uproot(g,h);
          g.removed=h;
          g.removeCd=actions.removeCooldown;
          g.linger=actions.lingerPut;
        }
      }else if(c.res[t]>0 and c.occ[t]==.none){
        working=actions.gather(g,c,t,dt);
        gathering=working;
      }
    }
    if(working or g.linger>0)work=m.tileCentre(h[0],h[1],c.height[t]);
  };
  // weaving: hands work at the chest while the queue runs
  if(g.weave.tick(g.player.inv.bag(),dt))|made|g.prog.say(txt.s.msg.wove,.{txt.item(made).name});
  if(g.weave.busy()and!working)work=g.player.pos+m.v3(@sin(g.player.facing),0,@cos(g.player.facing));
  // a one-off gesture keeps facing where it happened
  if(work==null and g.linger>0)work=g.player.work;
  g.player.work=work;
  g.player.gather=if(gathering)m.clamp01(g.gatherT/actions.gatherTime)else null;
  // decision: gathering with no move held, the wolf steps up to the node
  // until its paws can grip it (it crouches and pries it by hand)
  if(gathering and wish[0]==0 and wish[1]==0)if(work)|at|{
    // how far the node is, across and along, and its distance
    const dx=at[0]-g.player.pos[0];
    const dz=at[2]-g.player.pos[2];
    const d=@sqrt(dx*dx+dz*dz);
    // how eagerly to step, slowing as the paws reach it
    const go=m.clamp01((d-playerMod.gatherAt)*approach);
    if(d>1e-3)wish=.{dx/d*go,dz/d*go};
  };
  // out of its eyes, the wolf turns to face where they look
  // (the camera's yaw looks down -z turned, the wolf's facing down +z)
  g.player.aim=if(g.cam.inEyes())g.cam.yaw+m.pi else null;
  g.player.gaze=if(g.cam.inEyes())g.cam.gaze()else null;
  g.player.move(wish,ctl.down(in,.run),&g.world,dt);
  g.player.animate(&g.world,dt);
  g.cam.see(g.player.eyes());
  // the point the camera follows, above the wolf's feet
  const follow=g.player.pos+m.v3(0,followHeight,0);
  g.cam.target+=(follow-g.cam.target)*m.splat3(@min(1,dt*followLerp));
  if(g.specimen==null){
    try g.stars.update(g.gpa,&g.sky,g.player.pos,&g.world,dt);
    actions.catchStarlight(g,dt);
  }
  // stream the world around the player; chunks holding what we grew stay
  try g.world.stream(g.focus(),streamRadius,streamFrame);
  try g.world.far(g.focus(),streamRadius,&g.far);
  for(g.far.items)|c|try g.world.unload(c);
}
