# CLAUDE.md

## What this is

Player-centric Factorio-like automation game. Magically infused plants (parasitic +
symbiotic lineages that converge). Zig 0.16, zglfw + vulkan-zig, Windows, no asset
files (everything procedural). 2.5D top-down 3D. Adjustable pitch (30°–85°,
default 55°, Ctrl+W/S), yaw via Q/E. No free rotation.

## Build

```
zig build run                     # debug (validation on)
zig build run -Drelease=true      # ReleaseFast
zig build run -- --demo           # test garden + structures, fast-forwarded
zig build run -- --stress         # 120×120 plant field
zig build run -- --tod=0.9        # time of day (0=midnight, 0.5=noon)
zig build run -- --novsync --seed=0x1234
zig build run -- --load           # load save
zig build test                    # headless logic tests
```

Needs `VULKAN_SDK` (`vk.xml` + `glslc`). Pinned: vulkan-zig `zig-0.16-compat`,
zglfw `f04fdbf`. Upstream heads need 0.17.

## Performance

- 8 ms frame (120 FPS), RTX 3060-class, validation ON.
- 30 Hz fixed sim tick, decoupled from render.
- Chunk: 64×64 tiles, < 2 ms gen+upload, queue-based (no frame blocks).
- < 200 draw calls at stress. Instancing expected.

## Layers (import only downward)

```
core      math, color, rng, noise, registry
platform  window, input
gfx       Vulkan ctx, swapchain, buffers, pipelines, meshgen, meshlib
world     chunks (tile SoA + occupancy), generation, streaming
sim       items, species, plants (footprints, floaters), ecology tick
game      player, actions, structures, research, craft, sky, hud, view, play
render    renderer + passes, terrain meshing, camera
ui        SDF draw batch, font
main      wiring, frame loop
```

## Registries

One module per thing. Enum via `std.meta.DeclEnum`, dispatch via
`switch (id) { inline else => |k| reg.module(k).hook(...) }`.
Adding a thing = one file + one line in the namespace. Never add a `switch`
over registry kinds outside the registry file.

| Domain | Entry | Hooks |
|---|---|---|
| species | `sim/species.zig` | `def` |
| meshes | `gfx/meshlib.zig` | `build(b)` |
| structures | `game/structures.zig` | `def`, `State`, `tick`, `wants`, `output`, `release`, `configure`, `emit`, `describe` |
| research | `game/progression.zig` | `def`, `apply`, `unlocks`, `completed`, `veil` |
| hud panels | `game/hud.zig` | `draw`, `visible` |
| render passes | `render/renderer.zig` | `desc`, `Frame`, `initFrame`/`deinitFrame`, `record` |

Items (`sim/items.zig`) and weave recipes (`game/craft.zig`) are plain data tables.

## Conventions

- 2-space indent, `name:Type` (no space after colon), terse `//!`/`///` docs, LF.
- All math via `core/math.zig` (alias `m`): `m.f`, `m.ratio`, `m.floorTo`,
  `m.tileOf`, `m.tileAt`, `m.tileCentre`, `m.footprintCentre`, `m.dirVec`,
  `m.dirYaw`, `m.angleDiff`, `m.tau`, `m.pi`, `m.clamp`. Colours via
  `core/color.zig`. Never reach into `std.math` or hand-roll casts.
- No inline `std.ns.Name` — alias at file top.
- **Never hand-roll linear algebra.** Matrix/vec ops are methods on `M4`/`Vec3`
  in `core/math.zig`. Use `m.inverseRigid` for rotation+translation (camera,
  player), `m.inverseAffine` for scaled transforms, `m.inverse` (full adjugate)
  only as fallback. A call site reads `m.inverse(a)`, not a 20-line expansion.
  A singular matrix is a bug: `@panic` in debug, don't silently return zero.
