# Recipes: what adding a thing touches

Every place a new thing has to be wired, in order. Tests catch most misses
(named under each recipe), but going down the list saves the round trips.

Paths are under `src/` unless shown otherwise. Look a file up in
[files.md](files.md).

## A structure
1. **Its module**: `game/structures/<kind>.zig` with
   `pub const def:st.Def = .{ .item, .size, .mesh, .grow, ... }`.
   - The fields are `Def` in `game/structures.zig`.
   - Add hooks as needed (the list is in that file's header).
   - A `meshes` tuple for every library mesh it emits.
   - `meets` if it is a lineage structure.
2. **Register it**: one line in `kinds` in `game/structures.zig`.
3. **Mesh**: `gfx/meshes/<kind>.zig` with `build(b)` on a
   `growth.Skeleton` ([growth.md](growth.md)), built from its lineage's
   kit ([kits/README.md](kits/README.md)).
   - One line per mesh (and companion struct) in `parts` in
     `gfx/meshlib.zig`.
   - Keep draw order: translucent after what it covers.
4. **Bulb item**: a tag **at the end** of `items.Item` (`sim/items.zig`)
   and its colour in `infos`.
5. **Recipe**: a row in `game/craft.zig`.
   - `.needs` = its research.
   - Nothing for its lineage: who weaves it follows from the structure's
     `Def.lineage` (convergent or radiant: never the hands; convergent: a
     monfris too). `Def.lineage` (with `.evolves` if the unforming turns it
     into another) is the one place a lineage is said.
   - `.advanced` for a weave only a monfris makes.
6. **Research** that opens it (see below), or `.needs` an existing one.
7. **Strings** in `src/cfg/parasymi.cfg`:
   - `[item] <kind>.name/.short`;
   - `[structure] <kind>.name`;
   - any `describe` lines under `[describe]`, each also a field in
     `txt.Strings.describe` (`game/text.zig`).
8. **Bulb icon**: the `icon(ic, col)` hook (`game/icon.zig` kit).
9. **A discovery** (lineage pair):
   - a tag in `prog.Discovery`;
   - its case in `Progression.discover`;
   - its `[msg]` line + a `txt.Strings.msg` field.
10. **Optional**: put it in the demo garden (`game/setups.zig`).
11. **Check**: `zig build test`, then `--structure=<kind> --state=grow`
    and `--state=active` with `--inspect` ([testing.md](testing.md)).

Tests catch: missing/unknown cfg keys; a structure alone drawing an
undeclared mesh; an unfinished skeleton (debug assert).

## A species
1. **Its module**: `sim/species/<name>.zig` with `def` (stats, lineage,
   form, genome, `.seed`). One line in `parts` in `sim/species.zig`.
   If it yields, its genome's `pods` (and `podR`, `podAt` for a stemmed
   one) ripen on it where `.pluck` says the paws reach (its form's kit
   places them; a test holds the two together).
2. **Seed item**: a tag at the end of `items.Item` + its colour in
   `infos`.
3. **Seed icon**: `game/seeds/<name>.zig` (`item` + `icon`), one line in
   `kinds` in `game/seeds.zig`.
4. **Seed recipe** in `game/craft.zig` (germinator only: plants never set
   seed).
5. **Research gate**: `unlocks = [_]species.Id{.<name>}` in a research
   module (always-open seeds need none).
6. **Strings**: `[item] seed_<name>.name/.short`, `[plant] <name>.name`
   (+ `.stages` for staged species).
7. **Check**: `--plant=<name>` with `--state=grow`, `wither`, `live`, ….

Tests catch: a sown species without a seed icon; cfg keys.

## A research node
1. **Its module**: `game/research/<id>.zig` with `def:prog.Research`.
   - `.perUnit`, `.units`, `.unitTime`;
   - `.prereq`, with the host first;
   - `.branch` for a big step;
   - `.needs` for a discovery.

   Hooks as needed: `apply`, `unlocks`, `completed`, `veil`, `reveals`,
   `study`.
2. **Register it**: one line in `techs` in `game/progression.zig`.
3. **Strings**: `[research] <id>.name/.desc`.
4. **No layout work**: the sapling places it. If the layout test fails,
   fix the rules in `hud/research.zig`, never the node.

