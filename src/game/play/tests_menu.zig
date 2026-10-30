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
pub const testScreen=[2]f32{m.f(windowSize[0]),m.f(windowSize[1])};
test"the wolf stays put without input"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,defaultSeed);
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
  pub fn on(gg:*Game,i:*Input,want:hud.Pick,sc:[2]f32)!void{return press(gg,i,want,sc,.use);}
  /// press `a` with the mouse over the middle of the first row picking `want`
  pub fn press(gg:*Game,i:*Input,want:hud.Pick,sc:[2]f32,a:ctl.Action)!void{
    try hud.build(gg,sc);
    for(gg.rows.box[0..gg.rows.len],gg.rows.pick[0..gg.rows.len])|q,p|{
      if(!eqlDeep(p,want))continue;
      i.mouse=q.center();
      i.advance();
      ctl.hold(i,a,true);
      try gg.update(i,tickTime,sc);
      i.advance();
      ctl.hold(i,a,false);
      return;
    }
    return error.TestUnexpectedResult;
  }
};
test"clicking a research node or weave recipe picks it; number keys only pick the hotbar"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,defaultSeed);
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
  var g=try Game.init(gpa,defaultSeed);
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
test"the saved gardens scroll, save over one or delete it only when asked twice, and load"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,defaultSeed);
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
  try testing.expectEqual(@as(f32,2),g.gardenTop);
  in.scroll=-100;
  try g.update(&in,tickTime,screen);
  in.scroll=0;
  try testing.expectEqual(m.f(4),g.gardenTop);
  // the list follows, bringing the last rows into view
  for(0..60)|_|try g.update(&in,tickTime,screen);
  try testing.expectApproxEqAbs(m.f(4),g.gardenAt,0.01);
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
  var g=try Game.init(gpa,defaultSeed);
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
  var g=try Game.init(gpa,defaultSeed);
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
