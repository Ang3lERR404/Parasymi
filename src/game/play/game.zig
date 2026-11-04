//! the game: what it owns, starting and ending it, and the fixed-tick step.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type the game is built with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, tiles, facings
const m=engine.core.math;
/// the seeded random stream
const Rng=engine.core.rng.Rng;
/// the chunk layer: coordinates, tiles, chunks
const ck=lib.ck;
/// world generation: a tile's kind and height before it is streamed
const gen=lib.gen;
/// the garden's streamed world of chunks
const World=lib.world.World;
/// every plant growing in the garden
const Plants=lib.plants.Plants;
/// a plant's slot
const PlantId=lib.plants.Id;
/// the species registry: how high a floater hangs
const species=lib.species;
/// the ecology: the tick that grows, spreads and drains
const ecology=lib.ecology;
/// the ecology's own state, kept between ticks
const Ecology=ecology.Ecology;
/// what can be held: item kinds
const items=lib.items;
/// what the gardener has understood
const prog=lib.progression;
/// every player-facing string
const txt=lib.txt;
/// the engine's camera module
const camera=engine.render.camera;
/// the camera orbiting the wolf
const Camera=camera.Camera;
/// the garden's renderer: its plant meshes and stats
const renderer=lib.renderer;
/// the vertex layouts, for a plant's instance
const vertex=lib.vertex;
/// the UI's draw batch, which the HUD fills
const Draw=engine.ui.draw.Draw;
/// a scrolled list's place, for the saved gardens
const Scroll=engine.ui.scroll.Scroll;
/// the sky: day and night, and the starfall
const skyMod=lib.sky;
/// the player module
const playerMod=lib.player;
/// the vine-wolf the gardener plays
const Player=playerMod.Player;
/// the scene's list of moving parts
const Parts=lib.parts.Parts;
/// weaving: the queue of recipes woven by hand
const craft=lib.craft;
/// the structures registry: every structure standing
const st=lib.structures;
/// convergence: lineages meeting into something new
const convergence=lib.convergence;
/// the HUD: rows, picks, the sapling
const hud=lib.hud;
/// the settings
const options=lib.options;
/// saving: gardens' names and entries
const save=lib.save;
/// one thing alone, its state set by hand (`--plant`/`--structure`)
const Specimen=lib.specimen.Specimen;
/// how many hotbar slots there are
const barSlots=lib.play.barSlots;
/// how many gardens' rows are in view at once
const gardensShown=lib.play.gardensShown;
/// what a frame or a build may fail with: running out of memory
const Error=lib.play.Error;
/// what the cursor may carry
const Held=lib.play.Held;
/// the most catch-up ticks a frame may run
const maxCatchup=lib.play.maxCatchup;
/// what has the wolf's attention
const Mode=lib.play.Mode;
/// ground picking: how far the ray reaches, as times the camera's distance
const pickRangeMult=lib.play.pickRangeMult;
/// ground picking: the ray's step (metres)
const pickStep=lib.play.pickStep;
/// what only main can do
const Request=lib.play.Request;
/// the spawn search's radius (tiles)
const spawnSearch=lib.play.spawnSearch;
/// the spawn search's step (tiles)
const spawnStep=lib.play.spawnStep;
/// how many chunks stream in the first call
const streamInit=lib.play.streamInit;
/// how many rings of chunks are streamed round the gardener
const streamRadius=lib.play.streamRadius;
/// one simulation tick (s)
const tickTime=lib.play.tickTime;
/// the whole playable game: the garden and all that lives in it, the wolf,
/// progression, the camera and sky, the HUD and what it points at, and the
/// clocks that run them.
pub const Game=struct{
  /// the allocator everything the game owns is made with
  gpa:Allocator,
  /// the streamed world of chunks: tiles, heights, occupancy
  world:World,
  /// every plant growing in the garden
  plants:Plants=.{},
  /// every structure standing in the garden
  structs:st.Structures=.{},
  /// the ecology's state between ticks
  eco:Ecology=.{},
  /// the relays the structures hold (a diamond), gathered each tick for
  /// the light grid
  relays:std.ArrayList(lib.light.Relay)=.empty,
  /// the structures that take light, gathered each tick for the light grid
  users:std.ArrayList(lib.light.User)=.empty,
  /// beside `users`: which structure each is
  userIds:std.ArrayList(st.Id)=.empty,
  /// convergence's search for lineages meeting
  converge:convergence.Seeker=.{},
  /// what the gardener has understood, and the message log
  prog:prog.Progression=.{},
  /// the camera: following, in the wolf's eyes, or flying free
  cam:Camera=.{},
  /// the sky: the hour, day and night
  sky:skyMod.Sky=.{},
  /// the starlight falling at night, as motes
  stars:skyMod.Starfall,
  /// the vine-wolf: where it stands, its belly, its pose
  player:Player,
  /// the game's own random stream, seeded from the world's seed
  rng:Rng,
  /// the scene's moving parts, refilled each frame
  parts:Parts,
  /// the HUD's draw batch, rebuilt each frame
  ui:Draw,
  /// what a click on the HUD would land on, as drawn last frame
  rows:hud.Rows,
  /// the HUD area under the mouse this frame (panels show what it points at)
  pointed:?hud.Pick=null,
  /// the research sapling's growth, kept between frames
  sapling:hud.Sapling=.{},
  /// the queue of recipes woven by hand
  weave:craft.Crafter=.{},
  /// what has the wolf's attention now
  mode:Mode=.roam,
  /// something only main can do (it owns the window and the file system).
  request:?Request=null,
  /// the gardener's settings; main applies them when they change
  opts:options.Options=.{},
  /// each setting as the options panel shows it, easing toward its value:
  /// how open a toggle's bud is, where a slider's seed rides (-1: not yet
  /// shown, so it starts where it is)
  settingShown:[options.settingCount]f32=@splat(-1),
  /// what the GPU can take: its most MSAA samples, whether it traces rays
  /// (main sets it from the renderer)
  gpu:options.Gpu=.{},
  /// the garden being played, as saved (null until it is saved or loaded)
  slot:?save.Name=null,
  /// seconds played since the garden was last saved (autosave counts these)
  sinceSave:f64=0,
  /// the saved gardens menu: its list (main fills it on `.list`)
  gardens:std.ArrayList(save.Entry)=.empty,
  /// when the list was filled, in UI time (s), so ages keep counting up
  listedAt:f64=0,
  /// the chosen row: 0 a fresh garden, else `gardens[i - 1]`
  garden:usize=0,
  /// saving over the chosen garden was asked once already (the next SAVE does it)
  overwrite:bool=false,
  /// letting the chosen garden go was asked once already (the next DELETE does it)
  deleting:bool=false,
  /// alt mode: an icon over every structure of what it weaves or holds
  overview:bool=false,
  /// the name prompt: the name typed so far, its caret kept to the centre
  typed:save.Typed=.{},
  /// the mode the name prompt returns to
  namingFrom:Mode=.roam,
  /// the menu the options, keybinds and saved gardens go back to: the
  /// pause menu, or the main menu they were opened from
  menuHome:Mode=.paused,
  /// the wolf's sleep at the main menu (game/title.zig), read the first
  /// time it is shown
  sleep:?lib.engine.anim.clip.Clip=null,
  /// the saved gardens list's scroll: by wheel, its stem, or the row chosen
  gardenList:Scroll=.{.shown=gardensShown},
  /// the keybinds list's scroll: by wheel, its stem, or the row the keys are on
  bindList:Scroll=.{.shown=lib.play.bindsShown},
  /// the keybinds menu: the action listening for its new key, if any
  rebinding:?lib.controls.Action=null,
  /// keeps running while paused, so the UI still breathes.
  uiTime:f64=0,
  /// the hotbar's items
  bar:[barSlots]?items.Item=@splat(null),
  /// the selected hotbar slot
  hot:usize=0,
  /// what the cursor carries, if anything
  held:?Held=null,
  /// the tile of the structure whose panel is open (mode `.structure`); a
  /// tile, not an id, since ids move when a structure is removed
  open:m.Vice(i32,2)=.{0,0},
  /// the cursor, in screen pixels (tooltips and what is carried follow it);
  /// looking out of the wolf's eyes, the middle of the screen
  mouse:m.Vice(f32,2)=.{0,0},
  /// the cursor and the use button (mouse1) this frame, for the HUD's
  /// buttons to say whether they are hovered, pressed or held
  pointer:lib.engine.ui.button.Pointer=.{},
  /// the HUD row mouse1 went down on, while held: let go over it, it
  /// clicks (a row firing on release); held, it is dragged
  press:lib.engine.ui.button.Press(hud.Pick)=.{},
  /// the menu row the keys or the pad are on (null: the mouse leads); it
  /// is pointed at as the mouse would be, until the mouse moves
  keyFocus:?hud.Pick=null,
  /// the HUD row being typed into, if any
  typing:?hud.Pick=null,
  /// the window holds the cursor for looking out of the wolf's eyes; the
  /// frame it is taken its jump is not a look
  looking:bool=false,
  /// a click spent putting down or dropping what was carried does nothing
  /// in the garden until the button is let go
  useSpent:bool=false,
  /// facing for the next thing put down (R turns it while nothing is under
  /// the cursor; picking a seed takes the picked thing's)
  placeDir:m.Dir=0,
  /// remove, held: the tile last removed from (it is not removed from
  /// again until the cursor leaves it)
  removed:?m.Vice(i32,2)=null,
  /// the wait (s) before remove, held, removes the next tile
  removeCd:f32=0,
  /// the debug card is shown
  debug:bool=false,
  /// the tile under the cursor, if any (under a floater the cursor touches, its tile)
  hover:?m.Vice(i32,2)=null,
  /// the ground point under the cursor (y 0), or where a touched floater stands:
  /// a floater is put down right here, off the grid
  hoverAt:m.V3=@splat(0),
  /// the floating plant the cursor touches, if any: it is reached before the ground
  hoverFloat:?PlantId=null,
  /// how far the current gather has come (s)
  gatherT:f32=0,
  /// remove, pressed over a resource node: the node's tile, held to while
  /// remove stays down, however the cursor drifts as the camera follows the
  /// wolf walking up to it (null once let go, or the node is spent)
  gatherOn:?m.Vice(i32,2)=null,
  /// a ripe plant being plucked by paw, if any (game/pluck.zig)
  pluck:?lib.pluck.Pluck=null,
  /// the plucked plant's bend after the paws, springing back once let go
  tug:lib.pluck.Tug=.{},
  /// a short linger (s) for one-off gestures: the wolf keeps facing where it happened
  linger:f32=0,
  /// the wait (s) before the next thing is put down as the cursor sweeps
  plantCd:f32=0,
  /// the belly-full warning has been said for this press of remove
  fullWarned:bool=false,
  /// seconds of the world moving (not while frozen), for structures' turns
  time:f64=0,
  /// how many times faster than the clock the world runs (`--speed=`, for
  /// watching something slow unattended: its ticks, sky and air together,
  /// so all of it keeps in step; the air's step caps it at about 6 at 60 fps)
  speed:f64=1,
  /// how far the world moved this frame (s; 0 while frozen): what the air's
  /// moisture is stepped on by
  moved:f32=0,
  /// the moisture in the air over the hovered tile, as the GPU had it a
  /// frame or two ago: its mist, its cloud and its rain (null: not read
  /// back yet)
  air:?m.Vec(f32,3)=null,
  /// the weather: the field read back now and then, the ground soaked where it rained
  weather:lib.weather.Weather=.{},
  /// the moss the garden's creepers have grown, laid on every chunk
  moss:lib.moss.Moss=.{},
  /// the wild flowers sprung up by the pools
  wild:lib.wild.Wild=.{},
  /// unspent time (s) carried to the next fixed tick
  acc:f64=0,
  /// how long the simulation took this frame (ms), eased
  simMs:f32=0,
  /// how long a frame takes (ms), eased
  frameMs:f32=16,
  /// how many fixed ticks have run
  ticks:u64=0,
  /// the plant instances to draw this frame, one list per plant mesh
  inst:[renderer.plantMeshes]std.ArrayList(vertex.PlantInstance)=@splat(.empty),
  /// the plant instances caught for the rays this frame (`Scene.caught`):
  /// every plant of each patch in view, one list per caster mesh
  caught:[renderer.plantMeshes]std.ArrayList(vertex.PlantInstance)=@splat(.empty),
  /// the name each of those is caught under (`Scene.caughtIn`)
  caughtIn:[renderer.plantMeshes]std.ArrayList(u64)=@splat(.empty),
  /// the patches with a plant seen in them this frame (view.zig), each
  /// of whose plants is caught for the rays
  seenPatches:std.AutoHashMapUnmanaged(u64,void)=.empty,
  /// the chunks streamed far enough away to let go, gathered each frame
  far:std.ArrayList(*ck.Chunk)=.empty,
  /// the renderer's numbers from last frame
  renderStats:renderer.Stats=.{},
  /// `--plant`/`--structure`: one thing alone, its state set by hand (see
  /// specimen.zig); nothing else falls, grows or is drawn
  specimen:?Specimen=null,
  /// the first world event: where it stands (saved)
  unforming:lib.unforming.Unforming=.{},
  /// which act the garden is in: who the gardener is (game/act.zig)
  act:lib.act.Act=.wolf,
  /// the constellate tendrils drawn in the garden, and the one being drawn
  tendrils:lib.tendril.Tendrils=.{},
  /// the radiant plants as they were when it began, for their shards'
  /// flight (not saved)
  unformSources:std.ArrayList(lib.unforming.Source)=.empty,
  /// the ley nodes shattered as the ley lines sealed, for their shards'
  /// drift (not saved)
  leyDrifts:std.ArrayList(lib.unforming.Drift)=.empty,
  /// a fresh game on world `seed`: the wolf set down on the first fertile
  /// tile found spiralling out from the origin, the chunks round it streamed,
  /// and the waking messages said.
  pub fn init(gpa:Allocator,seed:u64)Error!Game{
    // the game being built
    var g:Game=.{
      .gpa=gpa,
      .world=World.init(gpa,seed),
      .rng=Rng.init(seed^0xA11CE),
      .stars=.{.rng=Rng.init(seed^0x57A2)},
      .player=.{.pos=m.v3(0.5,0,0.5)},
      .parts=Parts.init(gpa),
      .ui=.{.gpa=gpa},
      .rows=.{.gpa=gpa},
    };
    errdefer g.deinit();
    // start on dry land: spiral out from the origin until a fertile tile shows up.
    // the ring being searched (tiles from the origin)
    var r:i32=0;
    find:while(r<spawnSearch):(r+=spawnStep){
      // the step along the ring
      var a:i32=-r;
      while(a<=r):(a+=spawnStep){
        // the tile's row, and what generation makes of it
        const z=r-@divFloor(r,2);
        const s=gen.sample(seed,a,z);
        if(s.kind.fertile()){
          g.player.pos=m.tileCentre(a,z,s.height);
          break:find;
        }
      }
    }
    g.cam.target=g.player.pos;
    try g.world.stream(g.focus(),streamRadius,streamInit);
    g.prog.say(txt.s.msg.wake,.{});
    g.prog.say(txt.s.msg.nightHint,.{});
    return g;
  }
  /// frees everything the game owns.
  pub fn deinit(g:*Game)void{
    if(g.sleep)|*c|c.deinit();
    g.gardens.deinit(g.gpa);
    g.unformSources.deinit(g.gpa);
    g.leyDrifts.deinit(g.gpa);
    g.tendrils.deinit(g.gpa);
    g.moss.deinit(g.gpa);
    g.wild.deinit(g.gpa);
    for(&g.inst)|*l|l.deinit(g.gpa);
    for(&g.caught)|*l|l.deinit(g.gpa);
    for(&g.caughtIn)|*l|l.deinit(g.gpa);
    g.seenPatches.deinit(g.gpa);
    g.far.deinit(g.gpa);
    g.parts.deinit();
    g.ui.deinit();
    g.rows.deinit();
    g.stars.deinit(g.gpa);
    g.eco.deinit(g.gpa);
    g.relays.deinit(g.gpa);
    g.users.deinit(g.gpa);
    g.userIds.deinit(g.gpa);
    g.plants.deinit(g.gpa);
    g.structs.deinit(g.gpa);
    g.world.deinit();
  }
  /// the chunk the wolf stands in
  pub fn focus(g:*const Game)ck.Coord{
    // the tile the wolf stands on
    const t=m.tileAt(g.player.pos);
    return ck.Coord.ofTile(t[0],t[1]);
  }
  /// the ground's height at tile (`wx`, `wy`): the streamed chunk's, else generation's
  pub fn heightAt(g:*const Game,wx:i32,wy:i32)f32{
    if(g.world.chunkOfTile(wx,wy))|c|return c.height[ck.localIndex(wx,wy)];
    return gen.heightAt(g.world.seed,wx,wy);
  }
  /// what the cursor points at: `hover`, `hoverAt` and `hoverFloat` (none
  /// while `off`, as when inspecting)
  pub fn aim(g:*Game,cursor:m.Vice(f32,2),screen:m.Vice(f32,2),off:bool)void{
    g.hover=null;
    g.hoverFloat=null;
    if(off)return;
    // the ray through the cursor, the floater it touches first, and how far along it the march has come
    const ray=g.cam.ray(cursor[0],cursor[1],screen[0],screen[1]);
    const touched=g.plants.floaterOnRay(ray.o,ray.d,Hang,.{.g=g});
    // and the floating structure it touches first
    const touchedSt=g.structs.floaterOnRay(ray.o,ray.d,Ground,.{.g=g});
    var t:f32=0;
    // how far the march goes at most
    const maxT=g.cam.dist*pickRangeMult;
    while(t<maxT):(t+=pickStep){
      if(touchedSt)|f|if(f.t<=t and (if(touched)|p|f.t<=p.t else true)){
        // a floating structure before the ground (and any floating plant): its tile and where it stands
        const s=g.structs.get(f.id);
        g.hover=.{s.x,s.y};
        g.hoverAt=s.at;
        return;
      };
      if(touched)|f|if(f.t<=t){
        // a floater before the ground: its tile and where it stands
        g.hover=.{g.plants.list.items(.x)[f.id.idx()],g.plants.list.items(.y)[f.id.idx()]};
        g.hoverAt=g.plants.list.items(.at)[f.id.idx()];
        g.hoverFloat=f.id;
        return;
      };
      // the point reached, and the tile under it
      const p=ray.o+ray.d*m.splat3(t);
      const tile=m.tileAt(p);
      if(p[1]<=g.heightAt(tile[0],tile[1])){
        g.hover=tile;
        g.hoverAt=m.v3(p[0],0,p[2]);
        return;
      }
    }
  }
  /// the ground's height under each floating structure, for the cursor to touch it
  const Ground=struct{
    /// the garden they hang in
    g:*const Game,
    /// the ground's height at tile (`x`, `y`)
    pub fn at(h:Ground,x:i32,y:i32)f32{return h.g.heightAt(x,y);}
  };
  /// where each floating plant hangs, still, for the cursor to touch
  const Hang=struct{
    /// the garden they hang in
    g:*const Game,
    /// where floater `id` hangs: over its point, its species' height above the ground (never the water)
    pub fn at(h:Hang,id:PlantId)m.V3{
      // the plant columns, and where it stands
      const s=h.g.plants.list.slice();
      const c=s.items(.at)[id.idx()];
      return m.v3(c[0],@max(h.g.heightAt(s.items(.x)[id.idx()],s.items(.y)[id.idx()]),0)+species.get(s.items(.sp)[id.idx()]).hover,c[2]);
    }
  };
  /// the plant at tile `h`: the floater the cursor touches when `h` is the
  /// hovered tile, else whatever stands or floats there. The floater aimed at
  /// may have been uprooted since (removed this frame, its slot swapped or
  /// gone), so it counts only while a plant still stands in its slot on `h`.
  pub fn plantAt(g:*const Game,h:m.Vice(i32,2))?PlantId{
    if(g.hoverFloat)|f|if(g.hover)|hv|if(hv[0]==h[0] and hv[1]==h[1] and f.idx()<g.plants.list.len and g.plants.list.items(.x)[f.idx()]==h[0] and g.plants.list.items(.y)[f.idx()]==h[1])return f;
    return g.plants.at(&g.world,h[0],h[1]);
  }
  /// whether tile `h` holds a resource node with nothing on it: no
  /// structure, no plant, its stock not spent
  pub fn nodeAt(g:*const Game,h:m.Vice(i32,2))bool{
    // the tile's chunk (none, and nothing is there) and its index in it
    const c=g.world.chunkOfTile(h[0],h[1]) orelse return false;
    const t=ck.localIndex(h[0],h[1]);
    return c.res[t]>0 and c.occ[t]==.none and g.structs.at(&g.world,h[0],h[1])==null and g.plantAt(h)==null;
  }
  /// what structures' behaviour may touch, the wolf and the sky with the
  /// garden, and what befell it this tick (`ev`)
  pub fn structCtx(g:*Game,ev:lib.ecology.Events)st.Ctx{
    return.{.gpa=g.gpa,.w=&g.world,.plants=&g.plants,.g=&g.prog,.ss=&g.structs,.player=&g.player,.sky=&g.sky,.events=ev};
  }
  /// fixed-step simulation; never more than `maxCatchup` ticks per frame.
  pub fn simulate(g:*Game,frameDt:f64)Error!void{
    if(!g.mode.live())return;
    g.acc=@min(g.acc+frameDt*g.speed,tickTime*maxCatchup*g.speed);
    while(g.acc>=tickTime):(g.acc-=tickTime)try g.step();
  }
  /// one fixed tick of everything that lives: ecology, convergence,
  /// progression, structures.
  /// (see the test below for the headless harness)
  pub fn step(g:*Game)Error!void{
    if(g.specimen)|*sp|if(try sp.hold(g,tickTime)){
      g.ticks+=1;
      return;
    };
    // the modifiers this tick: progression's, the night, the structures'
    // part in the light grid
    var mods=g.prog.mods();
    mods.night=1-g.sky.daylight();
    try st.lightGrid(&g.structs,g.gpa,&g.relays,&g.users,&g.userIds);
    mods.relays=g.relays.items;
    mods.users=g.users.items;
    // what befell the garden this tick
    const ev=try g.eco.tick(g.gpa,&g.plants,&g.world,mods,tickTime);
    // each structure that takes light has its share of it
    for(g.structs.list.items)|*it|it.lit=0;
    for(g.userIds.items,g.eco.light.userLit.items)|id,v|g.structs.get(id).lit=v;
    // a specimen held in light (`--lit=`) has that share, whatever the grid gives
    if(g.specimen)|sp|if(sp.lit)|v|for(g.structs.list.items)|*it|{it.lit=v;};
    lib.beamGround.tick(g,tickTime);
    try g.converge.tick(g.gpa,&g.world,&g.plants,&g.structs,&g.prog);
    try g.structs.growTogether(g.gpa,&g.world,&g.prog,tickTime);
    try lib.moss.creep(g,tickTime);
    g.moss.apply(&g.world);
    try lib.wild.tick(g,tickTime);
    g.prog.absorb(ev,tickTime);
    try st.Structures.tickWith(g.structCtx(ev),tickTime);
    _=try lib.haloStructure.seek(g.structCtx(ev));
    lib.tendril.tick(g,tickTime);
    try lib.unforming.tick(g,tickTime);
    if(g.specimen)|*sp|try sp.after(g,tickTime);
    g.ticks+=1;
  }
  /// one frame of play (`frame.update`)
  pub const update=lib.play.frame.update;
  /// where the game is heard from (`hearing.ear`)
  pub const ear=lib.play.hearing.ear;
  /// the echo of the place it is heard from (`hearing.space`)
  pub const space=lib.play.hearing.space;
  /// how much the ground hides a sound somewhere (`hearing.muffle`)
  pub const muffle=lib.play.hearing.muffle;
  /// what the arsthraxia's sound plays now (`belly.arsthraxiaState`)
  pub const arsthraxiaState=lib.play.belly.arsthraxiaState;
  /// the view is in the wolf's eyes, its head hidden (`belly.headless`)
  pub const headless=lib.play.belly.headless;
  /// whether the cursor carries a given thing (`belly.holds`)
  pub const holds=lib.play.belly.holds;
  /// whether the mouse is over a given HUD row (`belly.points`)
  pub const points=lib.play.belly.points;
  /// whether mouse1 went down on a given HUD row and is held (`pointer.grips`)
  pub const grips=lib.play.pointer.grips;
  /// UI seconds, wrapped small for sway (`belly.uiT`)
  pub const uiT=lib.play.belly.uiT;
  /// the selected hotbar item (`belly.selected`)
  pub const selected=lib.play.belly.selected;
  /// what the cursor carries (`belly.carried`)
  pub const carried=lib.play.belly.carried;
  /// the item a carried slot holds (`belly.itemOf`)
  pub const itemOf=lib.play.belly.itemOf;
  /// the structure whose panel is open (`belly.opened`)
  pub const opened=lib.play.belly.opened;
  /// a slot of the open structure (`belly.storeSlot`)
  pub const storeSlot=lib.play.belly.storeSlot;
  /// a click on a belly slot (`belly.clickSlot`)
  pub const clickSlot=lib.play.belly.clickSlot;
  /// a click on a slot of the open structure (`belly.clickStore`)
  pub const clickStore=lib.play.belly.clickStore;
  /// a click on a hotbar slot (`belly.clickBar`)
  pub const clickBar=lib.play.belly.clickBar;
  /// put down what is carried anywhere but a slot (`belly.drop`)
  pub const drop=lib.play.belly.drop;
  /// throw away a belly stack (`belly.discard`)
  pub const discard=lib.play.belly.discard;
  /// move a stack straight across (`belly.moveAcross`)
  pub const moveAcross=lib.play.belly.moveAcross;
  /// put a carried stack down on a slot (`belly.putDown`)
  pub const putDown=lib.play.belly.putDown;
  /// works a resource node for a tick (`actions.gather`)
  pub const gather=lib.actions.gather;
  /// put the selected hotbar item into the world (`actions.put`)
  pub const put=lib.actions.put;
  /// whether the chosen hotbar item may go down at this tile (`actions.canPut`)
  pub const canPut=lib.actions.canPut;
  /// queues weave `i` (an index into `craft.hand`) in the wolf's own hands, taking its ingredients now (`actions.weaveByHand`)
  pub const weaveByHand=lib.actions.weaveByHand;
  /// give a structure everything from the belly it will take (`actions.feed`)
  pub const feed=lib.actions.feed;
  /// what a click (or the interact key) on a structure does (`actions.interact`)
  pub const interact=lib.actions.interact;
  /// turn what stands at a tile a quarter, clockwise or `back` (`actions.turnAt`)
  pub const turnAt=lib.actions.turnAt;
  /// take up the seed (or bulb) of what stands at a tile, facing as it does (`actions.pick`)
  pub const pick=lib.actions.pick;
  /// empty a structure into the belly (what fits) (`actions.takeFrom`)
  pub const takeFrom=lib.actions.takeFrom;
  /// uproot a structure (`actions.unbuild`)
  pub const unbuild=lib.actions.unbuild;
  /// start plucking a mature plant's yield by paw (`pluckOn` carries it on) (`actions.harvest`)
  pub const harvest=lib.actions.harvest;
  /// one frame of plucking (`actions.pluckOn`)
  pub const pluckOn=lib.actions.pluckOn;
  /// pull a plant up (`actions.uproot`)
  pub const uproot=lib.actions.uproot;
  /// starlight drifts toward the wolf's chest and is absorbed on touch (`actions.catchStarlight`)
  pub const catchStarlight=lib.actions.catchStarlight;
  /// the frozen world's menus, each frame (`menus.menu`)
  pub const menu=lib.play.menus.menu;
  /// does what a pause row says (`menus.choose`)
  pub const choose=lib.play.menus.choose;
  /// does what a main menu row says (`menus.chooseTitle`)
  pub const chooseTitle=lib.play.menus.chooseTitle;
  /// at the main menu, or a panel opened from it (no garden entered yet)
  pub fn atTitle(g:*const Game)bool{return g.mode==.title or (g.menuHome==.title and !g.mode.live());}
  /// opens the saved gardens (`menus.openGardens`)
  pub const openGardens=lib.play.menus.openGardens;
  /// opens the keybinds (`menus.openKeybinds`)
  pub const openKeybinds=lib.play.menus.openKeybinds;
  /// the keybinds list scrolled, or a key bound (`menus.keybinds`)
  pub const keybinds=lib.play.menus.keybinds;
  /// main has listed the gardens (`menus.listed`)
  pub const listed=lib.play.menus.listed;
  /// scrolls the gardens list (`menus.scroll`)
  pub const scroll=lib.play.menus.scroll;
  /// a saved gardens button (`menus.gardenAct`)
  pub const gardenAct=lib.play.menus.gardenAct;
  /// asks for the name of the garden to save (`menus.startNaming`)
  pub const startNaming=lib.play.menus.startNaming;
  /// whether the typed name is taken (`menus.nameTaken`)
  pub const nameTaken=lib.play.menus.nameTaken;
  /// OK on the name prompt (`menus.nameChosen`)
  pub const nameChosen=lib.play.menus.nameChosen;
  /// enter or leave the free camera (`menus.inspect`)
  pub const inspect=lib.play.menus.inspect;
  /// the free camera's flying (`menus.fly`)
  pub const fly=lib.play.menus.fly;
};
