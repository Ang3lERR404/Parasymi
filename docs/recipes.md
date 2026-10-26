# Recipes: what adding a thing touches

Every place a new thing has to be wired, in order. Tests catch most misses
(named under each), but going down the list saves the round trips. Paths
are under `src/` unless shown otherwise. Look a file up in
[files.md](files.md).

## A structure
1. `game/structures/<kind>.zig`: `pub const def:st.Def = .{ .item, .size,
   .mesh, .grow, ... }` (fields: `game/structures.zig` `Def`); hooks as
   needed (list in that file's header); `meshes` tuple for every library
   mesh it emits; `meets` if it is a lineage structure.
2. One line in `kinds` in `game/structures.zig`.
3. Mesh: `gfx/meshes/<kind>.zig` with `build(b)` on a `growth.Skeleton`
   ([growth.md](growth.md)), from its lineage's kit ([kits/README.md](kits/README.md));
   one line per mesh (and companion struct) in `parts` in `gfx/meshlib.zig`,
   in draw order (translucent after what it covers).
4. Bulb item: a tag **at the end** of `items.Item` (`sim/items.zig`) and its
   colour in `infos`.
5. Recipe: a row in `game/craft.zig` (`.needs` = its research;
   `.germinator = true` for convergent ones, `.advanced` for a monfris
   weave).
6. Research that opens it (see below), or `.needs` an existing one.
7. Strings in `src/cfg/parasymi.cfg`: `[item] <kind>.name/.short`,
   `[structure] <kind>.name`, any `describe` lines under `[describe]` (each
   also a field in `txt.Strings.describe`, `game/text.zig`).
8. Bulb icon: `icon(ic, col)` hook (`game/icon.zig` kit).
9. A discovery (lineage pair): a tag in `prog.Discovery`, its case in
   `Progression.discover`, its `[msg]` line + `txt.Strings.msg` field.
10. Optional: put it in the demo garden (`game/setups.zig`).
11. Check: `zig build test`, then `--structure=<kind> --state=grow` and
    `--state=active` with `--inspect` ([testing.md](testing.md)).

Tests: missing/unknown cfg keys; a structure alone drawing an undeclared
mesh; an unfinished skeleton (debug assert).

## A species
1. `sim/species/<name>.zig` with `def` (stats, lineage, form, genome,
   `.seed`); one line in `parts` in `sim/species.zig`.
2. Seed item at the end of `items.Item` + colour in `infos`.
3. Seed icon: `game/seeds/<name>.zig` (`item` + `icon`), one line in
   `kinds` in `game/seeds.zig`.
4. Seed recipe in `game/craft.zig` (germinator only: plants never set seed).
5. Research gate: `unlocks = [_]species.Id{.<name>}` in a research module
   (always-open seeds need none).
6. Strings: `[item] seed_<name>.name/.short`, `[plant] <name>.name`
   (+ `.stages` for staged species).
7. Check: `--plant=<name>` with `--state=grow`, `wither`, `live`, ….

Tests: a sown species without a seed icon; cfg keys.

## A research node
1. `game/research/<id>.zig` with `def:prog.Research` (`.per_unit`,
   `.units`, `.unit_time`, `.prereq` with the host first, `.branch` for a
   big step, `.needs` for a discovery); hooks `apply`, `unlocks`,
   `completed`, `veil`, `reveals`, `study` as needed.
2. One line in `techs` in `game/progression.zig`.
3. Strings: `[research] <id>.name/.desc`.
4. No layout work: the sapling places it. If the layout test fails, fix the
   rules in `hud/research.zig`, never the node.

## An item (not a seed or bulb)
1. Tag at the end of `items.Item`, colour in `infos`.
2. `[item] <id>.name/.short`.
3. Where it comes from (a node, a structure's `output`, a recipe) and goes.

## A library mesh (part)
1. `gfx/meshes/<name>.zig` `build(b)` (or a companion struct in its
   owner's file), one line in `parts` in `gfx/meshlib.zig` (draw order).
2. A new see-through role goes in `vertex.seeThrough`.
3. If a structure emits it, add it to that structure's `meshes`.

## A HUD panel
`game/hud/<name>.zig` with `draw(g, d, W, H)` (+ `visible(g)`), one line in
`panels` in `game/hud.zig` (later draws on top). Clickable things: a tag
in `hud.Pick`, their area a `hud.Box` (x, y, w, h) passed to `g.rows.add`.
Item slots use the `hud/slot.zig` component (`Slot`: a box, a pick, the
husk's share of the box; it registers its box, draws the husk and glows,
and its look scales with the box), never a hand-drawn husk. Strings under
`[hud]`.

## A render pass
`render/passes/<name>.zig` with `desc` (`.target`), `prepare`, `record`
(+ `Frame`, `initFrame`/`deinitFrame`), one line in `passes` in
`render/renderer.zig` (record order); its `desc` embeds its SPIR-V
(`.vert = @embedFile("x.vert")`). New shaders: the file in `shaders/`
with a `//!` header after `#version`, its name in `shaders` in `build.zig`.
A pass any game could use goes in the engine instead
(`engine/src/render/passes/`, shaders in `engine/shaders/` and
`engine/build.zig`; [engine.md](engine.md)).

## An input
An `ctl.Action` tag in `game/controls.zig` + a `[bind]` line in
`src/cfg/controls.cfg`; text names it as `{@action}`. Test: unbound
action.

## A player-facing string
A field in `txt.Strings` (`game/text.zig`) + a line in
`src/cfg/parasymi.cfg`, read via `txt.s.*`. Test: missing/unknown key.

## A source file
Give it a `//!` header (first sentence = what it is), then
`zig run tools/filemap.zig` to refresh [files.md](files.md).
