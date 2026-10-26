//! the playable layer: owns world + sim + progression + the player and runs a
//! frame: input -> actions (actions.zig), fixed-tick simulation, and what gets
//! drawn (view.zig). Nothing is pooled globally: items live in the player and
//! in structures, essence and seeds live in plants until harvested.
const lib = @import("../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const eqlDeep = std.meta.eql;
const swap = std.mem.swap;
const bufPrint = std.fmt.bufPrint;
const engine = lib.engine;
const m = engine.core.math;
const Rng = engine.core.rng.Rng;
const ck = lib.ck;
const gen = lib.gen;
const World = lib.world.World;
const species = lib.species;
const Plants = lib.plants.Plants;
const ecology = lib.ecology;
const Ecology = ecology.Ecology;
const items = lib.items;
const prog = lib.progression;
const txt = lib.txt;
const Input = engine.platform.input.Input;
const ctl = lib.controls;
const camera = engine.render.camera;
const Camera = camera.Camera;
const renderer = lib.renderer;
const vertex = lib.vertex;
const Draw = engine.ui.draw.Draw;
const sky_mod = lib.sky;
const player_mod = lib.player;
const Player = player_mod.Player;
const Parts = lib.parts.Parts;
const craft = lib.craft;
const st = lib.structures;
const actions = lib.actions;
const convergence = lib.convergence;
const hud = lib.hud;
const options = lib.options;
const save = lib.save;
const Specimen = lib.specimen.Specimen;

pub const TICK = 1.0 / 60.0;
/// the test gardens' world (`--demo`, `--stress`, `--plant`/`--structure`,
/// tests); a played game grows from a fresh seed each start
pub const DEFAULT_SEED:u64 = 0x5EED_0F_11FE;
/// the window's size when it opens
pub const WINDOW = [2]u16{ 1600, 900 };
const STREAM_RADIUS = 4;
/// the chunks resident round the gardener once streamed (a square of rings)
pub const STREAM_CHUNKS = (2 * STREAM_RADIUS + 1) * (2 * STREAM_RADIUS + 1);
/// nothing is drawn further than this from the camera target (inside the
/// streamed radius, so a low camera never runs off the generated world)
pub const DRAW_LIMIT:f32 = (STREAM_RADIUS - 0.5) * ck.SIZE;

/// max chunks to stream in a single call (initial load is generous,
/// per-frame is tight to avoid hitches)
const STREAM_INIT = 1 << 10;
const STREAM_FRAME = 4;

/// camera feel parameters (tune here, not scattered through update)
const FOLLOW_LERP:f32 = 6;
/// the camera follows a point this far above the wolf's feet
const FOLLOW_HEIGHT:f32 = 0.6;
/// gathering, the wolf walks up to the node this eagerly (wish per metre
/// still to go)
const APPROACH:f32 = 2;
/// how quickly the shown frame and sim timings follow the measured ones
pub const TIMING_EASE:f32 = 0.05;
/// free camera: Shift multiplies the fly speed; the wheel dollies this much a notch
const FLY_FAST:f32 = 3;
const DOLLY_PER_NOTCH:f32 = 0.4;
/// first person: the wolf's head is hidden once the view comes this close
/// to its eyes (easing in, it is seen until then)
const HEAD_CLEAR:f32 = 0.3;

/// the simulation never runs more than this many catch-up ticks a frame
const MAX_CATCHUP = 8;
/// the spawn search spirals out to this radius in steps of this many tiles
const SPAWN_SEARCH = 400;
const SPAWN_STEP = 3;

/// ray-march parameters for ground picking
const PICK_STEP:f32 = 0.1;
const PICK_RANGE_MULT:f32 = 4;

/// hotbar slots, in `ctl.slots` order. Each is empty or holds an item the
/// gardener dropped on it from the belly; it shows how many the belly holds.
pub const BAR = ctl.slots.len;
/// UI time handed to HUD motion wraps after this many seconds
const UI_WRAP:f64 = 1000;

/// what the cursor carries (one click lifts, the next puts down): a belly
/// slot's stack, a hotbar slot's item, or a stack from a slot of the
/// structure whose panel is open. It stays where it was until put down, so
/// closing the panel or saving loses nothing.
pub const Held = union(enum) { slot:usize, bar:usize, store:usize };
/// a stack put down within one inventory goes as far as it fits
const STACK_ANY:u32 = 1 << 16;

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
const GARDEN_NOTCH:f32 = 1;
const GARDEN_EASE:f32 = 14;

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

const Error = Allocator.Error;

pub const Game = struct {
  gpa:Allocator,
  world:World,
  plants:Plants = .{},
  structs:st.Structures = .{},
  eco:Ecology = .{},
  /// the standing fields of celestial energy (halos), gathered each tick
  fields:std.ArrayList(ecology.Field) = .empty,
  converge:convergence.Seeker = .{},
  prog:prog.Progression = .{},
  cam:Camera = .{},
  sky:sky_mod.Sky = .{},
  stars:sky_mod.Starfall,
  player:Player,
  rng:Rng,
  parts:Parts,
  ui:Draw,
  /// what a click on the HUD would land on, as drawn last frame
  rows:hud.Rows = .{},
  /// the HUD area under the mouse this frame (panels show what it points at)
  pointed:?hud.Pick = null,
  sapling:hud.Sapling = .{},
  weave:craft.Crafter = .{},

  mode:Mode = .roam,
  /// something only main can do (it owns the window and the file system).
  request:?Request = null,
  /// the gardener's settings; main applies them when they change
  opts:options.Options = .{},
  /// the most MSAA samples the GPU takes (main sets it from the renderer)
  most_samples:u32 = 8,
  /// the garden being played, as saved (null until it is saved or loaded)
  slot:?save.Name = null,
  /// seconds played since the garden was last saved (autosave counts these)
  since_save:f64 = 0,
  /// the saved gardens menu: its list (main fills it on `.list`, at
  /// `listed_at` in UI time), the chosen row (0: a fresh garden, else
  /// `gardens[i - 1]`), whether saving over it (or letting it go) was
  /// asked once already, and the first row in view (wanted, and eased toward)
  gardens:std.ArrayList(save.Entry) = .empty,
  listed_at:f64 = 0,
  garden:usize = 0,
  overwrite:bool = false,
  deleting:bool = false,
  /// the name prompt: the name typed so far, and the mode it returns to
  typed:save.Name = .{},
  naming_from:Mode = .roam,
  garden_top:f32 = 0,
  garden_at:f32 = 0,
  /// the list's scroll groove is held (dragged)
  scrolling:bool = false,
  /// keeps running while paused, so the UI still breathes.
  ui_time:f64 = 0,

  /// the hotbar's items and the selected slot
  bar:[BAR]?items.Item = @splat(null),
  hot:usize = 0,
  held:?Held = null,
  /// the tile of the structure whose panel is open (mode `.structure`); a
  /// tile, not an id, since ids move when a structure is removed
  open:[2]i32 = .{0, 0},
  /// the cursor, in screen pixels (tooltips and what is carried follow it);
  /// looking out of the wolf's eyes, the middle of the screen
  mouse:[2]f32 = .{0, 0},
  /// the window holds the cursor for looking out of the wolf's eyes; the
  /// frame it is taken its jump is not a look
  looking:bool = false,
  /// a click spent putting down or dropping what was carried does nothing
  /// in the garden until the button is let go
  use_spent:bool = false,
  /// facing for the next thing put down (R turns it while nothing is under
  /// the cursor; picking a seed takes the picked thing's)
  place_dir:m.Dir = 0,
  /// remove, held: the tile last removed from (it is not removed from
  /// again until the cursor leaves it) and the wait before the next
  removed:?[2]i32 = null,
  remove_cd:f32 = 0,
  debug:bool = false,
  hover:?[2]i32 = null,
  /// progress of the current gather, and a short linger for one-off gestures
  gather_t:f32 = 0,
  linger:f32 = 0,
  plant_cd:f32 = 0,
  full_warned:bool = false,

  time:f64 = 0,
  acc:f64 = 0,
  sim_ms:f32 = 0,
  frame_ms:f32 = 16,
  ticks:u64 = 0,
  inst:[renderer.PLANT_MESHES]std.ArrayList(vertex.PlantInstance) = @splat(.empty),
  far:std.ArrayList(*ck.Chunk) = .empty,
  render_stats:renderer.Stats = .{},
  /// `--plant`/`--structure`: one thing alone, its state set by hand (see
  /// specimen.zig); nothing else falls, grows or is drawn
  specimen:?Specimen = null,

  pub fn init(gpa:Allocator, seed:u64) Error!Game {
    var g:Game = .{
      .gpa = gpa,
      .world = World.init(gpa, seed),
      .rng = Rng.init(seed ^ 0xA11CE),
      .stars = .{ .rng = Rng.init(seed ^ 0x57A2) },
      .player = .{ .pos = m.v3(0.5, 0, 0.5) },
      .parts = Parts.init(gpa),
      .ui = .{ .gpa = gpa },
    };
    errdefer g.deinit();
    // start on dry land: spiral out from the origin until a fertile tile shows up.
    var r:i32 = 0;
    find: while (r < SPAWN_SEARCH) : (r += SPAWN_STEP) {
      var a:i32 = -r;
      while (a <= r) : (a += SPAWN_STEP) {
        const z = r - @divFloor(r, 2);
        const s = gen.sample(seed, a, z);
        if (s.kind.fertile()) {
          g.player.pos = m.tileCentre(a, z, s.height);
          break :find;
        }
      }
    }
    g.cam.target = g.player.pos;
    try g.world.stream(g.focus(), STREAM_RADIUS, STREAM_INIT);
    g.prog.say(txt.s.msg.wake, .{});
    g.prog.say(txt.s.msg.night_hint, .{});
    return g;
  }

  pub fn deinit(g:*Game) void {
    g.gardens.deinit(g.gpa);
    for (&g.inst) |*l| l.deinit(g.gpa);
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

  pub fn focus(g:*const Game) ck.Coord {
    const t = m.tileAt(g.player.pos);
    return ck.Coord.ofTile(t[0], t[1]);
  }

  pub fn heightAt(g:*const Game, wx:i32, wy:i32) f32 {
    if (g.world.chunkOfTile(wx, wy)) |c| return c.height[ck.localIndex(wx, wy)];
    return gen.heightAt(g.world.seed, wx, wy);
  }

  /// march the ray through the cursor until it dips below the terraced ground.
  fn pick(g:*const Game, cursor:[2]f32, screen:[2]f32) ?[2]i32 {
    const ray = g.cam.ray(cursor[0], cursor[1], screen[0], screen[1]);
    var t:f32 = 0;
    const max_t = g.cam.dist * PICK_RANGE_MULT;
    while (t < max_t) : (t += PICK_STEP) {
      const p = ray.o + ray.d * m.splat3(t);
      const tile = m.tileAt(p);
      if (p[1] <= g.heightAt(tile[0], tile[1])) return tile;
    }
    return null;
  }

  pub fn update(g:*Game, in:*const Input, dt:f32, screen:[2]f32) Error!void {
    g.ui_time += dt;
    g.frame_ms += (dt * m.MS_PER_S - g.frame_ms) * TIMING_EASE;
    g.cam.aspect = screen[0] / @max(screen[1], 1);

    // system keys work everywhere; Esc closes a panel first, then pauses
    // (not while a name is typed, nor for a garden that has none yet: a
    // name is asked for first)
    if (g.mode != .naming) {
      if (ctl.pressed(in, .save)) if (g.slot != null) { g.request = .save; } else g.startNaming();
      if (ctl.pressed(in, .load)) g.request = .load;
    }
    if (ctl.pressed(in, .fullscreen)) g.opts.fullscreen = !g.opts.fullscreen;
    if (ctl.pressed(in, .back)) switch (g.mode) {
      .roam => g.mode = .paused,
      .belly, .structure, .research, .paused => g.mode = .roam,
      .options, .gardens => g.mode = .paused,
      .naming => g.mode = g.naming_from,
      .inspect => g.inspect(in, false),
    } else if (!g.mode.live()) g.menu(in, dt);
    if (!g.mode.live()) {
      // (the frozen world's menus give back a cursor held for looking)
      if (g.looking) in.capture(false);
      g.looking = false;
      return;
    }

    g.time += dt;
    // the garden saves itself every so often (only time played counts)
    g.since_save += dt;
    if (g.opts.autosave > 0 and g.since_save >= m.f(g.opts.autosave) * m.S_PER_MIN and g.request == null) {
      g.request = .autosave;
      g.since_save = 0;
    }
    g.sky.update(dt);

    // decision: alt + free_cam (Ctrl+F) toggles the free inspection camera
    // (harvest alone, F, harvests)
    const alt = ctl.down(in, .alt);
    if (alt and ctl.pressed(in, .free_cam)) g.inspect(in, g.mode != .inspect);
    const inspecting = g.mode == .inspect;
    g.cam.tick(dt);

    // out of the wolf's eyes, the mouse looks round while nothing else wants
    // the cursor; what is used is what the middle of the screen is on
    const looking = g.cam.inEyes() and g.mode == .roam;
    if (looking != g.looking) {
      in.capture(looking);
      g.looking = looking;
    } else if (looking) g.cam.look(in.mouse_delta);
    const cursor = if (looking) [2]f32{screen[0] / 2, screen[1] / 2} else in.mouse;

    // panels and selection
    if (!inspecting) {
      if (ctl.pressed(in, .belly)) g.mode = if (g.mode == .belly) .roam else .belly;
      if (ctl.pressed(in, .research)) g.mode = if (g.mode == .research) .roam else .research;
    }
    if (ctl.pressed(in, .debug)) g.debug = !g.debug;
    // slot keys pick the hotbar slot, whichever panel is open
    if (!inspecting) for (ctl.slots, 0..) |a, i| {
      if (ctl.pressed(in, a)) g.hot = i;
    };

    // a click lands on the HUD panel under the mouse before the world: rows
    // choose research, weave a recipe, lift or put down an item; a panel's
    // backdrop just absorbs it
    g.mouse = cursor;
    // a structure's panel closes once it is gone or out of reach
    if (g.mode == .structure and g.opened() == null) g.mode = .roam;
    if (!g.mode.sorting()) g.held = null;
    if (g.held) |h| switch (h) {
      .slot => |i| if (g.player.inv.slot[i] == null) { g.held = null; },
      .bar => |i| if (g.bar[i] == null) { g.held = null; },
      .store => |i| if (g.storeSlot(i) == null) { g.held = null; },
    };
    const ui_hit = if (inspecting or looking) null else g.rows.at(cursor);
    g.pointed = ui_hit;
    if (!ctl.down(in, .use)) g.use_spent = false;
    if (ctl.pressed(in, .use)) {
      // held with use: a stack moves straight across to the other side
      const across = ctl.down(in, .take) and g.held == null and g.mode == .structure;
      if (ui_hit) |hit| switch (hit) {
        .panel, .research, .weave, .recipe => if (g.held != null) g.drop() else switch (hit) {
          .research => |id| g.prog.select(id),
          .weave => |i| actions.weaveByHand(g, i),
          .recipe => |r| if (g.opened()) |j| st.choose(g.structs.get(j), &g.prog, r),
          else => {},
        },
        .slot => |i| if (across) g.moveAcross(.{.slot = i}) else g.clickSlot(i),
        .store => |i| if (across) g.moveAcross(.{.store = i}) else g.clickStore(i),
        .bar => |i| if (g.mode.sorting()) g.clickBar(i) else { g.hot = i; },
        // drawn only while the world is frozen (see `menu`)
        .pause, .option, .back, .garden, .garden_act, .scroll => {},
      } else if (g.held != null) {
        g.drop();
        g.use_spent = true;
      }
    }
    if (ctl.pressed(in, .remove)) if (ui_hit) |hit| switch (hit) {
      .bar => |i| g.bar[i] = null,
      .panel, .research, .weave, .slot, .store, .recipe, .pause, .option, .back, .garden, .garden_act, .scroll => {},
    };
    if (ctl.pressed(in, .discard) and g.mode.sorting()) g.discard(ui_hit);

    // movement relative to the camera
    var mx:f32 = 0;
    var mz:f32 = 0;
    if (inspecting) {
      g.fly(in, dt);
    } else {
      if (ctl.down(in, .move_left)) mx -= 1;
      if (ctl.down(in, .move_right)) mx += 1;
      if (ctl.down(in, .move_forward)) mz += 1;
      if (ctl.down(in, .move_back)) mz -= 1;
    }
    const yaw = g.cam.yaw;
    var wish = [2]f32{@cos(yaw) * mx - @sin(yaw) * mz, -@sin(yaw) * mx - @cos(yaw) * mz};
    const wl = @sqrt(wish[0] * wish[0] + wish[1] * wish[1]);
    if (wl > 1) wish = .{ wish[0] / wl, wish[1] / wl };

    // the camera orbits round the wolf while dragged; the wheel zooms, all
    // the way in into its eyes
    if (!inspecting) {
      if (ctl.down(in, .orbit) and !g.cam.inEyes()) g.cam.orbit(in.mouse_delta);
      if (in.scroll != 0) g.cam.zoom(in.scroll, g.player.eyes());
    }

    // interaction with the hovered tile (none while inspecting)
    g.hover = if (inspecting) null else g.pick(cursor, screen);
    var working = false;
    var gathering = false;
    var work:?m.V3 = null;
    g.plant_cd -= dt;
    g.remove_cd -= dt;
    g.linger -= dt;
    const removing = ctl.down(in, .remove) and ui_hit == null;
    if (!removing) {
      g.gather_t = 0;
      g.full_warned = false;
      g.removed = null;
    }
    const near = if (g.hover) |h| g.player.inReach(h[0], h[1]) else false;
    // R turns what is under the cursor (within reach), else the next thing
    // put down; held with counter, the other way
    if (ctl.pressed(in, .rotate) and !inspecting) {
      const back = ctl.down(in, .counter);
      const turned = if (g.hover) |h| near and actions.turnAt(g, h, back) else false;
      if (!turned) g.place_dir +%= @as(m.Dir, if (back) 3 else 1);
    }
    if (g.hover) |h| if (near) if (g.world.chunkOfTile(h[0], h[1])) |c| {
      const t = ck.localIndex(h[0], h[1]);
      // what floats over a tile is reached first (it is drawn over what is under it)
      const on_struct = g.structs.at(&g.world, h[0], h[1]);
      const on_plant = if (on_struct == null) g.plants.at(&g.world, h[0], h[1]) else null;
      const using = ui_hit == null and !g.use_spent;
      // held, use puts what is in hand down wherever it fits as the cursor
      // sweeps; where it does not, a click interacts with a structure or
      // harvests a plant (so does interact, always)
      if (using and ctl.down(in, .use) and actions.canPut(g, h)) {
        if (g.plant_cd <= 0) try actions.put(g, h);
      } else if ((using and ctl.pressed(in, .use)) or ctl.pressed(in, .interact)) {
        if (on_struct) |j| {
          actions.interact(g, h, j);
          g.use_spent = ctl.down(in, .use);
        } else if (on_plant != null) actions.harvest(g, h);
      }
      if (ctl.pressed(in, .pick)) _ = actions.pick(g, h);
      if (ctl.pressed(in, .harvest) and !alt) {
        if (on_struct) |j| {
          if (ctl.down(in, .take)) actions.takeFrom(g, j) else actions.feed(g, j);
        } else actions.harvest(g, h);
      }
      if (ctl.pressed(in, .configure)) if (on_struct) |j| st.configure(&g.structs, j, &g.prog);
      // remove, pressed or held: what stands goes (one tile at a time as
      // the cursor sweeps), a resource node is gathered from
      if (removing) {
        if (on_struct != null or on_plant != null) {
          const fresh = if (g.removed) |r| r[0] != h[0] or r[1] != h[1] else true;
          if (ctl.pressed(in, .remove) or (fresh and g.remove_cd <= 0)) {
            if (on_struct) |j| actions.unbuild(g, j) else actions.uproot(g, h);
            g.removed = h;
            g.remove_cd = actions.REMOVE_COOLDOWN;
            g.linger = actions.LINGER_PUT;
          }
        } else if (c.res[t] > 0 and c.occ[t] == .none) {
          working = actions.gather(g, c, t, dt);
          gathering = working;
        }
      }
      if (working or g.linger > 0) work = m.tileCentre(h[0], h[1], c.height[t]);
    };
    // weaving: hands work at the chest while the queue runs
    if (g.weave.tick(g.player.inv.bag(), dt)) |made| g.prog.say(txt.s.msg.wove, .{txt.item(made).name});
    if (g.weave.busy() and !working) work = g.player.pos + m.v3(@sin(g.player.facing), 0, @cos(g.player.facing));
    // a one-off gesture keeps facing where it happened
    if (work == null and g.linger > 0) work = g.player.work;
    g.player.work = work;
    g.player.gather = if (gathering) m.clamp01(g.gather_t / actions.GATHER_TIME) else null;
    // decision: gathering with no move held, the wolf steps up to the node
    // until its paws can grip it (it crouches and pries it by hand)
    if (gathering and wish[0] == 0 and wish[1] == 0) if (work) |at| {
      const dx = at[0] - g.player.pos[0];
      const dz = at[2] - g.player.pos[2];
      const d = @sqrt(dx * dx + dz * dz);
      const go = m.clamp01((d - player_mod.GATHER_AT) * APPROACH);
      if (d > 1e-3) wish = .{ dx / d * go, dz / d * go };
    };

    // out of its eyes, the wolf turns to face where they look
    // (the camera's yaw looks down -z turned, the wolf's facing down +z)
    g.player.aim = if (g.cam.inEyes()) g.cam.yaw + m.pi else null;
    g.player.gaze = if (g.cam.inEyes()) g.cam.gaze() else null;
    g.player.move(wish, ctl.down(in, .run), &g.world, dt);
    g.player.animate(&g.world, dt);
    g.cam.see(g.player.eyes());
    const follow = g.player.pos + m.v3(0, FOLLOW_HEIGHT, 0);
    g.cam.target += (follow - g.cam.target) * m.splat3(@min(1, dt * FOLLOW_LERP));

    if (g.specimen == null) {
      try g.stars.update(g.gpa, &g.sky, g.player.pos, &g.world, dt);
      actions.catchStarlight(g, dt);
    }

    // stream the world around the player; chunks holding what we grew stay
    try g.world.stream(g.focus(), STREAM_RADIUS, STREAM_FRAME);
    try g.world.far(g.focus(), STREAM_RADIUS, &g.far);
    for (g.far.items) |c| try g.world.unload(c);
  }

  /// the view is in the wolf's eyes: its head is not drawn (its shadow is)
  pub fn headless(g:*const Game) bool {
    return switch (g.cam.view) {
      .eyes => |y| m.len(g.cam.viewEye() - y.pos) < HEAD_CLEAR,
      .follow, .free, .returning => false,
    };
  }

  /// is the cursor carrying `h`?
  pub fn holds(g:*const Game, h:Held) bool { return if (g.held) |x| eqlDeep(x, h) else false; }
  /// is the mouse over `p`?
  pub fn points(g:*const Game, p:hud.Pick) bool { return if (g.pointed) |x| eqlDeep(x, p) else false; }
  /// UI seconds, kept small enough for f32 sway and pulses.
  pub fn uiT(g:*const Game) f32 { return @floatCast(@mod(g.ui_time, UI_WRAP)); }

  /// the selected hotbar slot's item, if it holds one.
  pub fn selected(g:*const Game) ?items.Item { return g.bar[g.hot]; }

  /// what the cursor carries, if anything.
  pub fn carried(g:*const Game) ?items.Item { return if (g.held) |h| g.itemOf(h) else null; }

  /// the item a slot holds.
  fn itemOf(g:*const Game, h:Held) ?items.Item {
    return switch (h) {
      .slot => |i| if (g.player.inv.slot[i]) |s| s.item else null,
      .bar => |i| g.bar[i],
      .store => |i| if (g.storeSlot(i)) |s| s.item else null,
    };
  }

  /// the structure whose panel is open, while it stands within reach.
  pub fn opened(g:*const Game) ?st.Id {
    if (g.mode != .structure or !g.player.inReach(g.open[0], g.open[1])) return null;
    return g.structs.touched(&g.world, g.open[0], g.open[1]);
  }

  /// slot `i` of the open structure, if it holds a stack.
  pub fn storeSlot(g:*const Game, i:usize) ?items.Stack {
    const j = g.opened() orelse return null;
    return g.structs.list.items[j.idx()].inv.slot[i];
  }

  /// a click on belly slot `i`: lift its stack, or put down what is carried
  /// there (`putDown`). A hotbar item carried off its slot is taken off the
  /// hotbar. A structure's stack trades places only with one it would take.
  fn clickSlot(g:*Game, i:usize) void {
    const slot = &g.player.inv.slot;
    const h = g.held orelse {
      if (slot[i] != null) g.held = .{.slot = i};
      return;
    };
    g.held = null;
    switch (h) {
      .bar => |j| g.bar[j] = null,
      .slot => |j| if (j != i and putDown(&slot[j], &slot[i], STACK_ANY, true)) { g.held = h; },
      .store => |j| {
        const id = g.opened() orelse return;
        const there = if (slot[i]) |s| g.structs.wants(&g.prog, id, s.item) >= s.n else true;
        if (putDown(&g.structs.get(id).inv.slot[j], &slot[i], STACK_ANY, there)) g.held = h;
      },
    }
  }

  /// a click on slot `i` of the open structure: lift its stack, or put down
  /// what is carried there, as much of it as the structure will take (it
  /// trades places only when it takes the whole stack). A hotbar item is
  /// just put down.
  fn clickStore(g:*Game, i:usize) void {
    const id = g.opened() orelse return;
    const slot = &g.structs.get(id).inv.slot;
    const h = g.held orelse {
      if (slot[i] != null) g.held = .{.store = i};
      return;
    };
    g.held = null;
    switch (h) {
      .bar => |j| g.bar[j] = null,
      .store => |j| if (j != i and putDown(&slot[j], &slot[i], STACK_ANY, true)) { g.held = h; },
      .slot => |j| {
        const from = &g.player.inv.slot[j];
        const room = if (from.*) |s| g.structs.wants(&g.prog, id, s.item) else 0;
        if (putDown(from, &slot[i], room, room >= from.*.?.n)) g.held = h;
      },
    }
  }

  /// a click on hotbar slot `i`: put what is carried there (a stack
  /// assigns its item, a hotbar item trades places), or lift its item.
  fn clickBar(g:*Game, i:usize) void {
    const h = g.held orelse {
      if (g.bar[i] != null) g.held = .{.bar = i};
      return;
    };
    g.held = null;
    switch (h) {
      .slot, .store => g.bar[i] = g.itemOf(h) orelse g.bar[i],
      .bar => |j| swap(?items.Item, &g.bar[i], &g.bar[j]),
    }
  }

  /// put down what is carried anywhere but a slot: a stack goes back where
  /// it was, a hotbar item comes off the hotbar.
  fn drop(g:*Game) void {
    const h = g.held orelse return;
    g.held = null;
    switch (h) {
      .slot, .store => {},
      .bar => |i| g.bar[i] = null,
    }
  }

  /// throw away a belly stack for good: the one carried, else the one under
  /// the cursor. Only the belly's: a structure's slots and the hotbar keep theirs.
  fn discard(g:*Game, hit:?hud.Pick) void {
    const i = if (g.held) |h| switch (h) {
      .slot => |j| j,
      .bar, .store => return,
    } else if (hit) |p| switch (p) {
      .slot => |j| j,
      .panel, .research, .weave, .bar, .store, .recipe, .pause, .option, .back, .garden, .garden_act, .scroll => return,
    } else return;
    const s = g.player.inv.slot[i] orelse return;
    g.player.inv.slot[i] = null;
    g.held = null;
    g.prog.say(txt.s.msg.discarded, .{s.n, txt.item(s.item).name});
  }

  /// move a whole stack straight across, belly to the open structure (as
  /// much as it will take) or back (as much as fits).
  fn moveAcross(g:*Game, from:Held) void {
    const id = g.opened() orelse return;
    switch (from) {
      .slot => |i| if (g.player.inv.slot[i]) |*s| {
        s.n -= g.structs.insert(&g.prog, id, s.item, s.n);
        if (s.n == 0) g.player.inv.slot[i] = null;
      },
      .store => |i| if (g.structs.get(id).inv.slot[i]) |*s| {
        s.n -= g.player.inv.add(s.item, s.n);
        if (s.n == 0) g.structs.get(id).inv.slot[i] = null
        else g.prog.say(txt.s.msg.belly_full, .{});
      },
      .bar => {},
    }
  }

  /// put the carried stack `from` down on `to`: into an empty slot or onto
  /// the same item, as much as fits and `cap` allows; else the two trade
  /// places if `trade`. Returns whether some of it is still in hand.
  fn putDown(from:*?items.Stack, to:*?items.Stack, cap:u32, trade:bool) bool {
    const f = if (from.*) |*p| p else return false;
    var room:u32 = items.STACK;
    if (to.*) |t| {
      if (t.item != f.item) {
        if (trade) swap(?items.Stack, from, to);
        return !trade;
      }
      room -|= t.n;
    }
    const k:u16 = @intCast(@min(f.n, room, cap));
    if (k == 0) return true;
    if (to.*) |*t| t.n += k else to.* = .{.item = f.item, .n = k};
    f.n -= k;
    if (f.n > 0) return true;
    from.* = null;
    return false;
  }

  /// the pause menu and the panels opened from it, while the world is
  /// frozen: a click on a pause row does what it says; on an option it
  /// turns it (the other button turns it back); in the saved gardens it
  /// chooses a garden, or saves or loads it. Keys still work for the pause
  /// rows.
  fn menu(g:*Game, in:*const Input, dt:f32) void {
    g.mouse = in.mouse;
    const hit = g.rows.at(in.mouse);
    g.pointed = hit;
    if (g.mode == .paused) {
      if (ctl.pressed(in, .quit)) g.request = .quit;
      if (ctl.pressed(in, .options)) g.mode = .options;
      if (ctl.pressed(in, .gardens)) g.openGardens();
    }
    if (g.mode == .gardens) g.scroll(in, hit, dt);
    if (g.mode == .naming) g.typeName(in);
    const dir:i32 = if (ctl.pressed(in, .use)) 1 else if (ctl.pressed(in, .remove)) -1 else 0;
    if (dir == 0) return;
    switch (hit orelse return) {
      .pause => |row| if (dir > 0) g.choose(row),
      .option => |set| options.step(&g.opts, set, dir, g.most_samples),
      .back => if (dir > 0) { g.mode = .paused; },
      .garden => |i| if (dir > 0 and i != g.garden) {
        g.garden = i;
        g.overwrite = false;
        g.deleting = false;
      },
      .garden_act => |a| if (dir > 0) g.gardenAct(a),
      // the world's own rows, not the menus'
      .panel, .research, .weave, .slot, .bar, .store, .recipe, .scroll => {},
    }
  }

  fn choose(g:*Game, row:PauseRow) void {
    switch (row) {
      .@"resume" => g.mode = .roam,
      .options => g.mode = .options,
      .gardens => g.openGardens(),
      .fullscreen => g.opts.fullscreen = !g.opts.fullscreen,
      .quit => g.request = .quit,
    }
  }

  /// the saved gardens menu opens on a fresh list, the played garden chosen
  fn openGardens(g:*Game) void {
    g.mode = .gardens;
    g.request = .list;
    g.garden = 0;
    g.overwrite = false;
    g.deleting = false;
    g.garden_top = 0;
    g.garden_at = 0;
  }

  /// main has just listed the gardens (`gardens`): the played one is
  /// chosen (else the choice is kept in range) and scrolled into view.
  pub fn listed(g:*Game) void {
    g.listed_at = g.ui_time;
    g.overwrite = false;
    g.deleting = false;
    if (g.slot) |n| for (g.gardens.items, 1..) |e, i| if (e.name.is(n.slice())) { g.garden = i; };
    g.garden = @min(g.garden, g.gardens.items.len);
    const first = @max(m.f(g.garden) - m.f(GARDENS_SHOWN - 1), 0);
    g.garden_top = @min(m.clamp(g.garden_top, first, m.f(g.garden)), g.gardenScroll());
  }

  /// how far the gardens list scrolls (rows above the first in view)
  fn gardenScroll(g:*const Game) f32 {
    return m.f((g.gardens.items.len + 1) -| GARDENS_SHOWN);
  }

  /// the wheel scrolls the gardens list; its groove, held, drags it
  fn scroll(g:*Game, in:*const Input, hit:?hud.Pick, dt:f32) void {
    const most = g.gardenScroll();
    g.garden_top -= in.scroll * GARDEN_NOTCH;
    if (!ctl.down(in, .use)) g.scrolling = false;
    if (ctl.pressed(in, .use)) if (hit) |h| if (h == .scroll) { g.scrolling = true; };
    if (g.scrolling) if (g.rows.find(.scroll)) |r| {
      g.garden_top = m.clamp((in.mouse[1] - r[1]) / r[3], 0, 1) * most;
    };
    g.garden_top = m.clamp(g.garden_top, 0, most);
    g.garden_at += (g.garden_top - g.garden_at) * @min(1, dt * GARDEN_EASE);
  }

  /// SAVE: a fresh garden asks for its name; over a saved one only when
  /// asked twice. LOAD: the chosen saved garden. DELETE: the chosen one,
  /// when asked twice. OK and CANCEL: the name prompt's.
  fn gardenAct(g:*Game, a:GardenAct) void {
    const chosen:?save.Name = if (g.garden == 0) null else g.gardens.items[g.garden - 1].name;
    switch (a) {
      .save => if (chosen) |n| {
        if (g.overwrite) g.request = .{.save_as = n};
        g.overwrite = !g.overwrite;
      } else g.startNaming(),
      .load => if (chosen) |n| { g.request = .{.load_from = n}; },
      .delete => if (chosen) |n| {
        if (g.deleting) g.request = .{.delete = n};
        g.deleting = !g.deleting;
      },
      .ok => g.nameChosen(),
      .cancel => g.mode = g.naming_from,
    }
  }

  /// ask for the name of the garden about to be saved (over the mode it
  /// returns to); the gardens are listed, to know the names taken
  fn startNaming(g:*Game) void {
    g.naming_from = if (g.mode == .naming) g.naming_from else g.mode;
    g.mode = .naming;
    g.typed = .{};
    g.overwrite = false;
    g.request = .list;
  }

  /// the name prompt: typing adds to the name, erase takes back, confirm
  /// is OK
  fn typeName(g:*Game, in:*const Input) void {
    const was = g.typed.len;
    for (in.typed()) |c| g.typed.put(c);
    if (ctl.pressed(in, .erase)) g.typed.erase();
    if (g.typed.len != was) g.overwrite = false;
    if (ctl.pressed(in, .confirm)) g.nameChosen();
  }

  /// the garden typed is taken
  pub fn nameTaken(g:*const Game) bool {
    const n = g.typed.typed() orelse return false;
    for (g.gardens.items) |e| if (e.name.same(n)) return true;
    return false;
  }

  /// OK: save as the name typed (over a garden of that name only when
  /// asked twice); a name that cannot be one does nothing
  fn nameChosen(g:*Game) void {
    const n = g.typed.typed() orelse return;
    if (g.nameTaken() and !g.overwrite) {
      g.overwrite = true;
      return;
    }
    g.overwrite = false;
    g.mode = g.naming_from;
    g.request = .{.save_as = n};
  }

  /// enter or leave the free camera. Leaving gives the cursor back and eases
  /// the view home.
  fn inspect(g:*Game, in:*const Input, on:bool) void {
    if (on) {
      g.mode = .inspect;
      g.cam.startFree();
      return;
    }
    g.mode = .roam;
    if (g.cam.view == .free and g.cam.view.free.captured) in.capture(false);
    g.cam.endFree();
  }

  /// the free camera: click to hold the cursor and look around, WASD to fly
  /// (Shift faster), Q/E to roll, the wheel to dolly. Space and Ctrl+Space
  /// rise and sink.
  fn fly(g:*Game, in:*const Input, dt:f32) void {
    const f = switch (g.cam.view) {
      .free => |*f| f,
      .follow, .returning, .eyes => return,
    };
    // the frame the cursor is taken its jump is not a look
    var look:[2]f32 = .{ 0, 0 };
    if (ctl.pressed(in, .use) and !f.captured) {
      in.capture(true);
      f.captured = true;
    } else if (f.captured or ctl.down(in, .use)) {
      look = .{ -in.mouse_delta[0] * camera.LOOK, -in.mouse_delta[1] * camera.LOOK };
    }
    const speed = camera.FLY * dt * @as(f32, if (ctl.down(in, .fly_fast)) FLY_FAST else 1);
    var move = m.v3(0, 0, 0);
    if (ctl.down(in, .move_forward)) move[2] += speed;
    if (ctl.down(in, .move_back)) move[2] -= speed;
    if (ctl.down(in, .move_right)) move[0] += speed;
    if (ctl.down(in, .move_left)) move[0] -= speed;
    if (ctl.down(in, .rise)) move[1] += if (ctl.down(in, .alt)) -speed else speed;
    var roll:f32 = 0;
    if (ctl.down(in, .roll_left)) roll -= camera.ROLL * dt;
    if (ctl.down(in, .roll_right)) roll += camera.ROLL * dt;
    g.cam.fly(look, move, roll, in.scroll * DOLLY_PER_NOTCH);
  }

  /// what structures' behaviour may touch, the wolf and the sky with the
  /// garden, and what befell it this tick (`ev`)
  pub fn structCtx(g:*Game, ev:lib.ecology.Events) st.Ctx {
    return .{ .gpa = g.gpa, .w = &g.world, .plants = &g.plants, .g = &g.prog, .ss = &g.structs, .player = &g.player, .sky = &g.sky, .events = ev };
  }

  /// fixed-step simulation; never more than `MAX_CATCHUP` ticks per frame.
  pub fn simulate(g:*Game, frame_dt:f64) Error!void {
    if (!g.mode.live()) return;
    g.acc = @min(g.acc + frame_dt, TICK * MAX_CATCHUP);
    while (g.acc >= TICK) : (g.acc -= TICK) try g.step();
  }

  /// one fixed tick of everything that lives: ecology, convergence,
  /// progression, structures.
  /// (see the test below for the headless harness)
  pub fn step(g:*Game) Error!void {
    if (g.specimen) |*sp| if (try sp.hold(g, TICK)) {
      g.ticks += 1;
      return;
    };
    var mods = g.prog.mods();
    mods.night = 1 - g.sky.daylight();
    try st.fields(&g.structs, g.gpa, &g.fields);
    mods.fields = g.fields.items;
    const ev = try g.eco.tick(g.gpa, &g.plants, &g.world, mods, TICK);
    try g.converge.tick(g.gpa, &g.world, &g.plants, &g.structs, &g.prog);
    g.prog.absorb(ev, TICK);
    try st.Structures.tickWith(g.structCtx(ev), TICK);
    if (g.specimen) |*sp| try sp.after(g, TICK);
    g.ticks += 1;
  }
};

/// tests draw to a window of the default size
const TEST_SCREEN = [2]f32{ m.f(WINDOW[0]), m.f(WINDOW[1]) };

test "the wolf stays put without input" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  try lib.setups.demo(&g, 5);
  var in:Input = .{ .win = undefined };
  in.mouse = .{ -1e4, -1e4 };
  const start = g.player.pos;
  for (0..300) |_| {
    try g.update(&in, TICK, TEST_SCREEN);
    try g.simulate(TICK);
  }
  try testing.expectApproxEqAbs(start[0], g.player.pos[0], 0.05);
  try testing.expectApproxEqAbs(start[2], g.player.pos[2], 0.05);
}
/// headless clicks on the HUD
const click = struct {
  /// press the left button over the middle of the first row picking `want`
  fn on(gg:*Game, i:*Input, want:hud.Pick, sc:[2]f32) !void { return press(gg, i, want, sc, .use); }

  /// press `a` with the mouse over the middle of the first row picking `want`
  fn press(gg:*Game, i:*Input, want:hud.Pick, sc:[2]f32, a:ctl.Action) !void {
    try hud.build(gg, sc);
    for (gg.rows.rect[0..gg.rows.len], gg.rows.pick[0..gg.rows.len]) |q, p| {
      if (!eqlDeep(p, want)) continue;
      i.mouse = .{q[0] + q[2] / 2, q[1] + q[3] / 2};
      i.advance();
      ctl.hold(i, a, true);
      try gg.update(i, TICK, sc);
      i.advance();
      ctl.hold(i, a, false);
      return;
    }
    return error.TestUnexpectedResult;
  }
};

test "clicking a research node or weave recipe picks it; number keys only pick the hotbar" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  const screen = TEST_SCREEN;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};

  g.mode = .research;
  try click.on(&g, &in, .{.research = .ley_sight}, screen);
  try testing.expect(g.prog.current == .ley_sight);

  g.mode = .belly;
  _ = g.player.inv.add(.fibre, 2);
  _ = g.player.inv.add(.grit, 1);
  try testing.expect(craft.hand[craft.by_hand[0]].out == .conduit);
  try click.on(&g, &in, .{.weave = craft.by_hand[0]}, screen);
  try testing.expect(g.weave.busy());

  // with the belly open, a slot key picks the hotbar slot, not a recipe
  in.mouse = .{-1e4, -1e4};
  in.advance();
  ctl.hold(&in, .slot_3, true);
  try g.update(&in, TICK, screen);
  try testing.expectEqual(@as(usize, 2), g.hot);
  try testing.expectEqual(@as(usize, 1), g.weave.len);
}