## An item (not a seed or bulb)
1. A tag at the end of `items.Item`, its colour in `infos`.
2. `[item] <id>.name/.short`.
3. Where it comes from (a node, a structure's `output`, a recipe) and
   where it goes.

## A library mesh (part)
1. `gfx/meshes/<name>.zig` with `build(b)` (or a companion struct in its
   owner's file). One line in `parts` in `gfx/meshlib.zig` (draw order).
2. A new see-through role goes in `vertex.seeThrough`.
3. If a structure emits it, add it to that structure's `meshes`.

## A HUD panel
1. **Its module**: `game/hud/<name>.zig` with `draw(g, d, W, h)`
   (+ `visible(g)`).
2. **Register it**: one line in `panels` in `game/hud.zig` (later draws
   on top).
3. **Clickable things**:
   - The panel's own `pub const Pick` union, made into a HUD pick with
     `hud.row(.<panel>, ...)`.
   - Their area is a `hud.Box` (x, y, w, h) passed to `g.rows.add`.
   - What a click does is the panel's `click(g, p, press, in)` hook
     (play.zig never switches over picks).
   - The item a row shows (for the tooltip) is its `shows(g, p)`.
   - `hud.own` reads the pointed row back as the panel's `Pick`.
   - A button-like row clicks on release: `fire(p)` returns `.release`
     (slots and stems keep the default, `.press`).
   - A row held and dragged (a stem, a slider) is its `drag(g, p, box,
     at)`; left/right turning a focused row's value is its `nudge`.
   - The keys and pad reach every row of the top panel but those whose
     `focusable(p)` is false.
   - A row typed into gives its input with `edit(g, p)` and hears what
     the typing did with `typed(g, p, fed)`; setting `g.typing` to it
     makes it the one typed into.
4. **The panel itself** is `hud/panel.zig`'s `Panel` (`Panel.menu` for a
   veiled menu): its trellis, title and click-swallowing backdrop. Lay
   its rows out with the engine's `layout.Column`/`Grid`.
5. **Item slots** use the `hud/slot.zig` component, never a hand-drawn
   husk. A `Slot` is a box, a pick, and the husk's share of the box. It
   registers its box, draws the husk and glows, and its look scales with
   the box.
6. **Buttons** use `hud/button.zig` (`Button`: its middle, label, pick
   and box height); the engine's `ui/button.zig` says whether it is idle,
   hovering, pressed, held or released, the component only how each
   looks. A row that is a button in its own layout asks `stateOf(g, pick,
   box)`. Settings use `hud/toggle.zig`, `hud/picker.zig` and
   `hud/slider.zig`; a list longer than its room uses `hud/scroll.zig`
   (`List`: rows sliding by, cut to its box with `Draw.clipTo`, its stem).
7. **Text inputs** are an engine `TextInput(cap, accept)` fed each frame
   by `play/pointer.zig` (typed, the caret moved, selection, erase both
   ways, cut, paste, enter) and drawn by `hud/field.zig`, the text kept
   to the input's `alignment` (left, centre, right).
8. **Strings** under `[hud]`.

## A render pass
1. **Its module**: `render/passes/<name>.zig` with `desc` (`.target`),
   `prepare`, `record` (+ `Frame`, `initFrame`/`deinitFrame`). Its `desc`
   embeds its SPIR-V (`.vert = @embedFile("x.vert")`).
2. **Register it**: one line in `passes` in `render/renderer.zig` (record
   order; `.target` picks the stage: shadow, overhead, world, volume,
   screen, [engine.md](engine.md#renderer)).
3. **New shaders**: the file in `shaders/` with a `//!` header after
   `#version`, and its name in `shaders` in `build.zig`.

A pass any game could use goes in the engine instead
(`engine/src/render/passes/`, shaders in `engine/shaders/` and
`engine/build.zig`; [engine.md](engine.md)).

## An input
1. An `ctl.Action` tag in `game/controls.zig`.
2. A `[bind]` line in `src/cfg/controls.cfg`.
3. Its name in `[action]` of `src/cfg/parasymi.cfg` (the keybinds menu).
4. Text names it as `{@action}`.

Test catches: an unbound or unnamed action.

## A player-facing string
1. A field in `txt.Strings` (`game/text.zig`).
2. A line in `src/cfg/parasymi.cfg`.
3. Read it via `txt.s.*`.

Test catches: a missing/unknown key.

## A source file
1. Give it a `//!` header (first sentence = what it is).
2. Run `zig run tools/filemap.zig` to refresh [files.md](files.md).