- **All geometry watertight and seamless:** tubes share rings with smooth
  orientation, bundles are continuous, cones capped, leaf/petal meshes and
  UI SDFs show no cracks or seams. If a new primitive is added, verify no
  open edges or seam discontinuities.
- **Grown vines use Catmull-Rom splines** (`m.catmullRom`, `m.splineResample`)
  with `growthPath()` for control-point generation (wobble, curl, taper, seed).
  Never draw a vine as a straight line or a simple arc.
- **Wolf body is alive:** tail driven by spline from joint chain (wobble 0.06,
  curl 0.15), torso/limb tubes have 1–2% breathing radius modulation in the
  vertex shader, vine strands have baked wobble 0.03, ears/mane use
  `growthPath()` with curl 0.3. Skeleton is rigid (joints drive pose), surface
  is organic.
- UI: organic, animated, no boxes. SDFs in `shaders/ui.frag`.
- Edits: write to files, pass files to scripts. No inline heredocs.

## Zig 0.16 API notes

- `std.Io` replaces all old I/O. Pass an `Io` instance like an allocator.
- "Juicy Main": `main` accepts injected params. No global env/args.
- `@Type` removed. Use `@Pointer`, `@ErrorUnion`, explicit `error{...}` sets.
- `ArrayList{}` → `.empty`. `ArenaAllocator` is lock-free.
- Build: `root_module` + `Module`. Deps in `zig-pkg/`.

## Code design
- Tagged unions for exclusive states. Explicit error sets in public APIs.
- `comptime T: type` over `anytype`. Distinct types for domain IDs.
- Exhaustive `switch`. Pass allocators explicitly. `defer deinit()` immediately.
- Arena allocators for batch work. `std.testing.allocator` in tests.
- Vtable pattern for many-method interfaces. SoA for hot loops.
- `try` by default. Translate errors at module boundaries.

## Design
- No global resources. Items live in the player's belly, in structures, or
  in plants until harvested.
- Every plant is player-seeded and must grow before use.
- Research: Factorio-lab model. A structure consumes ingredients unit by unit.
- Hand-weaving is the bootstrap (wolf weaves seeds from gathered matter + starlight).
- Plants and structures share occupancy. Footprints: 1×1, 2×2, or floating.
- Player-centric, builds toward full automation.
- Root-digger: 1×1, adjacent to a node, extracts 1 item/4s, outputs to
  adjacent conduit/structure, buffers 8, idles when node empty.
  Recipe: 3 fibre + 2 grit + 1 ley shard. Gated by "Deep Rooting" research.

## Visual (current)
- Terrain: flat, biome-tinted tiles, one directional + ambient, flat shading.
- Plants: procedural (tubes via splines, spheres, leaf plates), vertex-shader
  sway. Parasitic: desaturated reds/oranges. Symbiotic: greens/teals.
- Sky: gradient dome, sun/moon, dusk glow, starlight motes at night.
- UI: wobbling membranes, seed-pod slots, tendril bars, soft glow. 150 ms anim.
- Wolf: translucent fresnel belly (amber) that inflates (+35%), drops and sags
  with fill, heavy contents jostling inside on springs; sap pectorals (denser
  sap, sprung gel) with chest vines tucked behind; contact shadows under feet,
  accent discipline (amber only on belly/eyes/inner ear, rest muted),
  anisotropic vine highlight along tube tangent.
- "Celestial / beyond comprehension" is the next phase target.

## Scope guard
Do NOT build without explicit direction: audio, multiplayer, PBR/IBL/post-processing,
Linux/macOS. Flag and stop if a task drifts toward these.

## Decision authority
Changes a layer boundary or build/run interface → stop and ask.
Otherwise decide and note with `// decision:` comment.

## Current state
Phases 1–10 complete (engine, terrain, plants, species, structures, footprints,
conduits, cache, germinator, research bloom, Hollowheart, Driftwisp, save/load,
pause, root-digger, spline vines, wolf "alive" pass).
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