# Controls

Defaults in `src/cfg/controls.cfg` (rebindable in the gardener's copy; see
[architecture.md](architecture.md#inputs)). Key names below are the defaults.

## Play
- WASD move, Shift run, MMB drag orbits the camera round the wolf (yaw
  free, pitch 8°–89°, default 55°), wheel zoom. Free inspection camera on
  Ctrl+F.
- LMB held plants the selected seed/bulb wherever it fits as the cursor
  sweeps; where it does not, a click on a structure interacts, on a plant
  harvests. E always interacts (harvests a plant). Interact: a structure
  that keeps items opens its panel, a paired one (`configure` hook) is
  configured, any other is fed from the belly.
- RMB pressed or held is the universal remove: uproots a plant, takes up
  a structure (one tile at a time as the cursor sweeps,
  `REMOVE_COOLDOWN`), gathers from a resource node while held (with no
  move held, the wolf steps up to the node, `GATHER_AT`, and pries it by
  hand).
- Q picks the seed/bulb of what is under the cursor: selects its hotbar
  slot, else puts it from the belly on the selected slot (if empty, else
  the first empty one, else over the selected one), and takes its facing.
- R turns what is under the cursor (in reach) a quarter clockwise,
  Shift+R counter-clockwise; with nothing there, the facing of the next
  thing put down (plants face too). A rooted plant/structure pulls its
  roots out, heaves up on them, steps round and digs back in
  (`sim/turn.zig`, 1.5 s); a floating (celestial) one just turns in the
  air. Not again until it has finished.
- Hovering a structure, plant or resource node shows its name and what it
  is doing on a card beside the cursor; bare ground shows its kind and
  ley by the top-left.
- F harvest/feed, Shift+F take, C configure.
- 1–9/0/-/=/Backspace pick hotbar slots only; research nodes and weave
  recipes are clicked in their panels.
- Tab belly (weave), T research, F3 debug, Esc closes a panel else pauses,
  F5 save (the garden being played), F9 load (its last save), F11
  fullscreen.

## Belly and hotbar
- Hotbar slots start empty. In the belly a click lifts a stack onto the
  cursor, the next puts it down (empty slot, merge, or swap: sorting by
  hand); dropped on a hotbar slot it assigns that item (any item); a lifted
  hotbar item swaps or, dropped elsewhere, comes off; RMB clears a hotbar
  slot.
- Every item stacks to 100 (`items.STACK`). Delete (`discard`) throws away
  the belly stack under the cursor (or carried), never a structure's.
  Hovering a slot shows the item's full name.

## Structure panels
LMB on a structure that keeps items (`Def.store`: sap cache, germinator,
arsthraxia, digger) opens its panel (`Mode.structure`, `hud/structure.zig`):
its slots beside the belly's, lifted/put down between them the same way
(into it only what it `wants`), Shift+LMB moves a stack across; a
germinator's panel also picks what it weaves, any weave
(`recipes`/`chosen`/`choose` hooks). Closes out of reach.

## Menus
- Pause rows are clicked or keyed: Q = save and quit, O = options,
  G = saved gardens.
- Options panel: LMB turns a setting, RMB turns it back, Esc/BACK returns
  to the pause menu.
- Saved gardens panel (pause menu only, `hud/gardens.zig`, `Mode.gardens`):
  A FRESH GARDEN then every save, newest first; wheel or drag its stem to
  scroll (`GARDENS_SHOWN` rows), LMB chooses, SAVE (twice to save over
  one), LOAD, BACK/Esc.

## Free cam
Click to look, WASD fly (Shift fast), Space/Ctrl+Space rise/sink, Q/E roll,
wheel dolly; eases back in 0.3 s.
