# Testing one plant or structure

For the headless tests: `zig build test` runs them all;
`zig build test -Dtest-filter=<text>` runs only those whose names hold
`<text>` (the test's own words, or its module path such as
`game.sound`), in the game's, the engine's and the editors' tests
alike. Given more than once, a test holding any of them runs.

`--plant`, `--structure`, `game/specimen.zig`.

This is the way to check a species' or structure's growth, look and work:
one thing alone in a fresh world. No demo garden, no scratch edits.

Use it whenever any of these change:

- a species or its genome;
- a plant kit (`structureKit` plant, `parasiteKit`, `convergenceKit`,
  `radiantKit`, meshgen drift);
- a structure, its mesh, growth skeleton or `emit`;
- plant or part shaders.

## Putting it down
`--plant=<species>` (a `species.Id` tag) or `--structure=<kind>` (a
`st.Kind` tag).

- **Where:** on the free tile nearest spawn, in a fresh world. A structure
  goes on a tile edge to edge with a resource node if one is within 8
  tiles, since it may work it.
- The wolf (not drawn) and the camera stand over it.
- **Only the meshes it draws are built** (`Specimen.only`), so loading is
  quick:
  - a species: its own (+ `shadow` for floaters);
  - a structure: `st.meshes(kind)` (its `mesh`, `preview` and `meshes`
    hook) + the resource node meshes.
- **Left out:** the wolf, ghosts and the starlit patches. A plant also has no
  nodes or structures.
- **Ignored:** saves, loads and autosave; also `--demo`/`--stress`/`--load`
  when used with it.
- **A water plant** (`Species.onWater`, the mire lily) gets a pond: a
  spring (`Parts.spring`) pours gently onto its tile until the water
  stands 0.2 m deep (for 90 s of the world's clock at most: on a slope
  it never fills, and left pouring it would flood the land), so it floats
  (give it 30 s or more of `--orbit`). Wild birds of paradise spring up
  round its edge (`--speed=6`, a release build, a few minutes).

## States
`--state=` picks what it shows (default `grow`). A state that does not
suit the thing stops the game (`error.BadState`).

Looping states run `--period=` seconds (default 8; `active` 30), hold
their end 1.5 s, then start again.

| state | for | shows |
|---|---|---|
| `grow` | both | growth (a structure: `grown`) 0 → 1, looped: the growing animation, emitted pieces forming in their tail |
| `0.2..0.8` | both | growth between two shares, looped |
| `0.4` / `mature` (`idle`) | both | held at that growth / grown |
| `wither` | plant | grown, health 1 → 0, looped (wilt; radiant ones come loose, dim) |
| `flow` | plant | grown, sap flow rising and ebbing (sine, one period) |
| `drain` | plant | grown, mana 1 → 0, looped (sap fill) |
| `dark` | plant | grown, a bloom's network dark |
| `live` | plant | real ecology from seed; resown 4 s after grown or dead |
| `turn` | both | grown, turned a quarter (R) every `turn.time` + 1 s: a rooted one pulls its roots out, steps round, digs back in; a floater turns in the air |
| `pluck` | plant | grown and ripe, plucked by the wolf (drawn, for once) as harvest does it in play: it steps up, each pluck bends the plant after its paws, the yield bursts out round them, the plant shivers and springs back, a pod empties to its nub, a bead goes to the belly; ripened full afresh 1.5 s after each harvest |
| `ripen` | plant | grown, its yield ripening 0 → full, looped: the pods swelling in turn, the plant taking on the yield's colour |
| `fill` | plant | grown, a light store (the astrocyme) filling empty → full → empty, looped: its flowers opening bottom up, coming apart top down (`stored`) |
| `unform` | radiant or dying plant | grown, then as the unforming takes it, looped: a radiant one glitches, cracks with light and breaks into shards; a symbiotic or parasitic one withers and crumbles to ash (`PlantInstance.glitch`) |
| `active` | structure | grown and working its real `tick`: every 0.4 s handed one of the next thing it `wants` (a carrier: into it from behind, let go 2 s later), what it made (an `output` it does not want) taken away; put down afresh each loop. Emitted pieces (cups, pours, roots to nodes, lids, crystals) as in play |