test "the pause menu opens the options; clicks turn them and lead back" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  const screen = TEST_SCREEN;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  g.opts = .{.aa = .off};

  g.mode = .paused;
  try click.on(&g, &in, .{.pause = .options}, screen);
  try testing.expectEqual(Mode.options, g.mode);
  try click.on(&g, &in, .{.option = .antialias}, screen);
  try testing.expectEqual(renderer.Antialias.fxaa, g.opts.aa);
  try click.on(&g, &in, .{.option = .vsync}, screen);
  try testing.expect(!g.opts.vsync);
  try click.on(&g, &in, .back, screen);
  try testing.expectEqual(Mode.paused, g.mode);
  try click.on(&g, &in, .{.pause = .@"resume"}, screen);
  try testing.expectEqual(Mode.roam, g.mode);
  // nothing moved while frozen
  try testing.expectEqual(@as(u64, 0), g.ticks);
}

test "the saved gardens scroll, save over one or delete it only when asked twice, and load" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  const screen = TEST_SCREEN;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};

  g.mode = .paused;
  try click.on(&g, &in, .{.pause = .gardens}, screen);
  try testing.expectEqual(Mode.gardens, g.mode);
  try testing.expect(g.request.? == .list);
  g.request = null;
  // main lists them: more than fit, so the list scrolls
  for (0..GARDENS_SHOWN + 3) |i| {
    var buf:[16]u8 = undefined;
    try g.gardens.append(gpa, .{.name = save.Name.of(bufPrint(&buf, "garden {d}", .{i}) catch unreachable).?, .age = @intCast(i * 90)});
  }
  g.listed();
  in.mouse = .{-1e4, -1e4};
  in.advance();
  in.scroll = -2;
  try g.update(&in, TICK, screen);
  in.scroll = 0;
  try testing.expectEqual(@as(f32, 2), g.garden_top);
  in.scroll = -100;
  try g.update(&in, TICK, screen);
  in.scroll = 0;
  try testing.expectEqual(m.f(4), g.garden_top);
  // the list follows, bringing the last rows into view
  for (0..60) |_| try g.update(&in, TICK, screen);
  try testing.expectApproxEqAbs(m.f(4), g.garden_at, 0.01);

  // a fresh garden asks its name first
  try click.on(&g, &in, .{.garden_act = .save}, screen);
  try testing.expectEqual(Mode.naming, g.mode);
  try testing.expect(g.request.? == .list);
  g.request = null;
  try click.on(&g, &in, .{.garden_act = .cancel}, screen);
  try testing.expectEqual(Mode.gardens, g.mode);
  try testing.expect(g.request == null);
  // a saved one only on the second click
  try click.on(&g, &in, .{.garden = 9}, screen);
  try testing.expectEqual(@as(usize, 9), g.garden);
  try click.on(&g, &in, .{.garden_act = .save}, screen);
  try testing.expect(g.request == null and g.overwrite);
  try click.on(&g, &in, .{.garden_act = .save}, screen);
  try testing.expectEqualStrings("garden 8", g.request.?.save_as.slice());
  g.request = null;
  try click.on(&g, &in, .{.garden_act = .load}, screen);
  try testing.expectEqualStrings("garden 8", g.request.?.load_from.slice());
  g.request = null;
  // the chosen one's delete, only on the second click
  try click.on(&g, &in, .{.garden_act = .delete}, screen);
  try testing.expect(g.request == null and g.deleting);
  try click.on(&g, &in, .{.garden_act = .delete}, screen);
  try testing.expectEqualStrings("garden 8", g.request.?.delete.slice());
  g.request = null;
  try click.on(&g, &in, .back, screen);
  try testing.expectEqual(Mode.paused, g.mode);
  try testing.expectEqual(@as(u64, 0), g.ticks);
}

