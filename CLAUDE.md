# CLAUDE.md

## What this is
Player-centric Factorio-like automation game. Magically infused plants (parasitic +
symbiotic lineages that converge). Zig 0.16, zglfw + vulkan-zig (Vulkan 1.3),
Windows, no asset files (every mesh, the font and all UI shapes are procedural).
2.5D top-down 3D. Adjustable pitch (30°–85°, default 55°), yaw via Q/E. No free
rotation in play; a free inspection camera is always available (Ctrl+F).

## Build
```
zig build run                     # debug (validation on)
zig build run -Drelease=true      # ReleaseFast (-Doptimize is not accepted)
zig build run -- --demo           # test garden + structures, fast-forwarded
zig build run -- --stress         # 120×120 plant field
zig build run -- --tod=0.9        # time of day (0=midnight, 0.5=noon)
zig build run -- --novsync --seed=0x1234
zig build run -- --load           # load save
zig build test                    # headless logic tests (no window/GPU)
```

Needs `VULKAN_SDK` (`vk.xml` + `glslc`). Pinned: vulkan-zig `zig-0.16-compat`,
zglfw `f04fdbf`. Upstream heads need 0.17. A stray `CPATH` breaks GLFW's C build.

## Controls
WASD move, Shift run, Q/E yaw, Ctrl+W/S pitch, wheel zoom. LMB gather/place,
RMB uproot, F harvest/feed, Shift+F take, C configure, R rotate, 1–9/0 hotbar,
Tab belly (weave), T research, F3 debug. Esc closes a panel, else pauses (Q in
pause = save and quit). F5 save, F9 load, F11 fullscreen.
Free cam (Ctrl+F): click to look, WASD fly (Shift fast), Space/Ctrl+Space
rise/sink, Q/E roll, wheel dolly, unclamped; eases back in 0.3 s.

## Performance targets
- 8 ms frame (120 FPS), RTX 3060-class, validation ON.
- 30 Hz fixed sim tick, decoupled from render (currently 60 Hz, `play.TICK`).
- Chunk: 64×64 tiles, < 2 ms gen+upload, queue-based (currently 32×32).
- < 200 draw calls at stress. Instancing expected.

## Layers (import only downward)

```
core      math, color, rng, noise, registry
platform  input, display (fullscreen)
gfx       Vulkan ctx, swapchain, buffers, pipelines, meshgen, meshlib
world     chunks (tile SoA + occupancy), generation, streaming
sim       items, species, plants (footprints, floaters), ecology tick
game      player, actions, structures, research, craft, sky, hud, view, play, save
render    renderer + passes, terrain meshing, camera
ui        SDF draw batch, font
main      wiring, frame loop, save/load/fullscreen requests
```

## Registries
One module per thing. Enum via `std.meta.DeclEnum`, dispatch via
`switch (id) { inline else => |k| reg.module(k).hook(...) }`; hooks optional
(`reg.has`). Adding a thing = one file + one line in the namespace. Never add a
`switch` over registry kinds outside the registry file; add a hook.

| Domain | Entry | Hooks |
|---|---|---|
| species | `sim/species.zig` | `def` (genome drives the grown mesh) |
| meshes | `gfx/meshlib.zig` | `build(b)` (order = draw order: translucent after what they cover) |
| structures | `game/structures.zig` | `def`, `State`, `tick`, `wants`, `output`, `release`, `configure`, `emit`, `describe`, `ground` |
| research | `game/progression.zig` | `def`, `apply`, `unlocks`, `completed`, `veil` |
| hud panels | `game/hud.zig` | `draw`, `visible` (draw order = declaration order) |
| render passes | `render/renderer.zig` | `desc`, `Frame`, `initFrame`/`deinitFrame`, `record` (sky, terrain, plants, parts, ui) |

Items (`sim/items.zig`) and weave recipes (`game/craft.zig`) are plain data tables.