### Held states
Held states skip the world's tick. (So a nebularbor held breathes only
its trickle: its roots drink in its tick. Use `active` to see its mist
and cloud, and from about ten seconds in its cloud gathering heavy and raining.)

- A plant gets growth, mana, flow, health and radiating written.
- A structure runs only its `link` hooks (`Structures.link`: a conduit's
  arches), with `grown` set and activity 0.
- Removed, it comes back.

An `active` arsthraxia studies the first open research that takes
ingredients.

### Not covered alone
Anything that needs a partner or neighbours; use `--demo` for those:

- sporecaster/driftbraid pairs;
- Vultrixi tethers to a monfris;
- a polyp's halo from blooms;
- conduit side roots, and crown roots to plants.

## Samples side by side
`--samples=<mesh>,<mesh>,...` lays library meshes (`meshlib` names, up to
8) along the x axis, 3 tiles apart, centred on the free tile nearest
spawn, so looks can be compared at once.

- A look for a structure is its own library mesh, named after the
  structure's mesh (`polypColony` beside `polyp`); it sways as that
  structure does.
- States: `grow`, a share or span of growth, `mature`.
- A sample mesh may list `glows` (`meshlib.Glow`): meshes lit from within
  drawn with it, each throwing its light into the air, as the structure
  would emit them (the arsthraxia's thought-bud hearts).
- Shoot it with `--inspect=player`: the orbit circles the line's middle.

```
zig build run -- --samples=polypColony,polyp,polypHydraPlumed --state=mature --inspect=player --shots=3 --orbit=9 --dist=3.2 --pitch=18 --tod=0.5
```

## What moves: a burst
A still shot is one instant; what lives in motion (a flicker, a spark, a
light that breathes) is checked as motion. `--burst=S` holds the
`--inspect` camera still and spreads its `--shots` over S seconds of the
game's clock; `zig build burst` then lays them out as one contact sheet
(`shots/<focus>_sheet.png`) and measures one spot's light through them,
printed as a curve: a breathing light is a wave, a still one a flat line
("it breathes" / "it is still"), and how much the spot changes from frame
to frame shows a spark jumping. Put the thing in the state that makes it
move first (`--state=active`, `--speed=` to get there sooner).

```
zig build run -- --demo --tod=0.0 --inspect=solcyriphon --burst=6 --shots=24 --dist=7 --pitch=70
zig build burst -- --focus=solcyriphon --shots=24 --at=800,600 --r=40 --cols=6
zig build run -- --structure=weftstone --state=active --speed=8 --inspect=weftstone --burst=2 --shots=18 --dist=1.4 --pitch=8 --tod=0.0
```
`--at=x,y` is the spot in the shot's pixels (unset: its middle), `--r=` its
radius. To prove a change made something move, measure the same spot in a
build without the change: other lights sweeping over it move it too.

What moves outside the game (another game in a borderless window, a
video) is caught with the capture frame, `zig build capture` (or the
gardener's desktop launcher): a see-through, borderless frame, always on
top, sized by its edges and dragged by its band. REC, or F9 wherever the
focus is, records a burst of what shows inside it over the seconds set
(- and +, or the wheel) into `shots/capture/<time>/`: its frames, one
`sheet.png` and `curve.txt` (the middle's light through them, as `zig
build burst` prints it); `shots/capture/latest.txt` names the newest.

## A sculpt in the world
`--sculpt=<name>` stands one of the gardener's sculpts (`src/mesh/<name>.mesh`,
made in the mesh editor) alone on the free tile nearest spawn, drawn
skinned and looping the clip of its own name (`src/anim/<name>.anim`, keyed
in the animation editor with `--mesh=<name>`); without one it stands at
rest. The game reads every sculpt at startup, the first 8 by name.

```
zig build run -- --sculpt=<name> --inspect=player --shots=3 --orbit=6 --dist=1.6 --pitch=15
```

## A playback trail, while the gardener plays
`--record` (or `--record=S`) leaves the game as it is and saves a shot,
HUD and all, every S seconds (5 by default) into `shots/trail_<time>/`:
`<n>.png` beside `<n>.txt`, a note of what the game believed then (the
mode, where back leads, the camera, the wolf's place, the hotbar, what
the cursor points at, every action pressed since the last shot). Read
the newest as they land to watch a playthrough nearly live, and to catch
a bug too quick to describe: the note says what the game thought, the
shot what it drew.

## Talking to Claude while playing (`--link`)
The game and Claude meet in `link\` in the project folder (the working
directory both start in; `game/link.zig`, kept out of git): plain files,
no sockets, so nothing in the game ever waits on Claude. Not AppData: the
Claude app is a packaged app, and Windows gives it and all it starts a
private copy of AppData, so a game started from the gardener's own
console and the bridge would each look in a different folder. Start the
game from the project folder.
- **The game** (`--link`): Enter opens the chat sidebar (WHISPERS) at the
  right; type, Enter sends, Esc closes (the world holds still while
  typing). Claude's answers hang beside play for 20 s, fading. The game
  rewrites `state.txt` each second (the trail's note), and answers a
  `wantFrame` with `frame.png` (half size, HUD and all).
- **The bridge** (`tools/bridge.zig`, `zig-out/bin/bridge.exe`, built by
  `zig build`): the MCP server Claude Code starts from `.mcp.json`. Tools:
  `reply` (into the sidebar), `game_state`, `game_frame`. It pushes each
  message the gardener sends into Claude's session as a channel event.
- **Pushing needs channels**, a Claude Code research preview: a terminal
  session (not the desktop app) started in this folder with
  `claude --dangerously-load-development-channels server:parasymi`
  (confirm the development-channel prompt and the new MCP server). Without
  the flag the three tools still work; the gardener's messages wait until
  Claude looks.
- Start the game (`zig build run -- --link`), then talk.

### The editors linked (`--link`)
- `zig build meshedit -- --mesh=<name> --link` or `zig build animedit --
  --wolf --link` (any subject): the editor meets Claude through the same
  `link/` folder (`tools/editlink.zig`). Link one thing at a time: the
  game or one editor.
- **The chat card** along the top: Enter opens it, as in the game (the
  key under Esc does too), Enter sends, Esc closes; the editor's own
  keys wait while it is open. While a name field is open (a form's, a
  bone's, a mark's, the sculpt's) Enter finishes the name instead.
  Naming a form or bone in meshedit is **F2**, linked or not (its
  toolbar button stays). Claude's answers show in gold.
- **Claude's tools:** `game_state` and `game_frame` tell and show the
  editor; `reply` lands in its card; `editor_document` gives the open
  sculpt or clip as the text its file holds; `editor_edit` takes a whole
  edited text back. Every change of forms (add, move, turn, size, shade,
  nest, bones) or of keys is one edited text. `editor_view` turns the
  editor's camera at once and answers with the frame: `home` (the first
  view), `focus` (meshedit: form N, from 1), `dots` (meshedit: the
  forms' handle dots shown or hidden, as `v` does), `ui` (the whole UI
  shown or hidden, as f1 does), `at`, `dist`, `yaw`,
  `pitch`, `zoom`, `pan` (across the view), each left out kept
  (`tools/orbit.zig` `Ask`, through `link/view.txt`). So Claude looks
  round a sculpt itself, with no window of its own on the gardener's
  screen and no mouse needed.
- **Every edit is one undoable step:** the editor takes it into its
  history, so ctrl+z takes back anything Claude did. An edit is refused
  (Claude is told why) while the gardener is dragging or typing, or when
  the text does not read. Nothing is saved until the gardener saves.
- **The file is watched** (`tools/ondisk.zig`): about once a second the
  editor looks at its file's modified time, and reads it again only when
  that moved. Holding what the file holds, it shows saved (so a sculpt
  Claude wrote to the file and also sent as an edit is not "unsaved").
  Changed on disk while nothing is unsaved in the editor, the file's is
  taken quietly, one undo step. Changed on disk while the editor has
  changes of its own too, nothing is overwritten: the note says so, the
  state shows it, and the gardener picks: ctrl+s keeps the editor's
  (saved over the file), f5 (the toolbar's "take file's") the file's.
- A bridge started before this was built needs a restart (a new Claude
  Code session) to offer the two new tools.

## Screenshots, unattended
Add `--inspect=<same species/kind>` and shape the orbit, e.g.

```
zig build run -- --plant=vesper --state=grow --period=5 --inspect=vesper --shots=6 --orbit=9 --dist=3.5 --pitch=25 --tod=0.5
zig build run -- --structure=rootDigger --state=active --period=20 --inspect=rootDigger --shots=3 --orbit=12 --dist=3 --pitch=30 --tod=0.5
```

- Shots land in `shots/<name>_<n>.png` after a 3 s settle.
- Read the PNGs to verify.
- A stage held still from every side: `--state=0.5`.
- **A structure in light** (its halo crown and ley-blue leaves,
  [visual.md](visual.md#the-sign-of-light)): alone it stands in no light,
  so hold it in a share of it with `--lit=<0..1>` (with any state; its
  shine eases up to it over a few seconds, so the first shots catch the
  crown gathering), and pick its crown with
  `--crown=<diadem|circlet|orrery|lotus>` (unset: its seed's):

```
zig build run -- --structure=germinator --state=mature --lit=1 --crown=lotus --inspect=germinator --shots=1 --orbit=12 --dist=3.2 --pitch=12 --tod=0.5
zig build run -- --structure=germinator --state=mature --lit=0.5 --inspect=germinator --shots=1 --orbit=12 --dist=3.2 --pitch=12 --tod=0.5
zig build run -- --structure=germinator --state=mature --lit=0.14 --crown=circlet --inspect=germinator --shots=1 --orbit=12 --dist=5 --pitch=4 --tod=0.5
```
  Half lit, the blue reaches halfway down; dim, only a few fragments are
  flying in and only its top tips are blue. In play (`--demo`), the
  germinator and arsthraxia by the solcyriphon wear it by day.

**Which growth each shot shows.** The loop runs from the start, and the
shots are spread over one turn of `--orbit` seconds. So shot `k` of `n`
shows growth about:

```
time   = 3 + k * orbit / n          // 3 s settle, then evenly spaced
growth = (time mod (period + 1.5)) / period   // the loop is period + 1.5 s hold
```

## Lights with shape
The points of light's shadows (rays and shadow wedges in the fog round
the lights nearest the camera) show best by night, low among plants, by
the light where a beam lands:

```
zig build run -- --demo --tod=0.0 --inspect=germinator --shots=2 --orbit=30 --dist=5 --pitch=10
```

For the same view without them, set `lightShadows = off` in the
gardener's `options.cfg` (or OPTIONS, LIGHT SHADOWS) and shoot again.

## Ray tracing on and off
`--rt=on` or `--rt=off` traces shadows as rays or draws them into maps
for this run, whatever OPTIONS says (like `--novsync`; a GPU that cannot
trace rays draws maps either way). Shoot the same view both ways to
compare:

```
zig build run -- --demo --rt=off --tod=0.3 --inspect=player --shots=4 --orbit=2 --dist=4 --pitch=30
zig build run -- --demo --rt=on --tod=0.3 --inspect=player --shots=4 --orbit=2 --dist=4 --pitch=30
zig build run -- --demo --rt=on --tod=0.0 --inspect=solcyriphon --shots=1 --orbit=30 --dist=9 --pitch=12
```

Four shots half a second apart catch the plants swaying: their shadows
must sway with them. The log's last lines say how many triangles cast
(`rays:`) and how often the levels were refitted or built.

## Faster than the clock
`--speed=N` runs the world N times faster: its ticks, its sky and the
air's moisture together, so everything keeps in step. For slow things
watched unattended (a grove's cloud forming and raining takes minutes):
at 6, two minutes show twelve. The air steps at most 0.1 s a frame, so
above about 6 at 60 fps it falls behind the rest.

```
zig build run -- --speed=6 --demo --inspect=nebularbor --shots=4 --orbit=120 --dist=22 --pitch=25
```

## First person
`--inspect=eyes` looks out of the wolf's eyes, turning round where it
stands, `--pitch=` degrees down (65 shows its chest and belly), e.g.

```
zig build run -- --demo --inspect=eyes --shots=4 --orbit=8 --pitch=30
```

## The unforming
`--unforming` begins the world event at once (its study learned), so it
can be watched unattended. With `--demo` the halo garden's blooms and
vespers shatter and the seed gathers over them; first person shows the
sky shattering, e.g.

```
zig build run -- --demo --unforming --inspect=eyes --pitch=-25 --shots=14 --orbit=14
zig build run -- --demo --unforming --inspect=polyp --dist=40 --pitch=3 --shots=10 --orbit=20
zig build run -- --plant=bloom --state=unform --period=6 --inspect=bloom --shots=6 --orbit=6 --dist=2.6 --pitch=15 --tod=0.5
zig build run -- --plant=lumenroot --state=unform --period=6 --inspect=lumenroot --shots=6 --orbit=6 --dist=2 --pitch=15 --tod=0.5
```
The star the seed gathers in hangs 14 m over the radiant plants' middle:
to see it, orbit that ground point from far and low (`--inspect=x,z
--dist=55 --pitch=1`; a negative pitch turns the camera over).
Its sound is checked headless (`sound/unforming.zig`'s test: it sounds in
every stretch, softly, the landing loudest, and rings away).
`--act2` begins the garden in act 2 after running the unforming through
(`--act2 --demo`: a planted seed, a yielder, a settled heart and two
tendrils, one rising over its middle and falling again, one on the
ground, run 200 s on):
the star hyena is the gardener, the strange seed in his keeping. With
`--structure=strangeSeed --state=active` it stands planted alone (a long
`--period=` keeps it from being put down afresh), e.g.

```
zig build run -- --act2 --structure=strangeSeed --state=active --period=2000 --speed=30 --inspect=strangeSeed --shots=4 --orbit=40 --dist=3.2 --pitch=10
zig build run -- --act2 --structure=yielder --state=active --period=2000 --inspect=yielder --shots=3 --orbit=30 --dist=3 --pitch=12
```

## The belly at one size
`--full=F` holds the wolf's belly F full (0..1) whatever it carries;
standing still past a third it takes the belly-rest pose, e.g.

```
zig build run -- --demo --full=1 --inspect=player --shots=6 --orbit=12 --dist=1.1 --pitch=5
```

## A HUD panel
`--panel=<title|belly|research|paused|options|keybinds|gardens|naming>` holds it open and
keeps the HUD in `--inspect` shots (`--panel=overview` roams with alt mode
held on), e.g.

```
zig build run -- --demo --panel=belly --inspect=player --shots=1 --orbit=2
```

Panels grow under the loading screen's fade, so shots show them grown.

## Rules for new things
- **Library meshes:** a structure that emits a library mesh lists it in
  its `meshes` hook (`pub const meshes = .{ .itemPod, ... };`), or
  `--structure` never builds it. The test "a structure alone draws only
  the meshes it declares" runs every kind through `grow` and `active`, and
  fails naming the kind and the missing mesh.
- **New plant inputs:** a new visual input to plants (a new
  `PlantInstance` field the shaders read) gets a state: a tag in `State`
  (+ `parse`, `suits`) and a line in `look`, plus its row here. The tests
  check parsing and loop timing.
