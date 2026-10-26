# Performance

- Target 8 ms (120 FPS), RTX 3060-class, validation on; 30 Hz fixed sim
  tick (currently 60 Hz, `play.TICK`); chunks 64×64 (currently 32×32),
  < 2 ms gen+upload; < 200 draw calls at stress.
- Measured release GPU time (4060 Ti, 1600×900, no vsync; timestamp queries
  per pass, `Renderer.gpu_ms`, F3 shows the total): demo 5.0 ms (AA off) /
  5.9 (msaa4) / 7.2 (msaa8), stress 11.1 (msaa8). Built-once meshes live in
  device memory (`Buffer.initWith`); per-frame buffers are host-visible.
  Streaming meshes at most `MESH_MS` (3 ms) of chunks a frame.
- **Computation-heavy work goes on the GPU**: dense or per-element visual
  work (grass, scatter, particles, procedural detail, deformation,
  animation fields) is generated in shaders (instancing, vertex/fragment
  fields, compute), never built on the CPU per frame or per chunk. The CPU
  keeps state and sim and sends small records (a tile's corners, a mote's
  state, four control points).
- Level of detail: every plant and library mesh is built at `meshgen.LODS`
  (3) levels by `Builder.lod` inside the primitives (each level keeps every
  other ring/row and half the sides), so new meshes get it free. Picked by
  eye distance (`lodAt`, `LOD_AT` 36/70). Plant slots (species, variant,
  lod); part slots `meshlib.slot(id, lod)`.
- Worker threads: CPU loops heavy enough to matter are split over cores
  with `jobs.each` ([architecture.md](architecture.md#parallel-loops-corejobszig)).
  In use: `Plants.rebuildLinks` (per plant), `World.stream` generation (per
  fresh chunk), `syncWorld` meshing (`MESH_BATCH` chunks, each its own
  scratch; Vulkan uploads stay on main). Measured gains (release): stress
  sim 1.6–10 → 0.6–5.6 ms/frame, chunk gen 0.50 → 0.20 ms, mesh+upload
  0.36 → 0.27 ms. The rest of the CPU frame is under 1 ms and hides behind
  the GPU (frames in flight), so profile before threading anything else.
- Culling: chunks (`CHUNK_RADIUS`), plants and parts are culled to the view
  frustum (`m.Frustum`; `Parts.look` sets the frame's eye and view).
- Shadows (engine `render/light.zig`): cost ~+3 ms on this machine's 35 ms demo
  frame.
- Post: bloom ~0.1 ms. AA release (demo): off 4.1, fxaa 3.9, msaa4 4.35,
  msaa8 4.9 ms.
- Shader optimization: read [shader-optimization.md](shader-optimization.md)
  first (researched methods, what is art-safe, how to measure per pass,
  what was applied). Optimizations change cost, never the picture; anything
  that alters the look (sample shading, hashes, precision) is the user's
  call.