## Conventions
- 2-space indent, `name:Type` (no space after colon), terse `//!`/`///` docs, LF.
- All math via `core/math.zig` (alias `m`): scalars, tiles, `m.dirVec`/`dirYaw`,
  vectors/matrices, `m.spring` (exact critically damped), `m.springDamper`
  (substepped spring-mass), `m.catmullRom`/`splineResample`, `m.alignY`.
  Colours via `core/color.zig`. Never reach into `std.math` or hand-roll casts.
- No inline `std.ns.Name` — alias at file top.
- **Never hand-roll linear algebra.** Use `m.inverseRigid` (rotation +
  translation), `m.inverseAffine` (scaled), `m.inverse` only as fallback. If a
  method is missing, add it + a test. A singular matrix is a bug: `@panic` in
  debug, don't silently return zero.
- **All geometry watertight and seamless:** tubes share rings (parallel
  transport), bundles continuous, cones/lofts capped, sheets shared-vertex.
  Deform meshes only with smooth position fields so shared vertices move alike.
- **Grown vines use Catmull-Rom splines** with `growthPath()`/`grow()`
  (wobble, curl, taper, seed; the root never moves). Never a straight line or
  simple arc.
- meshgen primitives: `tubeR`, `vine`, `braid`/`braidTurned`, `bundle`, `loft`
  (any cross-section), `patch` (grid sheet), `blade`/`bladeAlong`, `bands`
  (vines over an ellipsoid), `ellipsoid`, `cone`.
- Translucent sap: part `.bloom` with instance `fade < 1` → fresnel (amber at
  grazing angles, see-through centre); hue follows vertex colour, so instance
  `tint` shifts it. Part `.ear` inner face does the same.
- Push constants: `WorldPush` is 176 bytes (limit checked at pipeline creation).
- UI: organic, animated, no boxes. SDFs in `shaders/ui.frag`.
- Edits: write to files, pass files to scripts. No inline heredocs.

## Zig 0.16 API notes
- `std.Io` replaces all old I/O. Pass an `Io` instance like an allocator.
- "Juicy Main": `main` accepts injected params. No global env/args.
- `@Type` removed. Use `@Pointer`, `@ErrorUnion`, explicit `error{...}` sets.
- `ArrayList{}` → `.empty`. `ArenaAllocator` is lock-free.
- Build: `root_module` + `Module`. Deps in `zig-pkg/`.

## Code design
- Tagged unions for exclusive states (`Game.mode`, `Camera.view`,
  `Display.mode`, `Occ.get()`). Explicit error sets in public APIs
  (`Allocator.Error`, `save.Error`, `gfx.Error` folded via `ctx.fold`).
- `comptime T: type` over `anytype`. Distinct types for domain IDs
  (`PlantId`, `StructId`, `MeshSlot`, `Occ`).
- Exhaustive `switch`. Pass allocators explicitly. `defer deinit()` immediately;
  `errdefer` on init paths (half-built renderer frees cleanly).
- Arena allocators for batch work. `std.testing.allocator` in tests.
- Vtable pattern for many-method interfaces. SoA for hot loops.
- `try` by default. Translate errors at module boundaries.
- GPU buffers retired mid-frame wait in `Renderer.pending` until every frame
  in flight is done.

## Design
- No global resources. Items live in the player's belly, in structures, or
  in plants until harvested.
- Every plant is player-seeded and must grow before use.
- Research: Factorio-lab model. A structure consumes ingredients unit by unit.
- Hand-weaving is the bootstrap (wolf weaves seeds from gathered matter + starlight).
- Plants and structures share occupancy. Footprints: 1×1, 2×2, or floating.
- Player-centric, builds toward full automation.
- Structures: conduit (pulls from behind, pushes forward), sap cache,
  germinator, research bloom, root-digger.
- Root-digger: 1×1 on soil/moss, digs an adjacent node 1 item/4s into an
  8-item buffer, feeds adjacent structures (conduits pull from it), idles when
  no node. Recipe: 3 fibre + 2 grit + 1 ley shard. Gated by "Deep Rooting".
