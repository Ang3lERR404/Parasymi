//! what every key and mouse button does, loaded once at startup from
//! `filePath` (`controls.cfg`) and never read again; the KEYBINDS menu
//! rebinds an action (`rebind`, `reset`) and writes what differs from the
//! game's own back to the file (`write`). Game code asks about an
//! `Action`, never a key: `ctl.pressed(in, .harvest)`.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the cfg text is read with
const Allocator=std.mem.Allocator;
/// the I/O interface, for reading the cfg from home
const Io=std.Io;
/// a table with one slot per action
const EnumArray=std.enums.EnumArray;
/// the log, for a cfg that will not parse
const log=std.log;
/// strips spaces round a key's name
const trim=std.mem.trim;
/// splits one action's list of key names
const splitScalar=std.mem.splitScalar;
/// every tag of an enum, for the test that walks all actions
const values=std.enums.values;
/// the test harness
const testing=std.testing;
/// deep equality, for whether two bindings are the same key
const eqlDeep=std.meta.eql;
/// a text writer, for writing the bindings out
const Writer=Io.Writer;
/// the runtime cfg reader and its list separator
const ctext=lib.engine.core.text;
/// the platform's keyboard and mouse state
const input=lib.engine.platform.input;
/// this frame's keys and buttons, held and pressed
const Input=input.Input;
/// one key or mouse button, parsed from its name
const Bind=input.Bind;
/// the gardener's folder, where the editable cfg lives
const home=lib.home;
/// the cfg's file name, inside home
pub const filePath="controls.cfg";
/// the bindings as built: what an edited file leaves out falls back to these
const default=@embedFile("controls.cfg");
/// the cfg is a few kilobytes; anything near this is not one.
const maxCfg:usize=1<<16;
/// most alternatives one action can be bound to.
pub const maxBinds=4;
/// everything the gardener can ask of the game, each bound to keys or
/// buttons in `controls.cfg` (a cfg line per tag, by name)
pub const Action=enum{
  /// walk the way the camera looks
  moveForward,
  /// walk back toward the camera
  moveBack,
  /// walk to the left
  moveLeft,
  /// walk to the right
  moveRight,
  /// held with movement
  run,
  /// held: dragging the mouse orbits the camera round the wolf
  orbit,
  /// held: with it `freeCam` toggles the free camera and `rise` sinks
  alt,
  /// held: plant what is in hand; on a structure, interact; click a panel
  /// row; in the free camera, look
  use,
  /// interact with a structure (as `use` on it), harvest a plant
  interact,
  /// pressed or held: the universal remove (uproot a plant, take up a
  /// structure, gather from a resource node); clear a hotbar slot
  remove,
  /// take up the seed or bulb of what stands under the cursor
  pick,
  /// take a ripe plant's yield
  harvest,
  /// held with harvest: take from a structure instead of feeding it
  take,
  /// set up a paired or configurable structure
  configure,
  /// turn what stands under the cursor, else the next thing put down
  rotate,
  /// held with rotate: turn the other way (counter-clockwise)
  counter,
  /// with the belly open: throw away the belly stack under the cursor (or carried)
  discard,
  /// open or close the belly (the inventory)
  belly,
  /// open or close the research sapling
  research,
  /// alt mode: show or hide, over every structure, an icon of what it
  /// weaves or holds
  overview,
  /// hotbar slot 1, the leftmost (all of them in order: `slots`)
  slot1,
  /// hotbar slot 2
  slot2,
  /// hotbar slot 3
  slot3,
  /// hotbar slot 4
  slot4,
  /// hotbar slot 5
  slot5,
  /// hotbar slot 6
  slot6,
  /// hotbar slot 7
  slot7,
  /// hotbar slot 8
  slot8,
  /// hotbar slot 9
  slot9,
  /// hotbar slot 10
  slot10,
  /// hotbar slot 11
  slot11,
  /// hotbar slot 12
  slot12,
  /// hotbar slot 13
  slot13,
  /// with alt: toggle the free camera
  freeCam,
  /// in the free camera: fly faster while held
  flyFast,
  /// in the free camera: rise (with alt held, sink)
  rise,
  /// in the free camera: roll to the left
  rollLeft,
  /// in the free camera: roll to the right
  rollRight,
  /// close a panel, else pause
  back,
  /// while paused: leave the game
  quit,
  /// while paused: open the options
  options,
  /// while paused: open the saved gardens
  gardens,
  /// while paused: open the keybinds
  keybinds,
  /// typing: take back the selection, else the character before the caret
  erase,
  /// typing: take out the selection, else the character after the caret
  eraseAhead,
  /// typing: accept it; in a menu, choose the row the keys are on
  confirm,
  /// in a menu: move to the row above (the nearest that way)
  focusUp,
  /// in a menu: move to the row below
  focusDown,
  /// in a menu: move to the row on the left, or turn a setting back
  focusLeft,
  /// in a menu: move to the row on the right, or turn a setting on
  focusRight,
  /// in a menu: move to the next row (with extend, the one before)
  focusNext,
  /// held: moving the caret selects; with focusNext, steps back
  extend,
  /// typing: move the caret back a character
  caretLeft,
  /// typing: move the caret on a character
  caretRight,
  /// typing: move the caret before the first character
  caretHome,
  /// typing: move the caret after the last character
  caretEnd,
  /// held: with selectAll, copy, cut or paste, does that
  chord,
  /// typing, with chord: select all of the text
  selectAll,
  /// typing, with chord: copy the selection to the clipboard
  copy,
  /// typing, with chord: cut the selection to the clipboard
  cut,
  /// typing, with chord: paste the clipboard in at the caret
  paste,
  /// save the garden
  save,
  /// load the newest saved garden
  load,
  /// toggle fullscreen
  fullscreen,
  /// toggle the debug overlay
  debug,
};
/// the actions that pick hotbar slots, slot 0 first.
pub const slots=[_]Action{.slot1,.slot2,.slot3,.slot4,.slot5,.slot6,.slot7,.slot8,.slot9,.slot10,.slot11,.slot12,.slot13};
/// the keys and buttons one action is bound to, at most `maxBinds`
pub const Binds=struct{
  /// the bindings; only the first `len` are real
  list:[maxBinds]Bind=undefined,
  /// how many bindings are held
  len:u8=0,
  /// the real bindings, as a slice
  pub fn items(b:*const Binds)[]const Bind{return b.list[0..b.len];}
  /// whether `b` and `o` hold the same bindings in the same order
  pub fn same(b:*const Binds,o:*const Binds)bool{
    if(b.len!=o.len)return false;
    for(b.items(),o.items())|x,y|if(!eqlDeep(x,y))return false;
    return true;
  }
};
/// the cfg as written: each action a list of key and button names.
const Source=struct{bind:EnumArray(Action,[]const u8)=.initFill("")};
/// the loaded bindings; empty until `load` (headless tests `fill` them).
// decision: one process-wide table, set once at startup like `txt.s`;
// only the KEYBINDS menu changes it after, between frames.
pub var map:EnumArray(Action,Binds)=.initFill(.{});
/// the game's own bindings, as shipped, for what a reset returns to and
/// what is written back (empty until `load`; tests set it to `map`)
pub var stock:EnumArray(Action,Binds)=.initFill(.{});
/// the controls file could not be written
pub const WriteError=error{ControlsUnwritable};
/// the most the written file can hold (an action's line is well under
/// a hundred bytes)
const maxWritten:usize=1<<14;
/// the cfg could not be read, or named a key that does not exist
/// (or too many for one action)
pub const Error=error{NoControls,BadControls}||Allocator.Error;
/// reads and parses `filePath` (in `home`, made from the game's own when
/// missing) over the game's own bindings. Called once, at startup, before
/// the first frame.
pub fn load(gpa:Allocator,io:Io)Error!void{
  // the cfg text in home (made or refreshed from the game's own), freed once parsed
  const src=try home.stock(gpa,io,filePath,default);
  defer gpa.free(src);
  try fill(&.{default});
  stock=map;
  fill(&.{default,src})catch|e|switch(e){
    error.OutOfMemory=>return error.OutOfMemory,
    else=>{
      log.warn("{s}: ignoring the edited bindings",.{filePath});
      try fill(&.{default});
    },
  };
}
/// parses each cfg source of `texts` into `map` in turn, an action bound
/// in a later one replacing an earlier's (nothing of `texts` is kept).
pub fn fill(texts:[]const[]const u8)Error!void{
  // room for the parser's complaint, and the writer that fills it
  var badBuf:[256]u8=undefined;
  var bad:Io.Writer=.fixed(&badBuf);
  // every action's list of key names, later sources over earlier ones
  var src:Source=.{};
  for(texts)|text|ctext.parse(Source,&src,text,&bad)catch|e|{
    log.err("{s}: {t}: {s}",.{filePath,e,bad.buffered()});
    return error.BadControls;
  };
  // the bindings being built, and the walk over every action's names
  var out:EnumArray(Action,Binds)=.initFill(.{});
  var it=src.bind.iterator();
  while(it.next())|e|{
    // this action's bindings, and the walk over its key names
    const b=out.getPtr(e.key);
    var names=splitScalar(u8,e.value.*,ctext.listSep);
    while(names.next())|raw|{
      // one key's name, and the key or button it names
      const name=trim(u8,raw," \t");
      const one=Bind.parse(name)orelse{
        log.err("{s}: {t}: no key or button '{s}'",.{filePath,e.key,name});
        return error.BadControls;
      };
      if(b.len==maxBinds){
        log.err("{s}: {t}: more than {d} bindings",.{filePath,e.key,maxBinds});
        return error.BadControls;
      }
      b.list[b.len]=one;
      b.len+=1;
    }
  }
  map=out;
}
/// forgets every binding (tests, so they do not leak into the next)
pub fn unload()void{
  map=.initFill(.{});
  stock=.initFill(.{});
}
/// sets `b` in place of `a`'s first binding of its kind (the keyboard's
/// and mouse's, or the gamepad's), else beside its others while there is
/// room, else over its last; a key it already has leaves it as it is
pub fn rebind(a:Action,b:Bind)void{
  // the action's bindings
  const bs=map.getPtr(a);
  for(bs.items())|have|if(eqlDeep(have,b))return;
  for(bs.list[0..bs.len])|*have|if(have.onPad()==b.onPad()){
    have.*=b;
    return;
  };
  if(bs.len<maxBinds){
    bs.list[bs.len]=b;
    bs.len+=1;
    return;
  }
  bs.list[maxBinds-1]=b;
}
/// `a` bound as the game ships it again
pub fn reset(a:Action)void{map.set(a,stock.get(a));}
/// every action bound as the game ships it again
pub fn resetAll()void{map=stock;}
/// whether `a` is bound otherwise than the game ships it
pub fn changed(a:Action)bool{return!map.getPtrConst(a).same(stock.getPtrConst(a));}
/// writes the bindings that differ from the game's own to `w` as a cfg
/// (`[bind]`, a line each), so the rest follow the game's as it changes
pub fn format(w:*Writer)Writer.Error!void{
  try w.writeAll("# Parasymi: bindings set in the KEYBINDS menu (or by hand). Only\n# those changed from the game's own are here; the rest follow it.\n# `action = name | name`, names as in the game's controls.cfg.\n\n[bind]\n");
  for(values(Action))|a|if(changed(a)){
    try w.print("{t} = ",.{a});
    for(map.getPtrConst(a).items(),0..)|b,i|{
      if(i>0)try w.writeAll(&.{' ',ctext.listSep,' '});
      try b.write(w);
    }
    try w.writeByte('\n');
  };
}
/// writes the bindings to `filePath` in home: what differs from the
/// game's own, or (nothing changed) the game's own file, stamped, so it
/// follows the game again
pub fn write(io:Io)WriteError!void{
  // whether any action is bound otherwise than shipped
  const any=for(values(Action))|a|{
    if(changed(a))break true;
  }else false;
  if(!any)return home.restock(io,filePath,default);
  // room for the file, and the writer that fills it
  var buf:[maxWritten]u8=undefined;
  var w:Writer=.fixed(&buf);
  format(&w) catch return error.ControlsUnwritable;
  home.dir().writeFile(io,.{.sub_path=filePath,.data=w.buffered()}) catch return error.ControlsUnwritable;
}
/// is any key or button bound to `a` held?
pub fn down(in:*const Input,a:Action)bool{
  for(map.getPtrConst(a).items())|b|if(in.down(b))return true;
  return false;
}
/// did a key or button bound to `a` go down this frame?
pub fn pressed(in:*const Input,a:Action)bool{
  for(map.getPtrConst(a).items())|b|if(in.pressed(b))return true;
  return false;
}
/// was a key or button bound to `a` let go this frame?
pub fn released(in:*const Input,a:Action)bool{
  for(map.getPtrConst(a).items())|b|if(in.released(b))return true;
  return false;
}
/// did a key or button bound to `a` go down this frame, or (held long
/// enough) repeat, as a held arrow or erase does?
pub fn repeated(in:*const Input,a:Action)bool{
  for(map.getPtrConst(a).items())|b|if(in.repeated(b))return true;
  return false;
}
/// headless tests: hold `a`'s first binding down (or let it go).
pub fn hold(in:*Input,a:Action,on:bool)void{
  in.hold(map.getPtrConst(a).list[0],on);
}
test"the controls file binds every action"{
  defer unload();
  try fill(&.{@embedFile("controls.cfg")});
  for(values(Action))|a|try testing.expect(map.get(a).len>0);
  try testing.expectEqual(Bind{.button=.left},map.get(.use).list[0]);
}
test"a rebound action is written back, read back the same, and reset"{
  defer unload();
  try fill(&.{default});
  stock=map;
  // a key takes the place of the first key, a pad button of the first pad button
  rebind(.moveForward,.{.key=.i});
  rebind(.back,.{.pad=.y});
  try testing.expectEqual(Bind{.key=.i},map.get(.moveForward).list[0]);
  try testing.expectEqual(Bind{.key=.up},map.get(.moveForward).list[1]);
  try testing.expectEqual(Bind{.pad=.y},map.get(.back).list[1]);
  try testing.expect(changed(.moveForward) and changed(.back) and !changed(.use));
  // room for the file, the writer that fills it, and the bindings as written
  var buf:[maxWritten]u8=undefined;
  var w:Writer=.fixed(&buf);
  try format(&w);
  const want=map;
  try fill(&.{default,w.buffered()});
  for(values(Action))|a|try testing.expect(map.getPtrConst(a).same(want.getPtrConst(a)));
  reset(.moveForward);
  try testing.expect(!changed(.moveForward));
  resetAll();
  for(values(Action))|a|try testing.expect(!changed(a));
}
