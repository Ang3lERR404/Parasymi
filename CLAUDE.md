# CLAUDE.md

## What this is
Player-centric Factorio-like automation game: magically infused plants
(parasitic + symbiotic lineages that converge). Zig 0.16, zglfw + vulkan-zig
(Vulkan 1.3), Windows, no asset files (every mesh, the font and all UI shapes
are procedural) except `parasymi.cfg`, the player-facing strings, and
`controls.cfg`, the key/button bindings (both built into the game and written
out to the gardener's folder, below). 2.5D top-down 3D: pitch 30°–85° (default 55°), yaw Q/E, no
free rotation in play; free inspection camera on Ctrl+F.

## Build
```
zig build run                     # debug (validation on)
zig build run -Drelease=true      # ReleaseFast (-Doptimize is not accepted)
zig build run -- --demo           # test garden + structures, fast-forwarded
zig build run -- --stress         # 120×120 plant field
zig build run -- --tod=0.9        # time of day (0=midnight, 0.5=noon)
zig build run -- --novsync --seed=0x1234
zig build run -- --load           # load the newest saved garden
zig build run -- --demo --inspect # orbit the wolf, screenshots to shots/, then quit
zig build run -- --inspect=bloom --shots=12 --orbit=30 --dist=6 --pitch=25
                                  # focus: player | <species> | <structure> | x,z
zig build run -- --plant=bloom --state=wither --period=6
zig build run -- --structure=germinator --state=active
                                  # one thing alone, only its meshes built, never
                                  # saved; states held or looped (see Testing one
                                  # plant or structure)
zig build test                    # headless logic tests (no window/GPU)
```
Needs `VULKAN_SDK` (`vk.xml` + `glslc`). Pinned: vulkan-zig `zig-0.16-compat`,
zglfw `f04fdbf` (upstream heads need 0.17). A stray `CPATH` breaks GLFW's C
build. New shaders go in `build.zig`'s list.

## Testing one plant or structure (`--plant`, `--structure`, `game/specimen.zig`)
The way to check a species' or structure's growth, look and work: no demo
garden, no scratch edits. Use it whenever a species, its genome, a plant
kit (`parasite_kit`, `convergence_kit`, `radiant_kit`, meshgen herb/
drift), a structure, its mesh/growth skeleton/`emit`, or plant/part
shaders change.
- `--plant=<species>` (a `species.Id` tag) / `--structure=<kind>` (a
  `st.Kind` tag) puts it down on the free tile nearest spawn in a fresh
  world (a structure on one edge to edge with a resource node if any is
  within 8 tiles, for it may work it), the wolf (not drawn) and camera
  over it. Only the meshes it draws are built (`Specimen.only`), so loading
  is quick: a species' own (+ `shadow` for floaters); a structure's
  `st.meshes(kind)` (its `mesh`, `preview` and `meshes` hook) + the
  resource node meshes. The wolf, motes, ghosts and starfall are left out;
  a plant also has no nodes or structures. Saves, loads and autosave are
  ignored; `--demo`/`--stress`/`--load` are ignored with it.
- `--state=` (default `grow`); a state that does not suit the thing stops
  the game (`error.BadState`). Looping ones run `--period=` seconds
  (default 8; `active` 30), hold their end 1.5 s, start again:
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
  | `active` | structure | grown and working its real `tick`: every 0.4 s handed one of the next thing it `wants` (a carrier: into it from behind, let go 2 s later), what it made (an `output` it does not want) taken away; put down afresh each loop. Emitted pieces (cups, pours, roots to nodes, lids, crystals) as in play |
  Held states skip the world's tick: a plant gets growth, mana, flow,
  health, radiating written; a structure runs only its `link` hooks
  (`Structures.link`: a conduit's arches) with `grown` set and activity 0.
  Removed, it comes back. An `active` arsthraxia studies the first open
  research that takes ingredients.
- Not covered alone: what needs a partner or neighbours (sporecaster/
  driftbraid pairs, Vultrixi tethers to a monfris, a polyp's halo from
  blooms, conduit side roots and crown roots to plants); use `--demo` for
  those.
- Unattended, with screenshots: add `--inspect=<same species/kind>` and
  shape the orbit, e.g.
  `zig build run -- --plant=vesper --state=grow --period=5 --inspect=vesper --shots=6 --orbit=9 --dist=3.5 --pitch=25 --tod=0.5`
  `zig build run -- --structure=root_digger --state=active --period=20 --inspect=root_digger --shots=3 --orbit=12 --dist=3 --pitch=30 --tod=0.5`
  (shots land in `shots/<name>_<n>.png` after a 3 s settle; the loop runs
  from the start, so shot k of n over a turn of `--orbit` seconds shows
  growth about `((3 + k·orbit/n) mod (period+1.5)) / period`). Read the
  PNGs to verify. A stage held still from every side: `--state=0.5`.
- A structure that emits a library mesh lists it in its `meshes` hook
  (`pub const meshes = .{ .item_pod, ... };`), or `--structure` never
  builds it. The test "a structure alone draws only the meshes it
  declares" runs every kind through `grow` and `active` and fails naming
  the kind and the missing mesh.
- A new visual input to plants (a new `PlantInstance` field the shaders
  read) gets a state: a tag in `State` (+ `parse`, `suits`) and a line in
  `look`, plus its row here; the tests check parsing and loop timing.

## Controls
Defaults in `controls.cfg` (rebindable there): WASD move, Shift run, Q/E yaw, Ctrl+W/S pitch, wheel zoom. LMB gather/place,
RMB uproot, F harvest/feed, Shift+F take, C configure, R rotate. 1–9/0/-/=/Backspace pick
hotbar slots only; research nodes and weave recipes are clicked in their
panels. Hotbar slots start empty: in the belly a click lifts a stack onto
the cursor, the next puts it down (empty slot, merge, or swap: sorting by
hand); dropped on a hotbar slot it assigns that item (any item); a lifted
hotbar item swaps or, dropped elsewhere, comes off; RMB clears a hotbar
slot. Every item stacks to 100 (`items.STACK`). Delete (`discard`) throws
away the belly stack under the cursor (or carried), never a structure's.
Hovering a slot shows the item's full name. LMB on a structure that
keeps items (`Def.store`: sap cache, germinator, arsthraxia, digger)
opens its panel (`Mode.structure`, `hud/structure.zig`): its slots beside
the belly's, lifted/put down between them the same way (into it only what
it `wants`), Shift+LMB moves a stack across; a germinator's panel also
picks what it weaves, any weave (`recipes`/`chosen`/`choose` hooks). Closes out of reach.
Tab belly (weave), T research, F3 debug, Esc closes a panel else
pauses (pause rows are clicked or keyed: Q = save and quit, O = options,
G = saved gardens), F5 save (the garden being played), F9 load (its last
save), F11 fullscreen. Options panel: LMB turns a setting, RMB turns it
back, Esc/BACK returns to the pause menu. Saved gardens panel (pause menu
only, `hud/gardens.zig`, `Mode.gardens`): A FRESH GARDEN then every save,
newest first; wheel or drag its stem to scroll (`GARDENS_SHOWN` rows), LMB
chooses, SAVE (twice to save over one), LOAD, BACK/Esc.
Free cam: click to look, WASD fly (Shift fast), Space/Ctrl+Space rise/sink,
Q/E roll, wheel dolly; eases back in 0.3 s.

## Performance
- Target 8 ms (120 FPS), RTX 3060-class, validation on; 30 Hz fixed sim
  tick (currently 60 Hz, `play.TICK`); chunks 64×64 (currently 32×32),
  < 2 ms gen+upload; < 200 draw calls at stress.
- Measured release GPU time (4060 Ti, 1600×900, no vsync; timestamp
  queries per pass, `Renderer.gpu_ms`, F3 shows the total): demo 5.0 ms
  (AA off) / 5.9 (msaa4) / 7.2 (msaa8), stress 11.1 (msaa8). Built-once
  meshes live in device memory (`Buffer.initWith`); per-frame buffers are
  host-visible. Streaming meshes at most `MESH_MS` (3 ms) of chunks a frame.
- **Computation-heavy work goes on the GPU**: dense or per-element visual
  work (grass, scatter, particles, procedural detail, deformation, animation
  fields) is generated in shaders (instancing, vertex/fragment fields,
  compute), never built on the CPU per frame or per chunk. The CPU keeps
  state and sim and sends small records (a tile's corners, a mote's state,
  four control points).
- Level of detail: every plant and library mesh is built at `meshgen.LODS`
  (3) levels by `Builder.lod` inside the primitives (each level keeps every
  other ring/row and half the sides), so new meshes get it free. Picked by
  eye distance (`lodAt`, `LOD_AT` 36/70). Plant slots (species, variant,
  lod); part slots `meshlib.slot(id, lod)`.
- Worker threads: CPU loops heavy enough to matter are split over cores
  with `jobs.each` (see Conventions). In use: `Plants.rebuildLinks` (per
  plant), `World.stream` generation (per fresh chunk), `syncWorld` meshing
  (`MESH_BATCH` chunks, each its own scratch; Vulkan uploads stay on main).
  Measured gains (release): stress sim 1.6–10 → 0.6–5.6 ms/frame, chunk
  gen 0.50 → 0.20 ms, mesh+upload 0.36 → 0.27 ms. The rest of the CPU
  frame is under 1 ms and hides behind the GPU (frames in flight), so
  profile before threading anything else.
- Culling: chunks (`CHUNK_RADIUS`), plants and parts are culled to the view
  frustum (`m.Frustum`; `Parts.look` sets the frame's eye and view).
- Shader optimization: read `docs/shader-optimization.md` first (researched
  methods, what is art-safe, how to measure per pass, what was applied).
  Optimizations change cost, never the picture; anything that alters the
  look (sample shading, hashes, precision) is the user's call.

## Layers (import only downward)
```
core      math, color, rng, noise, registry
platform  input, display (fullscreen)
gfx       Vulkan ctx, swapchain, buffers, pipelines, meshgen, meshlib
world     chunks (tile SoA + occupancy), generation, streaming
sim       items, species, plants (footprints, floaters), ecology tick
game      player, actions, structures, research, craft, sky, hud, view, play, save
render    renderer + passes, post (bloom), terrain meshing, camera
ui        SDF draw batch, font
main      wiring, frame loop, save/load/fullscreen requests
```

## Registries
One module per thing; enum via `std.meta.DeclEnum`, dispatch via
`switch (id) { inline else => |k| reg.module(k).hook(...) }`, hooks optional
(`reg.has`). Adding a thing = one file + one line. Never `switch` over
registry kinds outside the registry file; add a hook.

| Domain | Entry | Hooks |
|---|---|---|
| species | `sim/species.zig` | `def` (genome drives the grown mesh) |
| meshes | `gfx/meshlib.zig` | `build(b)` (order = draw order: translucent after what they cover) |
| structures | `game/structures.zig` | `def`, `State`, `tick`, `link`, `wants`, `output`, `gives`, `receive`, `release`, `configure`, `recipes`, `chosen`, `choose`, `emit`, `describe`, `ground`, `field`, `hold`, `icon`, `meshes` |
| research | `game/progression.zig` | `def` (`.branch` for big steps), `apply`, `unlocks`, `completed`, `veil`, `reveals` |
| seed icons | `game/seeds.zig` | `item`, `icon` |
| hud panels | `game/hud.zig` | `draw`, `visible` (draw order = declaration order) |
| render passes | `render/renderer.zig` | `desc` (`.target`: shadow/world/screen), `Frame`, `initFrame`/`deinitFrame`, `prepare`, `record` (plants_shadow, parts_shadow, sky, terrain, detail, plants, parts, plants_glass, parts_glass, ui) |

Items (`sim/items.zig`, ids stored by value: new items go last) and weave
recipes (`game/craft.zig`) are plain data tables.

## Conventions
- 2-space indent, `name:Type`, terse `//!`/`///` docs, each file's own line endings (see Edits).
- All math via `core/math.zig` (`m`): scalars, `unorm8`, tiles (`footprint`
  and `ring` iterators, `Chunk.tileOf` back from a local index), `dirs`/`dirVec`/`dirYaw`,
  vectors/matrices, `spring`, `springDamper`, `catmullRom`/`splineResample`,
  `alignY`, `Frustum`. Colours via `core/color.zig`. Never reach into
  `std.math` or hand-roll casts. No inline `std.ns.Name`: alias at file top.
- **Never hand-roll linear algebra**: `m.inverseRigid`, `m.inverseAffine`,
  `m.inverse` only as fallback; add missing methods with a test. A singular
  matrix is a bug (`@panic` in debug).
- **Every flower has stamens** (`meshgen.stamens`: grown filaments, two-lobed
  pollen anthers, `.leaf` so they fold and open with the petals; icons
  `Icon.stamens`). Closed buds hide theirs.
- **Geometry watertight and seamless**: shared rings (parallel transport),
  capped cones/lofts, shared-vertex sheets; deform only with smooth position
  fields so shared vertices move alike.
- **Grown vines are Catmull-Rom splines** via `growthPath()`/`grow()` (the
  root never moves), never a straight line or simple arc, and taper to a
  point at both ends (no hard cuts).
- meshgen primitives: `tubeR`/`tubeC`, `vine`, `braid`/`braidTurned`, `bundle`,
  `loft`, `patch`, `lamina`, `blade`/`bladeAlong`, `petal`, `stamens`, `leavesAlong`, `bands`,
  `ellipsoid`, `cone`. Shared kits (each fully described in
  `docs/kits/<kit>_desc.md`, index `docs/kits/README.md`; update it with
  the kit): `structure_kit` (`rootMat`,
  `footLeaves`, `leafyVine` take an optional `kit.On` to grow on a
  spline), `wolf_kit` (`leaf`, `digit`, `claw`), `sculpt_kit` (SDF forms
  meshed and skinned), `mineral_kit`, `parasite_kit` (the parasitic
  lineage, its plant (`plant`, the coil form) and structures: a symbiote's
  braid gone strange. `lattice`: `FOLD` (5) strands wound each way, woven
  tight round the core, parting into an open cage (pearl beads where they
  cross, tu.y = how far parted) and gathering again; `stalk`/`section`/
  `parted`, `organs` (sacs on the core inside the cage), `crown` (`FOLD`
  fronds alike: one seed, exact turns, all at once, never a golden angle),
  `pod`/`podAt` (the body again, small, at a frond's tip, crowned by
  frondlets: it repeats itself), `foot`, `nodule`, `roots` (exact),
  `bladder`, `frond`/`frondPath`; structures on growth splines; pale skin
  with pearl/core by facing, lilac fronds, `sac` sap), `convergence_kit`
  (the lineages mixed at every scale, never layered: `weave` = a lattice
  of green wandering strands one way and pale exact ones the other,
  violet knots where they cross, banded core; `sac` = amber and blue sap
  swirling in arms, violet between; exact fives carrying living leaves
  and petals: `frond` (lilac, green leaflets, crozier tip), `bloom`
  (pale frondlet calyx, warm petals, stamens); `foot` rooted both ways;
  `plant` for the `entwined` form, `confluence` grown through keys),
  `radiant_kit` (the radiant/celestial lineage, its plants (`plant`, the
  celestial bloom, `radiant` form; `star`, the vesper, `star` form) and
  structures (the diamond,
  meshes/halo.zig): **never grown, only gathered**. No root, stem,
  growth spline or scaling: rigid fragments joined to nothing, each
  marked by `fragment` (tu.x assembly order, tu.y `Ring` + `THREAD`
  share on a thread, colour alpha bearing), coming in from afar on its
  own way, turning round the heart, settling in its turn, held by
  light (`thread`). Pieces: `core` (luminous core, stamen crown of
  light), `whorl` (floating petals, each threaded to the core),
  `leaves` (floating leaves under it, threaded up to it; ring `.leaves`,
  the only fragments that cast shadows), `motes`, `halo` (thin tilted ring), `cut` (a cut crystal, facets
  gathered foot up), `shards`. On the GPU one way for all: common.glsl
  `fragmentOf`, `gatherAway(order, pace, span, k)`, `gatherIn(p, from,
  away, shrink, turn)`/`gatherTurn`; plant.vert (`ARRIVE_*`) by the
  bloom's growth, part.vert (`PRISM_*`) by its halo's pull. A new
  radiant thing is built from these and gathered the same way, never
  with the other kits or growth splines (the test checks every vertex
  is a fragment on no spline).
  Symbiotic structures use
  `structure_kit` and the conduit's `arch` (its weave, spine and side
  roots: `conduit.arch`, `spineCtrl`, `core = null` for a bare weave).
- **Structures grow along growth splines** (`gfx/growth.zig`); every new
  structure mesh (and any piece of one that grows) is built this way, never
  grown by scaling the whole. Every structure is: sap cache, germinator,
  arsthraxia (and its research vines and offshoots), root-digger (and its roots, in
  the digging root to its node, grown by how far it reaches), polyp, conduit (each arch
  its own spline; side roots grown by how far they reach), loomfern,
  lithophage (and its roots), braided conduit (weave and each lane its
  own mesh on the same spline), ganglion (and its nerves), gathering crown
  (and its roots, `Root(n)` per distance), sporecaster. The diamond
  is the radiant lineage's: gathered, not grown (`radiant_kit`).
  - A mesh's `build` lays out a hidden `Skeleton`: `var sk =
    growth.Skeleton.begin(b)`, `sk.trunk(ctrl, .{})`, then `sk.branch(parent,
    u, ctrl, .{})` / `sk.vine(parent, u, mg.Growth, n, .{})` off it (a
    branch's first point is moved onto its parent at `u`). Splines are
    Catmull-Rom, resampled to `growth.RES` points (`sk.get(id).pts`).
  - Build along it: `sk.tube`, `sk.braid`, `sk.leaves` do it in one call;
    for anything else build with the usual primitives, then tag what was
    built since a `b.mark()`: `sk.along(b, mark, id)` (each vertex grows out
    of its nearest point on the spline as the front passes: tubes, braids,
    lofts, pods, bundles) or `sk.on(b, mark, id, u, .{.from, .delay, .span})`
    (one piece grown out of one point once the front reaches `u`: a leaf,
    petal, cup, stamens; stagger a whorl with `.delay`).
  - End with `sk.finish(b)` (it turns times into shares of the growth; a
    debug assert in `meshlib.build` catches a skeleton left unfinished).
  - Timing is the skeleton's alone, never hand-set: a spline takes time ∝
    its length (`Branch.pace`), its front tapers over `Branch.front`; a
    branch starts once its parent is done (`After.done`, default), or as
    the parent's front passes it (`.passing`), or with it (`.with`, e.g.
    roots); `.delay` waits longer.
  - On the GPU: each vertex carries `vertex.Grow` (`from`, `at`: start,
    span, spline start, spline done; binding 3, locations 21–22, zero = not
    on a spline). part.vert shrinks it into `from` until the structure's
    growth (`PartInstance.w.w`, `Look.grown`) reaches it, grows it out,
    thin (`SPROUT_THIN`) until its spline is done; foliage tips lag
    (`LEAF_LAG`). `b.xform` carries `from` along.
  - `grownScale` is a structure's research size only; nothing shoots up
    or fills out (the old whole-structure scale is gone).
  - Pieces a structure emits on its own (cups, cores, satellites) form in a
    last share kept free by `sk.tail = FORM` (a `pub const` in the mesh
    file): a mesh of its own carries that window
    (`growth.tag(b, mark, from, growth.tailWindow(FORM))`, emitted with
    `.grown = s.grown`); one the game places and sizes itself scales by
    `growth.formed(mesh.FORM, s.grown)`, the same curve. Never a separate
    hand-tuned threshold. A piece grown by something else (an offshoot by
    research progress) gets its own skeleton and that progress as `.grown`.
  - To watch growth: `--structure=<kind> --state=grow` (with
    `--inspect=<kind>` for shots); its emitted pieces at work:
    `--state=active` (see Testing one plant or structure). No scratch edits.
- **Leaves and petals have a body** (`meshgen.lamina`): a thin closed shell
  (`LAMINA_THICK` of the broadest half-width) rounded over at the edges, a
  small bevel; leaves (blades, fur leaves) fold toward a pale midrib vein
  raised in the fold, fading to the tip. Petals have no vein.
- Liquid essence (part `.essence`, a germinator's): solid, its colour the
  instance tint (sRGB), tu.x the way it flows (streaks), < 0 still.
- Translucent sap: part `.bloom` with instance `fade < 1` (fresnel, hue from
  vertex colour, `tint` shifts it); `.ear` inner face and `.resin` likewise.
- See-through is two passes: `plants`/`parts` keep only fragments with
  alpha ≥ 0.996 (writing depth); `plants_glass`/`parts_glass` (the same
  instances, shaders built with `-DGLASS`, build.zig `variants`) blend the
  rest over every solid surface, testing depth but writing none. A new
  see-through part role goes in `vertex.seeThrough`.
- `WorldPush` is 192 bytes (limit checked at pipeline creation).
- UI: organic, animated, no boxes; SDFs in `shaders/ui.frag`.
- **Never hard-code strings**: every player-facing string (messages, HUD
  labels, names/descriptions of items, plants, research, structures, tiles,
  the window title) lives in `parasymi.cfg`, read once at startup by
  `game/text.zig` (`txt.load` in main) and never again. Add a field to
  `txt.Strings` and a line to the cfg; show it via `txt.s.*`/`txt.item(i)`.
  Templates are runtime: `{0}`, `{1:.1}` (`core/text.zig`), passed to
  `Progression.say` / `Draw.print`; lists are `a | b` (`txt.nth`). The test
  build embeds the cfg and fails on a missing or unknown key. Not text:
  file paths/magic, shader names, CLI flags, log/panic messages, reflection.
- **Never hard-code inputs**: no key or mouse button is named in code. Every
  binding lives in `controls.cfg` (`[bind] action = name | name`, GLFW key
  names, `mouse_left`…), read once at startup by `game/controls.zig`
  (`controls.load` in main). Game code asks about an `ctl.Action`
  (`ctl.down`/`ctl.pressed(in, .harvest)`), never `glfw.Key`/`Button`;
  `platform/input.zig` only polls and answers for a `Bind`. New input = an
  `Action` tag + a cfg line (the test fails on an unbound action); modifiers
  are actions too (`alt`, `take`, `run`). Headless tests `ctl.fill` the
  embedded cfg and `ctl.hold` actions. The mouse wheel/cursor are axes, not
  bindings. Text never names a key either: write `{@action}` in
  `parasymi.cfg` (`FEED ({@harvest})`); `txt.load` (after `controls.load`)
  replaces it once with the bound key's `[key]`/`[mouse]` name (else its
  binding name in capitals), so labels follow rebinding.
- **Parallel loops** (`core/jobs.zig`): `jobs.each(io, n, min, Ctx, ctx,
  Ctx.run)` runs `run(ctx, lo, hi)` over [0, n) in ranges of at least
  `min` items (first range on the calling thread, the rest on main's
  `Io` pool) and returns once all are done. Never spawn threads or keep
  a pool of your own.
  - The pool: `w.io` (`World.io`, set by main after `Game.init` and in
    `restore`); anything holding the world uses it. `null` (headless
    tests, `Game.init`'s first stream) runs it all in place.
  - Only for work where each index writes only its own outputs and reads
    shared state that nothing writes meanwhile (the caller blocks, so the
    sim is still). Results must be identical to the serial loop: no
    shared accumulators, no order-dependent sums (the ecology tick
    scatters into neighbours, so it stays serial).
  - The pattern: a small struct of the inputs (slices, `*const`) with
    `fn run(c:Ctx, lo:usize, hi:usize) void`; see `Plants.Relink`,
    `World.Generate`, `Renderer.Meshing`. Errors go in a per-item
    `[]?E` checked after `each` returns; scratch is one per item, never
    shared. Allocate with the gpa (thread-safe); no Vulkan, GLFW, txt
    or controls calls inside `run`.
  - `min`: enough work a range to pay for a hand-off (~0.1 ms; e.g.
    `LINKS_MIN` 512 plants, 1 chunk).
  - Every new use gets a test that it matches the serial result
    (`testing.io` vs `null`, as in plants/world).
- Edits: write to files, pass files to scripts; no inline heredocs.
  Line endings are mixed (most files CRLF, some LF): keep each file's own
  (Python on Windows writes CRLF unless `newline=''`).

## Zig 0.16 notes
`std.Io` replaces old I/O (pass an `Io` like an allocator). "Juicy Main":
injected params, no global env/args. `@Type` removed (`@Pointer`,
`@ErrorUnion`, explicit `error{...}`). `ArrayList{}` → `.empty`;
`ArenaAllocator` is lock-free. Build: `root_module` + `Module`; deps in `zig-pkg/`.

## Code design
- Tagged unions for exclusive states (`Game.mode`, `Camera.view`,
  `Display.mode`, `Occ.get()`); explicit error sets in public APIs (folded
  via `ctx.fold`); distinct ID types (`PlantId`, `StructId`, `MeshSlot`, `Occ`).
- `comptime T: type` over `anytype`; exhaustive `switch`; explicit
  allocators; `defer deinit()` at once, `errdefer` on init paths; arenas
  for batch work; `std.testing.allocator` in tests; SoA for hot loops;
  `try` by default, translate errors at module boundaries.
- GPU buffers retired mid-frame wait in `Renderer.pending` until every frame
  in flight is done.

## Design
- No global resources: items live in the belly, structures or plants.
  Every plant is player-seeded and grows before use. Research is the
  Factorio-lab model (structures consume ingredients unit by unit).
  Plants never set seed: only a germinator weaves seeds (hand-weaving
  makes bulbs only, `craft.by_hand`). The germinator is the bootstrap,
  woven from fibre, grit and starlight, and the hub of automation: it
  weaves every recipe, seeds and bulbs (`craft.all`), and lets only what
  it wove go (`craft.woven`); always open: lumenroot/thornleech
  seeds, conduits, sap caches, germinator; other species research-gated
  (vesper by Seed Splicing: essence + convergence essence + fibre).
  Uprooting a sown plant always gives its seed back (it stays put while
  the belly is full); a confluence gives nothing.
  Plants and structures share occupancy; footprints 1×1, 2×2 or floating.
- Structures: conduit (pulls from behind, pushes forward; grows a side root
  to a plant beside/behind it and harvests it once the root arrives), sap
  cache, germinator, arsthraxia, root-digger (1×1 on soil/moss, digs an
  adjacent node 1 item/4 s into an 8-item buffer, feeds neighbours, idles
  with no node; 3 fibre + 2 grit + 1 ley shard; "Deep Rooting"). Put down,
  they grow (`Def.grow`: germinator 6 s, arsthraxia 8, sap cache and
  digger 4, conduit 1.5) and do no work until grown, growing along their
  growth splines. `Def.carrier` marks
  item carriers (conduit, braided conduit): they face a way, chain, and
  hand on to each other through `receive` (`Structures.handIn`, at the edge
  an item comes in by); carriers are never pulled from. `gives` says what
  a structure lets go (a braid pulls a different kind per lane);
  `st.handOff` feeds a producer's `output` to a non-carrier neighbour.
- Lineage structures (2nd tier of automation, each its own research):
  - Symbiotic (woven, green, amber sap):
    - Loomfern (1×1 soil/moss, "Living Looms"): weaves fibre, 1/12 s unfed,
      4 per essence fed at 3 s each; holds 12. A fern: fronds, croziers,
      a sheaf winding on its spindle from threads off the fronds.
    - Gathering crown ("Living Looms"): roots out to every plant within 2
      tiles (one root per plant's own tile) and gathers what is ripe, one
      unit/1.5 s in turn; holds 12.
    - Braided conduit ("Braided Roots", woven from 4 conduits): 4 lanes,
      one kind each, 3.5 tiles/s; joins and turns with conduits.
  - Parasitic (pale, alien, `parasite_kit`):
    - Lithophage ("Lithophagy"): drains grit/ley nodes on the 8 tiles
      round it (one per 3 s) into a crystal in its crop (6 grit, ley shard
      = 3), sapped back out as 6 grit into its cup; fed ley shards only,
      so the grit it holds is what it sapped (the gardener's call: grit).
    - Ganglion ("Lithophagy"): holds 8, hands one each 0.35 s round its
      sides in turn to whatever wants it, and to carriers not facing in:
      splits lines, feeds several germinators each what it needs.
    - Sporecaster ("Spore Casting"): paired by configuring one then its
      partner (`Structures.pairing`, the `configure(ss, id, g)` hook); spore
      carriers (free, 0.25 s apart, 5 of a kind) drift at 2.5 tiles/s,
      unlimited range, into the partner; home again if it is gone, hang
      over it while it is full. `Def.far`: its spores are drawn however
      far it stands.
- Convergent structures (3rd tier; each pair of lineage structures grown
  within `structures.MEET` (3) tiles is a discovery, `meets` hook +
  `Structures.meetings`, opening its research; woven by a germinator
  only, `Recipe.germinator`, from the pair's bulbs + 2 convergence
  essence; the confluence stays the only convergent plant):
  - Weftstone (loomfern + lithophage, WOVEN STONE): floating (its mesh
    carries `HOVER`, `Def.hover` 0), latches tendrils (emitted curves,
    `weftstone_tendril`) onto the nearest 6 grit/ley nodes within 2 tiles,
    draws one unit/2 s in turn into its bulb (12 grit, 4 ley), ionizes 4
    grit + 1 ley into a ley crystal in 6 s (crystal + sparks in the bulb),
    holds 8, hands them on.
  - Driftbraid (braided conduit + sporecaster, BRAIDED DRIFT; its look is
    the approved reference): paired both ways by configuring one then the
    other; sends what it is fed by spore, takes in what comes back, lets
    go only what came by spore (`kept` counts per kind).
  - Monfris (weftstone + driftbraid, INTERWEAVING):
    2x2, four corner weaves twining into one crowned trunk; weaves only the
    advanced tier (`Recipe.advanced`, `craft.advanced`; the germinator's
    `craft.all` leaves it out): for now the diamond (from ley crystals).
    Fed by at most 6 Vultrixi (`monfris.TETHERS`, an advanced weave has
    at most 6 kinds), by hand, or by conduits.
  - Vultrixi (gathering crown + ganglion, SHARED NERVES): floating;
    configure it, then a monfris, to tether it. It takes the ingredient
    of the weave at its place among the tethered, reaches a tendril into
    the nearest structure within 6 tiles that `gives` it (never a
    monfris or Vultrixi), pulls 1/s and sends it along its tether.
  - Floaters are reached (panel, feed, configure, unbuild) where nothing
    stands under them; nothing is sown or put under one.
- Confluence (`game/convergence.zig`): a mature symbiote and parasite within
  2 tiles (or joined by a conduit chain) root a 2×2 confluence beside them
  unless one already holds them. Never sown; grows 1.5× the slower parent
  (`span`) in 4 stages; yields convergence essence;
  mature, halves parasite drain within 3 tiles. "Convergence Theory" only
  reveals its yield.
- Celestial bloom (`species/bloom.zig`, `ecology.Radiance`): sown, floating
  (hover 3.2), yields nothing; radiates a 3.5-tile field. Blooms within 10
  tiles link into networks; a network radiates when it holds a mature bloom
  (then all its blooms do), so uprooting a linking bloom cuts off those
  beyond it. Plants with `needs_radiance` (vesper, for now) halt and
  wither (0.06 HP/s) outside every field. Worked out per tick from blooms
  only (pairwise links, then each radiating bloom's tiles). Hover panel
  shows RADIATING/DARK + links, DRAWING RADIANCE/WITHERING. Seed: 3
  starlight + 1 ley shard + 2 essence.
- Halo (`structures/polyp.zig`, `halo.zig` shared, `diamond.zig`): a
  polyp (1×1, grows 6 s; 4 fibre + 3 essence + 2 starlight + 2 ley shard)
  checks each tick for grown blooms (HP > 0.5) on the four
  points 5 tiles out E/S/W/N. Then, once ever, over 5 s: the blooms spiral
  in to where their cross of beams meets, the ring's heart at bloom hover
  (share ∝ e^(4k), 1.25 turns) and fold to buds, all on the GPU
  (common.glsl `haloSpiral`; the CPU sends only `[centre, k]`, instance `h`
  / `vertex.NO_HALO`, beams their held ends in `e.z`), while the diamond
  (1.6× its mesh) gathers there from its shards and projects the halo:
  needle rays of split light (`halo_projection`, part 12) running level
  out to a ring through the points (`halo_ring`, part 11: spectrum across
  its width, red inner edge as an ice halo, beam-like swells and motes
  running round). As they meet they are consumed, a flash spreads
  (`halo_flash`, part 9) and a DIAMOND structure (floating there,
  `Def.floating`/`hover`/`bare`) is put down; the polyp stays as it is. Ring field: radius 5 while
  forming; diamond field: radius 7. Points without a grown bloom dim their
  arcs to 0.3. A diamond discovers `.diamond`, opening CELESTIAL
  DEFRAGMENTATION, which lets diamonds be woven and put over
  any dry tile (they gather as they grow, then flash). The diamond is the
  world event's future launch point. Demo: west of the garden, the fourth
  bloom finishes ~20 s in.
- The gardener's folder (`game/home.zig`): `%LOCALAPPDATA%\Parasymi`
  holds `parasymi.cfg`, `controls.cfg`, `options.cfg` and `saves/`, all
  made on startup when missing (`home.open` first in main; `home.dir()`
  for every file); no cfg ever lives beside the game. The two stock cfgs
  are tracked in `src/cfg/`, embedded (`@embedFile`) and written
  with a `# stock <hash>` first line: an untouched copy is replaced when
  the repo's changes, an edited one is kept and read over the built-in
  (what it lacks falls back). So `src/cfg/` edits reach the game unless the
  AppData copy was hand-edited. Old `options.cfg`/`parasymi.sav` beside
  the game are copied in once.
- Save (`game/save.zig`, `saves/<name>.sav`): the world regenerates from the
  seed; only the gardener's changes are stored. Written to a `.tmp` then
  renamed over. `Game.slot` is the garden being played (F5/quit save into
  it, a fresh `garden N` if none); `Request` carries saves/loads/listing to
  main. Autosave (`autosave.sav`) every `Options.autosave` minutes of play
  (default 5, options panel: never..60). Bump `VERSION` when a stored
  layout changes (the fingerprint checks sizes only).

## Visual (current)
- Motion and wind: one garden-wide wind (`gardenWind`/`bendIn`,
  common.glsl), slow gusts rolling across as a wave. Everything grown bends
  from its root in it (h², tips lagging), per-thing `sway`; leaves breathe
  and lift a little; only parasites writhe.
- Terrain (`render/terrain_mesh.zig`): smooth, no walls; each tile a fan of
  four triangles, centre at the tile's height, corners shared (height,
  colour, ley averaged), smooth normals; no water (basins are level lowland).
  Detail grown on the GPU (detail pass, `detail.vert`) from one `DetailTile`
  per tile: grass blades on all but soil (tile-coloured, wind-swayed),
  clods and stones on soil; within `DETAIL_R` (28 tiles). Ley lines carry a
  faint drifting plexus; ley sight glows smoothly across tiles. info.z = 255
  marks the top surface. Fog closes in before the edge; paw contact shadows.
- Plants: 4 variants per species (by tile). Material (plant.frag) is the
  wolf's vocabulary: muted skin, fibre sheen, old growth densifying to root
  brown, colour carried by sap through thin/young tissue (`v_young`), no
  self-glow (rim at night), see-through petals. Plants scale up as they
  grow; parasites open their closed crowns. Holding a seed shows a ghost of
  the grown plant (green fits, red not). Forms (`species.Form`: herb 0,
  coil 1, drift 2, confluence 3, radiant 4, star 5; common.glsl
  `FORMS_FREE` = the radiant ones): symbiotes (`herb`) flare into
  roots, one vase leaf envelope (`leaf_from` for tree crowns), calyx and two
  whorls of real petals; vines grow leaves along them. Offshoots
  (`meshgen.offshoot`, genome `shoots` = per-variant count range): side
  stems off the main stem ending in a closed bud or a small bloom (looks
  only); colour alpha = 1 - how far out along one, and plant.vert folds
  them in against the stem until growth passes them. Parasites (`coil`,
  `parasite_kit.plant`): alien not hostile, exactly symmetric and dead
  upright (variants differ in proportion only): a lattice cage stalk on a
  bulbous foot, sacs hanging on its core inside, a bulb at its neck, a
  candelabrum of 5 fronds each ending in a pod crowned by 5 frondlets;
  plant.vert parts the cage from the foot up (tu.y) and opens the crown.
  Floaters (`drift`): a comb-jelly lantern (`meshgen.lantern`: clear sap,
  8 twisting comb rows in split-light colours, a golden spore inside;
  plant.frag shades it apart by tu.x 0.5, bright iridescent film, approved
  as is), catcher dish, hair-thin filaments waving in two lengths (a wave
  runs down them in plant.vert), slow bob over a ground shadow. Confluence: 8 growth keys of one vertex layout
  blended in plant.vert (binding 2), braid strands running on into red
  vines, translucent violet petals, sway ×1.5.
- Vesper (`star`, `radiant_kit.star`): an evening star come down,
  hanging `stem_h` (0.62) over its tile, nothing under it: a dusk-violet
  core (gold nucleus, 5 stamens), an upright cup of 5 pale-gold petals, a
  star of 5 long narrow violet rays lying open, 5 dusky leaves floating
  beneath (`GLOW` 0.3: living tissue, little light, they cast shadows),
  motes; no halo. It gathers as the bloom does but falls in from the sky
  (plant.vert `FORMS_FALLING`, `FALL_*`): the heart first, straight down,
  then each piece spiralling down on its thread. Keeps more of its own
  hue under the film (plant.frag `FORMS_OWN_HUE`). Withering out of
  radiance any radiant plant comes loose (`LOOSE_*`: pieces sink, drift
  out, hang open) and its light dims with health.
- Celestial bloom (`radiant`): a flower whose petals float free, gathered
  by its core: a luminous core with a crown of stamens, three whorls of
  narrow cupped petals (inner upright .. outer open) floating apart from it,
  each held by a thread of light, motes spiralling in, tilted halo. Pearl
  with an iridescent film (plant.frag `filmHue` by view angle). Fragments
  carry assembly order (tu.x), `radiant_kit.Ring` (tu.y; a thread adds its
  distance from its petal) and bearing (colour alpha): plant.vert spirals
  each in folded as a bud and opens it as growth passes it; grown, whorls
  turn slowly, alternating, and drift apart and back; it bobs and never
  bends. With the vesper, the garden's only true glow. Beams
  between linked blooms (`bloom_thread`, part `.thread`): soft rays, a
  camera-facing spindle bent in part.vert curve mode; no core, a faint haze
  with five soft streaks swelling from sender to receiver, iridescent
  (rainbow end to end, rolling along), tiny motes drifting inside shifting
  hue (seeded by the instance phase); dim when the network is dark; sent
  from the more grown bloom as it finishes. Demo: the halo garden's
  blooms; a bloom's stages are viewed with `--plant=bloom`.
- Structures (`structure_kit`) speak the plants' language: woven root mats,
  leafy vines, real petals, pods of resin sap (`Def.sap`, no own light).
  Germinator (`Def.still`: no breath, so its emitted pieces stay on it;
  `Def.preview` whole): a small tree, woven trunk on a root mat, five
  braided boughs rising round a core of thin resin sap held in a calyx and
  arching over it to hold flower cups (stamens) above it; a sapwood
  spindle runs up through the core. A weave is seen through by its
  progress alone: the cups hold what it stocks (pools of `.essence`, kept
  level), tip and pour it (curve-placed streams, colour in `q.yzw`); the
  core spins it into a whirl round the spindle (one arm per essence,
  turned by the area under the spin stage, whole turns per weave) and
  threads wind a seed of them on the spindle (kernel in the output's
  colour, a winding per essence). Arsthraxia (`Def.bare`, its own
  `emit`; never breathes or bobs): three braided stems twine up from a
  root mat, part into a cage round a resin pod threaded on a nerve and
  gather in a calyx under a violet flower (two whorls, emitted, opening
  and counter-turning while it studies). Each stem's core is a nerve
  (part `.nerve`, `mg.braidAround`): studying, violet thought climbs it
  (part.vert), a unit done sends a surge up (`flutter` = flare). Research
  grows on it: vines climbing the stems (Arsthraxia, `Study.vines`), a
  braided offshoot bough with a vine round it and its own flower per
  minor study. Sap cache: a resin gourd
  cupped by a calyx on a woven bole, a wicker basket over it (green vines
  one way, pale roots the other, over and under), a collar at its neck and
  a bud of sepals closing its mouth (`sap_cache_lid`, emitted): it opens
  as an item drops in (sinking to its stack, which swells) or rises out;
  contents hang inside. Root-digger: four braided roots break the ground
  (soil heaved round them) and twine up to grip a small resin gourd, a
  leaf tuft on top; its digging root (`digger_root`, a conduit arch whose
  `.core` runs home, tu.x 0 in the node) reaches to the node it works and
  withers from one gone; each item is prised loose (`digger_clod`s flung
  up about the claw), then swells up the core in its colour to the gourd. Conduit (`Def.bare`, its own
  `emit`): per tile a root digs up out of the soil at each edge it is fed
  from (`link` hook: `feeds`; `conduit`/`conduit_left`/`conduit_right`),
  arches (rising long, diving short) and digs back in at its front, so
  chains join underground in any turn; a sapwood core (part `.core`) in an
  over-under weave of strands, branchlets, leaves in twos/threes swept
  forward, soil heaped (a ridge pushed ahead where it dives) with rootlets.
  Carried essence swells and tints the core as it passes (part.vert,
  `Look.carry`/`carry_col`), amber pulses run the way it carries; side
  roots (`conduit_tap`) are smaller woven arches. Standing structures sway (`Def.sway`; conduits don't, so
  chains stay joined; hung parts follow via `Look.drop`), breathe at a fixed
  tempo, and grow in along their growth splines (trunk first, branches
  after, leaves unfolding as the front passes, emitted pieces last; see
  Conventions).
- Resource nodes (`mineral_kit`, flat facets): ley shards a violet crystal
  cluster; grit faceted stones with quartz chips; fibre a swaying clump of
  arching stalks.
- Sap everywhere is alive: bubbles rise inside, beads slide down its surface
  (`sapBubbles`/`sapDroplets`, mesh space). Sap glistens, never glows
  softly (`sapGlisten`, common.glsl, on every sap material): hard-edged
  mirrored lights (`hardSpot`: key light with a white-hot core, points of
  light, a sky window), winking skin facets, a sharp caustic through clear
  sap, a thin hard edge line; its colour gathers to a narrow edge band
  (`SAP_EDGE_POW`). The bloom post makes the glow round the glints.
- Sky: gradient dome, sun/moon, stars; star motes (faceted core, ring,
  needle rays) turn, twinkle, hover and trail echoes while falling. Low
  pitch widens the view toward the horizon.
- part.vert placement by `PartInstance.e.x`: 0 matrix, 1 curve (beams;
  `e.y` reach), 2 star mote, 3 skinned (`e.y` first bone).
- Lighting (`render/light.zig`): the key light (sun/moon) casts shadows
  through a cascaded shadow map (3 cascades, 1536², `fit` snaps them to
  texels so they hold still), drawn in one multiview pass per caster
  (`gl_ViewIndex`, `project()`), casters at their coarsest LOD
  (`light.caster`); shader variants with SHADOW leave out what is light
  itself (blooms, motes, beams, halo, ghosts, lanterns). Terrain receives
  but does not cast. Points of light (`Parts.light`: blooms, motes, ley
  shards, diamond and flash; at most `MAX_LIGHTS` 32, ranked in
  view.zig) and the cascades travel in `Lighting`, reached by address
  (`WorldPush.light`); common.glsl `keyShadow`, `pointLight`, `shadeLit`.
  Culling keeps what may cast into view (`Parts.sees`). Cost ~+3 ms on
  this machine's 35 ms demo frame.
- Post-processing (`render/post.zig`): world passes draw into an HDR image;
  brighter-than-white light blooms (5-level 13-tap down chain with soft-knee
  threshold and anti-firefly weighting, tent filter back up); composite
  adds the glow (0.7), rolls highlights off above 0.8 and a faint vignette;
  `Desc.screen` passes (UI) draw on top. ~0.1 ms.
- Anti-aliasing (`post.Antialias`: off, fxaa, msaa2/4/8; default msaa4):
  MSAA draws the world into multisampled colour + depth resolved (average)
  into the HDR image; plant/part passes (`Desc.per_sample`) shade per
  sample, since their solid/glass split is per fragment. FXAA (`fxaa.frag`,
  FXAA 3.11 quality) filters the composite (luma in alpha) before the UI.
  `Renderer.antialias`/`setVsync` switch at runtime (remake pipelines /
  swapchain). Release: off 4.1, fxaa 3.9, msaa4 4.35, msaa8 4.9 ms (demo).
- Options (`game/options.zig`, `hud/options.zig`): AA, vsync, fullscreen,
  autosave, stored in `options.cfg` (in the gardener's folder, written when one
  changes, kept across save loads); main applies `Game.opts` when it
  differs from what is in effect.
- Loading screen (`game/loading.zig`, wired in main): a living night
  (`Draw.night`, ui.frag) with the name, a tendril growing as far as what
  is made (leaves opening as it passes), the stage, percent, made/left.
  Stages: every mesh grown on a thread of its own (`Renderer.meshProgress`
  / `meshesReady` uploads once through), the world woken, its ground
  meshed in 25 ms slices (`World.unmeshed`); also after a load in play.
  It fades off play's first frames (0.6 s).
- UI: wobbling membranes, seed-pod slots, tendril bars, soft glow, stems
  (`Draw.limb`) and leaves/buds (`Draw.leaf`), seeds (`Draw.grain`) and
  gems (`Draw.gem`); 150 ms anim.
- Item icons (`game/icon.zig`): a structure's bulb is a split seed with a
  sprout or two showing what it does (its `icon` hook, drawn with the
  `Icon` kit: `coat`, `stem` along a Bézier, `leaf`, `bud`, `glow`, `gem`,
  `kernel`; sprouts sway). A plant's seed likewise, from its module in
  `game/seeds.zig` (`seeds/<species>.zig`: `item` + `icon`; the test fails
  on a sown species without one). Any other item is its colour fill with
  its short name, for now.
- Research panel (T, `hud/research.zig`) is a sapling in soil, laid out
  from the prerequisites alone, so it never needs placing or adjusting:
  - Adding research: one file in `research/` + one line in `techs`. Set
    `.branch = true` on a big step (new structures, species, an event);
    anything else is a leaf. Nothing else to do: no coordinates, no sizes.
  - Host: a node grows on the nearest branch up its *first* prerequisite
    chain, else on the trunk (so list the prerequisite it belongs to first).
  - Along a host, children sit one slot apart by depth (longest prereq
    chain; a `needs` discovery counts 1), then declaration order; leaves and
    branches each alternate sides. Stems are one slot longer than their
    children (branches ≥ `BRANCH_MIN`) and bend toward the light.
  - The fully grown, still tree is fitted to the panel (`fit`, slot ≤
    `max_slot` px), so nothing moves: the sapling starts small at the soil
    and fills the panel as research is done.
  - Known: grown leaf / branch with a violet bloom at its tip. Open: gold
    bud (glows; while studied a leaf unfurls and a branch shoot extends with
    progress). Locked: dim dormant bud where its host has grown, else
    hidden. The trunk reaches `TRUNK_LEAD` past its highest open/known
    node (eased, `play.Game.sapling`) and thickens with √(known).
  - Wind sways stems from the base (children follow), leaves flutter.
    Hovering a node (`Game.pointed`) shows its card (cost, progress, or
    what it is DORMANT on); else the studied one. Click selects.
  - The test asserts hosts come before what grows on them and no two nodes
    crowd (> 0.5 slot); if it fails after adding research, fix the layout
    rules there, never hand-place a node.
- Wolf (`game/player.zig` rig; muted greens/browns, amber only on belly,
  eyes, inner ears, beans, pectorals and rear):
  - One skin: `wolf_body` is sculpted (`sculpt_kit`: SDF ellipsoids, round
    cones, round boxes per bone, smooth union/carve, `ink` paints colour
    only) around the bind pose of `wolf_skeleton` (27 bones, `fk(Pose)`),
    meshed once with surface nets (`CELL` 5 mm, doubled per LOD), each
    vertex weighted to the bones of the forms nearest it (only across
    joints that are joined). GPU skinning: `vertex.Skin` beside the mesh
    buffer (binding 2), bones per frame via `Parts.pose`/`emitSkinned`
    (part.vert mode 3, buffer device address in `WorldPush.bones`).
    New wolf meshes are built in bind space and skinned; never rigid parts.
  - Over the hide: vines cast onto it from bone axes (`wind`/`line`, so
    they never jump across), fur leaves (`wolf_kit.leaf`) as hair over the
    crown with a forelock and nape mane, along the cheekbones, shoulder
    tufts, tail rings and tip; digits/claws (`wolf_kit.digit`); eyes set in
    carved sockets under the brow.
  - Head: short muzzle rising to an upturned nose (bean), lower jaw (own
    bone) tucked up under it, ears (`wolf_ears`, skinned to ear bones).
  - Resin sap (`.resin`, sprung `give`): pectorals (`wolf_pec`) on the
    chest, the rear (`wolf_rump`) on the pelvis, its lower edge partly
    following the thighs.
  - Belly (`wolf_belly`): convex egg sac on the gut; filling scales and
    drops the `gut` bone (lower half) and `gut_top` (upper half: as wide,
    its top kept where it hangs), so the swollen sac never folds (tested);
    tu.x = gut share of each vertex; the belly button pops out; up to 5
    lumps inside (in the gut bone's frame). `vertex.Skin` carries each
    weight's slope (`gx/gy/gz`): part.vert bends skinned normals by the
    true Jacobian, not the blended bones alone.
  - Motion: feet planted in the world, swung on arcs when the gait's phase
    (or, standing, a foot left behind) says; digitigrade leg IK
    (`solveLeg`: thigh+metatarsal as one link); pelvis bobs at footfalls,
    sways, turns and rolls, chest counter-turns; lean, bank, arms, head,
    ears and tail on springs (`Swing`); head steadied against the bob,
    idle look-around, ear flicks; breath and panting quicken with effort.
- "Celestial / beyond comprehension" is the next phase target.

## Rules
- **Scope guard**: no audio, multiplayer, PBR/IBL, further post-processing
  (bloom was asked for) or Linux/macOS without explicit direction; flag and
  stop if a task drifts there.
- **Decision authority**: a layer boundary or build/run interface change →
  stop and ask; otherwise decide and note with `// decision:`.
- **Plant rule**: everything grown has a proper growing animation, is moved
  by the garden's sway and matches the current plant quality, unless the
  user says otherwise.
- **Cohesion rule**: each visual overhaul sets the bar for everything of its
  kind; the whole wolf and all plants/structures are kept up with it; new
  grown things follow the current look, motion and growth via the shared
  kits, never older primitives (structures: growth splines, never the
  whole-structure scale).
- **Visual authority**: the user calls the shots on art direction, with NO
  compromises, period. Their word on look, motion, proportions,
  silhouette, material, technique (e.g. "on the GPU") and "does this read
  as X" is final. Build exactly what they describe: never substitute a
  cheaper, simpler or "equivalent" approach, never water it down, never
  ship a stand-in and call it done. If it can't be done as described,
  research another way (techniques, papers, docs, prior art) that delivers
  exactly what they described, and build that; never give up on it or
  fall back to less. If it's ambiguous, ask. "Off", "weak", "generic", "too X" is
  the acceptance criterion: implement their fix.
- **Finish line**: work until the phase's criteria are met; take the next
  step instead of "next I would…"; stop only for a blocking decision or
  phase completion.
- **Working**: commit and push `devel` after every verified change (builds,
  tests pass) without asking; never commit `parasymi.sav`; report broken
  work, don't commit it. Reports: a short list of changes, a real deviation
  or blocker as one bullet. Verify visual work in the running game (scratch
  copies may move the camera) and say what was not checked.

## Current state
Done: engine, terrain, streaming, plants + 7 species, ecology, structures,
footprints/floaters, research (18 nodes), hand weaving, save/load, pause,
fullscreen, root-digger, adjustable/free camera, sky, wolf anatomy and
planes/fur passes, confluence, celestial bloom + radiance, GPU detail,
LOD + culling, bloom post-processing, research sapling panel, halo + diamond structure + Celestial Defragmentation,
anti-aliasing (MSAA/FXAA) + options panel, the wolf as one sculpted skinned
mesh with procedural locomotion (planted feet, leg IK, springs), saved gardens
menu + autosave, files in `%LOCALAPPDATA%\Parasymi`, loading screen, growth splines
(every structure but the diamond), lineage structures (3 per lineage, see
Design).
**Next (vertical slice):**
1. ~~2–3 more per lineage~~ done as structures (the gardener's call)
2. Research tree to ~12 nodes
3. First world event (something that *happens*, not just a research unlock)
4. One "wow" visual moment (sky shift at convergence)
Target: a stranger plays 2 hours and says "I want to see what happens next."