test "the save key asks a garden without a name for one: typed, taken asks twice, OK saves" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  const screen = TEST_SCREEN;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  in.mouse = .{-1e4, -1e4};

  in.advance();
  ctl.hold(&in, .save, true);
  try g.update(&in, TICK, screen);
  in.advance();
  ctl.hold(&in, .save, false);
  try testing.expectEqual(Mode.naming, g.mode);
  try testing.expect(g.request.? == .list);
  g.request = null;
  try g.gardens.append(gpa, .{.name = save.Name.of("Moss").?, .age = 0});
  g.listed();
  // the world stands still while a name is typed; letters bound to
  // actions only type
  for ("moss?") |c| in.type1(c);
  try g.update(&in, TICK, screen);
  in.typed_len = 0;
  try testing.expectEqualStrings("moss", g.typed.slice());
  try testing.expectEqual(@as(u64, 0), g.ticks);
  try testing.expectEqual(Mode.naming, g.mode);
  // taken: OK asks first, then saves over it
  try click.on(&g, &in, .{.garden_act = .ok}, screen);
  try testing.expect(g.request == null and g.overwrite);
  try click.on(&g, &in, .{.garden_act = .ok}, screen);
  try testing.expectEqualStrings("moss", g.request.?.save_as.slice());
  try testing.expectEqual(Mode.roam, g.mode);
  g.request = null;

  // named, the save key saves at once; erase takes back, Esc cancels
  g.startNaming();
  for ("ab") |c| in.type1(c);
  try g.update(&in, TICK, screen);
  in.typed_len = 0;
  try click.press(&g, &in, .panel, screen, .erase);
  try testing.expectEqualStrings("a", g.typed.slice());
  try click.press(&g, &in, .panel, screen, .back);
  try testing.expectEqual(Mode.roam, g.mode);
  g.request = null;
  g.slot = save.Name.of("moss").?;
  in.advance();
  ctl.hold(&in, .save, true);
  try g.update(&in, TICK, screen);
  try testing.expect(g.request.? == .save);
}

