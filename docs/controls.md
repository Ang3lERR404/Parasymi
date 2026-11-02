# Controls

The defaults live in `src/cfg/controls.cfg`. They are rebound in the
pause menu's KEYBINDS, or by hand in the gardener's own copy (see
[architecture.md](architecture.md#inputs)). Key names below are the
defaults.

## Play
### Moving and the camera
- **WASD** move, **Shift** run, **wheel** zoom (or hold
  **Numpad +/−**, six notches a second).
- **MMB drag** orbits the camera round the wolf: yaw (turning round) is
  free; pitch (looking down) is 8°–89°, default 55°.
- **Ctrl+F:** free inspection camera.

### First person
- **Getting in:** zoomed all the way in, one more wheel notch eases into
  the wolf's eyes. A notch out eases back.
- **Looking:** the cursor is held and the mouse looks (up 75°, down 70°).
- **Moving:** WASD moves relative to the look; the wolf turns to face it
  (its head leads).
- **Aiming:** every action lands on whatever the seed at the screen's
  middle is on.
- A panel or the pause menu gives the cursor back.
- **Hiding the head:** once the view is within `headClear` of the eyes,
  the head (head, jaw and ear bones) is clipped away on the GPU
  (`parts.Look.hide`, part.vert `gl_ClipDistance`). Its shadow still
  falls.

### Planting and interacting
- **LMB held** plants the selected seed/bulb wherever it fits as the
  cursor sweeps.
- Where it does not fit, a click on a structure interacts; on a plant, it
  harvests.
- **E** always interacts (on a plant: harvests). A harvest is plucked by
  paw over a few seconds; moving lets it go.
- **What interacting does:**
  - a structure that keeps items opens its panel;
  - a paired one (`configure` hook) is configured;
  - any other is fed from the belly.

### Removing
**RMB**, pressed or held, is the universal remove:

- it uproots a plant;
- it takes up a structure, one tile at a time as the cursor sweeps
  (`removeCooldown`);
- held on a resource node, it gathers. With no move key held, the wolf
  steps up to the node (`gatherAt`) and pries it by hand.

### Picking and turning
- **Q** picks the seed/bulb of what is under the cursor, and takes its
  facing. It selects that item's hotbar slot if there is one. Else it puts
  it from the belly on the selected slot if empty, else on the first empty
  one, else over the selected one.
- **R** turns what is under the cursor (in reach) a quarter clockwise;
  **Shift+R** counter-clockwise. With nothing there, it sets the facing of
  the next thing put down (plants face too).
- **How turning looks** (`sim/turn.zig`, 1.5 s): a rooted plant or
  structure pulls its roots out, heaves up on them, steps round and digs
  back in. A floating (celestial) one just turns in the air. It can't be
  turned again until it has finished.

### Hover cards
Hovering a structure, plant or resource node shows its name and what it is
doing, on a card beside the cursor. Bare ground shows its kind and ley at
the top left.

### Other keys
- **F** harvest/feed, **Shift+F** take, **C** configure.
- **V** held (act 2): sweep the cursor from one structure to another, a
  tendril between them once let go; the wheel meanwhile sets how high the
  tile under the cursor floats, and the tiles swept after it.
- **1–9 / 0 / - / = / Backspace** pick hotbar slots only. Research nodes
  and weave recipes are clicked in their panels.
- **Tab** belly (weave), **T** research, **F3** debug.
- **Left Alt** alt mode: over every structure, what it weaves (its seed,
  haloed) or holds (its most plentiful items, with counts); over the wolf,
  what its hands weave.
- **Esc** closes a panel, else pauses.
- **F6** saves (into the garden being played; one never named asks its
  name first). **F9** loads (its last save). **F11** fullscreen.

## Belly and hotbar
- Hotbar slots start empty.
- **Sorting by hand in the belly:** a click lifts a stack onto the cursor;
  the next click puts it down (into an empty slot, merging, or swapping).
- **Dropped on a hotbar slot,** a stack assigns that item to it (any item).
- **A lifted hotbar item** swaps, or comes off if dropped elsewhere. RMB
  clears a hotbar slot.
- Every item stacks to 100 (`items.stack`).
- **Delete** (`discard`) throws away the belly stack under the cursor (or
  the one carried), never a structure's.
- Hovering a slot shows the item's full name.

## Structure panels
LMB on a structure that keeps items (`Def.store`: sap cache, germinator,
arsthraxia, digger) opens its panel (`Mode.structure`,
`hud/structure.zig`).

- Its slots sit beside the belly's. Stacks are lifted and put down between
  them the same way (into it, only what it `wants`).
- **Shift+LMB** moves a stack across.
- A germinator's panel also picks what it weaves, any weave
  (`recipes`/`chosen`/`choose` hooks).
- The panel closes when you are out of reach.

## Menus
A menu's buttons click when LMB is let go over them, so sliding off
first takes the click back. The keys and a gamepad work every menu:
**arrows / d-pad** move to the nearest row that way, **Tab / RB** to the
next (with **Shift**, the one before), **Enter / A** chooses it, **Esc /
B / Start** goes back. Moving the mouse gives it the lead again.

### Pause
Rows are clicked or keyed: **Q** = save and quit, **O** = options,
**K** = keybinds, **G** = saved gardens.

### Options panel
Toggles (a bud that blooms when on), pickers (a value between two leaves)
and the autosave slider (a seed riding a stem of stops). LMB turns a
setting, RMB turns it back; a picker's leaves turn it their way; the
slider is dragged along. **Left/Right** turn the setting the keys are on.
Esc/BACK returns to the pause menu.

### Keybinds panel
(Pause menu only; `hud/keybinds.zig`, `Mode.keybinds`.)

- **The list:** every action, its name and the keys bound to it. Scroll
  with the wheel or by dragging its stem (`bindsShown` rows).
- **Rebinding:** LMB (or Enter / A) on a row listens: the next key, mouse
  button or pad button pressed takes the place of the row's first binding
  of its kind (keyboard and mouse, or pad); its others stay. **Esc**
  cancels the listening.
- **RMB** sets a row back as the game ships it; **ALL DEFAULTS** every
  row. A row bound otherwise is marked `*`, in green.
- Each change is written at once to the gardener's `controls.cfg` (only
  the actions that differ; none, and the game's own file comes back) and
  every `{@action}` shown is redrawn with the new key.
- **BACK/Esc.**

### Saved gardens panel
(Pause menu only; `hud/gardens.zig`, `Mode.gardens`.)

- **The list:** A FRESH GARDEN, then every save, newest first. Scroll with
  the wheel or by dragging its stem (`gardensShown` rows). LMB chooses.
- **SAVE:** a fresh garden asks its name; press twice to save over an
  existing one.
- **LOAD.**
- **DELETE:** the chosen save's small button; press twice.
- **BACK/Esc.**

### Name prompt
(`hud/naming.zig`, `Mode.naming`; the world is frozen.)

- Type the name: letters, digits, a few marks (`save.Name.put`); it goes
  in at the caret.
- Left/Right, Home/End move the caret (with Shift, selecting); a click
  on the name puts it there.
- Backspace erases the selection or the letter before the caret, Delete
  the one after.
- Ctrl+A selects all, Ctrl+C copies, Ctrl+X cuts, Ctrl+V pastes.
- Enter/OK saves (press twice over a taken name).
- Esc/CANCEL returns.
- Never `autosave` or blank.

## Free cam
Click to look, **WASD** fly (**Shift** fast), **Space/Ctrl+Space**
rise/sink, **Q/E** roll, **wheel** dolly. It eases back in 0.3 s.
