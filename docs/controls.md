# Controls

Defaults in `src/cfg/controls.cfg` (rebindable in the gardener's copy; see
[architecture.md](architecture.md#inputs)). Key names below are the defaults.

## Play
- WASD move, Shift run, Q/E yaw, Ctrl+W/S pitch (30°–85°, default 55°),
  wheel zoom. No free rotation in play; free inspection camera on Ctrl+F.
- LMB gather/place, RMB uproot, F harvest/feed, Shift+F take, C configure,
  R rotate.
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
