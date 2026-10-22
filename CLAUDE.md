# Parasymi
A player-centric, Factorio-like automation game about magically infused plants
(parasitic and symbiotic lineages that eventually converge). Zig 0.16, GLFW
(zglfw) + Vulkan 1.3 (vulkan-zig, bindings generated from the SDK's `vk.xml`),
Windows first. No asset files: every mesh, the font and all UI shapes are
generated in code.

## Build, run, test

```
zig build run                     # debug build (Vulkan validation on)
zig build run -Drelease=true      # optimized (build.zig prefers ReleaseFast; -Doptimize is not accepted)
zig build run -- --demo           # starter garden + structures, fast-forwarded (testing only)
zig build run -- --stress         # 120x120 field of plants (perf)
zig build run -- --tod=0.9        # start at a time of day (0 midnight, 0.5 noon)
zig build run -- --novsync --seed=0x1234
zig build test                    # logic tests; game code runs headless (no window/GPU)
```

Needs `VULKAN_SDK` (for `vk.xml` and `glslc`). If GLFW fails to compile with
`unknown type name 'uint64_t'`, a stray `CPATH` pointing at another clang is
the cause. Dependencies are pinned to Zig-0.16-compatible revisions
(vulkan-zig `zig-0.16-compat`, zglfw `f04fdbf`); upstream heads need 0.17.

## Layers

Each layer imports only the ones above it:

```
core      math (all numeric helpers), color, rng, noise, registry
platform  window input
gfx       Vulkan context, swapchain, buffers, pipelines, meshgen primitives, mesh library
world     chunks (tile SoA + occupancy), pure generation, streaming
sim       items/inventories, species, plants (footprints, floaters), ecology tick
game      player, actions, structures, research, craft, sky, hud, view, play
render    renderer + passes, terrain meshing, camera
ui        Draw batch (SDF shapes + glyphs), font
main      wiring and the frame loop
```

## Registries: one module per thing
Every domain is a registry (`core/registry.zig`): a namespace lists one module
per part, the enum is derived from it with `std.meta.DeclEnum`, tables, tagged
unions and structs are gathered from the modules, and behaviour dispatches
with `switch (id) { inline else => |k| reg.module(k).hook(...) }`. Hooks are
optional (`reg.has(k, "hook")`).

| Domain | Registry | Module declares |
|---|---|---|
| species | `sim/species.zig` -> `sim/species/*.zig` | `def` |
| meshes | `gfx/meshlib.zig` -> `gfx/meshes/*.zig` | `build(b)` |
| structures | `game/structures.zig` -> `game/structures/*.zig` | `def`, `State`, `tick`, `wants`, `output`, `release`, `configure`, `emit`, `describe` |
| research | `game/progression.zig` -> `game/research/*.zig` | `def`, `apply`, `unlocks`, `completed`, `veil` |
| hud panels | `game/hud.zig` -> `game/hud/*.zig` | `draw`, `visible` (draw order = declaration order) |
| render passes | `render/renderer.zig` -> `render/passes/*.zig` | `desc`, `Frame`, `initFrame`/`deinitFrame`, `record` (record order = declaration order) |

Adding a thing = one new file + one line in its registry namespace. Never add
a `switch` over a registry's kinds outside the registry file; add a hook.

Items (`sim/items.zig`) and weave recipes (`game/craft.zig`) are plain data
tables on purpose.

## Conventions
- Style: 2-space indent, `name:Type` with no space after the colon, terse doc
  comments (`//!` per file, `///` per decl). LF line endings.
- Math lives in `core/math.zig` (imported as `m`): use `m.f(int)` for
  int->f32, `m.ratio(a, b)`, `m.floorTo(T, x)`, `m.tileOf`/`m.tileAt`,
  `m.tileCentre`/`m.footprintCentre`, `m.dirVec`/`m.dirYaw`, `m.angleDiff`,
  `m.tau`/`m.pi`/`m.clamp`, vectors and matrices. Colours go through
  `core/color.zig` (`rgb`, `shade`, `mix`, `toF`). Do not reach into
  `std.math` or hand-roll casts and tile maths elsewhere.
- No inline `std.ns.Name`: alias at the top of the file
  (`const Allocator = std.mem.Allocator;`, `const testing = std.testing;`).
- Generated meshes must be watertight: tubes share rings along the path,
  vertex-shader offsets must be identical for every copy of a shared vertex.
- UI is organic and animated, never boxes: membranes, pods, tendrils and
  glows as SDFs in `shaders/ui.frag`.

## Design direction
- No global resources: items live in the player's belly and in structures;
  essence and seeds live in plants until harvested.
- Every plant is seeded by the player; plants grow before they are usable.
- Research is Factorio-style: research blooms consume ingredients fed to them.
- Plants have footprints (multi-tile or floating), sharing occupancy with structures.
- Everything is player-centric and builds toward full automation.

## Zig 0.16 API notes

- `std.Io` replaces all old I/O (`GenericReader`, `AnyReader`, `FixedBufferStream`, `std.net` gone). Pass an `Io` instance like an allocator. `std.Io.Threaded` for thread-pool I/O.
- "Juicy Main": `main` accepts injected params (process, allocator). No global env/args.
- `@Type` removed. Use `@Pointer`, `@ErrorUnion`, explicit `error{...}` sets.
- `ArrayList{}` → `.empty`.
- `ArenaAllocator` is lock-free and thread-safe. `ThreadSafeAllocator` wrapper removed.
- Build: `root_module` + `Module` methods. Deps in `zig-pkg/`, not `.zig-cache`.
- Incremental compilation is real (~30 ms small rebuilds).

## Code design
- **Tagged unions** for mutually exclusive states. Never a struct with multiple nullable fields.
- **Explicit error sets** in public APIs. Never `anyerror` on a signature.
- **`comptime T: type`** over `anytype` unless you need polymorphism.
- **Distinct types** for domain IDs so the compiler catches mix-ups.
- **Exhaustive `switch`** with `else => unreachable` or error.
- **Pass allocators explicitly.** No global allocator.
- **`defer deinit()`** immediately after acquisition. `errdefer` for error paths.
- **Arena allocators** for batch/temporary work (e.g. chunk mesh gen, then free the whole arena).
- **`std.testing.allocator`** in tests (reports leaks with stack traces).
- **Vtable pattern** for many-method interfaces (one shared const table per type).
- **SoA for hot loops.** AoS only for small, cohesive per-entity state.
- **Registry + comptime dispatch** (`std.meta.DeclEnum` + `inline else`) for plugin-style extensibility.
- **Larger cohesive files** are idiomatic. Tests alongside implementation. Don't over-fragment.
- **`try` by default.** `catch` only with a genuine recovery strategy.
- **Translate errors at module boundaries:** map a dependency's error set onto your stable public set.
- **`defer task.cancel(io)`** for idempotent cancellation in concurrent code.
- Never hand-roll linear algebra. Matrix/vec ops are methods on `M4`/`Vec3`
  in `core/math.zig`. A call site should read `m.inverse(a)`, not a 20-line
  cofactor expansion. If the method doesn't exist, add it + a test first.