# Shader optimization: methods that keep the art

Research notes for future sessions (2026-10-25).

**The rule over all of it** (CLAUDE.md, Visual authority): **an
optimization may change cost, never the picture.**

A method is "art-safe" only if the frame comes out the same: bit for bit,
or within float rounding. Anything that trades look for speed is not ours
to take: fewer samples, coarser shading, lower precision that shows,
dropped effects. Flag it to the user and stop.

## 0. Measure first, per pass, on the GPU

**Lesson from the first round: the shaders were not the problem.**

Every buffer was in host memory (the CPU's RAM), so each draw fetched its
vertices over PCIe, the slow road between the CPU's memory and the
graphics card. The clues:
- plant/part passes cost the same with AA off as at msaa8;
- the same with a trivial fragment shader, and with a trivial vertex
  shader;
- the cost scaled with bytes per vertex.

So before touching shader math, knock things out one at a time (trivial
frag, trivial vert, AA off) and see which one moves the time.

### Read GPU time, not CPU time
The CPU frame hides behind the GPU (frames in flight), so `frameMs` says
little about a shader change. Read GPU time per pass instead:
- Vulkan timestamp queries are written around every pass
  (`vkCmdWriteTimestamp2`), with a query pool per frame in flight, read
  back after its fence.
- Ticks × `limits.timestampPeriod` = nanoseconds.
- F3 shows the GPU total; `Renderer.gpuMs` holds each pass (see
  §Measurement below for the scratch procedure).

### Compare like with like
- Same scene, same camera, vsync off, release build, and a long enough
  average (a few hundred frames). `--demo --inspect` orbits a fixed path.
- Compare screenshots before/after (`--inspect` shots) to prove the
  picture did not change.
- Vendor tools when you need to go deeper: Nsight Graphics (warp
  occupancy, register count, SFU/ALU/TEX limiter), RGA / RGP on AMD.

## 1. Don't shade what is thrown away (biggest wins here)

### Early depth test
The GPU can check "is something already in front of this?" *before*
running the fragment shader. A fragment that fails that early depth test
costs nothing.
- It is lost when the shader writes depth *and* may `discard`. Then the
  test has to wait until after the shader ("late Z").
- A pass that writes no depth may `discard` and still test early.
- `layout(early_fragment_tests) in;` forces it. It is safe only when the
  shader writes no depth.

(NVIDIA "Advanced API Performance: Shaders"; OpenGL wiki "Early Fragment
Test".)

### Two-pass solid/glass (ours, applied)
- `plants`/`parts` keep alpha >= SOLID and write depth.
- `*Glass` blend the rest, testing depth `less_or_equal`.

The waste: every visible opaque fragment passes depth *again* in the glass
pass (its depth is equal), is shaded in full, and is then discarded by
`keepPass`.

The art-safe fix:
- The glass pipelines test `less` (strictly nearer).
- The vertex stage's `gl_Position` is `invariant`, so both passes
  rasterize exactly the same depth.
- Now the opaque fragments fail early Z and are never shaded. The
  see-through ones wrote no depth in the solid pass, so they still pass.

The only change: two *different* surfaces that are exactly coplanar (the
z-fight case).

### Discard as early as the alpha is known
Where the alpha is decided before the expensive colour (an opaque material
in the glass pass), test `keepPass` first.

Derivatives (`surfaceTangent`) must be taken before any discard (uniform
control flow).

### Depth prepass with `equal` test
A classic foliage trick: draw depth only first, then shade only what
matches. It only pays with heavy overdraw and cheap vertex work. Our
vertex stages are heavy (growth, wind, skinning), so measure before trying.

## 2. MSAA and sample-rate shading

MSAA smooths edges by checking coverage at several points (samples) per
pixel.
- Plain MSAA shades once per pixel.
- **Sample shading (`minSampleShading` 1) shades every sample, which is
  supersampling**: ~4x fragment cost at msaa4.
- Khronos' MSAA sample says: leave it off unless needed.
  (docs.vulkan.org samples/performance/msaa.)

We enable it on plant/part passes because the solid/glass split is
decided per fragment by alpha. Turning it off, lowering
`minSampleShading`, or alpha-to-coverage *changes the edges* of the split:
**art decision, ask the user** before touching it.

Art-safe, and we already do both:
- keep the resolve in the render pass (`pResolveAttachments`);
- multisampled attachments use `store_op = dont_care` (we do for depth).

## 3. Do less work per fragment (exactly the same result)

### Fuse loops over the same data
Make one pass over the point lights that adds up every quantity needed:
plain facing, wrapped facing, the mirrored glint. Not three loops, each
re-reading the buffer and re-doing `d`, `dot(d,d)`, the window.

Keep each accumulator's add order so the sums match.

### Skip work whose weight is zero
If `x * f()` has `x == 0` for a whole region, wrap it in `if (x > 0)`.
Examples: sap glisten on old growth (`thin == 0`); health 0.

A warp is a group of pixels the GPU shades in lockstep. So:
- coherent branches (smooth inputs, per-instance values, `flat` values)
  cost little;
- a branch that flips per pixel inside a warp runs both sides.

Only branch on smooth or uniform values.

### Hoist what is the same for every fragment
Move it to the CPU/push constants or the vertex stage, e.g. `keyLight()`,
the sky colours from `DAYLIGHT`, `VEIL`.

Drivers usually fold uniform math, but not reliably across function
boundaries. Only do it when exact (same formula, same precision).

### Specialization constants / `#define` variants
Use them instead of runtime switches on per-pipeline values: the dead code
goes and register pressure drops. (Khronos sample
"specialization_constants".) Our GLASS/SHADOW variants already do this.

### Register pressure and occupancy
A shader needs registers (the GPU's scratch slots). Big ubershaders, like
part.frag's role switch, are sized by their worst branch. That means fewer
warps in flight and less latency hiding (the GPU has less other work to
switch to while it waits on memory).

Moving rarely used heavy branches (beams, halo, projection, energy) into
their own pipeline/variant can raise occupancy for the common materials,
at the cost of more draws. Measure with Nsight before/after. (GPUOpen
"Register pressure"; AMD GDC2017 GCN.)

### Low-level rules
From Persson, "Low-Level Thinking in High-Level Shading Languages", GDC
2013. Checked against the deck's speaker notes (the slides' code is
images). Its examples target VLIW Radeon HD 4870 disassembly, but most
rules are general.

**What you write is what you get.**
- IEEE float reordering is unsafe, so the compiler won't turn
  `(x - 0.3) * 2.5` into `x * 2.5 - 0.75`. The author has to.
- Reordering changes rounding (fine for us). But it can turn a value that
  should be exactly 0 slightly negative, so `sqrt`/`pow` of it gives NaN.
  Check the inputs' range before rewriting.

**MAD form** (multiply-add: one `a * b + c` is a single instruction).
- Any range remap is one multiply-add, plus a clamp at most:
  `clamp(x * scale + offset, 0, 1)`.
- Write a division as a multiply by the reciprocal, so an add folds into
  it.
- `acc += a*b + c*d` costs one more op than `acc += a*b; acc += c*d`,
  because the parentheses order it.

**Modifiers.**
- `abs` and negation are free on an operation's inputs, but cost a move
  on its output.
- `saturate`/`clamp(…,0,1)` is free on the output. Put the math inside it
  rather than clamping inputs (interpolants, constants, fetches).

**Scalar before vector.** This is the most widely applicable win, on
every GPU, says the deck.
- `normalize`, `length` and `distance` each hide a `dot`.
- Work out the scalar factor (an `inversesqrt` times any other scalar),
  then multiply the vector once.
- The compiler shares a `dot` only between textually identical
  subexpressions (`distance(a,b)` and `distance(b,a)` don't match).
- Rather than comparing squared lengths, reuse the `inversesqrt` that is
  computed anyway. Clamping a length becomes
  `v * min(1, maxLen * rsqrt(dot(v,v)))`.

**Cheap vs suspect.**
- Conditional assignment (`c ? a : b`) beats `sign()` and `step()`.
- Trigonometry is fine, but angles often mean the math wasn't finished (a
  `dot` may do it).
- Inverse trig (`atan`, `acos`) is almost always a sign of that.
- Merge chained transforms into one matrix on the CPU.

**Branches meant to skip work must stay branches.**
- HLSL has `[branch]`. In GLSL the equivalent is
  `GL_EXT_control_flow_attributes` `[[dont_flatten]]` (it gives SPIR-V
  `DontFlatten`).
- Use it on our skip branches (glisten, mirror) if a compiler flattens
  them.

**Tooling.**
- Just Cause 2 diffed the instruction and register counts of every shader
  edit and attached the diff to code reviews. That caught über-shader
  variants that a change shouldn't have touched.
- Our equivalent: Nsight Graphics shader profiler / RGA on the SPIR-V.

**Two notes.**
- Breaking dependency chains into trees helps VLIW/vector GPUs only, not
  scalar ones (NVIDIA DX10+, AMD GCN+, so not our RTX).
- Whether float results stay identical depends on the algebra (`x*x*x` vs
  `pow(x,3)` differs in the last bits). That rounding is acceptable and
  not a look change; NaNs and infinities are not.

### Hashes
Integer PCG (`pcg3d`, Jarzynski & Olano, JCGT 2020) is fast and good. But
a different hash moves every bubble, glint and star: an art change. Keep
our hashes; use PCG only for new effects.

## 4. Textures and memory

- Shadow PCF (soft shadow edges from several shadow-map taps) with
  `sampler2DArrayShadow` gets 2x2 compares per tap free in hardware. We
  use 4 taps = 16 compares. `textureGather` needs more ALU. Keep it.
  (NVIDIA shadow mapping paper; Castaño "Shadow Mapping Summary".)
- Uniform (warp-coherent) reads of buffers are fast; divergent reads of
  constant buffers serialize. Our `Lighting` is read uniformly (same index
  across the warp), which is good.

## 5. Vertex stage and memory

### Static vertex data in device-local memory (applied)
Done with `Buffer.initWith` and a staging copy.
- Host-visible memory on a discrete GPU is system RAM, read over PCIe on
  every draw.
- Per-frame data (instances, chunk meshes) may stay host-visible.
- Anything read every frame and written once must not.

### Don't hand-rewrite the skinned normal
The compiler already shares repeated buffer loads and simplifies
`transpose(inverse(J))`. Hand-rewriting the skinned normal (bones read
once, cofactors) gained nothing measurable. Don't redo it.

### What the vertex stage costs
Our vertex shaders do growth, wind and skinning per vertex, every frame,
per pass. The shadow variant (3 views, multiview) runs it again per
caster.
- Compressed vertex formats and fewer attributes cut fetch.
- LODs already cut counts.
- Shadow casters use the coarsest LOD (we do).

## Measurement (scratch procedure)

1. **Scratch edit** in `main.zig`'s play loop, after `r.draw`: count
   frames. At 1500, log each `renderer.Pass` field name with
   `r.gpuMs[i]`, then `r.gpuMs[renderer.glow]`, `[renderer.compose]`,
   `r.gpuTotal`, and call `window.setShouldClose(true)`. Revert it after
   (never commit it).
2. **Build and run**: `zig build -Drelease=true`, then
   `zig-out/bin/Parasymi.exe --demo --novsync --tod=0.45` (and
   `--stress`). AA comes from the gardener's `options.cfg`
   (`%LOCALAPPDATA%/Parasymi`): back it up, switch `antialias`, restore
   it.
3. **Knock-outs**: swap one snippet (e.g. `return 1.0` at the top of
   `keyShadow`), rebuild, bench, restore. Run twice; noise is ~0.01 ms.
4. **Prove the look held**: `--demo --inspect --shots=3 --tod=0.9` before
   and after (git stash), and compare the shots. Use a debug build for
   validation.

## Applied (2026-10-25), RTX 4060 Ti, 1600x900, demo, GPU ms

| step | msaa8 total | notes |
|---|---|---|
| baseline | 69.1 | parts 27.0, partsGlass 17.6, plants 10.8, plantsGlass 8.5 |
| glass `less` + early tests | 68.6 | lost in the bus-bound noise |
| meshes/skins/grows device-local | 8.2 | parts 1.6, plants 3.1; glass `less` now -0.2 |
| one pass over point lights, glisten skipped at 0 | 7.2 | plants 2.2 |

Now: demo off 5.0, msaa4 5.9, msaa8 7.2; stress msaa8 11.1 (plants 4.9).

What each piece still costs (knock-outs at msaa8):
- point lights ~0.45 (plants);
- key shadow ~0.3;
- sap bubbles ~0.25, glisten ~0.2, droplets ~0.15;
- the skinned normal's Jacobian ~0.3 (parts, vertex).

Tried, no gain:
- drawing the sky after the solids (the clear's cost just moves to the
  first pass);
- the skinned-normal rewrite above.

**Decided (the user, 2026-10-25): per-sample shading stays as it is.**
It is the largest single cost left on the plant/part passes (plants 1.0
ms at AA off, 2.2 at msaa8). But lowering `min_sample_shading`, shading
per pixel or alpha-to-coverage would change the edges: don't propose it
again unless the user raises it.

**Open, art-safe but bigger builds:**
- clustered/tiled light lists (at most ~0.45 ms here);
- splitting part.frag's rare roles into their own pipeline (occupancy;
  measure in Nsight first).

## Sources

- NVIDIA, Advanced API Performance: Shaders — developer.nvidia.com/blog/advanced-api-performance-shaders
- Khronos Vulkan Samples, MSAA — docs.vulkan.org/samples/latest/samples/performance/msaa/README.html
- Khronos Vulkan Samples, Specialization constants — docs.vulkan.org/samples/latest/samples/performance/specialization_constants/README.html
- E. Persson, Low-Level Thinking in High-Level Shading Languages (GDC 2013) — humus.name/Articles/Persson_LowLevelThinking.pdf (read in full from the gardener's copy; not kept in the repo)
- Imagination, Low-level GLSL optimisation (MAD form) — docs.imgtec.com/performance-guides/low-level-glsl
- AMD GPUOpen, register pressure / occupancy; GDC2017 Advanced Shader Programming on GCN — gpuopen.com
- Jarzynski & Olano, Hash Functions for GPU Rendering (JCGT 9(3), 2020) — jcgt.org/published/0009/03/02
- OpenGL wiki, Early Fragment Test — opengl.org/wiki/Early_Depth_Test
- NVIDIA, Transparency or Translucency Rendering — developer.nvidia.com/content/transparency-or-translucency-rendering
- I. Castaño, Shadow Mapping Summary — ludicon.com/castano/blog
- Vulkan tutorial, divergence audit — docs.vulkan.org/tutorial/latest/Advanced_Vulkan_Compute
