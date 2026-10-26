# The engine

`engine/` is a Zig package of its own (`engine/build.zig`,
`engine/build.zig.zon`). It holds whatever does not know it is a garden,
and Parasymi depends on it by path (`.engine = .{ .path = "engine" }`).
Game code reaches it as `@import("engine")` (`engine/src/engine.zig`):
`engine.core.math`, `engine.gfx.ctx`, `engine.render.renderer`,
`engine.ui.draw`, and also `engine.vk` and `engine.glfw` for the libraries
underneath. It never imports the game.

| Layer | Engine | Game (`src/`) |
|---|---|---|
| core | math, color, rng, noise, registry, jobs, text, png | — |
| platform | input, display | — |
| anim | `rig`: `Turn` (Y·X·Z, `blend`), `twoBone` (law-of-cosines IK), `inverses`, `skin` | the wolf's skeleton (`wolf_skeleton`: bones, offsets, `fk`, breath swell) and limb solvers (`player.solveLeg`/`solveArm`, built on `twoBone`) |
| gfx | ctx, swapchain, buffer, pipeline, `vertex` (`Mesh`, `Skin`, `Grow`, `MeshPose`, `Ui`, `Light`), `meshgen` (`Mesher(Part, stem)`: `Builder`, tubes, cone, loft, patch, ellipsoid, vines, braids, bands; LOD scheme; Growth/transport), `sculpt` (SDF forms, surface nets, bone weights) | meshgen (blades, laminae, petals, stamens, flowers, plants; re-exports the engine's), meshlib, growth, kits, `vertex` (instances; re-exports the rest) |
| world | `chunk` (grid: `SIZE`, `Coord`, `MeshSlot`, `localIndex`), `World(L)` (streaming) | `chunk` (the garden's tiles), `gen`, `world` (`World` over the garden's land) |
| render | `Renderer(G)`, post, light, camera, `passes/ui` | `renderer` (the garden's `G`), passes, terrain meshing |
| ui | draw, font | — |
| shaders | post, bloom, composite, fxaa, ui, `shadow.frag`, `light.glsl` | everything else; `common.glsl` includes `light.glsl` |

## How a game plugs in
- **Renderer**: `engine.render.renderer.Renderer(G)`, where `G` is a
  namespace (Parasymi's is `src/render/renderer.zig`, using `@This()`)
  declaring `name`, `passes` (the pass registry, record order; list
  `er.ui` as `ui` for the HUD), `Push` (holding `vp`, `eye_time`, `view`,
  `sun`, `light`), `Scene` (holding `push`, `clear`, `lights`, plus `ui`
  and `ui_time` for the UI pass), `Stats` (holding `draws`, `lights`,
  `gpu_ms`) and `Ext` (the game's own state, `r.ext`). It may also declare
  the hooks `start(r)`, `release(r)` and `carry(prev)`. Its comment block
  lists the full contract. Pass descriptors carry SPIR-V bytes
  (`.vert = @embedFile("plant.vert")`), so each module embeds its own
  shaders.
- **Meshes**: `engine.gfx.meshgen.Mesher(Part, stem)`, where `Part` is the
  game's `enum(u32)` of vertex roles and `stem` the role plain woody
  surfaces take. Parasymi's is `mg.gen` (`src/gfx/meshgen.zig`), whose
  `Builder` every mesh is built in. A sculpt meshes into it with
  `s.mesh(mg.gen, b, h, t, part)`.
- **World**: `engine.world.World(L)`, where `L` declares `Chunk` (holding
  `at`, `height`, `kind`, `occ`, `pins`, `gpu_slot`, `dirty`), `Kind`,
  `Occ` (with `.none`), `blank`, `generate` and `heightAt`. Parasymi's is
  `Land` in `src/world/world.zig`.
- **Shaders**: a world shader declares its push block `pc` and `SUN`, then
  includes `light.glsl` (`Lighting`, `project`, `keyShadow`,
  `pointLight`). The header of `light.glsl` lists what it expects.
- **Build**: the game's `build.zig` imports the engine's build
  (`const eb = @import("engine")`) for `eb.glslc`, `eb.registry` and
  `eb.compile`. It passes `target`, `optimize`, `glslc` and
  `vk-registry` to `b.dependency("engine", ...)` and compiles its own
  shaders with `-I` set to both shader folders. `zig build test` runs the
  game's tests and the engine's. `cd engine && zig build test` runs the
  engine's tests alone.

## Starting another game on it
Copy or reference `engine/` (a path or git dependency), then write a
`G` and an `L` like Parasymi's: a `render/renderer.zig` with your passes,
and a land if you want streamed chunks. Wire a `main` the way
`src/main.zig` does: window, `Input`, `Renderer.init`, then loop on
`draw`. The UI shapes in `ui.frag` (membranes, pods, tendrils) come in
Parasymi's style; restyle them there.
