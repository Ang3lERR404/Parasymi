//! the playable layer: owns world + sim + progression + the player and runs a
//! frame: input -> actions (actions.zig), fixed-tick simulation, and what gets
//! drawn (view.zig). Nothing is pooled globally: items live in the player and
//! in structures, essence and seeds live in plants until harvested.
const lib=@import("../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const ck=lib.ck;
const items=lib.items;
const ctl=lib.controls;
const options=lib.options;
const save=lib.save;
pub const game=@import("play/game.zig");
pub const frame=@import("play/frame.zig");
pub const belly=@import("play/belly.zig");
pub const menus=@import("play/menus.zig");
pub const testsMenu=@import("play/tests_menu.zig");
pub const testsBelly=@import("play/tests_belly.zig");
pub const testsPlace=@import("play/tests_place.zig");
pub const Game=game.Game;
pub const tickTime=1.0/60.0;
/// the test gardens' world (`--demo`, `--stress`, `--plant`/`--structure`,
/// tests); a played game grows from a fresh seed each start
pub const defaultSeed:u64=0x5EED_0F_11FE;
/// the window's size when it opens
pub const windowSize=[2]u16{1600,900};
pub const streamRadius=4;
/// the chunks resident round the gardener once streamed (a square of rings)
pub const streamChunks=(2*streamRadius+1)*(2*streamRadius+1);
/// nothing is drawn further than this from the camera target (inside the
/// streamed radius, so a low camera never runs off the generated world)
pub const drawLimit:f32=(streamRadius-0.5)*ck.sizeTiles;
/// max chunks to stream in a single call (initial load is generous,
/// per-frame is tight to avoid hitches)
pub const streamInit=1<<10;
pub const streamFrame=4;
/// camera feel parameters (tune here, not scattered through update)
pub const followLerp:f32=6;
/// the camera follows a point this far above the wolf's feet
pub const followHeight:f32=0.6;
/// gathering, the wolf walks up to the node this eagerly (wish per metre
/// still to go)
pub const approach:f32=2;
/// how quickly the shown frame and sim timings follow the measured ones
pub const timingEase:f32=0.05;
/// free camera: Shift multiplies the fly speed; the wheel dollies this much a notch
pub const flyFastSpeed:f32=3;
pub const dollyPerNotch:f32=0.4;
/// first person: the wolf's head is hidden once the view comes this close
/// to its eyes (easing in, it is seen until then)
pub const headClear:f32=0.3;
/// the simulation never runs more than this many catch-up ticks a frame
pub const maxCatchup=8;
/// the spawn search spirals out to this radius in steps of this many tiles
pub const spawnSearch=400;
pub const spawnStep=3;
/// ray-march parameters for ground picking
pub const pickStep:f32=0.1;
pub const pickRangeMult:f32=4;
/// hotbar slots, in `ctl.slots` order. Each is empty or holds an item the
/// gardener dropped on it from the belly; it shows how many the belly holds.
pub const barSlots=ctl.slots.len;
/// UI time handed to HUD motion wraps after this many seconds
pub const uiWrap:f64=1000;
/// what the cursor carries (one click lifts, the next puts down): a belly
/// slot's stack, a hotbar slot's item, or a stack from a slot of the
/// structure whose panel is open. It stays where it was until put down, so
/// closing the panel or saving loses nothing.
pub const Held=union(enum){slot:usize,bar:usize,store:usize};
/// a stack put down within one inventory goes as far as it fits
pub const stackAny:u32=1<<16;
/// can the gardener place this hotbar item yet (seed understood / always for bulbs)?
pub fn known(g:*const Game,item:items.Item)bool{
  return if(item.plants())|sp|g.prog.canPlant(sp)else true;
}
/// what only main can do (it owns the window and the file system)
pub const Request=union(enum){
  /// into the garden being played (`Game.slot`, which it has)
  save,
  /// back to the garden being played as last saved (else the newest)
  load,
  /// the autosave timer ran out: into `save.AUTO`
  autosave,
  /// the saved gardens menu wants its list (`Game.gardens`)
  list,
  /// the saved gardens menu or the name asked for: save as this garden
  saveAs:save.Name,
  /// the saved gardens menu: replace the running game with the chosen one
  loadFrom:save.Name,
  /// the saved gardens menu: let the chosen garden go
  delete:save.Name,
  /// save and leave
  quit,
};
/// the pause menu's rows, in `txt.s.hud.pause_labels` order
pub const PauseRow=enum{@"resume",options,gardens,fullscreen,quit};
/// the saved gardens menu's buttons (under its list, and the chosen
/// garden's delete), and the name prompt's
pub const GardenAct=enum{save,load,delete,ok,cancel};
/// saved gardens menu: rows in view at once (it scrolls past them), rows a
/// wheel notch scrolls, and how fast the list follows (1/s)
pub const gardensShown=7;
pub const gardenNotch:f32=1;
pub const gardenEase:f32=14;
/// what has the wolf's attention; only one at a time.
pub const Mode=enum{
  /// out in the garden: moving, gathering, placing
  roam,
  /// the belly is open (Tab): weaving by hand
  belly,
  /// a structure's panel is open (clicked in the garden, `Game.open`): its
  /// slots beside the belly's, and what it may be set to weave
  structure,
  /// the research list is open (T)
  research,
  /// the world is frozen and the pause menu is open (Esc)
  paused,
  /// the world is frozen and the options panel is open (from the pause menu)
  options,
  /// the world is frozen and the saved gardens are listed (from the pause
  /// menu): save as one, load one
  gardens,
  /// the world is frozen and a name is asked for the garden being saved
  /// (saving a fresh one, or the save key before it has a name)
  naming,
  /// the free camera is flying for inspection (Ctrl+F); the wolf stands idle
  inspect,
  /// the world keeps moving underneath (everything but the pause menu, the
  /// panels opened from it and the name prompt)
  pub fn live(md:Mode)bool{return md!=.paused and md!=.options and md!=.gardens and md!=.naming;}
  /// the belly's slots are open: stacks are lifted and put down
  pub fn sorting(md:Mode)bool{return md==.belly or md==.structure;}
};
pub const Error=Allocator.Error;
test{
  _=game;
  _=frame;
  _=belly;
  _=menus;
  _=testsMenu;
  _=testsBelly;
  _=testsPlace;
}
