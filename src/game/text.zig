//! every player-facing string, loaded once at startup from `filePath`
//! (`parasymi.cfg`) and never read again. Templates take positional
//! arguments (`{0}`, `{1:.1}`; see `core/text.zig`); lists are `a | b`.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the cfg text and the expanded strings come from
const Allocator=std.mem.Allocator;
/// the I/O interface, for reading the cfg from home
const Io=std.Io;
/// a table with one slot per enum tag: tiles, items, species, studies
const EnumArray=std.enums.EnumArray;
/// the log, for a cfg that will not parse
const log=std.log;
/// the arena the `{@action}` strings are written into
const ArenaAllocator=std.heap.ArenaAllocator;
/// reads an action from a `{@name}` token
const stringToEnum=std.meta.stringToEnum;
/// capitalises a binding's name
const toUpper=std.ascii.toUpper;
/// a check that holds at run time
const assert=std.debug.assert;
/// the test harness
const testing=std.testing;
/// every tag of an enum, for the test that every action is named
const values=std.enums.values;
/// finds a token in a string (tests)
const indexOf=std.mem.indexOf;
/// a type's fields, for counting list entries against enums
const fields=std.meta.fields;
/// the engine package
const engine=lib.engine;
/// the platform's keys and mouse buttons
const input=engine.platform.input;
/// the controls, whose bindings `{@action}` is written as
const ctl=lib.controls;
/// the runtime cfg reader, templates and list helpers
const ctext=engine.core.text;
/// the chunk grid, for the tile kinds' names
const ck=lib.ck;
/// what can be held, for the items' names
const items=lib.items;
/// the species registry, for the plants' names
const species=lib.species;
/// the research tree, for the studies' names
const prog=lib.progression;
/// the structures registry, for the structures' names
const st=lib.structures;
/// the gardener's folder, where the editable cfg lives
const home=lib.home;
/// the strings' file name, inside home
pub const filePath="parasymi.cfg";
/// the strings as built: what an edited file leaves out falls back to these
const default=@embedFile("parasymi.cfg");
/// the cfg is a few kilobytes; anything near this is not one.
const maxCfg:usize=1<<20;
/// the `n`th entry of an `a | b` list
pub const nth=ctext.nth;
/// how many entries an `a | b` list has
pub const count=ctext.count;
/// renders a template into a fixed buffer, cut short if it does not fit
pub const bufRender=ctext.bufRender;
/// a string, as the cfg gives it
const S=[]const u8;
/// a thing known by its name alone (a tile kind, a structure)
pub const Named=struct{
  /// the shown name
  name:S=""
};
/// an item's names: in full, and short enough to sit on its icon
pub const ItemText=struct{
  /// the item's full name
  name:S="",
  /// its short name, drawn on its icon
  short:S=""
};
/// a plant's names: its own, and one per growth stage if it is staged
pub const PlantText=struct{
  /// the plant's name
  name:S="",
  /// a list, one name per growth stage (staged species only)
  stages:?S=null
};
/// a study's name and description
pub const ResearchText=struct{
  /// the study's name
  name:S="",
  /// what it teaches, shown on its leaf
  desc:S=""
};
/// every player-facing string, in sections matching the cfg's `[section]`s
/// (field names are the cfg's keys)
pub const Strings=struct{
  /// the window
  window:struct{
    /// the window's title, the game's own name (also over the loading screen)
    title:S=""
  }=.{},
  /// the loading screen
  loading:struct{
    /// a list, one name per loading stage, in `loading.Stage` order
    stages:S="",
    /// how much is made, as a percentage (`{0}`)
    percent:S="",
    /// how many things are made (`{0}`) and how many are left (`{1}`)
    left:S=""
  }=.{},
  /// said into the message log
  msg:struct{
    /// said on waking in a fresh garden: gather what the ground offers
    wake:S="",
    /// the first night's hint: catch starlight, weave seeds in the belly
    nightHint:S="",
    /// the belly can hold no more
    bellyFull:S="",
    /// a tendril drawn to nothing
    tendrilNowhere:S="",
    /// a tendril the gardener has too few fragments to braid: how many it takes
    tendrilFragments:S="",
    /// none of the item (`{0}`) is left to put down
    noItem:S="",
    /// the item (`{0}`) needs a study not yet known
    notUnderstood:S="",
    /// the belly lacks what the weave (`{0}`) eats
    cannotWeave:S="",
    /// a weave (`{0}`) has finished
    wove:S="",
    /// a stack thrown away: how many (`{0}`) of what (`{1}`)
    discarded:S="",
    /// a structure would take nothing the wolf carries
    wantsNothing:S="",
    /// how many things (`{0}`) found no room when a structure was taken up
    spilled:S="",
    /// a plant (`{0}`) cannot be harvested yet; how grown it is (`{1}`%)
    stillGrowing:S="",
    /// a grown plant has nothing ripe to give yet
    notRipe:S="",
    /// what an unstudied plant gave: how many (`{0}`) of what (`{1}`)
    givesUp:S="",
    /// the lineages met but there is no 2x2 ground for a confluence
    lineagesStrain:S="",
    /// a confluence has taken root where the lineages met
    confluenceRoots:S="",
    /// a study (`{0}`) is now the labs' choice
    researching:S="",
    /// the study chosen (`{0}`) is already known
    alreadyKnown:S="",
    /// the study chosen (`{0}`) is still locked
    locked:S="",
    /// a study (`{0}`) is learned
    researched:S="",
    /// the discovery that symbiote and parasite entwine
    entwine:S="",
    /// after that discovery: seed splicing may be studied
    hybridStirs:S="",
    /// how many plants (`{0}`) withered since the last report
    withered:S="",
    /// convergence theory learned: essence converges where the lineages meet
    essenceConverges:S="",
    /// the thinning veil learned: the world event begins
    veilThins:S="",
    /// a minor study along arsthraxia learned: the labs put out an offshoot
    arsthraxiaGrows:S="",
    /// a germinator is set to a new weave (`{0}`)
    germinatorWeaves:S="",
    /// four blooms close a polyp's ring and it draws them in
    haloForms:S="",
    /// the blooms become one: a diamond floats over the polyp
    diamondForms:S="",
    /// after the diamond: celestial defragmentation may be studied
    latticeStirs:S="",
    /// the discovery of a loomfern grown beside a lithophage
    loomMeetsStone:S="",
    /// the discovery of a braided conduit grown beside a sporecaster
    braidMeetsSpore:S="",
    /// the discovery of a gathering crown grown beside a ganglion
    crownMeetsNerve:S="",
    /// the discovery of a weftstone grown beside a driftbraid
    weftMeetsDrift:S="",
    /// after a pairing's discovery: the study (`{0}`) it opens
    researchNamed:S="",
    /// the discovery of a polyp's first flower let drift
    flowerDrifts:S="",
    /// the first rain falls on the garden
    firstRain:S="",
    /// the first storm struck
    firstStorm:S="",
    /// a night beam first overdriving a plant
    overdrive:S="",
    /// the first starglass steeped in a driftwisp
    starglass:S="",
    /// the first evening silk steeped in a vesper
    eveningSilk:S="",
    /// the unforming learned, just before it begins
    unformingNear:S="",
    /// the unforming begun: the radiant plants shatter, the lineages die
    unformingBegins:S="",
    /// the seed of the shattered light fallen to the ground
    seedFalls:S="",
    /// a vultrixi is being configured: choose the monfris it feeds
    tetherChoose:S="",
    /// a vultrixi is tethered to the monfris chosen
    tethered:S="",
    /// the monfris chosen already holds all its tethers
    tetherFull:S="",
    /// a vultrixi's tether is cut: it feeds nothing
    tetherCut:S="",
    /// a monfris is set to a new weave (`{0}`)
    monfrisWeaves:S="",
    /// a driftbraid is being configured: choose the one it trades with
    braidChoose:S="",
    /// two driftbraids are paired and send to each other
    braidPaired:S="",
    /// a driftbraid's pairing is undone
    braidStill:S="",
    /// a sporecaster is being configured: choose the one it sends to
    sporesChoose:S="",
    /// a sporecaster is paired: its spores will drift there
    sporesPaired:S="",
    /// a sporecaster's pairing is undone
    sporesStill:S="",
    /// the garden is saved under a name (`{0}`)
    saved:S="",
    /// the timer has saved the garden
    autosaved:S="",
    /// saving failed, and why (`{0}`)
    saveFailed:S="",
    /// a saved garden has been loaded
    remembers:S="",
    /// there is no garden to load, and why (`{0}`)
    noSave:S="",
    /// the saves folder cannot be read, and why (`{0}`)
    noGardens:S="",
    /// fullscreen could not be entered, and why (`{0}`)
    noFullscreen:S="",
    /// the options file could not be written, and why (`{0}`)
    optionsUnsaved:S="",
    /// the controls file could not be written, and why (`{0}`)
    controlsUnsaved:S="",
    /// a saved garden (`{0}`) is deleted
    deleted:S="",
    /// a saved garden could not be deleted, and why (`{0}`)
    deleteFailed:S="",
  }=.{},
  /// the HUD's panels, hints, hovers and debug lines
  hud:struct{
    /// the controls line along the bottom, every `{@action}` as bound
    controls:S="",
    /// one ingredient in a recipe: how many (`{0}`) and its short name (`{1}`)
    ingredient:S="",
    /// what stands for something not yet understood
    unknown:S="",
    /// a slot's stock: how many (`{0}`) of how many (`{1}`), and a mark (`{2}`)
    stock:S="",
    /// the belly panel's title
    bellyTitle:S="",
    /// how full the belly is (`{0}`%)
    bellyFill:S="",
    /// how the belly's slots are worked
    bellyHint:S="",
    /// the heading over the hand-weaving recipes
    weave:S="",
    /// how a recipe is woven
    weaveHint:S="",
    /// how many weaves (`{0}`) are queued
    queued:S="",
    /// a recipe making one thing (`{0}`)
    recipe:S="",
    /// a recipe making several: what (`{0}`) and how many (`{1}`)
    recipeMany:S="",
    /// a recipe not yet understood, and the study it needs (`{0}`)
    recipeNeeds:S="",
    /// the research panel's title
    researchTitle:S="",
    /// how a study is chosen, and what the labs do with it
    researchHint:S="",
    /// a study's cost: units (`{0}`) and seconds each (`{1}`)
    researchCost:S="",
    /// a locked study, and what it needs first (`{0}`)
    researchDormant:S="",
    /// a study waiting on something not yet seen in the garden
    researchUnwitnessed:S="",
    /// a list, the key shown over each hotbar slot
    hotbarKeys:S="",
    /// a list, the four ways a thing faces: east, south, west, north
    facing:S="",
    /// what is put down next (`{0}`) and the way it faces (`{1}`)
    facingLabel:S="",
    /// a hovered thing not yet understood
    notUnderstood:S="",
    /// the hovered tile is out of reach
    tooFar:S="",
    /// the moisture in the air over the hovered tile: its mist, its cloud
    air:S="",
    /// a store holding nothing
    empty:S="",
    /// how a store's panel is opened
    openHint:S="",
    /// the heading over what a store holds
    holds:S="",
    /// how a store's slots are worked
    storeHint:S="",
    /// the heading over a germinator's or monfris' choice of weave
    weaveChoose:S="",
    /// a resource node hovered: what it gives (`{0}`) and how much is left (`{1}`)
    node:S="",
    /// a bare tile hovered: its ground (`{0}`) and its ley (`{1}`)
    tile:S="",
    /// a staged plant: its name, stage of how many, and how grown
    stage:S="",
    /// how grown the hovered thing is (`{0}`%)
    growth:S="",
    /// a relay of the light grid hovered: the light it carries, how many
    /// it links to, its health
    relay:S="",
    /// no light reaches the hovered relay
    dark:S="",
    /// an astrocyme hovered: the light it holds, of how much
    stored:S="",
    /// a solcyriphon hovered: the light it spreads by day, its beam by night
    makes:S="",
    /// the hovered plant is under a night beam
    overdriven:S="",
    /// the hovered plant is under a night beam, guarded
    guarded:S="",
    /// a plant hovered: its name, its yield and its health
    plant:S="",
    /// what stands for a yield not yet studied
    unknownYield:S="",
    /// a plant that draws light, and its share of it (`{0}`%)
    drawingRadiance:S="",
    /// a plant that draws light, short of it, withering
    withering:S="",
    /// a plant that needs soaked ground, on it and drinking
    soaked:S="",
    /// a plant that needs soaked ground, on dry ground, withering
    drying:S="",
    /// the label by the sap tendril
    sap:S="",
    /// the pause menu's title
    paused:S="",
    /// a list, the key shown by each pause row
    pauseKeys:S="",
    /// a list, the pause rows (`play.PauseRow` order)
    pauseLabels:S="",
    /// a list, the main menu's rows (`play.TitleRow` order)
    titleLabels:S="",
    /// under the main menu's continue: the garden it wakes into ({0} its name)
    titleContinue:S="",
    /// the options panel's title
    optionsTitle:S="",
    /// how an option is turned
    optionsHint:S="",
    /// a list, the options panel's rows (`options.Setting` order)
    optionLabels:S="",
    /// a list, every anti-aliasing mode's shown name
    antialias:S="",
    /// a list, a switch's two shown states: off, on
    toggle:S="",
    /// a list, every autosave interval (`options.autosaveMinutes` order)
    autosave:S="",
    /// the options panel's way back
    optionsBack:S="",
    /// the keybinds panel's title
    keybindsTitle:S="",
    /// how the keybinds panel is worked
    keybindsHint:S="",
    /// a row waiting for the key to bind it to
    keybindsListen:S="",
    /// an action bound to nothing
    keybindsNone:S="",
    /// the button that binds every action as the game ships it
    keybindsReset:S="",
    /// marks an action bound otherwise than the game ships it
    keybindsChanged:S="",
    /// the saved gardens panel's title
    gardensTitle:S="",
    /// the row that starts a fresh garden
    gardensFresh:S="",
    /// the autosave's name, as listed
    gardensAuto:S="",
    /// marks the garden being played
    gardensPlaying:S="",
    /// a list, how long ago a garden was saved: now, minutes, hours, days
    gardensAge:S="",
    /// the button that saves the garden
    gardensSave:S="",
    /// asks before saving over a garden
    gardensOverwrite:S="",
    /// the button that loads a garden
    gardensLoad:S="",
    /// how the saved gardens panel is worked
    gardensHint:S="",
    /// the button that deletes a garden
    gardensDelete:S="",
    /// asks before deleting a garden
    gardensDeleteSure:S="",
    /// the naming panel's title
    namingTitle:S="",
    /// the naming panel's accept button
    namingOk:S="",
    /// the naming panel's cancel button
    namingCancel:S="",
    /// how a name is typed
    namingHint:S="",
    /// shown while the free camera is on, and how to leave it
    freeCam:S="",
    /// how the free camera flies
    freeCamHint:S="",
    /// debug: frames a second (`{0}`) and frame time (`{1}` ms)
    fps:S="",
    /// debug: the GPU's frame time (`{0}` ms)
    gpu:S="",
    /// debug: the simulation's time (`{0}` ms) and its tick (`{1}`)
    sim:S="",
    /// debug: chunks, plants and built meshes
    counts:S="",
    /// debug: instances, parts and draw calls
    draws:S="",
    /// debug: the wolf's tile and the time of day
    pos:S="",
    /// debug: starlight motes and meshed chunks
    motes:S="",
  }=.{},
  /// one-line hover descriptions of structures
  describe:struct{
    /// a conduit carrying something (`{0}`)
    carries:S="",
    /// what stands for nothing carried or held
    nothing:S="",
    /// a germinator weaving something (`{0}`)
    weaves:S="",
    /// an arsthraxia with no study chosen
    chooseStudy:S="",
    /// an arsthraxia studying (`{0}`) and how fast (`{1}`%/min)
    studies:S="",
    /// a root-digger with no node beside it, and what it holds
    noNode:S="",
    /// a root-digger full: lead a conduit away
    diggerFull:S="",
    /// a root-digger digging (`{0}`), and what it holds
    digs:S="",
    /// a sap cache: holds anything, fed and taken from by hand
    cache:S="",
    /// a tanglehold: how many of its slots are taken, of how many
    hold:S="",
    /// a storm spire: how charged (%), and what it is doing
    storm:S="",
    /// a storm spire charging under the rain
    charging:S="",
    /// a storm spire waiting for rain
    waitingRain:S="",
    /// a storm spire with no ley crystal to spend
    noCrystal:S="",
    /// a storm spire's storm raging
    storming:S="",
    /// a loomfern weaving fibre by itself, and what it holds
    loom:S="",
    /// a loomfern weaving fibre from essence, and what it holds
    loomFed:S="",
    /// a loomfern full: lead a conduit away
    loomFull:S="",
    /// a lithophage drawing stone up its tendrils: how many, how far it
    /// reaches, its crystal and its grit
    lithDraws:S="",
    /// a lithophage sapping its crystal into grit
    lithSaps:S="",
    /// a lithophage with no stone in its reach to draw
    lithStarved:S="",
    /// a braided conduit's four lanes, each what it carries
    lanes:S="",
    /// an empty lane
    laneEmpty:S="",
    /// a ganglion sharing out to how many round it, and what it holds
    shares:S="",
    /// a gathering crown gathering from how many plants, and what it holds
    gathers:S="",
    /// a gathering crown full: lead a conduit away
    crownFull:S="",
    /// a sporecaster sending to a tile, its spores adrift, what it holds
    sends:S="",
    /// a sporecaster sending nowhere: how to pair it
    unpaired:S="",
    /// a driftbraid trading with a tile: spores adrift, fed, received
    trades:S="",
    /// a driftbraid trading with none: how to pair it
    untraded:S="",
    /// a monfris weaving (`{0}`), and how many vultrixi feed it
    loomWeaves:S="",
    /// a monfris waiting on what its weave needs
    loomWaits:S="",
    /// a vultrixi pulling something (`{0}`) for its monfris
    vultPulls:S="",
    /// a vultrixi whose monfris needs nothing from it now
    vultIdle:S="",
    /// a vultrixi tethered to none: how to tether it
    vultLoose:S="",
    /// an untethered Vultrixi relaying an item along its kin
    vultRelays:S="",
    /// a nebularbor drinking and breathing: water drunk, into the mist and into its cloud, a minute
    breathes:S="",
    /// a root well: how full it is (%), and what it is doing
    rootWell:S="",
    /// a root well pouring what it holds round its foot
    pouring:S="",
    /// a root well holding what it caught (the ground round it soaked)
    holding:S="",
    /// a strange seed planted: how many fragments drift round it, how many are still to come
    seedFragments:S="",
    /// a strange seed lying where it fell, never planted
    seedLies:S="",
    /// a yielder still being built: how many petals are snapped on, of the four
    yielderPetals:S="",
    /// a whole yielder at work: how many fragments it holds
    yielderWhole:S="",
    /// a constellate petal put down with no core near enough
    petalWaiting:S="",
    /// a constellate petal drifting over to the core it merges with
    petalDrifting:S="",
    /// a constellate part put down that nothing has taken in yet
    partFloats:S="",
    /// a heart bloomed, waiting for petals on its first bloom: how many are on
    heartPetals:S="",
    /// a heart still playing its story toward settling
    heartForming:S="",
    /// a heart settled into a builder: the fragments it holds, the part it makes next
    heartBuilds:S="",
    /// a heart with a part whole on top of its rose: which
    heartReady:S="",
    /// a weftstone drawing nodes up, its grit, ley and crystals
    weftDraws:S="",
    /// a weftstone ionizing a ley crystal
    weftIonizes:S="",
    /// a weftstone with no stone within reach to draw
    weftStarved:S="",
    /// a polyp with no grown bloom near enough to feed on, and how near
    polypHungry:S="",
    /// a polyp feeding: its flowers adrift and the most it lets drift
    polypFeeds:S="",
    /// a diamond projecting its halo, and how many points are lit
    diamond:S="",
  }=.{},
  /// the time of day's names
  sky:struct{
    /// dawn, near the horizon in the morning
    dawn:S="",
    /// dusk, near the horizon in the evening
    dusk:S="",
    /// the sun up
    day:S="",
    /// the sun down
    night:S=""
  }=.{},
  /// each tile kind's name
  tile:EnumArray(ck.Kind,Named)=.initFill(.{}),
  /// each item's names
  item:EnumArray(items.Item,ItemText)=.initFill(.{}),
  /// each plant's names
  plant:EnumArray(species.Id,PlantText)=.initFill(.{}),
  /// each study's name and description
  research:EnumArray(prog.Id,ResearchText)=.initFill(.{}),
  /// each structure's name
  structure:EnumArray(st.Kind,Named)=.initFill(.{}),
  /// each action's name, as the keybinds panel lists it
  action:EnumArray(ctl.Action,S)=.initFill(""),
  /// shown names of keys (for `{@action}`); optional
  key:EnumArray(input.Key,?S)=.initFill(null),
  /// shown names of mouse buttons (for `{@action}`); optional
  mouse:EnumArray(input.Button,?S)=.initFill(null),
  /// shown names of gamepad buttons (for `{@action}`); optional
  pad:EnumArray(input.PadButton,?S)=.initFill(null),
  /// shown names of gamepad triggers (for `{@action}`); optional
  trigger:EnumArray(input.Trigger,?S)=.initFill(null),
};
/// the loaded strings; empty until `load` (headless tests run without them).
// decision: one process-wide table, set once at startup and read-only
// after, instead of threading a pointer through every HUD and message site.
pub var s:Strings=.{};
/// the cfg's text, owned while the strings point into it
var src:[]u8=&.{};
/// holds the strings `{@action}` tokens were written into
var arena:?ArenaAllocator=null;
/// the strings file cannot be read, or will not parse
pub const Error=error{NoStrings,BadStrings}||Allocator.Error;
/// reads and parses `filePath` (in `home`, made from the game's own when
/// missing) over the game's own strings. Called once, at startup, before
/// anything is shown.
pub fn load(gpa:Allocator,io:Io)Error!void{
  assert(src.len==0);
  src=try home.stock(gpa,io,filePath,default);
  errdefer unload(gpa);
  fill(gpa,&.{default,src})catch|e|switch(e){
    error.OutOfMemory=>return error.OutOfMemory,
    else=>{
      // the gardener's file is broken: the game's own still read
      log.warn("{s}: ignoring the edited strings",.{filePath});
      unload(gpa);
      try fill(gpa,&.{default});
    },
  };
}
/// parses each cfg source of `texts` (which must outlive the strings) into
/// `s` in turn, later ones over earlier; then writes each `{@action}` as
/// the key or button bound to it, so what is shown follows `controls.cfg`
/// (loaded first).
pub fn fill(gpa:Allocator,texts:[]const[]const u8)Error!void{
  // room for the parser's complaint, and the writer that fills it
  var badBuf:[256]u8=undefined;
  var bad:Io.Writer=.fixed(&badBuf);
  for(texts)|text|ctext.parse(Strings,&s,text,&bad)catch|e|{
    log.err("{s}: {t}: {s}",.{filePath,e,bad.buffered()});
    return error.BadStrings;
  };
  assert(arena==null);
  arena=.init(gpa);
  ctext.expand(Strings,&s,arena.?.allocator(),action,&bad)catch|e|return switch(e){
    error.OutOfMemory=>error.OutOfMemory,
    else=>{log.err("{s}: {t}: {s}",.{filePath,e,bad.buffered()});return error.BadStrings;},
  };
}
/// forgets every string and frees what held them
pub fn unload(gpa:Allocator)void{
  if(src.len>0)gpa.free(src);
  src=&.{};
  if(arena)|*a|a.deinit();
  arena=null;
  s=.{};
}
/// `{@name}`: the first key or button bound to action `name`.
fn action(w:*Io.Writer,name:[]const u8)Io.Writer.Error!bool{
  // the action named; none, and the token is not one
  const a=stringToEnum(ctl.Action,name) orelse return false;
  // the keys and buttons bound to it
  const binds=ctl.map.getPtrConst(a).items();
  if(binds.len>0)try bindName(w,binds[0]);
  return true;
}
/// how a key or button is shown: its `[key]`/`[mouse]` name in the cfg,
/// else its binding name in capitals.
// decision: only keys whose binding name reads badly (left_shift, one,
// mouse_left) get a cfg name; F5, TAB, W show as they are bound.
pub fn bindName(w:*Io.Writer,b:input.Bind)Io.Writer.Error!void{
  // the binding's cfg name (if any) and its tag name
  const named,const tag=switch(b){
    .key=>|k|.{s.key.get(k),@tagName(k)},
    .button=>|k|.{s.mouse.get(k),@tagName(k)},
    .pad=>|k|.{s.pad.get(k),@tagName(k)},
    .trigger=>|k|.{s.trigger.get(k),@tagName(k)},
  };
  if(named)|n|return w.writeAll(n);
  for(tag)|c|try w.writeByte(toUpper(c));
}
/// an item's names
pub fn item(i:items.Item)ItemText{return s.item.get(i);}
/// a plant's names
pub fn plant(id:species.Id)PlantText{return s.plant.get(id);}
/// a study's name and description
pub fn research(id:prog.Id)ResearchText{return s.research.get(id);}
/// a structure's name
pub fn structure(k:st.Kind)[]const u8{return s.structure.get(k).name;}
/// a tile kind's name
pub fn tile(k:ck.Kind)[]const u8{return s.tile.get(k).name;}
test"the strings file fills every key, shown with the bound keys"{
  // the test allocator
  const gpa=testing.allocator;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  defer unload(gpa);
  try fill(gpa,&.{default});
  try testing.expect(indexOf(u8,s.hud.controls,ctext.token)==null);
  // rebinding changes what is shown
  unload(gpa);
  try ctl.fill(&.{@embedFile("controls.cfg")++"\n[bind]\nbelly = mouse_middle | b\n"});
  try fill(gpa,&.{default});
  try testing.expect(indexOf(u8,s.msg.nightHint,s.mouse.get(.middle).?)!=null);
  try testing.expectEqual(count(s.hud.pauseKeys),count(s.hud.pauseLabels));
  for(values(ctl.Action))|a|try testing.expect(s.action.get(a).len>0);
  try testing.expectEqual(fields(lib.play.PauseRow).len,count(s.hud.pauseLabels));
  try testing.expectEqual(fields(lib.play.TitleRow).len,count(s.hud.titleLabels));
  // the options module, whose lists the strings must match
  const opt=lib.options;
  try testing.expectEqual(fields(opt.Setting).len,count(s.hud.optionLabels));
  try testing.expectEqual(fields(@FieldType(opt.Options,"aa")).len,count(s.hud.antialias));
  try testing.expectEqual(2,count(s.hud.toggle));
  try testing.expectEqual(opt.autosaveMinutes.len,count(s.hud.autosave));
  try testing.expectEqual(4,count(s.hud.gardensAge));
  try testing.expectEqual(4,count(s.hud.facing));
}
