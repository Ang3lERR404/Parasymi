//! play tested: standing still, clicking the HUD, the menus and saving.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the test helpers
const testing=std.testing;
/// deep equality, to find the row picking what is wanted
const eqlDeep=std.meta.eql;
/// writing into a fixed buffer, for gardens' names
const bufPrint=std.fmt.bufPrint;
/// the engine package
const engine=lib.engine;
/// all the maths: conversions, minutes
const m=engine.core.math;
/// a clipboard of a test's own
const Clip=engine.platform.input.Clip;
/// the keys and buttons, set by hand here
const Input=engine.platform.input.Input;
/// the bindings: actions held and loaded
const ctl=lib.controls;
/// the renderer, for its antialiasing choices
const renderer=lib.renderer;
/// the weave recipes, some woven by hand
const craft=lib.craft;
/// the HUD: building it, its rows to click
const hud=lib.hud;
/// saving: gardens' names
const save=lib.save;
/// the test gardens' world seed
const defaultSeed=lib.play.defaultSeed;
/// how many gardens' rows are in view at once
const gardensShown=lib.play.gardensShown;
/// the game under test
const Game=lib.play.game.Game;
/// what has the wolf's attention
const Mode=lib.play.Mode;
/// one simulation tick (s), each frame's step here
const tickTime=lib.play.tickTime;
/// the window's size when it opens
const windowSize=lib.play.windowSize;
/// tests draw to a window of the default size
pub const testScreen=m.Vice(f32,2){m.f(windowSize[0]),m.f(windowSize[1])};
test"the wolf stays put without input"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  try lib.setups.demo(&g,5);
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  in.mouse=.{-1e4,-1e4};
  // where the wolf stood at the start
  const start=g.player.pos;
  for(0..300)|_|{
    try g.update(&in,tickTime,testScreen);
    try g.simulate(tickTime);
  }
  try testing.expectApproxEqAbs(start[0],g.player.pos[0],0.05);
  try testing.expectApproxEqAbs(start[2],g.player.pos[2],0.05);
}
/// headless clicks on the HUD
pub const click=struct{
  /// press the left button over the middle of the first row picking `want`
  pub fn on(gg:*Game,i:*Input,want:hud.Pick,sc:m.Vice(f32,2))!void{return press(gg,i,want,sc,.use);}
  /// press `a` with the mouse over the middle of the first row picking
  /// `want`, a frame down and (for `use`, whose buttons click as it is let
  /// go) a frame let go
  pub fn press(gg:*Game,i:*Input,want:hud.Pick,sc:m.Vice(f32,2),a:ctl.Action)!void{
    try hud.build(gg,sc);
    for(gg.rows.all())|r|{
      if(!eqlDeep(r.pick,want))continue;
      i.mouse=r.box.center();
      i.advance();
      ctl.hold(i,a,true);
      try gg.update(i,tickTime,sc);
      i.advance();
      ctl.hold(i,a,false);
      if(a==.use)try gg.update(i,tickTime,sc);
      return;
    }
    return error.TestUnexpectedResult;
  }
  /// press the key (or button) of `a` for a frame, the HUD drawn first,
  /// and let it go
  pub fn key(gg:*Game,i:*Input,a:ctl.Action,sc:m.Vice(f32,2))!void{
    try hud.build(gg,sc);
    i.advance();
    ctl.hold(i,a,true);
    try gg.update(i,tickTime,sc);
    i.advance();
    ctl.hold(i,a,false);
  }
};
test"clicking a research node or weave recipe picks it; number keys only pick the hotbar"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  // the screen the clicks land on
  const screen=testScreen;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  g.mode=.research;
  try click.on(&g,&in,hud.row(.research,.{.node=.leySight}),screen);
  try testing.expect(g.prog.current==.leySight);
  g.mode=.belly;
  _=g.player.inv.add(.fibre,2);
  _=g.player.inv.add(.grit,1);
  try testing.expect(craft.hand[craft.byHand[0]].out==.conduit);
  try click.on(&g,&in,hud.row(.belly,.{.weave=craft.byHand[0]}),screen);
  try testing.expect(g.weave.busy());
  // with the belly open, a slot key picks the hotbar slot, not a recipe
  in.mouse=.{-1e4,-1e4};
  in.advance();
  ctl.hold(&in,.slot3,true);
  try g.update(&in,tickTime,screen);
  try testing.expectEqual(@as(usize,2),g.hot);
  try testing.expectEqual(@as(usize,1),g.weave.len);
}
test"the pause menu opens the options; clicks turn them and lead back"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  // the screen the clicks land on
  const screen=testScreen;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  g.opts=.{.aa=.off};
  g.mode=.paused;
  try click.on(&g,&in,hud.row(.pause,.{.row=.options}),screen);
  try testing.expectEqual(Mode.options,g.mode);
  try click.on(&g,&in,hud.row(.options,.{.setting=.antialias}),screen);
  try testing.expectEqual(renderer.Antialias.fxaa,g.opts.aa);
  try click.on(&g,&in,hud.row(.options,.{.setting=.vsync}),screen);
  try testing.expect(!g.opts.vsync);
  try click.on(&g,&in,hud.row(.options,.back),screen);
  try testing.expectEqual(Mode.paused,g.mode);
  try click.on(&g,&in,hud.row(.pause,.{.row=.@"resume"}),screen);
  try testing.expectEqual(Mode.roam,g.mode);
  // nothing moved while frozen
  try testing.expectEqual(@as(u64,0),g.ticks);
}
test"the main menu: its panels lead back to it, continue wants a garden saved, new garden goes in, leave asks main"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  // the screen the clicks land on
  const screen=testScreen;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  g.mode=.title;
  // the stage is drawn, with only the menu's panels over it
  _=try lib.view.scene(&g,screen);
  try testing.expect(g.atTitle());
  try testing.expect(g.rows.find(hud.row(.title,.{.row=.newGarden}))!=null);
  // nothing saved: continue is not offered
  try testing.expect(g.rows.find(hud.row(.title,.{.row=.@"continue"}))==null);
  // the options lead back to the main menu, not the pause menu
  try click.on(&g,&in,hud.row(.title,.{.row=.options}),screen);
  try testing.expectEqual(Mode.options,g.mode);
  try testing.expect(g.atTitle());
  try click.on(&g,&in,hud.row(.options,.back),screen);
  try testing.expectEqual(Mode.title,g.mode);
  // so do the keybinds, by the back key too
  try click.on(&g,&in,hud.row(.title,.{.row=.keybinds}),screen);
  try testing.expectEqual(Mode.keybinds,g.mode);
  in.advance();
  ctl.hold(&in,.back,true);
  try g.update(&in,tickTime,screen);
  ctl.hold(&in,.back,false);
  try testing.expectEqual(Mode.title,g.mode);
  // back at the main menu, the back key does nothing
  in.advance();
  ctl.hold(&in,.back,true);
  try g.update(&in,tickTime,screen);
  ctl.hold(&in,.back,false);
  try testing.expectEqual(Mode.title,g.mode);
  // leave asks main to close, saving nothing
  try click.on(&g,&in,hud.row(.title,.{.row=.leave}),screen);
  try testing.expect(g.request.?==.leave);
  g.request=null;
  // new garden goes into the garden grown behind it; paused there, the
  // options lead back to the pause menu again
  try click.on(&g,&in,hud.row(.title,.{.row=.newGarden}),screen);
  try testing.expectEqual(Mode.roam,g.mode);
  try testing.expect(!g.atTitle());
  // the research tree opened at once is the garden's, not the main menu
  g.mode=.research;
  try testing.expect(!g.atTitle());
  g.mode=.roam;
  in.advance();
  ctl.hold(&in,.back,true);
  try g.update(&in,tickTime,screen);
  ctl.hold(&in,.back,false);
  try testing.expectEqual(Mode.paused,g.mode);
  try click.on(&g,&in,hud.row(.pause,.{.row=.options}),screen);
  try click.on(&g,&in,hud.row(.options,.back),screen);
  try testing.expectEqual(Mode.paused,g.mode);
}
test"the saved gardens scroll, save over one or delete it only when asked twice, and load"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  // the screen the clicks land on
  const screen=testScreen;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  g.mode=.paused;
  try click.on(&g,&in,hud.row(.pause,.{.row=.gardens}),screen);
  try testing.expectEqual(Mode.gardens,g.mode);
  try testing.expect(g.request.?==.list);
  g.request=null;
  // main lists them: more than fit, so the list scrolls
  for(0..gardensShown+3)|i|{
    // room to write this garden's name in
    var buf:[16]u8=undefined;
    try g.gardens.append(gpa,.{.name=save.Name.of(bufPrint(&buf,"garden {d}",.{i}) catch unreachable).?,.age=@intCast(i*90)});
  }
  g.listed();
  in.mouse=.{-1e4,-1e4};
  in.advance();
  in.scroll=-2;
  try g.update(&in,tickTime,screen);
  in.scroll=0;
  try testing.expectEqual(@as(f32,2),g.gardenList.top);
  in.scroll=-100;
  try g.update(&in,tickTime,screen);
  in.scroll=0;
  try testing.expectEqual(m.f(4),g.gardenList.top);
  // the list follows, bringing the last rows into view
  for(0..60)|_|try g.update(&in,tickTime,screen);
  try testing.expectApproxEqAbs(m.f(4),g.gardenList.at,0.01);
  // a fresh garden asks its name first
  try click.on(&g,&in,hud.row(.gardens,.{.act=.save}),screen);
  try testing.expectEqual(Mode.naming,g.mode);
  try testing.expect(g.request.?==.list);
  g.request=null;
  try click.on(&g,&in,hud.row(.gardens,.{.act=.cancel}),screen);
  try testing.expectEqual(Mode.gardens,g.mode);
  try testing.expect(g.request==null);
  // a saved one only on the second click
  try click.on(&g,&in,hud.row(.gardens,.{.garden=9}),screen);
  try testing.expectEqual(@as(usize,9),g.garden);
  try click.on(&g,&in,hud.row(.gardens,.{.act=.save}),screen);
  try testing.expect(g.request==null and g.overwrite);
  try click.on(&g,&in,hud.row(.gardens,.{.act=.save}),screen);
  try testing.expectEqualStrings("garden 8",g.request.?.saveAs.slice());
  g.request=null;
  try click.on(&g,&in,hud.row(.gardens,.{.act=.load}),screen);
  try testing.expectEqualStrings("garden 8",g.request.?.loadFrom.slice());
  g.request=null;
  // the chosen one's delete, only on the second click
  try click.on(&g,&in,hud.row(.gardens,.{.act=.delete}),screen);
  try testing.expect(g.request==null and g.deleting);
  try click.on(&g,&in,hud.row(.gardens,.{.act=.delete}),screen);
  try testing.expectEqualStrings("garden 8",g.request.?.delete.slice());
  g.request=null;
  try click.on(&g,&in,hud.row(.gardens,.back),screen);
  try testing.expectEqual(Mode.paused,g.mode);
  try testing.expectEqual(@as(u64,0),g.ticks);
}
test"the save key asks a garden without a name for one: typed, taken asks twice, OK saves"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  // the screen the clicks land on
  const screen=testScreen;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  in.mouse=.{-1e4,-1e4};
  in.advance();
  ctl.hold(&in,.save,true);
  try g.update(&in,tickTime,screen);
  in.advance();
  ctl.hold(&in,.save,false);
  try testing.expectEqual(Mode.naming,g.mode);
  try testing.expect(g.request.?==.list);
  g.request=null;
  try g.gardens.append(gpa,.{.name=save.Name.of("Moss").?,.age=0});
  g.listed();
  // the world stands still while a name is typed; letters bound to
  // actions only type
  for("moss?")|c|in.type1(c);
  try g.update(&in,tickTime,screen);
  in.typedLen=0;
  try testing.expectEqualStrings("moss",g.typed.slice());
  try testing.expectEqual(@as(u64,0),g.ticks);
  try testing.expectEqual(Mode.naming,g.mode);
  // taken: OK asks first, then saves over it
  try click.on(&g,&in,hud.row(.gardens,.{.act=.ok}),screen);
  try testing.expect(g.request==null and g.overwrite);
  try click.on(&g,&in,hud.row(.gardens,.{.act=.ok}),screen);
  try testing.expectEqualStrings("moss",g.request.?.saveAs.slice());
  try testing.expectEqual(Mode.roam,g.mode);
  g.request=null;
  // named, the save key saves at once; erase takes back, Esc cancels
  g.startNaming();
  for("ab")|c|in.type1(c);
  try g.update(&in,tickTime,screen);
  in.typedLen=0;
  try click.press(&g,&in,.panel,screen,.erase);
  try testing.expectEqualStrings("a",g.typed.slice());
  try click.press(&g,&in,.panel,screen,.back);
  try testing.expectEqual(Mode.roam,g.mode);
  g.request=null;
  g.slot=save.Name.of("moss").?;
  in.advance();
  ctl.hold(&in,.save,true);
  try g.update(&in,tickTime,screen);
  try testing.expect(g.request.?==.save);
}
test"the garden saves itself once the autosave interval is played"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  in.mouse=.{-1e4,-1e4};
  g.opts.autosave=1;
  // each frame's step (s), and how many frames ran before it asked
  const stepS:f32=0.5;
  var frames:usize=0;
  while(g.request==null):(frames+=1)try g.update(&in,stepS,testScreen);
  try testing.expect(g.request.?==.autosave);
  try testing.expectEqual(@as(usize,m.sPerMin/stepS),frames);
  // never, when turned off
  g.request=null;
  g.opts.autosave=0;
  for(0..1000)|_|try g.update(&in,stepS,testScreen);
  try testing.expect(g.request==null);
}
test"a menu button clicks as mouse1 is let go over it; sliding off first takes it back"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  // the screen the clicks land on
  const screen=testScreen;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  g.mode=.paused;
  try hud.build(&g,screen);
  // the options row, pressed and held: nothing yet
  const b=g.rows.find(hud.row(.pause,.{.row=.options})).?;
  in.mouse=b.center();
  in.advance();
  ctl.hold(&in,.use,true);
  try g.update(&in,tickTime,screen);
  try testing.expectEqual(Mode.paused,g.mode);
  // slid off and let go: still nothing
  in.mouse=.{-1e4,-1e4};
  in.advance();
  try g.update(&in,tickTime,screen);
  in.advance();
  ctl.hold(&in,.use,false);
  try g.update(&in,tickTime,screen);
  try testing.expectEqual(Mode.paused,g.mode);
  // pressed and let go over it: it opens the options
  try click.on(&g,&in,hud.row(.pause,.{.row=.options}),screen);
  try testing.expectEqual(Mode.options,g.mode);
}
test"the keys move between a menu's rows, turn settings left and right, and confirm chooses"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  // the screen the clicks land on
  const screen=testScreen;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window), the mouse out of the way
  var in:Input=.{.win=undefined};
  in.mouse=.{-1e4,-1e4};
  g.opts=.{.aa=.off};
  g.mode=.paused;
  // down from nowhere lands on the first row, down again on the next
  try click.key(&g,&in,.focusDown,screen);
  try testing.expect(eqlDeep(g.keyFocus.?,hud.row(.pause,.{.row=.@"resume"})));
  try click.key(&g,&in,.focusDown,screen);
  try testing.expect(eqlDeep(g.keyFocus.?,hud.row(.pause,.{.row=.options})));
  // the row the keys are on is pointed at, as the mouse would
  try testing.expect(g.points(hud.row(.pause,.{.row=.options})));
  try click.key(&g,&in,.confirm,screen);
  try testing.expectEqual(Mode.options,g.mode);
  // in the options, right turns the setting the keys are on, not moving off it
  try click.key(&g,&in,.focusDown,screen);
  try testing.expect(eqlDeep(g.keyFocus.?,hud.row(.options,.{.setting=.antialias})));
  try click.key(&g,&in,.focusRight,screen);
  try testing.expectEqual(renderer.Antialias.fxaa,g.opts.aa);
  try click.key(&g,&in,.focusLeft,screen);
  try testing.expectEqual(renderer.Antialias.off,g.opts.aa);
  // tab steps on through the rows, round past the last
  try click.key(&g,&in,.focusNext,screen);
  try testing.expect(eqlDeep(g.keyFocus.?,hud.row(.options,.{.setting=.vsync})));
  try click.key(&g,&in,.focusRight,screen);
  try testing.expect(!g.opts.vsync);
  // the autosave slider stops at its ends
  g.opts.autosave=60;
  g.keyFocus=hud.row(.options,.{.setting=.autosave});
  try click.key(&g,&in,.focusRight,screen);
  try testing.expectEqual(@as(u8,60),g.opts.autosave);
  try click.key(&g,&in,.focusLeft,screen);
  try testing.expectEqual(@as(u8,30),g.opts.autosave);
  // the mouse moving takes the lead back
  in.mouseDelta=.{3,0};
  try g.update(&in,tickTime,screen);
  in.mouseDelta=.{0,0};
  try testing.expect(g.keyFocus==null);
}
test"a slider is dragged along its stem; a picker's leaves turn it either way"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  // the screen the clicks land on
  const screen=testScreen;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  g.opts=.{.aa=.fxaa,.autosave=5};
  g.mode=.options;
  try hud.build(&g,screen);
  // the autosave row: pressed at its right end, then dragged far left
  const b=g.rows.find(hud.row(.options,.{.setting=.autosave})).?;
  in.mouse=.{b.x+b.w-4,b.y+b.h/2};
  in.advance();
  ctl.hold(&in,.use,true);
  try g.update(&in,tickTime,screen);
  try testing.expectEqual(@as(u8,60),g.opts.autosave);
  in.mouse=.{b.x-200,b.y-300};
  in.advance();
  try g.update(&in,tickTime,screen);
  try testing.expectEqual(@as(u8,0),g.opts.autosave);
  in.advance();
  ctl.hold(&in,.use,false);
  try g.update(&in,tickTime,screen);
  // the picker's leaves: the left turns it back, the right on
  try click.on(&g,&in,hud.row(.options,.{.less=.antialias}),screen);
  try testing.expectEqual(renderer.Antialias.off,g.opts.aa);
  try click.on(&g,&in,hud.row(.options,.{.more=.antialias}),screen);
  try testing.expectEqual(renderer.Antialias.fxaa,g.opts.aa);
}
test"the name prompt's caret moves, typing goes in there, and a selection is cut and pasted"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  // the screen the clicks land on
  const screen=testScreen;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window), with a clipboard of its own
  var clip=Clip{};
  var in:Input=.{.win=undefined,.ownClip=&clip};
  in.mouse=.{-1e4,-1e4};
  g.startNaming();
  g.request=null;
  for("moss")|c|in.type1(c);
  try g.update(&in,tickTime,screen);
  in.typedLen=0;
  // two back, and a letter typed there
  try click.key(&g,&in,.caretLeft,screen);
  try click.key(&g,&in,.caretLeft,screen);
  in.type1('a');
  try g.update(&in,tickTime,screen);
  in.typedLen=0;
  try testing.expectEqualStrings("moass",g.typed.slice());
  // all of it selected and cut away, then pasted back twice
  ctl.hold(&in,.chord,true);
  try click.key(&g,&in,.selectAll,screen);
  try click.key(&g,&in,.cut,screen);
  try testing.expectEqualStrings("",g.typed.slice());
  try testing.expectEqualStrings("moass",clip.slice());
  try click.key(&g,&in,.paste,screen);
  try click.key(&g,&in,.paste,screen);
  ctl.hold(&in,.chord,false);
  try testing.expectEqualStrings("moassmoass",g.typed.slice());
  // a click on the field puts the caret where it lands: at its start
  const b=g.rows.find(hud.row(.naming,.field)).?;
  in.mouse=.{b.x+1,b.y+b.h/2};
  in.advance();
  ctl.hold(&in,.use,true);
  try g.update(&in,tickTime,screen);
  in.advance();
  ctl.hold(&in,.use,false);
  try testing.expectEqual(@as(usize,0),g.typed.caret);
  // confirm hands it on: saved under that name
  try click.key(&g,&in,.confirm,screen);
  try testing.expectEqualStrings("moassmoass",g.request.?.saveAs.slice());
}
test"the HUD holds as many clickable rows as are drawn"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  for(0..500)|i|try g.rows.add(.{.x=m.f(i)*4,.y=0,.w=4,.h=4},hud.row(.pause,.{.row=.quit}));
  try testing.expectEqual(@as(usize,500),g.rows.all().len);
  try testing.expect(g.rows.at(.{1997,2})!=null);
}
test"a keybind clicked listens: the next key binds it, back cancels, the other button resets it"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  // the screen the clicks land on
  const screen=testScreen;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  ctl.stock=ctl.map;
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  g.mode=.paused;
  try click.on(&g,&in,hud.row(.pause,.{.row=.keybinds}),screen);
  try testing.expectEqual(Mode.keybinds,g.mode);
  try click.on(&g,&in,hud.row(.keybinds,.{.action=.run}),screen);
  try testing.expectEqual(ctl.Action.run,g.rebinding.?);
  // back while listening cancels, the menu stays
  try click.key(&g,&in,.back,screen);
  try testing.expectEqual(null,g.rebinding);
  try testing.expectEqual(Mode.keybinds,g.mode);
  // listening again, the next key pressed is the new one
  try click.on(&g,&in,hud.row(.keybinds,.{.action=.run}),screen);
  in.advance();
  in.hold(.{.key=.b},true);
  try g.update(&in,tickTime,screen);
  in.advance();
  in.hold(.{.key=.b},false);
  try testing.expectEqual(null,g.rebinding);
  try testing.expectEqual(engine.platform.input.Bind{.key=.b},ctl.map.get(.run).list[0]);
  try testing.expect(g.request.?==.bindings);
  g.request=null;
  // the other button sets it back as shipped
  try click.press(&g,&in,hud.row(.keybinds,.{.action=.run}),screen,.remove);
  try testing.expect(!ctl.changed(.run));
  try testing.expect(g.request.?==.bindings);
  try click.on(&g,&in,hud.row(.keybinds,.back),screen);
  try testing.expectEqual(Mode.paused,g.mode);
}
/// presses action `a` for one frame and lets it go (the next frame's
/// press is fresh)
fn tap(g:*Game,in:*Input,a:ctl.Action,screen:m.Vice(f32,2))!void{
  in.advance();
  ctl.hold(in,a,true);
  try g.update(in,tickTime,screen);
  in.advance();
  ctl.hold(in,a,false);
}
test"the chat to Claude: opened only when linked, typed, sent, closed"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,testing.io,defaultSeed);
  defer g.deinit();
  // the screen the clicks land on
  const screen=testScreen;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  in.mouse=.{-1e4,-1e4};
  // not linked: the key does nothing
  try tap(&g,&in,.chat,screen);
  try testing.expectEqual(Mode.roam,g.mode);
  g.linked=true;
  try tap(&g,&in,.chat,screen);
  try testing.expectEqual(Mode.chat,g.mode);
  try testing.expect(!g.atTitle());
  // the world holds still; letters bound to actions only type
  const ticks=g.ticks;
  // (a frame holds at most `maxTyped` characters: typed over two)
  for([_][]const u8{"hello wolf, ","see this?"})|part|{
    for(part)|c|in.type1(c);
    try g.update(&in,tickTime,screen);
    in.typedLen=0;
  }
  try testing.expectEqualStrings("hello wolf, see this?",g.chat.typed.slice());
  try testing.expectEqual(ticks,g.ticks);
  // the save and load keys wait while a message is typed
  try tap(&g,&in,.save,screen);
  try tap(&g,&in,.load,screen);
  try testing.expect(g.request==null);
  // the panel is drawn with its field to click
  _=try lib.view.scene(&g,screen);
  try testing.expect(g.rows.find(hud.row(.chat,.field))!=null);
  // enter sends it and closes; main hands it on and clears it
  try tap(&g,&in,.confirm,screen);
  try testing.expectEqual(Mode.roam,g.mode);
  try testing.expect(g.chatSent);
  try testing.expect(g.typing==null);
  g.chatSent=false;
  g.chat.typed.clear();
  // Esc closes without sending, the half typed kept
  try tap(&g,&in,.chat,screen);
  for("half")|c|in.type1(c);
  try g.update(&in,tickTime,screen);
  in.typedLen=0;
  try tap(&g,&in,.back,screen);
  try testing.expectEqual(Mode.roam,g.mode);
  try testing.expect(!g.chatSent);
  try testing.expectEqualStrings("half",g.chat.typed.slice());
  // nothing typed: enter only closes
  g.chat.typed.clear();
  try tap(&g,&in,.chat,screen);
  try tap(&g,&in,.confirm,screen);
  try testing.expectEqual(Mode.roam,g.mode);
  try testing.expect(!g.chatSent);
  // an answer hangs beside play, drawn without the panel's field
  g.chat.add(.claude,"I see the wolf near the river, all looks well from here, a long answer that wraps over several lines",g.uiTime);
  try testing.expect(hud.panels.chat.visible(&g));
  // a message of the gardener's that never reached Claude, drawn marked
  g.chat.add(.gardener,"did this get through?",g.uiTime);
  g.chat.failLast();
  try testing.expect(g.chat.kept()[g.chat.count-1].failed);
  _=try lib.view.scene(&g,screen);
  try testing.expect(g.rows.find(hud.row(.chat,.field))==null);
  // long gone, it hangs no more
  g.uiTime+=60;
  try testing.expect(!hud.panels.chat.visible(&g));
  // the pause menu does not open from the chat's Esc
  try tap(&g,&in,.chat,screen);
  try tap(&g,&in,.back,screen);
  try testing.expectEqual(Mode.roam,g.mode);
}
