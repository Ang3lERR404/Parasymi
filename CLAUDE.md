# CLAUDE.md

Parasymi: a player-centric Factorio-like automation game of magically
infused plants (symbiotic, parasitic and radiant lineages that converge).
Zig 0.16, zglfw + vulkan-zig (Vulkan 1.3), Windows only. No asset files:
every mesh, the font and all UI shapes are procedural; the only data files
are `src/cfg/parasymi.cfg` (strings), `src/cfg/controls.cfg` (bindings) and
animation clips in `src/anim/*.anim` and sculpts in `src/mesh/*.mesh` (from
the tools' editors; the game reads neither yet).
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
| how anything looks or moves | [docs/visual.md](docs/visual.md) |
| a structure mesh / anything that grows | [docs/growth.md](docs/growth.md) |
| a mesh kit (structure, parasite, convergence, radiant, mineral, sculpt, wolf) | [docs/kits/README.md](docs/kits/README.md) + its `_desc.md` |
| checking one plant/structure in game | [docs/testing.md](docs/testing.md) |
| strings, inputs, threads, math, materials, passes | [docs/architecture.md](docs/architecture.md) |
| frame time, LOD, culling, threading | [docs/performance.md](docs/performance.md) |
| shaders, for speed | [docs/shader-optimization.md](docs/shader-optimization.md) |
| player controls | [docs/controls.md](docs/controls.md) |

When a change alters what one of these says, update it in the same commit.

## Rules
- **Visual authority**: the user calls the shots on art direction, with NO
  compromises. Their word on look, motion, proportions, silhouette,
  material, technique ("on the GPU") and "does this read as X" is final.
  Build exactly what they describe: never a cheaper/simpler/"equivalent"
  substitute, never a stand-in called done. If it can't be done as
  described, research another way that delivers exactly that. Ambiguous →
  ask. "Off", "weak", "generic", "too X" is the acceptance criterion.
- **Scope guard**: no multiplayer, PBR/IBL, further post-processing
  or Linux/macOS without explicit direction; flag and stop if a task drifts
  there.
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
- **Working**: commit and push `devel` after every verified change (builds,
  tests pass) without asking; never commit `parasymi.sav`; report broken
  work, don't commit it. Verify visual work in the running game
  (`--plant`/`--structure` + `--inspect` shots, read the PNGs) and say what
  was not checked.
- **Reports**: a short list of changes; a real deviation or blocker as one
  bullet.

## Build and run
```
zig build test                    # headless logic tests (no window/GPU)
zig build run                     # debug (validation on)
zig build run -Drelease=true      # ReleaseFast (-Doptimize is not accepted)
zig build run -- --demo           # test garden + structures, fast-forwarded
zig build run -- --stress         # 120×120 plant field
zig build run -- --load           # newest saved garden
zig build run -- --plant=<species> | --structure=<kind> [--state= --period=]
                                  # one thing alone (docs/testing.md)
zig build run -- --inspect=<player|eyes|species|kind|x,z> --shots=N --orbit=S --dist=D --pitch=P
                                  # orbit + screenshots to shots/, then quit
zig build run -- --panel=<belly|research|paused|options|gardens>
                                  # hold a HUD panel open (kept in --inspect shots)
zig build run -- --tod=0.5 --seed=0x1234 --novsync
zig build animedit -- --wolf | --plant=<species> | --structure=<kind> [--clip=<name> --at=S --channel=<name> --shot]
                                  # animation editor (tools/animedit.zig): keys a clip
                                  # on the real renderer, saves src/anim/<name>.anim;
                                  # wolf joints are clickable, their gizmo keys them
zig build meshedit -- [--mesh=<name> --gizmo=move|turn|size --shot]
                                  # mesh editor (tools/meshedit.zig): SDF forms melted
                                  # into one surface beside the wolf, saves src/mesh/<name>.mesh;
                                  # the selected form's gizmo (1/2/3) moves, turns, sizes it
                                  # (gizmos: tools/gizmo.zig)
```
Each start grows a fresh world; `--seed=` repeats one; `--demo`/`--stress`/
`--plant`/`--structure` use `play.DEFAULT_SEED`. Needs `VULKAN_SDK`
(`vk.xml` + `glslc`). Pinned: vulkan-zig `zig-0.16-compat`, zglfw
`f04fdbf` (upstream heads need 0.17), zig-wsapi `4f64035` (its `zig-0.16`
branch; the engine's `wasapi`, Windows audio). A stray `CPATH` breaks GLFW's C
build. New shaders go in `build.zig`'s list (the engine's in
`engine/build.zig`'s); `zig build test` also runs the engine's tests.

## Layers (import only downward)
`engine/src/` (`@import("engine")`, never imports the game):
```
core      math, color, rng, noise, registry, jobs, text, png
platform  input, display (fullscreen)
anim      joint turns, two-bone IK, skinning matrices, keyframed clips
gfx       Vulkan ctx, swapchain, buffers, pipelines, mesh/UI/light layouts,
          mesh builder + primitives (Mesher), SDF sculpting,
          growth splines (Grower)
world     chunk grid, World(L) streaming
render    Renderer(G) frame orchestration, post (bloom, AA), light, camera, ui pass
ui        SDF draw batch, font
```
`src/` (the game):
```
gfx       meshgen (plant pieces), meshlib, growth (the garden's Grower), kits,
          instance layouts
world     chunks (tile SoA + occupancy), generation, the garden's World
sim       items, species, plants (footprints, floaters), ecology tick
game      player, actions, structures, research, craft, sky, hud, view, play, save
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
| structures | `game/structures.zig` | `def`, `State`, `tick`, `link`, `wants`, `output`, `gives`, `receive`, `release`, `configure`, `recipes`, `chosen`, `choose`, `emit`, `describe`, `ground`, `field`, `hold`, `icon`, `meshes`, `meets`, `adopts`, `pairs` |
| research | `game/progression.zig` | `def` (`.branch` for big steps), `apply`, `unlocks`, `completed`, `veil`, `reveals` |
| seed icons | `game/seeds.zig` | `item`, `icon` |
| hud panels | `game/hud.zig` | `draw`, `visible` (draw order = declaration order) |
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
  matrix is a bug.
- Threads only via `jobs.each` on `w.io`, results identical to serial,
  with a test proving it. Never spawn threads or keep a pool.
- Dense per-element visual work runs on the GPU, never per frame/chunk on
  the CPU.
- `WorldPush` ≤ 192 bytes. A new see-through part role goes in
  `vertex.seeThrough`. A structure that emits a library mesh lists it in its
  `meshes` hook.
- Bump `save.VERSION` when a stored layout changes.

Meshes:
- Every flower has stamens (`meshgen.stamens`); closed buds hide theirs.
- Geometry watertight and seamless (shared rings, capped tubes/lofts,
  smooth deformation fields only).
- Grown vines are Catmull-Rom splines (`growthPath()`/`grow()`), root
  fixed, tapering to a point at both ends.
- Leaves and petals have a body (`meshgen.lamina`); leaves fold to a
  midrib, petals have none.
- Structures grow along a `growth.Skeleton`, timing from the skeleton
  only ([docs/growth.md](docs/growth.md)).
- Radiant things are gathered, never grown: `radiant_kit` fragments only,
  no splines.
- Wolf meshes are built in bind space and skinned, never rigid.
- Research layout is never hand-placed; fix the layout rules.

## Style
- 2-space indent, `name:Type`, terse `//!`/`///` docs. No inline
  `std.ns.Name`: alias at file top.
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
Done and next: [docs/design.md](docs/design.md#roadmap). Next (vertical
slice): first world event (the diamond is its launch point), one "wow"
visual moment (sky shift at convergence). Target: a stranger plays 2 hours
and says "I want to see what happens next."
