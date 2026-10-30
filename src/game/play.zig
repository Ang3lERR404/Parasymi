//! the playable layer: owns world + sim + progression + the player and runs a
//! frame: input -> actions (actions.zig), fixed-tick simulation, and what gets
//! drawn (view.zig). Nothing is pooled globally: items live in the player and
//! in structures, essence and seeds live in plants until harvested.
const lib = @import("../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const ck = lib.ck;
const items = lib.items;
const ctl = lib.controls;
const options = lib.options;
const save = lib.save;
pub const game = @import("play/game.zig");
pub const frame = @import("play/frame.zig");
pub const belly = @import("play/belly.zig");
pub const menus = @import("play/menus.zig");
pub const tests_menu = @import("play/tests_menu.zig");
pub const tests_belly = @import("play/tests_belly.zig");
pub const tests_place = @import("play/tests_place.zig");
pub const Game = game.Game;

pub const TICK = 1.0 / 60.0;
/// the test gardens' world (`--demo`, `--stress`, `--plant`/`--structure`,
/// tests); a played game grows from a fresh seed each start
pub const DEFAULT_SEED:u64 = 0x5EED_0F_11FE;
/// the window's size when it opens
pub const WINDOW = [2]u16{ 1600, 900 };
pub const STREAM_RADIUS = 4;
/// the chunks resident round the gardener once streamed (a square of rings)
pub const STREAM_CHUNKS = (2 * STREAM_RADIUS + 1) * (2 * STREAM_RADIUS + 1);
/// nothing is drawn further than this from the camera target (inside the
/// streamed radius, so a low camera never runs off the generated world)
pub const DRAW_LIMIT:f32 = (STREAM_RADIUS - 0.5) * ck.SIZE;

/// max chunks to stream in a single call (initial load is generous,
/// per-frame is tight to avoid hitches)
pub const STREAM_INIT = 1 << 10;
pub const STREAM_FRAME = 4;

/// camera feel parameters (tune here, not scattered through update)
pub const FOLLOW_LERP:f32 = 6;
/// the camera follows a point this far above the wolf's feet
pub const FOLLOW_HEIGHT:f32 = 0.6;
/// gathering, the wolf walks up to the node this eagerly (wish per metre
/// still to go)
pub const APPROACH:f32 = 2;
/// how quickly the shown frame and sim timings follow the measured ones
pub const TIMING_EASE:f32 = 0.05;
/// free camera: Shift multiplies the fly speed; the wheel dollies this much a notch
pub const FLY_FAST:f32 = 3;
pub const DOLLY_PER_NOTCH:f32 = 0.4;
/// first person: the wolf's head is hidden once the view comes this close
/// to its eyes (easing in, it is seen until then)
pub const HEAD_CLEAR:f32 = 0.3;

/// the simulation never runs more than this many catch-up ticks a frame
pub const MAX_CATCHUP = 8;
/// the spawn search spirals out to this radius in steps of this many tiles
pub const SPAWN_SEARCH = 400;
pub const SPAWN_STEP = 3;

/// ray-march parameters for ground picking
pub const PICK_STEP:f32 = 0.1;
pub const PICK_RANGE_MULT:f32 = 4;

/// hotbar slots, in `ctl.slots` order. Each is empty or holds an item the
/// gardener dropped on it from the belly; it shows how many the belly holds.
pub const BAR = ctl.slots.len;
/// UI time handed to HUD motion wraps after this many seconds
pub const UI_WRAP:f64 = 1000;

/// what the cursor carries (one click lifts, the next puts down): a belly
/// slot's stack, a hotbar slot's item, or a stack from a slot of the
/// structure whose panel is open. It stays where it was until put down, so
/// closing the panel or saving loses nothing.
pub const Held = union(enum) { slot:usize, bar:usize, store:usize };
/// a stack put down within one inventory goes as far as it fits
pub const STACK_ANY:u32 = 1 << 16;

/// can the gardener place this hotbar item yet (seed understood / always for bulbs)?
pub fn known(g:*const Game, item:items.Item) bool {
  return if (item.plants()) |sp| g.prog.canPlant(sp) else true;
}

/// what only main can do (it owns the window and the file system)
pub const Request = union(enum) {
  /// into the garden being played (`Game.slot`, which it has)
  save,
  /// back to the garden being played as last saved (else the newest)
  load,
  /// the autosave timer ran out: into `save.AUTO`
  autosave,
  /// the saved gardens menu wants its list (`Game.gardens`)
  list,
  /// the saved gardens menu or the name asked for: save as this garden
  save_as:save.Name,
  /// the saved gardens menu: replace the running game with the chosen one
  load_from:save.Name,
  /// the saved gardens menu: let the chosen garden go
  delete:save.Name,
  /// save and leave
  quit,
};

/// the pause menu's rows, in `txt.s.hud.pause_labels` order
pub const PauseRow = enum { @"resume", options, gardens, fullscreen, quit };
/// the saved gardens menu's buttons (under its list, and the chosen
/// garden's delete), and the name prompt's
pub const GardenAct = enum { save, load, delete, ok, cancel };
/// saved gardens menu: rows in view at once (it scrolls past them), rows a
/// wheel notch scrolls, and how fast the list follows (1/s)
pub const GARDENS_SHOWN = 7;
pub const GARDEN_NOTCH:f32 = 1;
pub const GARDEN_EASE:f32 = 14;

/// what has the wolf's attention; only one at a time.
pub const Mode = enum {
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
  pub fn live(md:Mode) bool { return md != .paused and md != .options and md != .gardens and md != .naming; }
  /// the belly's slots are open: stacks are lifted and put down
  pub fn sorting(md:Mode) bool { return md == .belly or md == .structure; }
};

pub const Error = Allocator.Error;

test {
  _ = game;
  _ = frame;
  _ = belly;
  _ = menus;
  _ = tests_menu;
  _ = tests_belly;
  _ = tests_place;
}
