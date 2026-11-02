//! the playable layer: owns world + sim + progression + the player and runs a
//! frame: input -> actions (actions.zig), fixed-tick simulation, and what gets
//! drawn (view.zig). Nothing is pooled globally: items live in the player and
//! in structures, essence and seeds live in plants until harvested.
const lib=@import("../lib.zig");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=lib.engine.core.math;
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type a frame may fail with
const Allocator=std.mem.Allocator;
/// the chunk layer, for how many tiles a chunk spans
const ck=lib.ck;
/// what can be held: item kinds
const items=lib.items;
/// the bindings, for the hotbar's slot keys
const ctl=lib.controls;
/// the settings, kept in the game
const options=lib.options;
/// saving, for a garden's name
const save=lib.save;
/// the game itself: its state and how it is built and torn down
pub const game=@import("play/game.zig");
/// a frame: input, actions, ticks, camera, and what is drawn
pub const frame=@import("play/frame.zig");
/// what the wolf carries: hotbar, belly, an opened structure's slots
pub const belly=@import("play/belly.zig");
/// the menus: pause, options, saved gardens, the name prompt
pub const menus=@import("play/menus.zig");
/// where the garden is heard from: the ear, the place's echo, what hides a sound
pub const hearing=@import("play/hearing.zig");
/// the HUD by mouse, keys and pad: clicks, drags, focus, typing
pub const pointer=@import("play/pointer.zig");
/// the menus' tests
pub const testsMenu=@import("play/tests_menu.zig");
/// the belly's and carrying's tests
pub const testsBelly=@import("play/tests_belly.zig");
/// placing's tests
pub const testsPlace=@import("play/tests_place.zig");
/// the playable game: world, sim, progression, the wolf and its HUD
pub const Game=game.Game;
/// one simulation tick (s): sixty a second
pub const tickTime=1.0/60.0;
/// the test gardens' world (`--demo`, `--stress`, `--plant`/`--structure`,
/// tests); a played game grows from a fresh seed each start
pub const defaultSeed:u64=0x5EED_0F_11FE;
/// the window's size when it opens
pub const windowSize=m.Vice(u16,2){1600,900};
/// how many rings of chunks are streamed round the gardener
pub const streamRadius=4;
/// the chunks resident round the gardener once streamed (a square of rings)
pub const streamChunks=(2*streamRadius+1)*(2*streamRadius+1);
/// nothing is drawn further than this from the camera target (inside the
/// streamed radius, so a low camera never runs off the generated world)
pub const drawLimit:f32=(streamRadius-0.5)*ck.sizeTiles;
/// at most this many chunks are streamed in the first call (generous: the
/// whole first view)
pub const streamInit=1<<10;
/// at most this many chunks stream in each frame after (tight, to avoid hitches)
pub const streamFrame=4;
/// camera feel: how quickly the camera follows the wolf (share a second)
pub const followLerp:f32=6;
/// the camera follows a point this far above the wolf's feet
pub const followHeight:f32=0.6;
/// gathering, the wolf walks up to the node this eagerly (wish per metre
/// still to go)
pub const approach:f32=2;
/// how quickly the shown frame and sim timings follow the measured ones
pub const timingEase:f32=0.05;
/// free camera: Shift multiplies the fly speed by this much
pub const flyFastSpeed:f32=3;
/// free camera: the wheel dollies this far a notch (share of the distance)
pub const dollyPerNotch:f32=0.4;
/// first person: the wolf's head is hidden once the view comes this close
/// to its eyes (easing in, it is seen until then)
pub const headClear:f32=0.3;
/// the simulation never runs more than this many catch-up ticks a frame
pub const maxCatchup=8;
/// the spawn search spirals out to this radius (tiles)
pub const spawnSearch=400;
/// the spawn search steps out this many tiles at a time
pub const spawnStep=3;
/// ground picking: the ray marches in steps this long (metres)
pub const pickStep:f32=0.1;
/// ground picking: the ray reaches this many times the camera's distance
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
pub const Held=union(enum){
  /// a belly slot's stack, by the slot's index
  slot:usize,
  /// a hotbar slot's item, by the slot's index
  bar:usize,
  /// a stack from the open structure's slot, by its index
  store:usize
};
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
  /// the autosave timer ran out: into `save.auto`
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
  /// the keybinds menu changed the bindings: write them out, and show
  /// every `{@action}` as now bound
  bindings,
};
/// the pause menu's rows, in `txt.s.hud.pauseLabels` order
pub const PauseRow=enum{
  /// back to the garden, the world moving again
  @"resume",
  /// the options panel
  options,
  /// the keybinds
  keybinds,
  /// the saved gardens
  gardens,
  /// fullscreen on or off
  fullscreen,
  /// save and leave
  quit
};
/// the saved gardens menu's buttons (under its list, and the chosen
/// garden's delete), and the name prompt's
pub const GardenAct=enum{
  /// SAVE: write the garden as the chosen one (a fresh one asks its name)
  save,
  /// LOAD: return to the chosen garden
  load,
  /// the chosen garden's small DELETE: let it go
  delete,
  /// the name prompt's OK: save under the typed name
  ok,
  /// the name prompt's CANCEL: back to where it was asked
  cancel
};
/// saved gardens menu: rows in view at once (it scrolls past them)
pub const gardensShown=7;
/// saved gardens menu: how many rows a wheel notch scrolls
pub const gardenNotch:f32=1;
/// saved gardens menu: how fast the list follows (share a second)
pub const gardenEase:f32=14;
/// keybinds menu: rows in view at once (it scrolls past them)
pub const bindsShown=12;
/// keybinds menu: the height (pixels) of one action's row
pub const bindRowH:f32=40;
/// keybinds menu: how many rows a wheel notch scrolls
pub const bindNotch:f32=2;
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
  /// the world is frozen and the keybinds are listed (from the pause
  /// menu): an action clicked listens for its new key
  keybinds,
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
  pub fn live(md:Mode)bool{return md!=.paused and md!=.options and md!=.keybinds and md!=.gardens and md!=.naming;}
  /// the belly's slots are open: stacks are lifted and put down
  pub fn sorting(md:Mode)bool{return md==.belly or md==.structure;}
};
/// what a frame or a game's building may fail with: running out of memory
pub const Error=Allocator.Error;
test{
  _=game;
  _=frame;
  _=belly;
  _=menus;
  _=hearing;
  _=testsMenu;
  _=testsBelly;
  _=testsPlace;
}
