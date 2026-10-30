//! the game: what it owns, starting and ending it, and the fixed-tick step.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const Rng=engine.core.rng.Rng;
const ck=lib.ck;
const gen=lib.gen;
const World=lib.world.World;
const Plants=lib.plants.Plants;
const ecology=lib.ecology;
const Ecology=ecology.Ecology;
const items=lib.items;
const prog=lib.progression;
const txt=lib.txt;
const camera=engine.render.camera;
const Camera=camera.Camera;
const renderer=lib.renderer;
const vertex=lib.vertex;
const Draw=engine.ui.draw.Draw;
const skyMod=lib.sky;
const playerMod=lib.player;
const Player=playerMod.Player;
const Parts=lib.parts.Parts;
const craft=lib.craft;
const st=lib.structures;
const convergence=lib.convergence;
const hud=lib.hud;
const options=lib.options;
const save=lib.save;
const Specimen=lib.specimen.Specimen;
const barSlots=lib.play.barSlots;
const Error=lib.play.Error;
const Held=lib.play.Held;
const maxCatchup=lib.play.maxCatchup;
const Mode=lib.play.Mode;
const pickRangeMult=lib.play.pickRangeMult;
const pickStep=lib.play.pickStep;
const Request=lib.play.Request;
const spawnSearch=lib.play.spawnSearch;
const spawnStep=lib.play.spawnStep;
const streamInit=lib.play.streamInit;
const streamRadius=lib.play.streamRadius;
const tickTime=lib.play.tickTime;
pub const Game=struct{
  gpa:Allocator,
  world:World,
  plants:Plants=.{},
  structs:st.Structures=.{},
  eco:Ecology=.{},
  /// the standing fields of celestial energy (halos), gathered each tick
  fields:std.ArrayList(ecology.Field)=.empty,
  converge:convergence.Seeker=.{},
  prog:prog.Progression=.{},
  cam:Camera=.{},
  sky:skyMod.Sky=.{},
  stars:skyMod.Starfall,
  player:Player,
  rng:Rng,
  parts:Parts,
  ui:Draw,
  /// what a click on the HUD would land on, as drawn last frame
  rows:hud.Rows=.{},
  /// the HUD area under the mouse this frame (panels show what it points at)
  pointed:?hud.Pick=null,
  sapling:hud.Sapling=.{},
  weave:craft.Crafter=.{},
  mode:Mode=.roam,
  /// something only main can do (it owns the window and the file system).
  request:?Request=null,
  /// the gardener's settings; main applies them when they change
  opts:options.Options=.{},
  /// the most MSAA samples the GPU takes (main sets it from the renderer)
  mostSamples:u32=8,
  /// the garden being played, as saved (null until it is saved or loaded)
  slot:?save.Name=null,
  /// seconds played since the garden was last saved (autosave counts these)
  sinceSave:f64=0,
  /// the saved gardens menu: its list (main fills it on `.list`, at
  /// `listed_at` in UI time), the chosen row (0: a fresh garden, else
  /// `gardens[i - 1]`), whether saving over it (or letting it go) was
  /// asked once already, and the first row in view (wanted, and eased toward)
  gardens:std.ArrayList(save.Entry)=.empty,
  listedAt:f64=0,
  garden:usize=0,
  overwrite:bool=false,
  deleting:bool=false,
  /// the name prompt: the name typed so far, and the mode it returns to
  typed:save.Name=.{},
  namingFrom:Mode=.roam,
  gardenTop:f32=0,
  gardenAt:f32=0,
  /// the list's scroll groove is held (dragged)
  scrolling:bool=false,
  /// keeps running while paused, so the UI still breathes.
  uiTime:f64=0,
  /// the hotbar's items and the selected slot
  bar:[barSlots]?items.Item=@splat(null),
  hot:usize=0,
  held:?Held=null,
  /// the tile of the structure whose panel is open (mode `.structure`); a
  /// tile, not an id, since ids move when a structure is removed
  open:[2]i32=.{0,0},
  /// the cursor, in screen pixels (tooltips and what is carried follow it);
  /// looking out of the wolf's eyes, the middle of the screen
  mouse:[2]f32=.{0,0},
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
  /// again until the cursor leaves it) and the wait before the next
  removed:?[2]i32=null,
  removeCd:f32=0,
  debug:bool=false,
  hover:?[2]i32=null,
  /// progress of the current gather, and a short linger for one-off gestures
  gatherT:f32=0,
  linger:f32=0,
  plantCd:f32=0,
  fullWarned:bool=false,
  time:f64=0,
  acc:f64=0,
  simMs:f32=0,
  frameMs:f32=16,
  ticks:u64=0,
  inst:[renderer.plantMeshes]std.ArrayList(vertex.PlantInstance)=@splat(.empty),
  far:std.ArrayList(*ck.Chunk)=.empty,
  renderStats:renderer.Stats=.{},
  /// `--plant`/`--structure`: one thing alone, its state set by hand (see
  /// specimen.zig); nothing else falls, grows or is drawn
  specimen:?Specimen=null,
  pub fn init(gpa:Allocator,seed:u64)Error!Game{
    var g:Game=.{
      .gpa=gpa,
      .world=World.init(gpa,seed),
      .rng=Rng.init(seed^0xA11CE),
      .stars=.{.rng=Rng.init(seed^0x57A2)},
      .player=.{.pos=m.v3(0.5,0,0.5)},
      .parts=Parts.init(gpa),
      .ui=.{.gpa=gpa},
    };
    errdefer g.deinit();
    // start on dry land: spiral out from the origin until a fertile tile shows up.
    var r:i32=0;
    find:while(r<spawnSearch):(r+=spawnStep){
      var a:i32=-r;
      while(a<=r):(a+=spawnStep){
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
  pub fn deinit(g:*Game)void{
    g.gardens.deinit(g.gpa);
    for(&g.inst)|*l|l.deinit(g.gpa);
    g.far.deinit(g.gpa);
    g.parts.deinit();
    g.ui.deinit();
    g.stars.deinit(g.gpa);
    g.eco.deinit(g.gpa);
    g.fields.deinit(g.gpa);
    g.plants.deinit(g.gpa);
    g.structs.deinit(g.gpa);
    g.world.deinit();
  }
  pub fn focus(g:*const Game)ck.Coord{
    const t=m.tileAt(g.player.pos);
    return ck.Coord.ofTile(t[0],t[1]);
  }
  pub fn heightAt(g:*const Game,wx:i32,wy:i32)f32{
    if(g.world.chunkOfTile(wx,wy))|c|return c.height[ck.localIndex(wx,wy)];
    return gen.heightAt(g.world.seed,wx,wy);
  }
  /// march the ray through the cursor until it dips below the terraced ground.
  pub fn pick(g:*const Game,cursor:[2]f32,screen:[2]f32)?[2]i32{
    const ray=g.cam.ray(cursor[0],cursor[1],screen[0],screen[1]);
    var t:f32=0;
    const maxT=g.cam.dist*pickRangeMult;
    while(t<maxT):(t+=pickStep){
      const p=ray.o+ray.d*m.splat3(t);
      const tile=m.tileAt(p);
      if(p[1]<=g.heightAt(tile[0],tile[1]))return tile;
    }
    return null;
  }
  /// what structures' behaviour may touch, the wolf and the sky with the
  /// garden, and what befell it this tick (`ev`)
  pub fn structCtx(g:*Game,ev:lib.ecology.Events)st.Ctx{
    return.{.gpa=g.gpa,.w=&g.world,.plants=&g.plants,.g=&g.prog,.ss=&g.structs,.player=&g.player,.sky=&g.sky,.events=ev};
  }
  /// fixed-step simulation; never more than `MAX_CATCHUP` ticks per frame.
  pub fn simulate(g:*Game,frameDt:f64)Error!void{
    if(!g.mode.live())return;
    g.acc=@min(g.acc+frameDt,tickTime*maxCatchup);
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
    var mods=g.prog.mods();
    mods.night=1-g.sky.daylight();
    try st.fields(&g.structs,g.gpa,&g.fields);
    mods.fields=g.fields.items;
    const ev=try g.eco.tick(g.gpa,&g.plants,&g.world,mods,tickTime);
    try g.converge.tick(g.gpa,&g.world,&g.plants,&g.structs,&g.prog);
    g.prog.absorb(ev,tickTime);
    try st.Structures.tickWith(g.structCtx(ev),tickTime);
    if(g.specimen)|*sp|try sp.after(g,tickTime);
    g.ticks+=1;
  }
  pub const update=lib.play.frame.update;
  pub const arsthraxiaState=lib.play.belly.arsthraxiaState;
  pub const headless=lib.play.belly.headless;
  pub const holds=lib.play.belly.holds;
  pub const points=lib.play.belly.points;
  pub const uiT=lib.play.belly.uiT;
  pub const selected=lib.play.belly.selected;
  pub const carried=lib.play.belly.carried;
  pub const itemOf=lib.play.belly.itemOf;
  pub const opened=lib.play.belly.opened;
  pub const storeSlot=lib.play.belly.storeSlot;
  pub const clickSlot=lib.play.belly.clickSlot;
  pub const clickStore=lib.play.belly.clickStore;
  pub const clickBar=lib.play.belly.clickBar;
  pub const drop=lib.play.belly.drop;
  pub const discard=lib.play.belly.discard;
  pub const moveAcross=lib.play.belly.moveAcross;
  pub const putDown=lib.play.belly.putDown;
  pub const menu=lib.play.menus.menu;
  pub const choose=lib.play.menus.choose;
  pub const openGardens=lib.play.menus.openGardens;
  pub const listed=lib.play.menus.listed;
  pub const gardenScroll=lib.play.menus.gardenScroll;
  pub const scroll=lib.play.menus.scroll;
  pub const gardenAct=lib.play.menus.gardenAct;
  pub const startNaming=lib.play.menus.startNaming;
  pub const typeName=lib.play.menus.typeName;
  pub const nameTaken=lib.play.menus.nameTaken;
  pub const nameChosen=lib.play.menus.nameChosen;
  pub const inspect=lib.play.menus.inspect;
  pub const fly=lib.play.menus.fly;
};
