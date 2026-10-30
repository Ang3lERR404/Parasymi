//! every player-facing string, loaded once at startup from `PATH`
//! (`parasymi.cfg`) and never read again. Templates take positional
//! arguments (`{0}`, `{1:.1}`; see `core/text.zig`); lists are `a | b`.
const lib=@import("../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const Io=std.Io;
const EnumArray=std.enums.EnumArray;
const log=std.log;
const ArenaAllocator=std.heap.ArenaAllocator;
const stringToEnum=std.meta.stringToEnum;
const toUpper=std.ascii.toUpper;
const assert=std.debug.assert;
const testing=std.testing;
const indexOf=std.mem.indexOf;
const fields=std.meta.fields;
const engine=lib.engine;
const input=engine.platform.input;
const ctl=lib.controls;
const ctext=engine.core.text;
const ck=lib.ck;
const items=lib.items;
const species=lib.species;
const prog=lib.progression;
const st=lib.structures;
const home=lib.home;
pub const filePath="parasymi.cfg";
/// the strings as built: what an edited file leaves out falls back to these
const default=@embedFile("parasymi.cfg");
/// the cfg is a few kilobytes; anything near this is not one.
const maxCfg:usize=1<<20;
pub const nth=ctext.nth;
pub const count=ctext.count;
pub const bufRender=ctext.bufRender;
const S=[]const u8;
pub const Named=struct{name:S=""};
pub const ItemText=struct{name:S="",short:S=""};
/// `stages`: a list, one name per growth stage (staged species only).
pub const PlantText=struct{name:S="",stages:?S=null};
pub const ResearchText=struct{name:S="",desc:S=""};
pub const Strings=struct{
  window:struct{title:S=""}=.{},
  /// the loading screen: `stages` a list, one name per stage
  loading:struct{stages:S="",percent:S="",left:S=""}=.{},
  /// said into the message log
  msg:struct{
    wake:S="",nightHint:S="",
    bellyFull:S="",noItem:S="",notUnderstood:S="",cannotWeave:S="",wove:S="",discarded:S="",
    wantsNothing:S="",spilled:S="",stillGrowing:S="",notRipe:S="",givesUp:S="",
    lineagesStrain:S="",confluenceRoots:S="",
    researching:S="",alreadyKnown:S="",locked:S="",researched:S="",
    entwine:S="",hybridStirs:S="",withered:S="",
    essenceConverges:S="",veilThins:S="",arsthraxiaGrows:S="",
    germinatorWeaves:S="",haloForms:S="",diamondForms:S="",latticeStirs:S="",
    loomMeetsStone:S="",braidMeetsSpore:S="",crownMeetsNerve:S="",weftMeetsDrift:S="",researchNamed:S="",
    tetherChoose:S="",tethered:S="",tetherFull:S="",tetherCut:S="",monfrisWeaves:S="",
    braidChoose:S="",braidPaired:S="",braidStill:S="",
    sporesChoose:S="",sporesPaired:S="",sporesStill:S="",
    saved:S="",autosaved:S="",saveFailed:S="",remembers:S="",noSave:S="",noGardens:S="",
    noFullscreen:S="",optionsUnsaved:S="",deleted:S="",deleteFailed:S="",
  }=.{},
  hud:struct{
    controls:S="",ingredient:S="",unknown:S="",stock:S="",
    bellyTitle:S="",bellyFill:S="",bellyHint:S="",weave:S="",weaveHint:S="",queued:S="",
    recipe:S="",recipeMany:S="",recipeNeeds:S="",
    researchTitle:S="",researchHint:S="",researchCost:S="",
    researchDormant:S="",researchUnwitnessed:S="",
    hotbarKeys:S="",facing:S="",facingLabel:S="",notUnderstood:S="",
    tooFar:S="",empty:S="",openHint:S="",holds:S="",storeHint:S="",weaveChoose:S="",node:S="",tile:S="",stage:S="",growth:S="",
    bloom:S="",radiating:S="",dark:S="",noMature:S="",
    plant:S="",unknownYield:S="",drawingRadiance:S="",withering:S="",
    sap:S="",paused:S="",pauseKeys:S="",pauseLabels:S="",
    optionsTitle:S="",optionsHint:S="",optionLabels:S="",
    antialias:S="",toggle:S="",autosave:S="",optionsBack:S="",
    gardensTitle:S="",gardensFresh:S="",gardensAuto:S="",gardensPlaying:S="",gardensAge:S="",
    gardensSave:S="",gardensOverwrite:S="",gardensLoad:S="",gardensHint:S="",
    gardensDelete:S="",gardensDeleteSure:S="",
    namingTitle:S="",namingOk:S="",namingCancel:S="",namingHint:S="",
    freeCam:S="",freeCamHint:S="",
    fps:S="",gpu:S="",sim:S="",counts:S="",draws:S="",pos:S="",motes:S="",
  }=.{},
  /// one-line hover descriptions of structures
  describe:struct{
    carries:S="",nothing:S="",weaves:S="",chooseStudy:S="",studies:S="",
    noNode:S="",diggerFull:S="",digs:S="",cache:S="",
    loom:S="",loomFed:S="",loomFull:S="",
    lithDraws:S="",lithSaps:S="",lithStarved:S="",
    lanes:S="",laneEmpty:S="",
    shares:S="",gathers:S="",crownFull:S="",
    sends:S="",unpaired:S="",
    trades:S="",untraded:S="",loomWeaves:S="",loomWaits:S="",vultPulls:S="",vultIdle:S="",vultLoose:S="",weftDraws:S="",weftIonizes:S="",weftStarved:S="",
    haloOpen:S="",haloForming:S="",haloFormed:S="",diamond:S="",
  }=.{},
  sky:struct{dawn:S="",dusk:S="",day:S="",night:S=""}=.{},
  tile:EnumArray(ck.Kind,Named)=.initFill(.{}),
  item:EnumArray(items.Item,ItemText)=.initFill(.{}),
  plant:EnumArray(species.Id,PlantText)=.initFill(.{}),
  research:EnumArray(prog.Id,ResearchText)=.initFill(.{}),
  structure:EnumArray(st.Kind,Named)=.initFill(.{}),
  /// shown names of keys and mouse buttons (for `{@action}`); optional
  key:EnumArray(input.Key,?S)=.initFill(null),
  mouse:EnumArray(input.Button,?S)=.initFill(null),
};
/// the loaded strings; empty until `load` (headless tests run without them).
// decision: one process-wide table, set once at startup and read-only
// after, instead of threading a pointer through every HUD and message site.
pub var s:Strings=.{};
var src:[]u8=&.{};
/// holds the strings `{@action}` tokens were written into
var arena:?ArenaAllocator=null;
pub const Error=error{NoStrings,BadStrings}||Allocator.Error;
/// reads and parses `PATH` (in `home`, made from the game's own when
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
pub fn unload(gpa:Allocator)void{
  if(src.len>0)gpa.free(src);
  src=&.{};
  if(arena)|*a|a.deinit();
  arena=null;
  s=.{};
}
/// `{@name}`: the first key or button bound to action `name`.
fn action(w:*Io.Writer,name:[]const u8)Io.Writer.Error!bool{
  const a=stringToEnum(ctl.Action,name) orelse return false;
  const binds=ctl.map.getPtrConst(a).items();
  if(binds.len>0)try bindName(w,binds[0]);
  return true;
}
/// how a key or button is shown: its `[key]`/`[mouse]` name in the cfg,
/// else its binding name in capitals.
// decision: only keys whose binding name reads badly (left_shift, one,
// mouse_left) get a cfg name; F5, TAB, W show as they are bound.
pub fn bindName(w:*Io.Writer,b:input.Bind)Io.Writer.Error!void{
  const named,const tag=switch(b){
    .key=>|k|.{s.key.get(k),@tagName(k)},
    .button=>|k|.{s.mouse.get(k),@tagName(k)},
  };
  if(named)|n|return w.writeAll(n);
  for(tag)|c|try w.writeByte(toUpper(c));
}
pub fn item(i:items.Item)ItemText{return s.item.get(i);}
pub fn plant(id:species.Id)PlantText{return s.plant.get(id);}
pub fn research(id:prog.Id)ResearchText{return s.research.get(id);}
pub fn structure(k:st.Kind)[]const u8{return s.structure.get(k).name;}
pub fn tile(k:ck.Kind)[]const u8{return s.tile.get(k).name;}
test"the strings file fills every key, shown with the bound keys"{
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
  try testing.expectEqual(fields(lib.play.PauseRow).len,count(s.hud.pauseLabels));
  const opt=lib.options;
  try testing.expectEqual(fields(opt.Setting).len,count(s.hud.optionLabels));
  try testing.expectEqual(fields(@FieldType(opt.Options,"aa")).len,count(s.hud.antialias));
  try testing.expectEqual(2,count(s.hud.toggle));
  try testing.expectEqual(opt.autosaveMinutes.len,count(s.hud.autosave));
  try testing.expectEqual(4,count(s.hud.gardensAge));
  try testing.expectEqual(4,count(s.hud.facing));
}
