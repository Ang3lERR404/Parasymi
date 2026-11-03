# CLAUDE.md

Parasymi: a player-centric Factorio-like automation game of magically
infused plants (symbiotic, parasitic and radiant lineages that converge).
Zig 0.16, zglfw + vulkan-zig (Vulkan 1.3), Windows only. No asset files:
every mesh, the font and all UI shapes are procedural; the only data files
are `src/cfg/parasymi.cfg` (strings), `src/cfg/controls.cfg` (bindings) and
animation clips in `src/anim/*.anim` and sculpts in `src/mesh/*.mesh` (from
the tools' editors; still procedural: forms melted into one surface at
startup, never stored meshes). The game reads every sculpt and the clip of
its own name at startup (`game/sculpts.zig`, also `sculpts/` in the
gardener's folder) into 8 library slots, drawn skinned, the clip looping.
The generic half (core, platform, Vulkan base, generic renderer and world
streaming, UI) is its own package in `engine/`, reached as
`@import("engine")`; see [docs/engine.md](docs/engine.md).
2.5D top-down 3D camera orbiting the wolf (MMB drag: yaw free, pitch
8°–89°; zoomed all the way in, first person from its eyes; free cam for
inspection).

## Read before you touch
**Before writing any code, read [docs/zig.md](docs/zig.md)** (Zig 0.16
idioms and what not to do), every session.

| Working on | Read first |
|---|---|
| any code | [docs/zig.md](docs/zig.md) |
| finding a file | [docs/files.md](docs/files.md) (one line per source file and shader) |
| the engine package, what is generic, how the game plugs in | [docs/engine.md](docs/engine.md) |
| adding a structure, species, research, item, mesh, panel, pass, input, string | [docs/recipes.md](docs/recipes.md) (every place to wire it) |
| gameplay, structures' behaviour, research, saves | [docs/design.md](docs/design.md) |
| the research tree (its shape, growth, looks, the view) | [docs/research-tree.md](docs/research-tree.md) |
| the light grid: radiant plants, what makes, carries, uses and guards light, its numbers | [docs/radiant-plants.md](docs/radiant-plants.md) |
| the unforming (the first world event, step by step) | [docs/unforming.md](docs/unforming.md) |
| act 2: the star hyena, the constellate lineage, what the gardener decided | [docs/act2.md](docs/act2.md) |
| the constellate tendril's exact look | [docs/tendril.md](docs/tendril.md) |
| how anything looks or moves | [docs/visual.md](docs/visual.md) |
| the constellate tendril (the plexus web, its braid, exact numbers) | [docs/tendril.md](docs/tendril.md) |
| a structure mesh / anything that grows | [docs/growth.md](docs/growth.md) |
| a mesh kit (structure, parasite, convergence, radiant, mineral, sculpt, wolf) | [docs/kits/README.md](docs/kits/README.md) + its `_desc.md` |
| checking one plant/structure in game | [docs/testing.md](docs/testing.md) |
| strings, inputs, threads, math, materials, passes | [docs/architecture.md](docs/architecture.md) |
| frame time, LOD, culling, threading | [docs/performance.md](docs/performance.md) |
| making a frame cheaper (measure, knock-outs, proving the look held, what worked) | [docs/optimizing.md](docs/optimizing.md) |
| shaders, for speed | [docs/shader-optimization.md](docs/shader-optimization.md) |
| player controls | [docs/controls.md](docs/controls.md) |
| what is left to do (the only list of it) | [docs/todo.md](docs/todo.md) |

When a change alters what one of these says, update it in the same commit.

## Rules
- **Visual authority**: the user calls the shots on art direction, with NO
  compromises. Their word on look, motion, proportions, silhouette,
  material, technique ("on the GPU") and "does this read as X" is final.
  Build exactly what they describe: never a cheaper/simpler/"equivalent"
  substitute, never a stand-in called done. If it can't be done as
  described, research another way that delivers exactly that. Ambiguous →
  ask. "Off", "weak", "generic", "too X" is the acceptance criterion.
- **Scope guard**: no multiplayer, PBR/IBL or Linux/macOS without
  explicit direction; flag and stop if a task drifts there.
- **Decision authority**: a layer boundary or build/run interface change →
  stop and ask; otherwise decide and note with `// decision:`.
- **Plant rule**: everything grown has a proper growing animation, is moved
  by the garden's sway and matches the current plant quality.
- **Cohesion rule**: each visual overhaul sets the bar for its kind; the
  whole wolf and all plants/structures are kept up with it; new grown
  things use the shared kits and growth splines, never older primitives or
  whole-structure scaling.
- **Finish line**: work until the phase's criteria are met; take the next
  step instead of "next I would…"; stop only for a blocking decision.
- **Working**: commit `devel` after every verified change (builds,
  tests pass) without asking, and push once 10 commits are waiting
  unpushed, after the sweep below; never commit `parasymi.sav`; report broken
  work, don't commit it. Verify visual work in the running game
  (`--plant`/`--structure` + `--inspect` shots, read the PNGs) and say what
  was not checked.
- **Pre-push sweep**: every 10 commits, before pushing, scan the whole
  codebase: (1) hoist repeating magic numbers to named constants at the
  top of their file, merged into one new or existing tuning file when
  they start to conflict (the engine's and the game's kept apart);
  (2) optimise code to run at its best without changing behaviour or
  the look (verify as usual); (3) round the code out into dedicated
  "class" modules (a struct type with its methods) where it is most
  likely to be reused. Commit the sweep (verified), then push.
- **Reports**: a short list of changes; a real deviation or blocker as one
  bullet.

## Build and run
```
zig build test                    # headless logic tests (no window/GPU)
zig build run                     # debug (validation on); opens on the main menu
zig build run -Drelease=true      # ReleaseFast (-Doptimize is not accepted)
zig build run -- --demo           # test garden + structures, fast-forwarded
zig build run -- --stress         # 120×120 plant field
zig build run -- --load           # newest saved garden
zig build run -- --demo --unforming   # the world event begins at once (docs/testing.md)
zig build run -- --act2           # act 2 after the unforming: the star hyena (docs/testing.md)
zig build run -- --plant=<species> | --structure=<kind> [--state= --period=]
                                  # one thing alone (docs/testing.md)
                                  # a structure: --lit=S holds it in light (crown,
                                  # ley-blue), --crown=diadem|circlet|orrery|lotus
zig build run -- --sculpt=<name>  # one of your sculpts alone, looping its clip
zig build run -- --samples=<mesh>,<mesh>   # looks side by side along x (docs/testing.md)
zig build run -- --inspect=<player|eyes|species|kind|x,z> --shots=N --orbit=S --dist=D --pitch=P
                                  # orbit + screenshots to shots/, then quit
zig build run -- --panel=<title|belly|research|paused|options|keybinds|gardens|naming|overview>
                                  # hold a HUD panel open (kept in --inspect shots)
zig build run -- --tod=0.5 --seed=0x1234 --novsync
zig build run -- --full=0.7       # the wolf's belly held 70% full (docs/testing.md)
zig build run -- --speed=6        # the world runs 6x faster (ticks, sky, air together;
                                  # for slow things watched unattended, docs/testing.md)
zig build animedit -- --wolf | --plant=<species> | --structure=<kind> | --mesh=<sculpt> [--clip=<name> --at=S --channel=<name> --shot]
                                  # animation editor (tools/animedit.zig): keys a clip
                                  # on the real renderer, saves src/anim/<name>.anim;
                                  # wolf joints are clickable, their gizmo keys them
                                  # (both editors: a toolbar of buttons down the right
                                  # side does what every key does; `h` shows the help)
                                  # the camera orbits freely as meshedit's, `.` focuses
                                  # the selected joint (tools/orbit.zig)
zig build meshedit -- [--mesh=<name> --gizmo=move|turn|size --shot]
                                  # mesh editor (tools/meshedit.zig): SDF forms melted
                                  # into one surface on bare ground, saves src/mesh/<name>.mesh;
                                  # the selected form's gizmo (1/2/3) moves, turns, sizes it;
                                  # `m` picks the shader (part role) a form is drawn with;
                                  # `x` twins a form mirrored across the middle (x=0);
                                  # click the path (top left) to rename the sculpt: its
                                  # clip and every nest using it follow (`--rename=`)
                                  # `t` shapes (tubes curl; a nest places another
                                  # sculpt as one form, `p` picks it), `i` inks,
                                  # ctrl+click groups, `g` snaps;
                                  # `j` rig mode: bones (joint, parent, twin) the skin
                                  # rides, test-turned to try it; `o` a form's bone
                                  # (`--rig`, `--try=p,y,r` for shots)
                                  # the camera orbits freely, `.` focuses the selected form
                                  # (gizmos: tools/gizmo.zig)
                                  # both editors: ctrl+z undo, ctrl+y redo, a whole
                                  # drag one step (tools/history.zig)
zig build audiocheck              # sound path check (tools/audiocheck.zig): plays a
                                  # dsp.Voice through platform.audio, records it back by
                                  # loopback, fails unless heard at its pitch (needs speakers)
```
Each start grows a fresh world; `--seed=` repeats one; `--demo`/`--stress`/
`--plant`/`--structure` use `play.defaultSeed`. Needs `VULKAN_SDK`
(`vk.xml` + `glslc`). Pinned: vulkan-zig `zig-0.16-compat`, zglfw
`f04fdbf` (upstream heads need 0.17), zig-wsapi `4f64035` (its `zig-0.16`
branch; the engine's `wasapi`, Windows audio). A stray `CPATH` breaks GLFW's C
build. New shaders go in `build.zig`'s list (the engine's in
`engine/build.zig`'s); `zig build test` also runs the engine's tests.

## Layers (import only downward)
`engine/src/` (`@import("engine")`, never imports the game):
```
core      math, color, rng, noise, registry, jobs, text, png, dsp
platform  input (keys, mouse, gamepad, clipboard), display (fullscreen),
          audio (WASAPI output)
anim      joint turns, two-bone IK, skinning matrices, keyframed clips
gfx       Vulkan ctx, swapchain, buffers, pipelines, mesh/UI/light layouts,
          mesh builder + primitives (Mesher), SDF sculpting,
          growth splines (Grower)
world     chunk grid, World(L) streaming
render    Renderer(G) frame orchestration, post (bloom, AA), light, camera, ui pass
ui        SDF draw batch (clipped), font, layout box (x, y, w, h + hit test),
          columns and grids, buttons, text inputs, scroll, slider, focus
```
`src/` (the game):
```
gfx       meshgen (plant pieces), meshlib, growth (the garden's Grower), kits,
          instance layouts
world     chunks (tile SoA + occupancy), generation, the garden's World
sim       items, species, plants (footprints, floaters), ecology tick
game      player, actions, structures, research, craft, sky, sound, hud, view, play, save
render    the garden's renderer (passes, scene, mesh growing), terrain meshing
main      wiring, frame loop, save/load/fullscreen requests
lib       the import hub: std, engine and every game module (`@import("parasymi")` in tools/)
```
Game files import only `lib.zig` (`const lib = @import("../lib.zig"); const
std = lib.std;`), never another file by path; a new module gets one line
there. Registry part lists still `@import` their own members. The layer
order above still holds for what a module may use.

## Registries
One module per thing; enum via `std.meta.DeclEnum`, dispatch via
`switch (id) { inline else => |k| reg.module(k).hook(...) }`, hooks optional
(`reg.has`). Adding a thing = one file + one line. Never `switch` over
registry kinds outside the registry file; add a hook.

| Domain | Entry | Hooks |
|---|---|---|
| species | `sim/species.zig` | `def` (genome drives the grown mesh) |
| meshes | `gfx/meshlib.zig` | `build(b)` (order = draw order: translucent after what they cover) |
| structures | `game/structures.zig` | `def`, `State`, `tick`, `link`, `wants`, `output`, `gives`, `receive`, `release`, `handOver`, `message`, `configure`, `recipes`, `chosen`, `choose`, `sown`, `emit`, `describe`, `ground`, `field`, `hold`, `icon`, `meshes`, `meets`, `adopts`, `pairs`, `crownAt` |
| research | `game/progression.zig` | `def` (`.branch` for big steps), `apply`, `unlocks`, `completed`, `veil`, `reveals` |
| seed icons | `game/seeds.zig` | `item`, `icon` |
| hud panels | `game/hud.zig` | `draw`, `visible` (draw order = declaration order), `Pick`, `click`, `shows`, `fire`, `focusable`, `drag`, `nudge`, `edit`, `typed`, `atTitle` (drawn at the main menu) |
| render passes | `render/renderer.zig` (`passes`; engine `Renderer(G)`) | `desc` (`.target`: shadow/world/screen), `Frame`, `initFrame`/`deinitFrame`, `prepare`, `record` |

Items (`sim/items.zig`, ids stored by value: new items go last) and weave
recipes (`game/craft.zig`) are plain data tables.

## Hard invariants (tests or asserts catch most)
Code:
- No hard-coded player-facing strings: field in `txt.Strings` + cfg line,
  shown via `txt.s.*`; never name a key in text, write `{@action}`.
- No hard-coded inputs: an `ctl.Action` tag + a `controls.cfg` line; never
  `glfw.Key`/`Button` in game code.
- All math via engine `core/math.zig` (`m`), colours via `core/color.zig`; never
  `std.math`, hand-rolled casts or hand-rolled linear algebra. A singular
  matrix is a bug. Use its helpers over writing them out: `Vec`/`Vice`/`Mat`
  (never bare `@Vector` or small `[N]T`), `dist`, `unlerp`, `damp`/`dampV`/
  `dampBy` (never `x+=(t-x)*@min(1,dt*k)`), `sumOf`, `meanOf`, `lenOf`,
  `splatOf` ([docs/architecture.md](docs/architecture.md#math) has the
  table); a pattern that repeats gets a new helper with a test.
- Threads only via `jobs.each` on `w.io`, results identical to serial,
  with a test proving it. Never spawn threads or keep a pool (the audio
  device's render thread is zig-wsapi's own, fed through `audio.Output`;
  work beside the frames that touches no game state, the renderer's mesh
  growing and `--inspect` shot writing, runs as an `io.concurrent` task,
  awaited before what it holds is freed).
- Dense per-element visual work runs on the GPU, never per frame/chunk on
  the CPU.
- `WorldPush` ≤ 192 bytes. A new see-through part role goes in
  `vertex.seeThrough`. A structure that emits a library mesh lists it in its
  `meshes` hook.
- Bump `version` in `save.zig` when a stored layout changes (not for structures:
  they are `record`s, read by field name; a `State` owning memory has a
  `deinit`, and `Structures.remove`'s result is the caller's to `deinit`).

Meshes:
- Every flower has stamens (`meshgen.stamens`); closed buds hide theirs.
- Geometry watertight and seamless (shared rings, tubes/lofts closed in
  rounded ends, `Builder.tips`; smooth deformation fields only). Only
  thorns and claws keep sharp points (`.sharp`).
- Grown vines are Catmull-Rom splines (`growthPath()`/`grow()`), root
  fixed, tapering at both ends to a rounded point; a branch flares into
  the stem it leaves (`meshgen.collar`).
- Leaves and petals have a body (`meshgen.lamina`); leaves fold to a
  midrib, petals have none.
- Structures grow along a `growth.Skeleton`, timing from the skeleton
  only ([docs/growth.md](docs/growth.md)).
- Radiant things are gathered, never grown: `radiantKit` fragments only,
  no splines.
- Wolf meshes are built in bind space and skinned, never rigid.
- Research layout is never hand-placed; fix the layout rules.

## Style
- Names: camelCase for everything (functions, variables, constants,
  fields, enum tags, registry members, cfg keys); only types are
  PascalCase. File names stay snake_case (`sap_cache.zig` holds
  `sapCache`). Outside names (std, vulkan, glfw key names) stay as they are.
- Whitespace: none that isn't needed. `pub fn f(a:T,b:U)R{`, `a+b*c`,
  `const x=y;`, `.{.x=0}`, `if(x)|v|{`, `}else{`; a binary operator spaced
  on one side (a line break, or `a - -b`) is spaced on both. 2-space indent.
  Zero blank lines anywhere; a comment sits directly above its code, a
  space after `//`, `///`, `//!`. Never run `zig fmt` (it undoes this).
- Locals start as `var inv=Inventory{};`, the type on the value.
- Docs: every declaration, field, enum tag, constant and variable has a
  doc comment (`///`; `//` for locals, where Zig rejects `///`), in the
  project's poetic voice and also saying plainly what the code does.
  `docs/*.md` read the same way: for people first.
- No inline `std.ns.Name`: alias at file top.
- Tagged unions for exclusive states (`Game.mode`, `Camera.view`,
  `Display.mode`, `Occ.get()`); explicit error sets in public APIs (folded
  via `ctx.fold`); distinct ID types (`PlantId`, `StructId`, `MeshSlot`,
  `Occ`).
- `comptime T: type` over `anytype`; exhaustive `switch`; explicit
  allocators; `defer deinit()` at once, `errdefer` on init paths; arenas
  for batch work; `std.testing.allocator` in tests; SoA for hot loops;
  `try` by default, translate errors at module boundaries.
- Edits: write content to files and pass files to scripts; no big inline
  heredocs.
- Line endings: always LF (`.gitattributes` `eol=lf`). Python on Windows
  writes CRLF unless `newline=''`.
- Every source file and shader starts with a `//!` header (a shader's
  right after `#version`); after adding, removing or re-describing one,
  run `zig run tools/filemap.zig` to refresh `docs/files.md`.

## Zig 0.16
`std.Io` replaces old I/O (pass an `Io` like an allocator). "Juicy Main":
injected params, no global env/args. `@Type` removed (`@Pointer`,
`@ErrorUnion`, explicit `error{...}`). `ArrayList{}` → `.empty`;
`ArenaAllocator` is lock-free. Build: `root_module` + `Module`; deps in
`zig-pkg/`.

## Where things stand
Done and next: [docs/design.md](docs/design.md#roadmap). The vertical
slice's list is done (the first world event, launched from the diamond, and
the sky shift at convergence); what comes next is the gardener's to name.
Everything still to add, change or mend lives in [docs/todo.md](docs/todo.md)
and nowhere else: a kept idea is written there, a finished one struck.
Target: a stranger plays 2 hours and says "I want to see what happens next."
