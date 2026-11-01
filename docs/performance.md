# Performance

## Targets
- 8 ms a frame (120 FPS) on an RTX 3060-class card, validation on.
- A fixed sim tick of 30 Hz (currently 60 Hz, `play.tickTime`).
- Chunks 64×64 (currently 32×32), under 2 ms to generate and upload.
- Under 200 draw calls at stress.

## Where it stands
Measured release GPU time on a 4060 Ti at 1600×900, no vsync. Timestamp
queries time each pass (`Renderer.gpuMs`); F3 shows the total.

| Scene | AA | GPU ms |
|---|---|---|
| demo | off | 5.0 |
| demo | msaa4 | 5.9 |
| demo | msaa8 | 7.2 |
| stress | msaa8 | 11.1 |

That was 2026-10-25. By 2026-11-01 the richer garden had grown it to
demo 22.2 (off) / 38.4 (msaa8) and stress 52.5 (msaa8): the vertex
stage of triangle-soup meshes, run three times per plant (solid, glass,
shadow). Welding the meshes into indexed ones brought it to demo 25.9 /
stress 21.6 (msaa8); drawing only the see-through triangles in the glass
passes, to demo 22.8 / stress 17.1; lighter shader builds for the
always-solid triangles, to demo 18.2 / stress 15.6. The breakdown and the methods ranked are in
[shader-optimization.md](shader-optimization.md#round-two-2026-11-01-the-vertices-are-the-cost-now).

Memory:
- Built-once meshes live in device memory (`Buffer.initWith`).
- Per-frame buffers are host-visible.

Streaming meshes at most `meshMs` (3 ms) of chunks a frame.

## Computation-heavy work goes on the GPU
Dense or per-element visual work is generated in shaders, never built on
the CPU per frame or per chunk. That means grass, scatter, particles,
procedural detail, deformation and animation fields.

Shaders make it with instancing, vertex/fragment fields or compute.

The CPU keeps the state and the sim, and sends small records: a tile's
corners, a mote's state, four control points.

## Fog
The fog (`fog.frag`) marches at half the screen's size, 28 steps through
the low slab the garden stands in, the haze above it summed in closed form,
each point of light summed in closed form too. Measured release on a 4060
Ti at 1600×900, `--demo`: the march about 0.9 ms, its composite about
0.1 ms, the overhead map about 0.2 ms.

The overhead map draws only 4 chunks a frame (new ones first, then the
rest in turn): the chunks' ground buffers are host-visible, so reading all
of them every frame cost 2.6 ms.

## Level of detail
Every plant and library mesh is built at `meshgen.lods` (3) levels of
detail, so far-away things use fewer triangles.
- `Builder.lod` does it inside the primitives, so new meshes get it free.
- Each level keeps every other ring/row and half the sides.
- The level is picked by eye distance (`lodAt`, `lodDistances` 36/70).
- Plant slots are (species, variant, lod); part slots are
  `meshlib.slot(id, lod)`.

## Worker threads
CPU loops heavy enough to matter are split over the cores with
`jobs.each` ([architecture.md](architecture.md#parallel-loops-engine-corejobszig)).

In use:
- `Plants.rebuildLinks`, per plant;
- `World.stream` generation, per fresh chunk;
- `syncWorld` meshing, `meshBatch` chunks, each with its own scratch
  (Vulkan uploads stay on main).

Measured gains (release):

| Work | Before | After |
|---|---|---|
| stress sim | 1.6–10 ms/frame | 0.6–5.6 ms/frame |
| chunk gen | 0.50 ms | 0.20 ms |
| mesh+upload | 0.36 ms | 0.27 ms |

The rest of the CPU frame is under 1 ms and hides behind the GPU (frames
in flight). So profile before threading anything else.

### CPU methods to reach for next
While the GPU takes 20–50 ms, the CPU is hidden and speeding it up shows
nothing. When it leads again:
- **Measure with zones, not guesses**: Tracy (`ztracy`) or Superluminal
  on Windows give a per-function timeline of every frame, threads
  included.
- **No allocation in the frame**: a per-frame arena reset each frame for
  scratch lists; the general allocator only for what outlives it.
- **Data laid out for the loop**: SoA for what a hot loop reads (as
  chunks' tiles already are), small hot fields apart from cold ones.
- **SIMD through `m.Vec`** on wide loops (the ecology tick, link
  rebuilding), and `jobs.each` for anything still serial past 1 ms.

## Culling
Chunks (`chunkRadius`), plants and parts are culled to the view frustum
(`m.Frustum`): anything outside the camera's view is skipped.
`Parts.look` sets the frame's eye and view.

## Shadows and post
- Shadows (engine `render/light.zig`) cost ~+3 ms on this machine's 35 ms
  demo frame.
- Bloom costs ~0.1 ms.
- AA in release (demo): off 4.1, fxaa 3.9, msaa4 4.35, msaa8 4.9 ms.

## Shader optimization
Read [optimizing.md](optimizing.md) (the working method and scripts) and
[shader-optimization.md](shader-optimization.md) (the researched rules) first. It holds the
researched methods, what is art-safe, how to measure per pass, and what
was applied.

Optimizations change cost, never the picture. Anything that alters the
look (sample shading, hashes, precision) is the user's call.