test "the garden saves itself once the autosave interval is played" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  in.mouse = .{-1e4, -1e4};
  g.opts.autosave = 1;
  const step_s:f32 = 0.5;
  var frames:usize = 0;
  while (g.request == null) : (frames += 1) try g.update(&in, step_s, TEST_SCREEN);
  try testing.expect(g.request.? == .autosave);
  try testing.expectEqual(@as(usize, m.S_PER_MIN / step_s), frames);
  // never, when turned off
  g.request = null;
  g.opts.autosave = 0;
  for (0..1000) |_| try g.update(&in, step_s, TEST_SCREEN);
  try testing.expect(g.request == null);
}

test "a germinator's panel: choose its seed, put in only what it weaves from, move stacks across" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  const screen = TEST_SCREEN;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  const x, const z = m.tileAt(g.player.pos);
  var fp = m.footprint(x + 1, z, 2);
  while (fp.next()) |p| {
    const c = g.world.chunkOfTile(p[0], p[1]).?;
    const t = ck.localIndex(p[0], p[1]);
    c.kind[t] = .soil;
    c.res[t] = 0;
    c.occ[t] = .none;
  }
  try testing.expect(try g.structs.place(gpa, &g.world, x + 1, z, .germinator, 0, 0));
  const id = g.structs.at(&g.world, x + 1, z).?;
  g.player.inv = .{};
  g.player.inv.slot[0] = .{.item = .fibre, .n = 30};
  g.player.inv.slot[1] = .{.item = .grit, .n = 5};
  g.mode = .structure;
  g.open = .{x + 1, z};
  try testing.expect(g.opened() != null);

  // set to thornleech, it takes no fibre: the stack stays in hand
  const thorn = for (craft.seeds) |r| {
    if (craft.hand[r].out == .seed_thornleech) break r;
  } else unreachable;
  try click.on(&g, &in, .{.recipe = thorn}, screen);
  try testing.expectEqual(@as(?u8, thorn), st.chosen(g.structs.get(id)));
  try click.on(&g, &in, .{.slot = 0}, screen);
  try click.on(&g, &in, .{.store = 0}, screen);
  try testing.expect(g.holds(.{.slot = 0}));
  try testing.expect(g.structs.get(id).inv.slot[0] == null);
  try click.on(&g, &in, .panel, screen);
  // grit it takes, the whole stack
  try click.on(&g, &in, .{.slot = 1}, screen);
  try click.on(&g, &in, .{.store = 2}, screen);
  try testing.expectEqual(@as(u32, 5), g.structs.get(id).inv.count(.grit));
  try testing.expect(g.held == null and g.player.inv.slot[1] == null);
  // a locked seed is not chosen
  const vesper = for (craft.seeds) |r| {
    if (craft.hand[r].out == .seed_vesper) break r;
  } else unreachable;
  try click.on(&g, &in, .{.recipe = vesper}, screen);
  try testing.expectEqual(@as(?u8, thorn), st.chosen(g.structs.get(id)));
  // back to lumenroot: fibre goes in up to what it stocks, the rest in hand
  try click.on(&g, &in, .{.recipe = craft.seeds[0]}, screen);
  try click.on(&g, &in, .{.slot = 0}, screen);
  try click.on(&g, &in, .{.store = 0}, screen);
  try testing.expectEqual(@as(u32, 20), g.structs.get(id).inv.count(.fibre));
  try testing.expectEqual(@as(u32, 10), g.player.inv.count(.fibre));
  try click.on(&g, &in, .panel, screen);
  // with take held, a click moves a stack straight back
  ctl.hold(&in, .take, true);
  try click.on(&g, &in, .{.store = 2}, screen);
  ctl.hold(&in, .take, false);
  try testing.expectEqual(@as(u32, 5), g.player.inv.count(.grit));
  try testing.expectEqual(@as(u32, 0), g.structs.get(id).inv.count(.grit));
  // out of reach, the panel closes
  g.player.pos += m.v3(40, 0, 0);
  try g.update(&in, TICK, screen);
  try testing.expectEqual(Mode.roam, g.mode);
}