- Save (`game/save.zig`, `parasymi.sav`): the world regenerates from the seed;
  only the gardener's changes are stored. Bump `VERSION` when a stored layout
  changes (the fingerprint checks sizes only).

## Visual (current)
- Terrain: flat, biome-tinted tiles, one directional + ambient, flat shading.
  Fog closes in before the drawn edge; contact shadows under the wolf's feet.
- Plants: grown spline stems/tendrils, 4 mesh variants per species (picked by
  tile), vertex-shader sway. Parasitic: desaturated reds/oranges. Symbiotic:
  greens/teals.
- Sky: gradient dome pass (fog colour at the horizon), sun/moon, stars,
  starlight motes. Low pitch widens the view and lifts it toward the horizon.
- UI: wobbling membranes, seed-pod slots, tendril bars, soft glow. 150 ms anim.
- Wolf (rigid joint skeleton, organic surface; `game/player.zig` rig):
  - Muted greens/browns; amber only on belly, eyes, inner ears (and beans).
  - Head: flat-bridged lofted muzzle, jaw seam, nose bean, side-set eyes,
    tall ears (sap inner face 50%, antihelix ridge), grown-tendril mane.
  - Torso: three sections (broad loose-woven chest, tight vine-corset waist,
    hips); sap pectorals (80%) on springs, chest vines tucked behind.
  - Belly: translucent sap (72%), inflates +35% and drops/sags with fill;
    up to 5 dark lumps inside on spring-dampers driven by acceleration.
  - Arms: deltoid caps, bicep/tricep, forearm tapering 1.1→0.7.
  - Rear: two plump vine lobes nearly touching, sap nodes (40%), firm springs;
    tailbone knot above them; tail is a braided spline rebuilt each frame.
  - Legs: anthro digitigrade (vertical thigh, calf back to a high hock with a
    +25% swell, forward metatarsal), long flat feet, sap beans (80%, browner),
    central pad flattens 10% when planted.
  - Breathing 2% torso / 1% limbs (CPU instance scale); body strands wobble
    0.03; anisotropic sheen along vine tangents.
- "Celestial / beyond comprehension" is the next phase target.

## Scope guard
Do NOT build without explicit direction: audio, multiplayer, PBR/IBL/post-processing,
Linux/macOS. Flag and stop if a task drifts toward these.

## Decision authority
Changes a layer boundary or build/run interface → stop and ask.
Otherwise decide and note with `// decision:` comment.

## Current state
Done: engine, terrain, streaming, plants + 5 species, ecology, structures,
footprints/floaters, research (8 nodes), hand weaving, save/load, pause,
fullscreen, root-digger, spline vines, adjustable/free camera, sky dome, wolf
anatomy + "alive" passes.
**Next (post-prototype / vertical slice):**
1. 2–3 more species per lineage + convergence hybrid
2. Research tree to ~12 nodes
3. First world event (something that *happens*, not just a research unlock)
4. Bloom + one "wow" visual moment (sky shift at convergence)
Target: a stranger plays 2 hours and says "I want to see what happens next."

## Finish line
Work until the current phase's acceptance criteria are met. Don't end with
"next I would…" — take the next step. Stop only for a blocking decision or
phase completion.

## Visual authority
The user is the artist. On all visual/aesthetic decisions (proportions,
silhouette, material feel, "does this read as X"), their word is final.
If they say something looks "off," "weak," "generic," or "too X," that
is the acceptance criterion — implement the fix they describe, don't
propose alternatives or ask for justification.

## Working rules
- Commit and push `devel` after every verified change (builds, tests pass),
  without asking. Never commit `parasymi.sav`. Broken work is reported, not
  committed.
- Reports: no commentary. End a task with a short list of changes only;
  a real deviation or blocker is one bullet.
- Verify visual work in the running game (a scratch copy may move the camera);
  say what was not checked.
