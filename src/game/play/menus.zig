//! the pause menu, the saved gardens, naming a garden, inspecting and flying.
const lib = @import("../../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const Input = engine.platform.input.Input;
const ctl = lib.controls;
const camera = engine.render.camera;
const hud = lib.hud;
const save = lib.save;
const DOLLY_PER_NOTCH = lib.play.DOLLY_PER_NOTCH;
const FLY_FAST = lib.play.FLY_FAST;
const GARDENS_SHOWN = lib.play.GARDENS_SHOWN;
const GARDEN_EASE = lib.play.GARDEN_EASE;
const GARDEN_NOTCH = lib.play.GARDEN_NOTCH;
const Game = lib.play.game.Game;
const GardenAct = lib.play.GardenAct;
const PauseRow = lib.play.PauseRow;

/// the pause menu and the panels opened from it, while the world is
/// frozen: a click on a pause row does what it says; on an option it
/// turns it (the other button turns it back); in the saved gardens it
/// chooses a garden, or saves or loads it. Keys still work for the pause
/// rows.
pub fn menu(g:*Game, in:*const Input, dt:f32) void {
  g.mouse = in.mouse;
  const hit = g.rows.at(in.mouse);
  g.pointed = hit;
  if (g.mode == .paused) {
    if (ctl.pressed(in, .quit)) g.request = .quit;
    if (ctl.pressed(in, .options)) g.mode = .options;
    if (ctl.pressed(in, .gardens)) g.openGardens();
  }
  if (g.mode == .naming) g.typeName(in);
  if (hit) |p| {
    if (ctl.pressed(in, .use)) hud.click(g, p, .use, in)
    else if (ctl.pressed(in, .remove)) hud.click(g, p, .remove, in);
  }
  if (g.mode == .gardens) g.scroll(in, dt);
}

pub fn choose(g:*Game, row:PauseRow) void {
  switch (row) {
    .@"resume" => g.mode = .roam,
    .options => g.mode = .options,
    .gardens => g.openGardens(),
    .fullscreen => g.opts.fullscreen = !g.opts.fullscreen,
    .quit => g.request = .quit,
  }
}

/// the saved gardens menu opens on a fresh list, the played garden chosen
pub fn openGardens(g:*Game) void {
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
pub fn gardenScroll(g:*const Game) f32 {
  return m.f((g.gardens.items.len + 1) -| GARDENS_SHOWN);
}

/// the wheel scrolls the gardens list; its groove, held, drags it
/// (a click on it takes hold of it: the gardens panel's `click`)
pub fn scroll(g:*Game, in:*const Input, dt:f32) void {
  const most = g.gardenScroll();
  g.garden_top -= in.scroll * GARDEN_NOTCH;
  if (!ctl.down(in, .use)) g.scrolling = false;
  if (g.scrolling) if (g.rows.find(hud.row(.gardens, .scroll))) |r| {
    g.garden_top = m.clamp(r.local(in.mouse)[1], 0, 1) * most;
  };
  g.garden_top = m.clamp(g.garden_top, 0, most);
  g.garden_at += (g.garden_top - g.garden_at) * @min(1, dt * GARDEN_EASE);
}

/// SAVE: a fresh garden asks for its name; over a saved one only when
/// asked twice. LOAD: the chosen saved garden. DELETE: the chosen one,
/// when asked twice. OK and CANCEL: the name prompt's.
pub fn gardenAct(g:*Game, a:GardenAct) void {
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
pub fn startNaming(g:*Game) void {
  g.naming_from = if (g.mode == .naming) g.naming_from else g.mode;
  g.mode = .naming;
  g.typed = .{};
  g.overwrite = false;
  g.request = .list;
}

/// the name prompt: typing adds to the name, erase takes back, confirm
/// is OK
pub fn typeName(g:*Game, in:*const Input) void {
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
pub fn nameChosen(g:*Game) void {
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
pub fn inspect(g:*Game, in:*const Input, on:bool) void {
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
pub fn fly(g:*Game, in:*const Input, dt:f32) void {
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