test "a click lifts a stack, the next puts it down; dropped on the hotbar it assigns" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  const screen = TEST_SCREEN;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  for (g.bar) |b| try testing.expect(b == null);
  g.mode = .belly;
  g.player.inv = .{};
  g.player.inv.slot[0] = .{.item = .fibre, .n = 30};
  g.player.inv.slot[1] = .{.item = .conduit, .n = 3};
  g.player.inv.slot[2] = .{.item = .fibre, .n = 80};

  // sort by hand: into an empty slot, then trade places
  try click.on(&g, &in, .{.slot = 0}, screen);
  try testing.expectEqual(@as(?items.Item, .fibre), g.carried());
  try click.on(&g, &in, .{.slot = 5}, screen);
  try testing.expect(g.held == null and g.player.inv.slot[0] == null);
  try testing.expectEqual(@as(u16, 30), g.player.inv.slot[5].?.n);
  try click.on(&g, &in, .{.slot = 5}, screen);
  try click.on(&g, &in, .{.slot = 1}, screen);
  try testing.expectEqual(items.Item.fibre, g.player.inv.slot[1].?.item);
  try testing.expectEqual(items.Item.conduit, g.player.inv.slot[5].?.item);
  // onto a stack of the same: as much as fits, the rest stays in hand
  try click.on(&g, &in, .{.slot = 1}, screen);
  try click.on(&g, &in, .{.slot = 2}, screen);
  try testing.expectEqual(items.STACK, g.player.inv.slot[2].?.n);
  try testing.expectEqual(@as(u16, 10), g.player.inv.slot[1].?.n);
  try testing.expect(g.holds(.{.slot = 1}));
  try click.on(&g, &in, .{.slot = 1}, screen);
  try testing.expect(g.held == null);

  // onto the hotbar: the slot takes the item, the stack stays in the belly
  try click.on(&g, &in, .{.slot = 5}, screen);
  try click.on(&g, &in, .{.bar = 3}, screen);
  try testing.expectEqual(@as(?items.Item, .conduit), g.bar[3]);
  try testing.expectEqual(@as(u32, 3), g.player.inv.count(.conduit));
  // hotbar items trade places, and come off when dropped elsewhere
  try click.on(&g, &in, .{.bar = 3}, screen);
  try click.on(&g, &in, .{.bar = 0}, screen);
  try testing.expect(g.bar[3] == null and g.bar[0] == .conduit);
  g.mode = .roam;
  try click.on(&g, &in, .{.bar = 0}, screen);
  try testing.expectEqual(@as(?items.Item, .conduit), g.selected());
  g.mode = .belly;
  try click.on(&g, &in, .{.bar = 0}, screen);
  try click.on(&g, &in, .panel, screen);
  try testing.expect(g.bar[0] == null and g.selected() == null);
}

