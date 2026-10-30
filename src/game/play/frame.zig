//! one frame of play: input read into actions, the camera, the HUD's picks.
const lib = @import("../../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const ck = lib.ck;
const txt = lib.txt;
const Input = engine.platform.input.Input;
const ctl = lib.controls;
const player_mod = lib.player;
const st = lib.structures;
const actions = lib.actions;
const hud = lib.hud;
const APPROACH = lib.play.APPROACH;
const Error = lib.play.Error;
const FOLLOW_HEIGHT = lib.play.FOLLOW_HEIGHT;
const FOLLOW_LERP = lib.play.FOLLOW_LERP;
const Game = lib.play.game.Game;
const STREAM_FRAME = lib.play.STREAM_FRAME;
const STREAM_RADIUS = lib.play.STREAM_RADIUS;
const TIMING_EASE = lib.play.TIMING_EASE;

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
    if (ui_hit) |hit| hud.click(g, hit, .use, in) else if (g.held != null) {
      g.drop();
      g.use_spent = true;
    }
  }
  if (ctl.pressed(in, .remove)) if (ui_hit) |hit| hud.click(g, hit, .remove, in);
  // discard throws away the belly stack carried, else the one under the cursor
  if (ctl.pressed(in, .discard) and g.mode.sorting()) {
    if (g.held) |h| switch (h) {
      .slot => |i| g.discard(i),
      .bar, .store => {},
    } else if (ui_hit) |hit| hud.click(g, hit, .discard, in);
  }

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
