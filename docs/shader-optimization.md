# Shader optimization: methods that keep the art

Research notes for future sessions (2026-10-25). The rule over all of it
(CLAUDE.md, Visual authority): **an optimization may change cost, never the
picture.** A method is "art-safe" only if the frame comes out the same (bit
for bit or within float rounding). Anything that trades look for speed
(fewer samples, coarser shading, lower precision that shows, dropped
effects) is not ours to take: flag it to the user and stop.

## 0. Measure first, per pass, on the GPU

- The CPU frame hides behind the GPU (frames in flight), so `frame_ms` says
  little about a shader change. Read GPU time per pass: Vulkan timestamp
  queries written around every pass (`vkCmdWriteTimestamp2`, a query pool
  per frame in flight, read back after its fence; ticks x
  `limits.timestampPeriod` ns). F3 shows the GPU total; `Renderer.gpu_ms`
  holds each pass (see §Measurement below for the scratch procedure).
- Same scene, same camera, vsync off, release build, long enough average
  (a few hundred frames): `--demo --inspect` orbits a fixed path.
- Compare screenshots before/after (`--inspect` shots) to prove the
  picture did not change. Vendor tools when deeper: Nsight Graphics (warp
  occupancy, register count, SFU/ALU/TEX limiter), RGA / RGP on AMD.

## 1. Don't shade what is thrown away (biggest wins here)

- **Early depth test.** A fragment that fails depth before the shader runs
  costs nothing. It is lost when the shader writes depth *and* may
  `discard` (late Z). A pass that writes no depth may `discard` and still
  test early; `layout(early_fragment_tests) in;` forces it (safe only when
  the shader writes no depth). (NVIDIA "Advanced API Performance: Shaders";
  OpenGL wiki "Early Fragment Test".)
- **Two-pass solid/glass (ours).** `plants`/`parts` keep alpha >= SOLID and
  write depth; `*_glass` blend the rest testing depth `less_or_equal`. So
  every visible opaque fragment passes depth *again* in the glass pass
  (equal depth), is shaded in full and then discarded by `keepPass`. Art-
  safe fix: the glass pipelines test `less` (strictly nearer), with the
  vertex stage's `gl_Position` `invariant` so both passes rasterize the
  same depth: the opaque fragments fail early Z and are never shaded; the
  see-through ones wrote no depth in the solid pass and still pass.
  Only change: two *different* surfaces exactly coplanar (z-fight case).
- **Discard as early as the alpha is known.** Where the alpha is decided
  before the expensive colour (an opaque material in the glass pass), test
  `keepPass` first. Derivatives (`surfaceTangent`) must be taken before any
  discard (uniform control flow).
- **Depth prepass with `equal` test** (classic foliage trick): only pays
  with heavy overdraw and cheap vertex work; our vertex stages are heavy
  (growth, wind, skinning), so measure before trying.

## 2. MSAA and sample-rate shading

- Plain MSAA shades once per pixel; **sample shading (`minSampleShading`
  1) shades every sample = supersampling**, ~4x fragment cost at msaa4.
  Khronos' MSAA sample: leave it off unless needed. (docs.vulkan.org
  samples/performance/msaa.)
- We enable it on plant/part passes because the solid/glass split is
  decided per fragment by alpha. Turning it off, lowering
  `minSampleShading`, or alpha-to-coverage *changes edges* of the split:
  **art decision, ask the user** before touching it.
- Art-safe: keep resolve in the render pass (`pResolveAttachments`, we do),
  multisampled attachments `store_op = dont_care` (we do for depth).

## 3. Do less work per fragment (exactly the same result)

- **Fuse loops over the same data.** One pass over the point lights that
  accumulates every quantity needed (plain facing, wrapped facing, the
  mirrored glint) instead of three loops each re-reading the buffer and
  re-doing `d`, `dot(d,d)`, the window. Keep each accumulator's add order
  so the sums match.
- **Skip work whose weight is zero.** `x * f()` with `x == 0` for a whole
  region (sap glisten on old growth: `thin == 0`; health 0) → `if (x > 0)`.
  Coherent branches (smooth inputs, per-instance values, `flat` values)
  cost little; a branch that flips per pixel inside a warp runs both sides,
  so only branch on smooth or uniform values.