test "discard throws away a belly stack, hovered or carried, never a structure's" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  const screen = TEST_SCREEN;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  g.mode = .belly;
  g.player.inv = .{};
  g.player.inv.slot[0] = .{.item = .fibre, .n = 30};
  g.player.inv.slot[1] = .{.item = .grit, .n = 7};
  g.bar[0] = .grit;

  // under the cursor
  try click.press(&g, &in, .{.slot = 0}, screen, .discard);
  try testing.expect(g.player.inv.slot[0] == null);
  try testing.expectEqual(@as(u32, 7), g.player.inv.count(.grit));
  // carried: lifted, then thrown away wherever the cursor is
  try click.on(&g, &in, .{.slot = 1}, screen);
  try click.press(&g, &in, .{.bar = 0}, screen, .discard);
  try testing.expect(g.held == null and g.player.inv.used() == 0);
  // the hotbar keeps its item; with the belly closed nothing goes
  try testing.expectEqual(@as(?items.Item, .grit), g.bar[0]);
  g.player.inv.slot[2] = .{.item = .fibre, .n = 5};
  g.mode = .roam;
  in.advance();
  ctl.hold(&in, .discard, true);
  try g.update(&in, TICK, screen);
  try testing.expectEqual(@as(u32, 5), g.player.inv.count(.fibre));
}

/// headless: the mouse over the middle of tile `t`, as the camera sees it now
fn aim(g:*const Game, in:*Input, t:[2]i32, sc:[2]f32) void {
  const q = m.mulV(g.cam.viewProj(), .{m.f(t[0]) + 0.5, g.heightAt(t[0], t[1]), m.f(t[1]) + 0.5, 1});
  in.mouse = .{(q[0] / q[3] + 1) / 2 * sc[0], (q[1] / q[3] + 1) / 2 * sc[1]};
}

/// headless: one frame with `a` pressed (held down this frame only) over tile `t`
fn pressAt(g:*Game, in:*Input, t:[2]i32, a:ctl.Action) !void {
  aim(g, in, t, TEST_SCREEN);
  in.advance();
  ctl.hold(in, a, true);
  try g.update(in, TICK, TEST_SCREEN);
  in.advance();
  ctl.hold(in, a, false);
  try g.update(in, TICK, TEST_SCREEN);
}

test "R turns what is under the cursor (Shift back), Q picks its bulb, a click opens it, remove takes it up, held use puts one down" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, DEFAULT_SEED);
  defer g.deinit();
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  var in:Input = .{.win = undefined};
  const x, const z = m.tileAt(g.player.pos);
  for (0..4) |dx| {
    const tx = x + 1 + @as(i32, @intCast(dx));
    const c = g.world.chunkOfTile(tx, z).?;
    const t = ck.localIndex(tx, z);
    c.kind[t] = .soil;
    c.res[t] = 0;
    c.occ[t] = .none;
  }
  const at = [2]i32{x + 2, z};
  try testing.expect(try g.structs.place(gpa, &g.world, at[0], at[1], .sap_cache, 0, 0));
  g.player.inv = .{};

  // R: a quarter clockwise, rooted, and not again until it has turned
  try pressAt(&g, &in, at, .rotate);
  const id = g.structs.at(&g.world, at[0], at[1]).?;
  try testing.expectEqual(@as(m.Dir, 1), g.structs.get(id).dir);
  try testing.expect(g.structs.get(id).turn.busy(g.time, true));
  try pressAt(&g, &in, at, .rotate);
  try testing.expectEqual(@as(m.Dir, 1), g.structs.get(id).dir);
  // the next thing put down keeps its own facing
  try testing.expectEqual(@as(m.Dir, 0), g.place_dir);
  // once turned, Shift+R turns it back
  g.time += lib.turn.TIME;
  ctl.hold(&in, .counter, true);
  try pressAt(&g, &in, at, .rotate);
  ctl.hold(&in, .counter, false);
  try testing.expectEqual(@as(m.Dir, 0), g.structs.get(id).dir);

  // Q: none in the belly, nothing to pick; with one, onto the hotbar
  try pressAt(&g, &in, at, .pick);
  try testing.expect(g.selected() == null);
  _ = g.player.inv.add(.sap_cache, 1);
  g.hot = 4;
  try pressAt(&g, &in, at, .pick);
  try testing.expectEqual(@as(?items.Item, .sap_cache), g.selected());
  try testing.expectEqual(@as(usize, 4), g.hot);

  // a click on it opens its panel, even with a bulb in hand
  try pressAt(&g, &in, at, .use);
  try testing.expectEqual(Mode.structure, g.mode);
  g.mode = .roam;
  // so does interact
  try pressAt(&g, &in, at, .interact);
  try testing.expectEqual(Mode.structure, g.mode);
  g.mode = .roam;

  // remove takes it up: its bulb comes back
  try pressAt(&g, &in, at, .remove);
  try testing.expect(g.structs.at(&g.world, at[0], at[1]) == null);
  try testing.expectEqual(@as(u32, 2), g.player.inv.count(.sap_cache));

  // held, use puts the bulb in hand down where it fits, turned as R left it
  g.place_dir = 3;
  aim(&g, &in, at, TEST_SCREEN);
  in.advance();
  ctl.hold(&in, .use, true);
  for (0..3) |_| try g.update(&in, TICK, TEST_SCREEN);
  ctl.hold(&in, .use, false);
  const put = g.structs.at(&g.world, at[0], at[1]) orelse return error.TestUnexpectedResult;
  try testing.expectEqual(@as(m.Dir, 3), g.structs.get(put).dir);
  try testing.expectEqual(@as(u32, 1), g.player.inv.count(.sap_cache));
}