- **Hoist what is the same for every fragment** to the CPU/push constants
  or the vertex stage (e.g. `keyLight()`, sky colours from `DAYLIGHT`,
  `VEIL`): drivers usually fold uniform math, but not across function
  boundaries reliably. Only exact (same formula, same precision).
- **Specialization constants / `#define` variants** instead of runtime
  switches on per-pipeline values: dead code goes, register pressure
  drops. (Khronos sample "specialization_constants".) Our GLASS/SHADOW
  variants already do this.
- **Register pressure → occupancy.** Big ubershaders (part.frag's role
  switch) are sized by their worst branch: fewer warps in flight, less
  latency hiding. Moving rarely used heavy branches (beams, halo,
  projection, energy) into their own pipeline/variant can raise occupancy
  for the common materials, at the cost of more draws. Measure with
  Nsight before/after. (GPUOpen "Register pressure"; AMD GDC2017 GCN.)
- **MAD form, cheap ops** (Persson, "Low-Level Thinking in High-Level
  Shading Languages", GDC 2013; PowerVR Low-Level GLSL guide): write
  `a*b+c`; fold constants into one side (`x * (1/k)`), `clamp(x,0,1)` is
  free as a modifier, `inversesqrt` over `1/sqrt`, `dot(v,v)` over
  `length` when comparing, `normalize` once and reuse. `pow(x, n)` for
  small integer n → multiplies (exp2/log2 run on the quarter-rate SFU).
  These are float-identical only when the algebra is (x*x*x vs pow(x,3)
  differs in the last bits: acceptable rounding, not a look change).
- **Hashes.** Integer PCG (`pcg3d`, Jarzynski & Olano, JCGT 2020) is fast
  and good, but a different hash moves every bubble/glint/star: an art
  change. Keep our hashes; use PCG only for new effects.

## 4. Textures and memory

- Shadow PCF with `sampler2DArrayShadow` gets 2x2 compares per tap free in
  hardware (we use 4 taps = 16 compares). `textureGather` needs more ALU.
  Keep. (NVIDIA shadow mapping paper; Castaño "Shadow Mapping Summary".)
- Uniform (warp-coherent) reads of buffers are fast; divergent reads of
  constant buffers serialize. Our `Lighting` is read uniformly (same index
  across the warp) — good.

## 5. Vertex stage

- Our vertex shaders do growth, wind, skinning per vertex every frame per
  pass: the shadow variant (3 views, multiview) runs it again per caster.
  Compressed vertex formats and fewer attributes cut fetch; LODs already
  cut counts. Shadow casters at coarsest LOD (we do).

## Measurement (scratch procedure)

1. `zig build -Drelease=true`.
2. Scratch edit in `main.zig`'s loop: after N (e.g. 600) frames log
   `r.gpu_ms` per pass and quit. Revert after.
3. `zig-out/bin/parasymi --demo --novsync` (and `--stress`), fixed camera.
4. Change the shader, repeat; compare per pass; check shots for sameness.

## Applied (2026-10-25)

See git log "Shaders: ..." for what was applied and the measured gains;
the table at the end of this file is updated with each round.

## Sources

- NVIDIA, Advanced API Performance: Shaders — developer.nvidia.com/blog/advanced-api-performance-shaders
- Khronos Vulkan Samples, MSAA — docs.vulkan.org/samples/latest/samples/performance/msaa/README.html
- Khronos Vulkan Samples, Specialization constants — docs.vulkan.org/samples/latest/samples/performance/specialization_constants/README.html
- E. Persson, Low-Level Thinking in High-Level Shading Languages (GDC 2013) — humus.name/Articles/Persson_LowLevelThinking.pdf
- Imagination, Low-level GLSL optimisation (MAD form) — docs.imgtec.com/performance-guides/low-level-glsl
- AMD GPUOpen, register pressure / occupancy; GDC2017 Advanced Shader Programming on GCN — gpuopen.com
- Jarzynski & Olano, Hash Functions for GPU Rendering (JCGT 9(3), 2020) — jcgt.org/published/0009/03/02
- OpenGL wiki, Early Fragment Test — opengl.org/wiki/Early_Depth_Test
- NVIDIA, Transparency or Translucency Rendering — developer.nvidia.com/content/transparency-or-translucency-rendering
- I. Castaño, Shadow Mapping Summary — ludicon.com/castano/blog
- Vulkan tutorial, divergence audit — docs.vulkan.org/tutorial/latest/Advanced_Vulkan_Compute
